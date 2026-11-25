package doctor

import (
	"context"
	"errors"
	"fmt"
	"time"
)

const perSide = 4 // one warm-up and three measured runs

// Doctor does the next piece of work of an audit.
type Doctor struct {
	Ash    Ash
	GitHub GitHub
	Public Public
	OpenAI OpenAI
	Poll   time.Duration
	RunMax time.Duration
	// Develop makes a moving picture small; nil means an edition without pictures.
	Develop func(context.Context, []byte) ([]byte, error)
	// TypeSafe is the outside fact-checker; nil means none.
	TypeSafe *TypeSafe
}

// refused is a reason to stop the audit instead of retrying.
type refused struct{ error }

func (r refused) Unwrap() error { return r.error }

// noModel means that a model did not answer or gave nothing usable.
type noModel struct{ error }

func (n noModel) Unwrap() error { return n.error }

// githubLimit is GitHub's limit for reading without credentials.
type githubLimit struct{ until time.Time }

func (g githubLimit) Error() string {
	return "GitHub asks us to wait until " + g.until.Format(time.TimeOnly)
}

// Step works on the oldest audit. It reports whether there was any.
func (d Doctor) Step(ctx context.Context) (bool, error) {
	audits, err := d.Ash.OpenAll(ctx)
	if err != nil || len(audits) == 0 {
		return false, err
	}
	return true, d.work(ctx, &audits[0])
}

func (d Doctor) work(ctx context.Context, au *Audit) error {
	var err error
	switch {
	case au.Repository != d.GitHub.repo:
		err = d.foreign(ctx, au)
		if until, ok := limited(err); ok {
			return githubLimit{until}
		}
	case au.State == "examining":
		err = d.examine(ctx, au)
	case au.State == "awaiting_approval":
		err = d.approval(ctx, au)
	default:
		err = d.measure(ctx, au)
	}
	var r refused
	if errors.As(err, &r) {
		return errors.Join(d.Ash.Log(ctx, au.ID, "stopped", r.Error(), ""), d.Ash.Stop(ctx, au.ID, r.Error()))
	}
	return err
}

func (d Doctor) examine(ctx context.Context, au *Audit) error {
	trials, err := d.Ash.Trials(ctx, au.ID)
	if err != nil {
		return err
	}
	if len(trials) > 0 { // proposed before a restart
		return d.Ash.RequestApproval(ctx, au.ID, nil)
	}
	main, newest, err := d.newest(ctx, au)
	if err != nil {
		return err
	}
	workflow, _, err := d.GitHub.File(ctx, au.BaseSHA)
	if err != nil {
		return err
	}
	runs, err := d.GitHub.Runs(ctx, "status=success&head_sha="+au.BaseSHA)
	if err != nil {
		return err
	}
	if len(runs) == 0 {
		return refused{errors.New("There is no successful run of this commit.")}
	}
	jobs, err := d.GitHub.Jobs(ctx, runs[0].ID)
	if err != nil {
		return err
	}
	if newest {
		if err := d.Ash.Identify(ctx, au.ID, au.BaseSHA, workflowPath, main, len(jobs)); err != nil {
			return err
		}
	}
	if err := d.Ash.Log(ctx, au.ID, "github", readLine(len(jobs)), d.GitHub.URL(runs[0].ID)); err != nil {
		return err
	}
	file, notices := examineFile(workflow)
	if err := d.notices(ctx, au, notices); err != nil {
		return err
	}
	facts := append(file, Facts(workflow, jobs, nil)...)
	facts = facts[:min(maxFacts-1, len(facts))]
	if err := d.Ash.RecordFacts(ctx, au.ID, facts, usable(jobs, 10)); err != nil {
		return err
	}
	advice, err := d.ask(ctx, au, workflow, jobs, facts, measurable)
	if err != nil {
		return err
	}
	if err := d.findings(ctx, au, advice); err != nil {
		return err
	}
	patched, err := Apply(workflow, advice.Edits)
	if err != nil {
		return refused{fmt.Errorf("The proposed change was refused: %w", err)}
	}
	if fact, ok := planned(workflow, patched, jobs); ok {
		if err := d.Ash.RecordFacts(ctx, au.ID, append(facts, fact), usable(jobs, 10)); err != nil {
			return err
		}
	}
	if err := d.Ash.Log(ctx, au.ID, "openai", "The analyst has a proposal.", ""); err != nil {
		return err
	}
	if err := d.Ash.Propose(ctx, Trial{AuditID: au.ID, Attempt: 1, Goal: advice.Goal, Hypothesis: cut(advice.Hypothesis, 1000), Original: workflow, Patch: patched, Branch: branch(au, "trial")}); err != nil {
		return err
	}
	return d.Ash.RequestApproval(ctx, au.ID, jobs)
}

// newest chooses the commit of the newest successful run on the default branch, if none was given.
func (d Doctor) newest(ctx context.Context, au *Audit) (string, bool, error) {
	if au.BaseSHA != "" {
		return "", false, nil
	}
	branch, err := d.GitHub.DefaultBranch(ctx)
	if err != nil {
		return "", false, err
	}
	runs, err := d.GitHub.Successful(ctx, branch)
	if err != nil {
		return "", false, err
	}
	for _, r := range runs {
		if shaName.MatchString(r.HeadSHA) {
			au.BaseSHA = r.HeadSHA
			return branch, true, nil
		}
	}
	return "", false, refused{errors.New("No successful workflow run on the default branch was found.")}
}

// notices stores what only the requester may know.
func (d Doctor) notices(ctx context.Context, au *Audit, list []Notice) error {
	for _, n := range list {
		n.AuditID = au.ID
		if err := d.Ash.Notify(ctx, n); err != nil {
			return err
		}
	}
	return nil
}

var errBudget = errors.New("The model budget is used up.")

// findings stores what the model says; a statement that its facts do not support is left out.
func (d Doctor) findings(ctx context.Context, au *Audit, advice Advice) error {
	kept := 0
	for i, f := range advice.Findings[:min(5, len(advice.Findings))] {
		err := d.Ash.RecordFinding(ctx, Finding{AuditID: au.ID, Kind: f.Kind, Position: i + 1, Title: cut(f.Title, 90), Text: cut(f.Text, 600), Advice: cut(f.Advice, 400), Evidence: f.Evidence})
		var s StatusError
		if errors.As(err, &s) && s.Code >= 400 && s.Code < 500 {
			continue
		}
		if err != nil {
			return err
		}
		kept++
	}
	return d.Ash.Log(ctx, au.ID, "openai", fmt.Sprintf("Findings supported by the facts: %d of %d.", kept, len(advice.Findings)), "")
}

// ask makes one paid call, if the budget allows it, and accounts for it.
func (d Doctor) ask(ctx context.Context, au *Audit, workflow string, jobs []Job, facts []Fact, kinds []string) (Advice, error) {
	ok, err := d.Ash.BudgetLeft(ctx)
	if err != nil {
		return Advice{}, err
	}
	if !ok {
		return Advice{}, refused{errBudget}
	}
	advice, in, out, err := d.OpenAI.Ask(ctx, workflow, jobs, facts, kinds)
	if in > 0 {
		if e := d.Ash.Spent(ctx, au.ID, d.OpenAI.Model, in, out); e != nil {
			return Advice{}, refused{errors.New("A model call could not be accounted for.")}
		}
	}
	if err != nil {
		return Advice{}, noModel{refused{fmt.Errorf("The model gave no usable answer: %w", err)}}
	}
	return advice, nil
}

func readLine(jobs int) string {
	if jobs == 1 {
		return "Read the workflow and 1 job."
	}
	return fmt.Sprintf("Read the workflow and %d jobs.", jobs)
}

func branch(au *Audit, side string) string { return "builddoctor/" + cut(au.ID, 8) + "-" + side }

func (d Doctor) measure(ctx context.Context, au *Audit) error {
	trials, err := d.Ash.Trials(ctx, au.ID)
	if err != nil {
		return err
	}
	if len(trials) == 0 {
		return refused{errors.New("There is no trial to measure.")}
	}
	t := trials[0]
	runs, err := d.Ash.Runs(ctx, au.ID)
	if err != nil {
		return err
	}
	base, cand, known := 0, 0, map[int64]bool{}
	for _, r := range runs {
		known[r.GitHub] = true
		if r.TrialID == nil {
			base++
		} else {
			cand++
		}
	}
	if base+cand == 0 {
		if err := d.prepare(ctx, au, t); err != nil {
			return err
		}
	}
	if base >= perSide && cand >= perSide {
		v, err := d.Ash.Evaluate(ctx, t.ID)
		if err != nil {
			return err
		}
		if err := d.Ash.Log(ctx, au.ID, "verdict", "Verdict: "+v+".", ""); err != nil {
			return err
		}
		return d.Ash.Finish(ctx, au.ID)
	}
	// Alternate, so that both sides see the same weather.
	if base <= cand {
		return d.one(ctx, au, branch(au, "base"), nil, base == 0, known, base+cand+1)
	}
	return d.one(ctx, au, t.Branch, &t.ID, cand == 0, known, base+cand+1)
}

func (d Doctor) prepare(ctx context.Context, au *Audit, t Trial) error {
	if t.Branch != branch(au, "trial") {
		return refused{errors.New("The trial branch is not the expected one.")}
	}
	if err := d.GitHub.Branch(ctx, branch(au, "base"), au.BaseSHA); err != nil {
		return err
	}
	if err := d.GitHub.Branch(ctx, t.Branch, au.BaseSHA); err != nil {
		return err
	}
	if err := d.GitHub.Put(ctx, t.Branch, t.Patch, "BuildDoctor trial"); err != nil {
		return err
	}
	return d.Ash.Log(ctx, au.ID, "patch", "Prepared one branch without and one with the change.", "")
}

func (d Doctor) one(ctx context.Context, au *Audit, br string, trial *string, warm bool, known map[int64]bool, n int) error {
	ctx, cancel := context.WithTimeout(ctx, d.RunMax)
	defer cancel()
	side := "baseline"
	if trial != nil {
		side = "trial"
	}
	if err := d.quiet(ctx, known); err != nil {
		return err
	}
	filter := "event=workflow_dispatch&branch=" + br
	id, err := d.fresh(ctx, filter, known) // adopt a run started before a restart
	if err != nil {
		return err
	}
	if id == 0 {
		if err := d.GitHub.Dispatch(ctx, br); err != nil {
			return err
		}
		for id == 0 {
			if err := d.wait(ctx); err != nil {
				return err
			}
			if id, err = d.fresh(ctx, filter, known); err != nil {
				return err
			}
		}
	}
	if err := d.Ash.Log(ctx, au.ID, "run_started", fmt.Sprintf("Run %d of %d started.", n, 2*perSide), d.GitHub.URL(id)); err != nil {
		return err
	}
	for {
		run, err := d.GitHub.Run(ctx, id)
		if err != nil {
			return err
		}
		if run.Status == "completed" {
			jobs, err := d.GitHub.Jobs(ctx, id)
			if err != nil {
				return err
			}
			// The last look shows every job as done, so that no clock on the page runs on.
			_ = d.Ash.Progress(ctx, au.ID, n, side, jobs)
			if err := d.Ash.Record(ctx, Run{au.ID, trial, id, run.HeadSHA, warm, run.Started, jobs}); err != nil {
				return err
			}
			return d.Ash.Log(ctx, au.ID, "run_finished", fmt.Sprintf("Run %d of %d finished.", n, 2*perSide), d.GitHub.URL(id))
		}
		// Progress is for watching only; a failure here never stops the measurement.
		if jobs, err := d.GitHub.Jobs(ctx, id); err == nil {
			_ = d.Ash.Progress(ctx, au.ID, n, side, jobs)
		}
		if err := d.wait(ctx); err != nil {
			return err
		}
	}
}

// quiet waits until no foreign run is active, so that runs do not disturb each other.
func (d Doctor) quiet(ctx context.Context, known map[int64]bool) error {
	for {
		busy := false
		for _, s := range []string{"queued", "in_progress"} {
			runs, err := d.GitHub.Runs(ctx, "status="+s)
			if err != nil {
				return err
			}
			for _, r := range runs {
				busy = busy || r.Event != "workflow_dispatch" || known[r.ID]
			}
		}
		if !busy {
			return nil
		}
		if err := d.wait(ctx); err != nil {
			return err
		}
	}
}

func (d Doctor) fresh(ctx context.Context, filter string, known map[int64]bool) (int64, error) {
	runs, err := d.GitHub.Runs(ctx, filter)
	if err != nil {
		return 0, err
	}
	for i := len(runs) - 1; i >= 0; i-- {
		if !known[runs[i].ID] {
			return runs[i].ID, nil
		}
	}
	return 0, nil
}

func (d Doctor) wait(ctx context.Context) error {
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-time.After(d.Poll):
		return nil
	}
}
