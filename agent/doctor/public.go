package doctor

import (
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"regexp"
	"slices"
	"sort"
	"strings"
	"time"
)

// Public reads public repositories. It has no credentials, or a token that GitHub limits to public
// repositories; the answer is checked for "private" in both cases.
type Public struct{ c caller }

// NewPublic takes the base of the API. WithToken adds the file of a token. Redirects (renamed repositories) stay on the same host.
func NewPublic(base string, timeout time.Duration) Public {
	h := &http.Client{Timeout: timeout, CheckRedirect: func(r *http.Request, via []*http.Request) error {
		if len(via) > 3 || r.URL.Host != via[0].URL.Host || r.URL.Scheme != via[0].URL.Scheme {
			return errors.New("redirect refused")
		}
		return nil
	}}
	return Public{caller{base: base, media: "application/vnd.github+json", http: h}}
}

// WithToken uses the token in a file for requests to the base address only.
func (p Public) WithToken(file string) (Public, error) {
	home, err := url.Parse(p.c.base)
	if err != nil {
		return p, err
	}
	h := *p.c.http
	h.Transport = &readToken{home: home, file: file, next: http.DefaultTransport}
	p.c.http = &h
	return p, nil
}

// Same rule as the application; checked again because the name becomes part of an address.
var repoName = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9._-]{1,100}$`)
var workflowName = regexp.MustCompile(`^\.github/workflows/[A-Za-z0-9._-]{1,100}\.ya?ml$`)
var branchName = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._/-]{0,99}$`)
var shaName = regexp.MustCompile(`^[0-9a-f]{40}$`)

// Reading is what was read of a repository.
type Reading struct {
	SHA, Path, Branch, Workflow string
	RunID                       int64
	Jobs, All                   []Job // the ten that are shown, and those the model sees
	Total                       int
	History                     []past
	Trouble                     []Fact
	Runs                        map[string][]past // of every workflow that was read
	About                       About
	base                        string
}

// Read finds the slowest recent workflow of the default branch.
func (p Public) Read(ctx context.Context, repo string) (Reading, error) {
	var f Reading
	if !repoName.MatchString(repo) || strings.HasSuffix(repo, "/.") || strings.HasSuffix(repo, "/..") {
		return f, refused{errors.New("This is not a repository name.")}
	}
	base := "/repos/" + repo
	var r struct {
		Private  *bool
		Disabled bool
		Branch   string `json:"default_branch"`
		About
	}
	if err := p.c.do(ctx, "GET", base, nil, &r); err != nil {
		return f, gone(err)
	}
	if r.Private == nil || *r.Private || r.Disabled {
		return f, refused{errors.New("Only public repositories can be examined.")}
	}
	if !branchName.MatchString(r.Branch) {
		return f, refused{errors.New("The name of the default branch is not supported.")}
	}
	f.Branch, f.About = r.Branch, r.About.short()
	var l struct {
		Runs []struct {
			ID      int64
			Path    string
			Result  string    `json:"conclusion"`
			SHA     string    `json:"head_sha"`
			Started time.Time `json:"run_started_at"`
			Updated time.Time `json:"updated_at"`
			Attempt int       `json:"run_attempt"`
		} `json:"workflow_runs"`
	}
	if err := p.c.do(ctx, "GET", base+"/actions/runs?status=completed&event=push&per_page=50&branch="+url.QueryEscape(r.Branch), nil, &l); err != nil {
		return f, gone(err)
	}
	var longest time.Duration = -1
	seen := map[string]bool{} // only the newest successful run of every workflow
	history := map[string][]past{}
	for _, run := range l.Runs {
		path, _, _ := strings.Cut(run.Path, "@")
		if workflowName.MatchString(path) && shaName.MatchString(run.SHA) {
			history[path] = append(history[path], past{run.ID, run.Result, secs(run.Started, run.Updated), run.SHA, run.Attempt})
		}
		if run.Result != "success" || seen[path] || !workflowName.MatchString(path) || !shaName.MatchString(run.SHA) {
			continue
		}
		seen[path] = true
		if d := run.Updated.Sub(run.Started); d > longest {
			longest, f.RunID, f.Path, f.SHA = d, run.ID, path, run.SHA
		}
	}
	if f.RunID == 0 {
		return f, refused{errors.New("No successful workflow run on the default branch was found.")}
	}
	f.History, f.Runs, f.base = history[f.Path], history, base
	type file struct{ Type, Encoding, Content string }
	content := async(func() (c file, err error) {
		err = p.c.do(ctx, "GET", base+"/contents/"+f.Path+"?ref="+f.SHA, nil, &c)
		return c, err
	})
	trouble := async(func() ([]Fact, error) { return p.trouble(ctx, base, history, f.Path), nil })
	var j struct {
		Total int `json:"total_count"`
		Jobs  []Job
	}
	noJobs := p.c.do(ctx, "GET", fmt.Sprintf("%s/actions/runs/%d/jobs?per_page=100", base, f.RunID), nil, &j)
	c, noFile := content()
	found, _ := trouble()
	if noFile != nil {
		return f, gone(noFile)
	}
	b, err := base64.StdEncoding.DecodeString(strings.ReplaceAll(c.Content, "\n", ""))
	if c.Type != "file" || c.Encoding != "base64" || err != nil || len(b) == 0 || len(b) > 20_000 {
		return f, refused{errors.New("The workflow file is empty, too large or not a plain file.")}
	}
	f.Workflow = string(b)
	if noJobs != nil {
		return f, gone(noJobs)
	}
	f.Jobs, f.All = usable(j.Jobs, 10), usable(j.Jobs, 40)
	f.Total = min(max(j.Total, len(f.Jobs)), 1000)
	if len(f.Jobs) == 0 {
		return f, refused{errors.New("The run has no finished jobs.")}
	}
	f.Trouble = found
	return f, nil
}

// gone turns "you will never see this" into an end; everything else may be tried again.
func gone(err error) error {
	var s StatusError
	if errors.As(err, &s) {
		switch s.Code {
		case http.StatusNotFound, http.StatusGone, http.StatusUnavailableForLegalReasons:
			return refused{errors.New("This project was not found, or it is not public.")}
		}
	}
	return err
}

// limited tells how long GitHub asks to wait, if it does.
func limited(err error) (time.Time, bool) {
	var s StatusError
	if errors.As(err, &s) && (s.Code == http.StatusForbidden || s.Code == http.StatusTooManyRequests) {
		return s.Reset, true
	}
	return time.Time{}, false
}

var oddInName = regexp.MustCompile(`[^A-Za-z0-9_ .,:()/+-]+`)

// usable keeps the longest finished jobs, in order of their start, with plain and unique names.
func usable(in []Job, most int) []Job {
	out := []Job{}
	for _, j := range in {
		switch j.Conclusion {
		case "success", "failure", "cancelled", "timed_out":
		default:
			continue
		}
		if j.Started.IsZero() || j.Completed.Before(j.Started) {
			continue
		}
		j.Name = strings.Join(strings.Fields(oddInName.ReplaceAllString(j.Name, " ")), " ")
		out = append(out, j)
	}
	sort.SliceStable(out, func(a, b int) bool {
		return out[a].Completed.Sub(out[a].Started) > out[b].Completed.Sub(out[b].Started)
	})
	out = out[:min(len(out), most)]
	sort.SliceStable(out, func(a, b int) bool { return out[a].Started.Before(out[b].Started) })
	names := map[string]bool{}
	for i := range out {
		name := cut(out[i].Name, 55)
		if name == "" {
			name = "job"
		}
		for k := 2; names[name]; k++ {
			name = fmt.Sprintf("%s %d", cut(out[i].Name, 55), k)
		}
		names[name] = true
		out[i].Name = strings.TrimSpace(name)
	}
	return out
}

// foreign examines a repository of somebody else: it only reads.
func (d Doctor) foreign(ctx context.Context, au *Audit) (failed error) {
	if au.State != "examining" {
		return refused{errors.New("This project may only be examined.")}
	}
	f, err := d.Public.Read(ctx, au.Repository)
	if err != nil {
		return err
	}
	if err := d.Ash.Identify(ctx, au.ID, f.SHA, f.Path, f.Branch, f.Total); err != nil {
		return err
	}
	run := fmt.Sprintf("https://github.com/%s/actions/runs/%d", au.Repository, f.RunID)
	if err := d.Ash.Log(ctx, au.ID, "github", readLine(f.Total), run); err != nil {
		return err
	}
	file, notices := examineFile(f.Workflow)
	facts := slices.Concat(f.Trouble, file, Facts(f.Workflow, f.All, f.History))
	facts = facts[:min(maxFacts-1-maxRounds*maxQuestions, len(facts))] // places for the answers and the plan
	cast := async(func() (string, error) { return d.cast(ctx, au.ID, f.About) })
	defer func() { // no call is left behind, and none without an account
		_, lost := cast()
		failed = worse(failed, lost)
	}()
	if err := d.notices(ctx, au, notices); err != nil {
		return err
	}
	trials, err := d.Ash.Trials(ctx, au.ID)
	if err != nil {
		return err
	}
	found, err := d.Ash.Findings(ctx, au.ID)
	if err != nil {
		return err
	}
	if len(trials)+len(found) > 0 { // proposed before a restart; the findings cite the stored facts
		facts = au.Facts
	} else {
		if err := d.Ash.RecordFacts(ctx, au.ID, facts, f.Jobs); err != nil {
			return err
		}
		more, err := d.wonder(ctx, au, f, facts)
		if err != nil {
			return err
		}
		if len(more) > len(facts) {
			facts = more
			if err := d.Ash.RecordFacts(ctx, au.ID, facts, f.Jobs); err != nil {
				return err
			}
		}
		advice, err := d.ask(ctx, au, f.Workflow, f.All, facts, Kinds)
		if _, lost := cast(); lost != nil {
			return lost
		}
		if errors.Is(err, errBudget) { // the facts stand without a model
			if err := d.Ash.Log(ctx, au.ID, "openai", "The model budget is used up. The facts are computed without it.", ""); err != nil {
				return err
			}
			return d.Ash.FinishExamination(ctx, au.ID, f.Jobs)
		}
		if without(ctx, err) {
			return d.unfinished(ctx, au, f.Jobs, "The model did not answer. The facts are computed without it.")
		}
		if err != nil {
			return err
		}
		if err := d.findings(ctx, au, advice); err != nil {
			return err
		}
		goal, why := advice.Goal, advice.Hypothesis
		patched, err := Apply(f.Workflow, limits(f.Workflow, advice.Edits, f.All))
		found := err == nil
		if !found { // nothing from the analyst; code may still repair what the grade takes points off for
			goal = "bill"
			var limit Fact
			patched, why, limit, found = repair(f.Workflow, f.All)
			if limit.ID != "" { // the votes need it
				facts = append(facts, limit)
				if err := d.Ash.RecordFacts(ctx, au.ID, facts, f.Jobs); err != nil {
					return err
				}
			}
		}
		if !found {
			if err := d.Ash.Log(ctx, au.ID, "openai", "No change from the safe list would help here.", ""); err != nil {
				return err
			}
		} else if err := d.Ash.Propose(ctx, Trial{AuditID: au.ID, Attempt: 1, Goal: goal, Hypothesis: cut(why, 1000), Original: f.Workflow, Patch: patched, Branch: branch(au, "trial")}); err != nil {
			return err
		}
	}
	if trials, err = d.Ash.Trials(ctx, au.ID); err != nil {
		return err
	}
	if len(trials) > 0 && planOf(facts) == nil {
		if fact, ok := planned(f.Workflow, trials[0].Patch, f.All); ok {
			facts = append(facts, fact)
			if err := d.Ash.RecordFacts(ctx, au.ID, facts, f.Jobs); err != nil {
				return err
			}
		}
	}
	figure, err := cast()
	if err != nil {
		return err
	}
	if found, err = d.Ash.Findings(ctx, au.ID); err != nil {
		return err
	}
	sketches := async(func() ([]sketch, error) { return d.sketch(ctx, au.ID, figure, found, facts) })
	err = d.council(ctx, au, facts, f.Workflow)
	drawn, lost := sketches()
	err = worse(err, lost)
	if without(ctx, err) {
		return d.unfinished(ctx, au, f.Jobs, "The council could not vote, so no statement is shown. The facts are computed without it.")
	}
	if err != nil {
		return err
	}
	if err := d.press(ctx, au.ID, figure, facts, drawn); err != nil {
		return err
	}
	return d.Ash.FinishExamination(ctx, au.ID, f.Jobs)
}

// without tells that only the model failed, while the agent itself goes on working.
func without(ctx context.Context, err error) bool {
	var n noModel
	return ctx.Err() == nil && errors.As(err, &n)
}

// unfinished ends an Examination that has its facts but no word of a model.
func (d Doctor) unfinished(ctx context.Context, au *Audit, jobs []Job, why string) error {
	if err := d.Ash.Log(ctx, au.ID, "openai", why, ""); err != nil {
		return err
	}
	return d.Ash.FinishExamination(ctx, au.ID, jobs)
}
