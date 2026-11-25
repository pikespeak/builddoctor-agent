package doctor

import (
	"context"
	"net/http"
	"time"
)

// Ash is the client of the BuildDoctor application.
type Ash struct{ c caller }

// NewAsh uses the shared secret of the agent.
func NewAsh(base, token string, h *http.Client) Ash {
	return Ash{caller{base: base + "/api/json", token: token, media: "application/vnd.api+json", files: base + "/api", http: h}}
}

// Audit as the application reports it.
type Audit struct {
	ID         string `json:"-"`
	State      string `json:"state"`
	Repository string `json:"repository"`
	BaseSHA    string `json:"base_sha"`
	Facts      []Fact `json:"facts"`
}

// Trial as the application reports it. Original and Patch hold the workflow file before and after.
type Trial struct {
	ID         string `json:"-"`
	AuditID    string `json:"audit_id,omitempty"`
	Attempt    int    `json:"attempt"`
	Goal       string `json:"goal"`
	Hypothesis string `json:"hypothesis"`
	Original   string `json:"original,omitempty"`
	Patch      string `json:"patch"`
	Branch     string `json:"branch"`
	Verdict    string `json:"verdict,omitempty"`
	Status     string `json:"status,omitempty"`
}

// Job is one finished job.
type Job struct {
	Name       string    `json:"name"`
	Conclusion string    `json:"conclusion"`
	Status     string    `json:"status,omitempty"`
	Started    time.Time `json:"started_at"`
	Completed  time.Time `json:"completed_at"`
	Created    time.Time `json:"created_at,omitzero"`
	Steps      []Step    `json:"steps,omitempty"`
}

// Step of a job, as GitHub reports it.
type Step struct {
	Name      string    `json:"name"`
	Started   time.Time `json:"started_at"`
	Completed time.Time `json:"completed_at"`
}

// Finding is one statement of the model with the facts it rests on.
type Finding struct {
	AuditID  string   `json:"audit_id"`
	Position int      `json:"position"`
	Title    string   `json:"title"`
	Text     string   `json:"text"`
	Advice   string   `json:"advice"`
	Evidence []string `json:"evidence"`
	Kind     string   `json:"kind,omitempty"`
	ID       string   `json:"-"`
	Status   string   `json:"status,omitempty"`
}

// Review is the word of one role of the council.
type Review struct {
	FindingID string `json:"finding_id,omitempty"`
	TrialID   string `json:"trial_id,omitempty"`
	Role      string `json:"role"`
	Verdict   string `json:"verdict"`
	Reason    string `json:"reason"`
	Model     string `json:"model"`
	Version   int    `json:"version"`
}

// Run is one measured workflow run.
type Run struct {
	AuditID string    `json:"audit_id,omitempty"`
	TrialID *string   `json:"trial_id"`
	GitHub  int64     `json:"github_run_id"`
	SHA     string    `json:"sha"`
	Warmup  bool      `json:"warmup"`
	Started time.Time `json:"started_at"`
	Jobs    []Job     `json:"jobs"`
}

type item[T any] struct {
	ID         string `json:"id,omitempty"`
	Type       string `json:"type"`
	Attributes T      `json:"attributes"`
}
type one[T any] struct {
	Data item[T] `json:"data"`
}
type many[T any] struct {
	Data []item[T] `json:"data"`
}

// OpenAll returns the audits with work, the oldest first.
func (a Ash) OpenAll(ctx context.Context) ([]Audit, error) {
	var r many[Audit]
	if err := a.c.do(ctx, "GET", "/audits/open", nil, &r); err != nil {
		return nil, err
	}
	out := []Audit{}
	for _, d := range r.Data {
		d.Attributes.ID = d.ID
		out = append(out, d.Attributes)
	}
	return out, nil
}

// Identify tells which commit and workflow are examined and how many jobs its run has.
func (a Ash) Identify(ctx context.Context, id, sha, path, branch string, jobs int) error {
	return a.audit(ctx, id, "identify", map[string]any{"base_sha": sha, "workflow_path": path, "default_branch": branch, "jobs_total": jobs})
}

// Findings of an audit, whatever their state.
func (a Ash) Findings(ctx context.Context, audit string) ([]Finding, error) {
	var r many[Finding]
	if err := a.c.do(ctx, "GET", "/findings/for_audit/"+audit, nil, &r); err != nil {
		return nil, err
	}
	out := []Finding{}
	for _, d := range r.Data {
		d.Attributes.ID = d.ID
		out = append(out, d.Attributes)
	}
	return out, nil
}

// Review stores the word of a role.
func (a Ash) Review(ctx context.Context, r Review) error {
	kind := "trial"
	if r.FindingID != "" {
		kind = "finding"
	}
	return a.c.do(ctx, "POST", "/reviews/"+kind, one[Review]{item[Review]{Type: "review", Attributes: r}}, nil)
}

// Notify stores a weakness for the requester only.
func (a Ash) Notify(ctx context.Context, n Notice) error {
	return a.c.do(ctx, "POST", "/notices", one[Notice]{item[Notice]{Type: "notice", Attributes: n}}, nil)
}

// Decide asks the chair; it answers published or withheld.
func (a Ash) Decide(ctx context.Context, kind, id string) (string, error) {
	var r one[struct {
		Status string `json:"status"`
	}]
	err := a.c.do(ctx, "PATCH", "/"+kind+"s/"+id+"/decide", one[struct{}]{item[struct{}]{ID: id, Type: kind}}, &r)
	return r.Data.Attributes.Status, err
}

// ApproveByCouncil starts a cleared trial; the application checks the limits.
func (a Ash) ApproveByCouncil(ctx context.Context, id string) error {
	return a.audit(ctx, id, "approve_by_council", map[string]any{})
}

// LeaveToRequester ends the council's part.
func (a Ash) LeaveToRequester(ctx context.Context, id string) error {
	return a.audit(ctx, id, "leave_to_requester", map[string]any{})
}

// RecordFacts stores the computed facts and the jobs.
func (a Ash) RecordFacts(ctx context.Context, id string, facts []Fact, jobs []Job) error {
	return a.audit(ctx, id, "record_facts", map[string]any{"facts": facts, "examined_jobs": settled(jobs)})
}

// RecordFinding stores a finding; the application refuses one that its facts do not support.
func (a Ash) RecordFinding(ctx context.Context, f Finding) error {
	return a.c.do(ctx, "POST", "/findings", one[Finding]{item[Finding]{Type: "finding", Attributes: f}}, nil)
}

// FinishExamination ends an audit that only reads.
func (a Ash) FinishExamination(ctx context.Context, id string, jobs []Job) error {
	return a.audit(ctx, id, "finish_examination", map[string]any{"examined_jobs": settled(jobs)})
}

// ReportWait tells when GitHub lets the agent read again.
func (a Ash) ReportWait(ctx context.Context, id string, until time.Time) error {
	return a.audit(ctx, id, "report_wait", map[string]any{"waiting_until": until.UTC().Truncate(time.Second)})
}

// ReportError counts a failure; the application decides when it is enough.
func (a Ash) ReportError(ctx context.Context, id string) error {
	return a.audit(ctx, id, "report_error", map[string]any{})
}

// RequestApproval hands over what was examined.
func (a Ash) RequestApproval(ctx context.Context, id string, jobs []Job) error {
	m := map[string]any{}
	if len(jobs) > 0 {
		m["examined_jobs"] = settled(jobs)
	}
	return a.audit(ctx, id, "request_approval", m)
}

// Progress tells what the running workflow does.
func (a Ash) Progress(ctx context.Context, id string, number int, side string, jobs []Job) error {
	live := []map[string]any{}
	for _, j := range jobs {
		stage := "queued"
		if !j.Completed.IsZero() {
			stage = "done"
		} else if j.Status == "in_progress" {
			stage = "running"
		}
		l := map[string]any{"name": j.Name, "stage": stage}
		// GitHub gives a queued job a start as well; only a real start counts.
		if stage != "queued" && !j.Started.IsZero() {
			l["started_at"] = j.Started
		}
		if stage == "done" {
			l["completed_at"] = j.Completed
		}
		live = append(live, l)
	}
	return a.audit(ctx, id, "report_progress", map[string]any{"live_number": number, "live_side": side, "live_jobs": live})
}

// Finish ends an audit.
func (a Ash) Finish(ctx context.Context, id string) error {
	return a.audit(ctx, id, "finish", map[string]any{})
}

func (a Ash) audit(ctx context.Context, id, action string, m map[string]any) error {
	return a.c.do(ctx, "PATCH", "/audits/"+id+"/"+action, one[map[string]any]{item[map[string]any]{id, "audit", m}}, nil)
}

// Stop ends an audit with a reason.
func (a Ash) Stop(ctx context.Context, id, reason string) error {
	return a.c.do(ctx, "PATCH", "/audits/"+id+"/stop", one[map[string]string]{item[map[string]string]{id, "audit", map[string]string{"reason": cut(reason, 200)}}}, nil)
}

// Trials of an audit.
func (a Ash) Trials(ctx context.Context, audit string) ([]Trial, error) {
	var r many[Trial]
	if err := a.c.do(ctx, "GET", "/trials/for_audit/"+audit, nil, &r); err != nil {
		return nil, err
	}
	out := []Trial{}
	for _, d := range r.Data {
		d.Attributes.ID = d.ID
		out = append(out, d.Attributes)
	}
	return out, nil
}

// Propose stores a trial.
func (a Ash) Propose(ctx context.Context, t Trial) error {
	return a.c.do(ctx, "POST", "/trials", one[Trial]{item[Trial]{Type: "trial", Attributes: t}}, nil)
}

// Evaluate asks the application for the verdict.
func (a Ash) Evaluate(ctx context.Context, id string) (string, error) {
	var r one[Trial]
	err := a.c.do(ctx, "PATCH", "/trials/"+id+"/evaluate", one[struct{}]{item[struct{}]{ID: id, Type: "trial"}}, &r)
	return r.Data.Attributes.Verdict, err
}

// Runs recorded for an audit.
func (a Ash) Runs(ctx context.Context, audit string) ([]Run, error) {
	var r many[Run]
	if err := a.c.do(ctx, "GET", "/runs/for_audit/"+audit, nil, &r); err != nil {
		return nil, err
	}
	out := []Run{}
	for _, d := range r.Data {
		out = append(out, d.Attributes)
	}
	return out, nil
}

// Record stores a run once.
func (a Ash) Record(ctx context.Context, r Run) error {
	r.Jobs = settled(r.Jobs)
	return a.c.do(ctx, "POST", "/runs", one[Run]{item[Run]{Type: "run", Attributes: r}}, nil)
}

// Log stores a visible step.
func (a Ash) Log(ctx context.Context, audit, kind, message, reference string) error {
	m := map[string]string{"audit_id": audit, "kind": kind, "status": "ok", "message": cut(message, 300)}
	if reference != "" {
		m["reference"] = reference
	}
	return a.c.do(ctx, "POST", "/events", one[map[string]string]{item[map[string]string]{Type: "agent_event", Attributes: m}}, nil)
}

// BudgetLeft tells whether a model call is allowed.
func (a Ash) BudgetLeft(ctx context.Context) (bool, error) {
	var ok bool
	err := a.c.do(ctx, "GET", "/ai_calls/budget_left", nil, &ok)
	return ok, err
}

// Spent records a model call.
func (a Ash) Spent(ctx context.Context, audit, model string, in, out int) error {
	m := map[string]any{"audit_id": audit, "model": model, "input_tokens": in, "output_tokens": out}
	return a.c.do(ctx, "POST", "/ai_calls", one[map[string]any]{item[map[string]any]{Type: "ai_call", Attributes: m}}, nil)
}

func cut(s string, n int) string {
	if r := []rune(s); len(r) > n {
		return string(r[:n])
	}
	return s
}

// settled drops what the application does not store about a job.
func settled(jobs []Job) []Job {
	out := append([]Job{}, jobs...)
	for i := range out {
		out[i].Status, out[i].Created, out[i].Steps = "", time.Time{}, nil
	}
	return out
}
