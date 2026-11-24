package doctor

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

const wf = "on: push\npermissions:\n  contents: read\njobs:\n  vet:\n    runs-on: ubuntu-24.04\n    steps:\n      - uses: actions/setup-go@v5\n        with:\n          cache: false\n  test:\n    needs: vet\n    runs-on: ubuntu-24.04\n    steps:\n      - run: go test\n"

func TestApply(t *testing.T) {
	got, err := Apply(wf, []Edit{{Kind: "remove_needs", Job: "test"}, {Kind: "enable_setup_cache", Job: "vet"}})
	if err != nil || strings.Contains(got, "needs:") || strings.Contains(got, "cache:") || !strings.Contains(got, "contents: read") {
		t.Fatal(got, err)
	}
	for _, e := range [][]Edit{nil, {{Kind: "remove_needs", Job: "vet"}}, {{Kind: "remove_needs", Job: "nope"}}, {{Kind: "run_shell", Job: "vet"}}, {{Kind: "enable_setup_cache", Job: "test"}}} {
		if _, err := Apply(wf, e); err == nil {
			t.Fatal("accepted", e)
		}
	}
	for _, w := range []string{"", "a: [", "jobs: {x: {}}"} {
		if _, err := Apply(w, []Edit{{Kind: "enable_setup_cache", Job: "x"}}); err == nil {
			t.Fatal("accepted", w)
		}
	}
}

// world plays GitHub, OpenAI and the application.
type world struct {
	mu           sync.Mutex // a handler may still run after its client gave up
	state, model string
	trials       []map[string]any
	runs         []map[string]any
	gh           []map[string]any
	events       []string
	progress     []string
	stopped      string
	budget       bool
	fail         string
	puts         int
	repo, good   string // answers for an audit without a commit
	noSHA        bool
	identified   string
}

func (w *world) sha() any {
	if w.noSHA {
		return nil
	}
	return "abc"
}

func (w *world) ServeHTTP(res http.ResponseWriter, req *http.Request) {
	b, _ := io.ReadAll(req.Body)
	w.mu.Lock()
	defer w.mu.Unlock()
	p := req.Method + " " + req.URL.Path
	if w.fail != "" && strings.HasPrefix(p, w.fail) {
		res.WriteHeader(500)
		return
	}
	send := func(v any) { json.NewEncoder(res).Encode(v) }
	attrs := func() map[string]any {
		var d struct {
			Data struct{ Attributes map[string]any }
		}
		json.Unmarshal(b, &d)
		return d.Data.Attributes
	}
	items := func(in []map[string]any) map[string]any {
		out := []any{}
		for i, a := range in {
			out = append(out, map[string]any{"id": fmt.Sprint("t", i), "attributes": a})
		}
		return map[string]any{"data": out}
	}
	job := map[string]any{"name": "vet", "conclusion": "success", "started_at": "2026-11-23T19:44:00Z", "completed_at": "2026-11-23T19:44:09Z"}
	switch {
	case p == "GET /api/json/audits/open":
		if w.state == "" {
			send(items(nil))
			return
		}
		send(map[string]any{"data": []any{map[string]any{"id": "12345678-aaaa", "attributes": map[string]any{"state": w.state, "repository": "o/r", "base_sha": w.sha()}}}})
	case strings.HasSuffix(p, "/request_approval"), strings.HasSuffix(p, "/finish"):
		w.state = ""
		send(map[string]any{})
	case strings.HasSuffix(p, "/identify"):
		w.identified = fmt.Sprint(attrs()["base_sha"], attrs()["default_branch"])
		send(map[string]any{})
	case p == "GET /repos/o/r":
		io.WriteString(res, w.repo)
	case strings.HasSuffix(p, "/workflows/ci.yml/runs"):
		io.WriteString(res, w.good)
	case strings.HasSuffix(p, "/report_progress"):
		w.progress = append(w.progress, fmt.Sprint(attrs()["live_jobs"]))
	case strings.HasSuffix(p, "/record_facts"), p == "POST /api/json/findings":
		send(map[string]any{})
	case strings.HasSuffix(p, "/stop"):
		w.state, w.stopped = "", fmt.Sprint(attrs()["reason"])
	case strings.HasPrefix(p, "GET /api/json/trials"):
		send(items(w.trials))
	case p == "POST /api/json/trials":
		w.trials = append(w.trials, attrs())
	case strings.HasSuffix(p, "/evaluate"):
		send(map[string]any{"data": map[string]any{"attributes": map[string]any{"verdict": "accepted"}}})
	case strings.HasPrefix(p, "GET /api/json/runs"):
		send(items(w.runs))
	case p == "POST /api/json/runs":
		w.runs = append(w.runs, attrs())
	case p == "POST /api/json/events":
		w.events = append(w.events, fmt.Sprint(attrs()["kind"]))
	case p == "GET /api/json/ai_calls/budget_left":
		send(w.budget)
	case p == "POST /api/json/ai_calls":
	case strings.HasPrefix(p, "GET /repos/o/r/contents"):
		send(map[string]any{"type": "file", "encoding": "base64", "sha": "blob", "content": base64.StdEncoding.EncodeToString([]byte(wf))})
	case strings.HasPrefix(p, "PUT /repos/o/r/contents"):
		w.puts++
	case p == "POST /repos/o/r/git/refs":
		res.WriteHeader(422)
	case strings.HasSuffix(p, "/dispatches"):
		w.gh = append([]map[string]any{{"id": len(w.gh) + 1, "status": "completed", "event": "workflow_dispatch", "head_sha": "abc", "run_started_at": "2026-11-23T19:44:00Z"}}, w.gh...)
		res.WriteHeader(204)
	case p == "GET /repos/o/r/actions/runs":
		if s := req.URL.Query().Get("status"); s == "success" {
			send(map[string]any{"workflow_runs": []any{map[string]any{"id": 99}}})
		} else if s != "" {
			send(map[string]any{})
		} else {
			send(map[string]any{"workflow_runs": w.gh})
		}
	case strings.HasSuffix(p, "/jobs"):
		send(map[string]any{"jobs": []any{job}})
	case strings.HasPrefix(p, "GET /repos/o/r/actions/runs/"):
		send(w.gh[0])
	case p == "POST /v1/responses":
		send(map[string]any{"status": "completed", "output": []any{map[string]any{"content": []any{map[string]any{"type": "output_text", "text": w.model}}}}, "usage": map[string]any{"input_tokens": 5, "output_tokens": 6}})
	default:
		res.WriteHeader(404)
	}
}

func start(t *testing.T, w *world) Doctor {
	s := httptest.NewServer(w)
	t.Cleanup(s.Close)
	return Doctor{NewAsh(s.URL, "secret", s.Client()), NewGitHub(s.URL, "o/r", s.Client()), NewPublic(s.URL, time.Second), NewOpenAI(s.URL, "m", s.Client()), time.Millisecond, time.Second}
}

const good = `{"goal":"wait","hypothesis":"They need not wait.","edits":[{"kind":"remove_needs","job":"test"}]}`

func TestAnAuditWithoutACommitTakesTheNewestGoodRun(t *testing.T) {
	fresh := func() *world {
		return &world{state: "examining", model: good, budget: true, noSHA: true, repo: `{"default_branch":"main"}`, good: `{"workflow_runs":[{"head_sha":"odd?"},{"head_sha":"` + sha40 + `"}]}`}
	}
	w := fresh()
	if _, err := start(t, w).Step(context.Background()); err != nil || w.identified != sha40+"main" || len(w.trials) != 1 {
		t.Fatal(err, w.identified, w.stopped)
	}
	for _, change := range []func(*world){func(w *world) { w.repo = `{"default_branch":"a;b"}` }, func(w *world) { w.good = `{}` }} {
		w := fresh()
		change(w)
		if _, err := start(t, w).Step(context.Background()); err != nil || w.stopped == "" {
			t.Fatal(err, w.stopped)
		}
	}
	for _, f := range []string{"GET /repos/o/r", "GET /repos/o/r/actions/workflows", "PATCH /api/json/audits/12345678-aaaa/identify"} {
		w := fresh()
		w.fail = f
		if _, err := start(t, w).Step(context.Background()); err == nil || w.stopped != "" {
			t.Fatal(f, err)
		}
	}
}

func TestWholeAudit(t *testing.T) {
	w := &world{state: "examining", model: good, budget: true}
	d := start(t, w)
	ctx := context.Background()
	if worked, err := d.Step(ctx); !worked || err != nil || len(w.trials) != 1 {
		t.Fatal(worked, err, w.trials, w.stopped)
	}
	w.state = "measuring"
	for i := 0; w.state != "" && i < 20; i++ {
		if _, err := d.Step(ctx); err != nil {
			t.Fatal(err)
		}
	}
	warm, trial := 0, 0
	for _, r := range w.runs {
		if r["warmup"] == true {
			warm++
		}
		if r["trial_id"] != nil {
			trial++
		}
	}
	if w.trials[0]["original"] != wf || len(w.progress) != 8 || !strings.Contains(w.progress[7], "done") {
		t.Fatal(w.trials, w.progress)
	}
	if len(w.runs) != 8 || warm != 2 || trial != 4 || w.puts != 1 || len(w.gh) != 8 {
		t.Fatal(len(w.runs), warm, trial, w.puts, len(w.gh))
	}
	if w.events[len(w.events)-1] != "verdict" {
		t.Fatal(w.events)
	}
	if worked, err := d.Step(ctx); worked || err != nil {
		t.Fatal("no work expected", err)
	}
}

func TestRefusals(t *testing.T) {
	for name, w := range map[string]*world{
		"budget":  {state: "examining", model: good},
		"edit":    {state: "examining", budget: true, model: `{"goal":"wait","hypothesis":"x","edits":[{"kind":"remove_needs","job":"vet"}]}`},
		"goal":    {state: "examining", budget: true, model: `{"goal":"fun","hypothesis":"x","edits":[]}`},
		"json":    {state: "examining", budget: true, model: `hello`},
		"nothing": {state: "measuring"},
	} {
		d := start(t, w)
		if _, err := d.Step(context.Background()); err != nil || w.stopped == "" {
			t.Fatal(name, err, w.stopped)
		}
	}
	w := &world{state: "examining"}
	d := start(t, w)
	d.GitHub.repo = "other/repo"
	if _, err := d.Step(context.Background()); err != nil || w.stopped == "" {
		t.Fatal(err)
	}
}

func TestRestartAdoptsProposalAndRun(t *testing.T) {
	w := &world{state: "examining", trials: []map[string]any{{"branch": "builddoctor/12345678-trial"}}}
	d := start(t, w)
	if _, err := d.Step(context.Background()); err != nil || len(w.trials) != 1 || w.state != "" {
		t.Fatal(err)
	}
	w.state = "measuring"
	w.gh = []map[string]any{{"id": 7, "status": "completed", "head_sha": "abc", "run_started_at": "2026-11-23T19:44:00Z"}}
	if _, err := d.Step(context.Background()); err != nil || len(w.gh) != 1 || len(w.runs) != 1 {
		t.Fatal(err, w.gh, w.runs)
	}
}

func TestServerErrorsAreRetriedLater(t *testing.T) {
	for _, f := range []string{"GET /api/json/audits", "GET /api/json/trials", "GET /repos/o/r/contents", "GET /repos/o/r/actions/runs", "POST /api/json/events", "GET /api/json/ai_calls", "POST /api/json/trials"} {
		w := &world{state: "examining", model: good, budget: true, fail: f}
		if _, err := start(t, w).Step(context.Background()); err == nil || w.stopped != "" {
			t.Fatal(f, err, w.stopped)
		}
	}
	for _, f := range []string{"GET /api/json/runs", "POST /repos/o/r/git", "PUT /repos", "GET /repos/o/r/actions/runs", "POST /repos/o/r/actions", "POST /api/json/runs"} {
		w := &world{state: "measuring", fail: f, trials: []map[string]any{{"branch": "builddoctor/12345678-trial", "patch": "x"}}}
		if _, err := start(t, w).Step(context.Background()); err == nil || w.stopped != "" {
			t.Fatal(f, err, w.stopped)
		}
	}
}

func TestRunTimeout(t *testing.T) {
	w := &world{state: "measuring", trials: []map[string]any{{"branch": "builddoctor/12345678-trial"}}, gh: []map[string]any{{"id": 7, "status": "in_progress", "run_started_at": "2026-11-23T19:44:00Z"}}}
	d := start(t, w)
	d.RunMax = 50 * time.Millisecond
	if _, err := d.Step(context.Background()); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatal(err)
	}
	w.mu.Lock()
	defer w.mu.Unlock()
	if len(w.progress) == 0 || !strings.Contains(w.progress[0], "done") {
		t.Fatal(w.progress)
	}
}

func TestReadLine(t *testing.T) {
	if readLine(1) != "Read the workflow and 1 job." || readLine(3) != "Read the workflow and 3 jobs." {
		t.Fatal(readLine(1), readLine(3))
	}
}

func TestProgressStages(t *testing.T) {
	w := &world{}
	d := start(t, w)
	err := d.Ash.Progress(context.Background(), "x", 1, "trial", []Job{{Name: "a", Status: "in_progress"}, {Name: "b", Status: "queued"}})
	if strings.Contains(w.progress[0], "_at") {
		t.Fatal("no time without a real start", w.progress)
	}
	now := time.Now()
	if err := d.Ash.Progress(context.Background(), "x", 1, "trial", []Job{{Name: "a", Status: "queued", Started: now}, {Name: "b", Status: "in_progress", Started: now}, {Name: "c", Started: now, Completed: now}}); err != nil {
		t.Fatal(err)
	}
	if got := w.progress[1]; strings.Count(got, "started_at") != 2 || strings.Count(got, "completed_at") != 1 {
		t.Fatal(got)
	}
	if err != nil || !strings.Contains(w.progress[0], "running") || !strings.Contains(w.progress[0], "queued") {
		t.Fatal(err, w.progress)
	}
}
