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
	"slices"
	"strings"
	"sync"
	"testing"
	"time"
)

const sha40 = "0123456789012345678901234567890123456789"

// wood plays GitHub without credentials, OpenAI and the application for many projects.
type wood struct {
	mu       sync.Mutex
	open     map[string]string // audit to repository
	measure  map[string]bool
	done     map[string]string
	errors   map[string]int
	trials   map[string]map[string]any
	logs     []string
	facts    string
	finds    []map[string]any
	notices  []map[string]any
	attempt  string
	asks     []string // answers of the model to the question rounds
	rounds   []string
	asked    int
	final    string
	recorded int
	wait     string
	notes    string
	failed   map[string]string // run to its jobs
	broke    bool              // the budget is used up
	model    string
	repo     string // body of the repository answer
	runs     string
	file     string
	jobs     string
	code     map[string]int // path suffix to status
	header   http.Header
	auth     string
	now, top int // projects at the same time, by their model calls
	slow     time.Duration
}

func newWood() *wood {
	return &wood{
		open: map[string]string{}, measure: map[string]bool{}, done: map[string]string{}, errors: map[string]int{}, trials: map[string]map[string]any{}, code: map[string]int{}, header: http.Header{},
		model: good, repo: `{"private":false,"default_branch":"main"}`, file: wf,
		runs: `{"workflow_runs":[{"id":1,"path":".github/workflows/fast.yml","conclusion":"success","head_sha":"` + sha40 + `","run_started_at":"2026-11-23T10:00:00Z","updated_at":"2026-11-23T10:01:00Z"},{"id":2,"path":".github/workflows/ci.yml@main","conclusion":"success","head_sha":"` + sha40 + `","run_started_at":"2026-11-23T10:00:00Z","updated_at":"2026-11-23T10:09:00Z"},{"id":3,"path":".github/workflows/ci.yml","conclusion":"success","head_sha":"` + sha40 + `","run_started_at":"2026-11-23T10:00:00Z","updated_at":"2026-11-23T11:09:00Z"},{"id":4,"path":"dynamic/codeql","conclusion":"success","head_sha":"` + sha40 + `","run_started_at":"2026-11-23T10:00:00Z","updated_at":"2026-11-23T19:09:00Z"}]}`,
		jobs: `{"total_count":1,"jobs":[{"name":"vet","conclusion":"success","started_at":"2026-11-23T10:00:00Z","completed_at":"2026-11-23T10:00:09Z"}]}`,
	}
}

func (w *wood) ServeHTTP(res http.ResponseWriter, req *http.Request) {
	b, _ := io.ReadAll(req.Body)
	p := req.URL.Path
	beside := strings.Contains(string(b), "describes a software project") || strings.Contains(string(b), "tongue-in-cheek")
	if p == "/v1/responses" && !beside { // one at a time in every project
		w.mu.Lock()
		w.now++
		w.top = max(w.top, w.now)
		w.mu.Unlock()
		time.Sleep(w.slow)
		defer func() { w.mu.Lock(); w.now--; w.mu.Unlock() }()
	}
	w.mu.Lock()
	defer w.mu.Unlock()
	if strings.HasPrefix(p, "/repos/") {
		w.auth += req.Header.Get("Authorization")
	}
	for s, c := range w.code {
		if strings.HasSuffix(p, s) {
			for k, v := range w.header {
				res.Header()[k] = v
			}
			res.WriteHeader(c)
			return
		}
	}
	var d struct {
		Data struct{ Attributes map[string]any }
	}
	json.Unmarshal(b, &d)
	at := d.Data.Attributes
	id := ""
	if parts := strings.Split(p, "/"); len(parts) > 4 && strings.HasPrefix(p, "/api/json/audits/") {
		id = parts[4]
	}
	send := func(v any) { json.NewEncoder(res).Encode(v) }
	end := func(how string) { w.done[id] = how; delete(w.open, id) }
	switch {
	case strings.HasSuffix(p, "/audits/open"):
		out := []any{}
		for id, repo := range w.open {
			state := "examining"
			if w.measure[id] {
				state = "measuring"
			}
			out = append(out, map[string]any{"id": id, "attributes": map[string]any{"state": state, "repository": repo}})
		}
		send(map[string]any{"data": out})
	case strings.HasSuffix(p, "/report_wait"):
		w.wait = fmt.Sprint(at["waiting_until"])
	case strings.HasSuffix(p, "/finish_examination"):
		end("examined")
	case strings.HasSuffix(p, "/stop"):
		end(fmt.Sprint(at["reason"]))
	case strings.HasSuffix(p, "/report_error"):
		if w.errors[id]++; w.errors[id] == 3 {
			end("errors")
		}
	case strings.HasPrefix(p, "/api/json/trials"):
		if req.Method == "POST" {
			w.trials[fmt.Sprint(at["audit_id"])] = at
		} else {
			send(map[string]any{"data": []any{}})
		}
	case strings.HasSuffix(p, "/record_facts"):
		w.facts = fmt.Sprint(at["facts"])
		w.recorded++
	case p == "/api/json/findings":
		if strings.Contains(fmt.Sprint(at["title"]), "invented") {
			res.WriteHeader(400)
			return
		}
		w.finds = append(w.finds, at)
	case p == "/api/json/ai_calls/budget_left":
		send(!w.broke)
	case p == "/api/json/events":
		w.logs = append(w.logs, fmt.Sprint(at["message"]))
	case p == "/v1/responses" && strings.Contains(string(b), "who may ask"):
		text := `{"questions":[]}`
		if len(w.asks) > 0 {
			text, w.asks = w.asks[0], w.asks[1:]
		}
		w.rounds = append(w.rounds, string(b))
		send(map[string]any{"status": "completed", "output": []any{map[string]any{"content": []any{map[string]any{"type": "output_text", "text": text}}}}, "usage": map[string]any{"input_tokens": w.asked, "output_tokens": 6}})
	case p == "/v1/responses" && (strings.Contains(string(b), "describes a software project") || strings.Contains(string(b), "tongue-in-cheek")):
		send(map[string]any{"status": "completed", "output": []any{map[string]any{"content": []any{map[string]any{"type": "output_text", "text": "{}"}}}}, "usage": map[string]any{"input_tokens": 5, "output_tokens": 6}})
	case p == "/v1/responses":
		w.final = string(b)
		send(map[string]any{"status": "completed", "output": []any{map[string]any{"content": []any{map[string]any{"type": "output_text", "text": w.model}}}}, "usage": map[string]any{"input_tokens": 5, "output_tokens": 6}})
	case p == "/api/json/notices":
		w.notices = append(w.notices, at)
	case strings.HasSuffix(p, "/attempts/1"):
		io.WriteString(res, w.attempt)
	case strings.HasSuffix(p, "/annotations"):
		io.WriteString(res, w.notes)
	case strings.HasSuffix(p, "/runs/91/jobs"), strings.HasSuffix(p, "/runs/92/jobs"), strings.HasSuffix(p, "/runs/93/jobs"):
		io.WriteString(res, w.failed[p[len(p)-7:len(p)-5]])
	case strings.HasSuffix(p, "/jobs"):
		io.WriteString(res, w.jobs)
	case strings.HasSuffix(p, "/actions/runs"):
		io.WriteString(res, w.runs)
	case strings.Contains(p, "/contents/"):
		send(map[string]any{"type": "file", "encoding": "base64", "content": base64.StdEncoding.EncodeToString([]byte(w.file))})
	case strings.HasPrefix(p, "/repos/"):
		io.WriteString(res, w.repo)
	}
}

func (w *wood) crew(t *testing.T) (*Crew, *httptest.Server) {
	s := httptest.NewServer(w)
	t.Cleanup(s.Close)
	d := Doctor{NewAsh(s.URL, "secret", s.Client()), NewGitHub(s.URL, "o/r", s.Client()), NewPublic(s.URL, time.Second), NewOpenAI(s.URL, "m", s.Client()), time.Millisecond, time.Second, nil, nil}
	return &Crew{Doctor: d, Rest: time.Millisecond}, s
}

// until runs the crew until the condition holds.
func (w *wood) until(t *testing.T, c *Crew, ok func() bool) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	go func() {
		for ctx.Err() == nil {
			w.mu.Lock()
			if ok() {
				cancel()
			}
			w.mu.Unlock()
			time.Sleep(time.Millisecond)
		}
	}()
	c.Run(ctx)
	if errors.Is(ctx.Err(), context.DeadlineExceeded) {
		t.Fatal("timed out", w.done, w.errors)
	}
}

func TestManyProjectsAtOnce(t *testing.T) {
	w := newWood()
	w.slow = 30 * time.Millisecond
	for i := range 12 {
		w.open[fmt.Sprint("a", i)] = fmt.Sprint("some/project", i)
	}
	c, _ := w.crew(t)
	w.until(t, c, func() bool { return len(w.done) == 12 })
	if w.top != maxExaminations {
		t.Fatal("at the same time:", w.top)
	}
	for id, how := range w.done {
		if how != "examined" || w.trials[id]["original"] != wf {
			t.Fatal(id, how, w.trials[id])
		}
	}
	if w.auth != "" {
		t.Fatal("credentials were sent to the public API")
	}
}

func TestOneBrokenProjectBlocksNobody(t *testing.T) {
	w := newWood()
	w.open["bad"], w.open["good"] = "some/broken", "some/fine"
	w.code["/some/broken"] = 500
	c, _ := w.crew(t)
	w.until(t, c, func() bool { return len(w.done) == 2 })
	if w.done["bad"] != "errors" || w.done["good"] != "examined" {
		t.Fatal(w.done)
	}
}

func TestNothingFound(t *testing.T) {
	w := newWood()
	w.model = `{"goal":"wait","hypothesis":"Fine as it is.","edits":[]}`
	w.file = strings.ReplaceAll(wf, "    runs-on", "    timeout-minutes: 5\n    runs-on")
	w.open["a"] = "some/project"
	c, _ := w.crew(t)
	w.until(t, c, func() bool { return len(w.done) == 1 })
	if w.done["a"] != "examined" || len(w.trials) != 0 || !strings.Contains(strings.Join(w.logs, " "), "No change") {
		t.Fatal(w.done, w.trials, w.logs)
	}
}

func TestCodeRepairsWhatTheAnalystLeaves(t *testing.T) {
	w := newWood()
	w.model = `{"goal":"wait","hypothesis":"Fine as it is.","edits":[]}`
	w.open["a"] = "some/project"
	c, _ := w.crew(t)
	w.until(t, c, func() bool { return len(w.done) == 1 })
	got := w.trials["a"]
	if w.done["a"] != "examined" || got["goal"] != "bill" || !strings.Contains(fmt.Sprint(got["patch"]), "timeout-minutes: 10") || !strings.Contains(fmt.Sprint(got["hypothesis"]), "does not make any step faster") || strings.Contains(strings.Join(w.logs, " "), "No change") {
		t.Fatal(w.done, got, w.logs)
	}
}

func TestForeignProjectsKeepTheirNeeds(t *testing.T) {
	w := newWood() // the analyst proposes remove_needs, which only our own project may get
	w.open["a"] = "some/project"
	c, _ := w.crew(t)
	w.until(t, c, func() bool { return len(w.done) == 1 })
	if w.done["a"] != "examined" || !strings.Contains(fmt.Sprint(w.trials["a"]["patch"]), "needs: vet") || slices.Contains(ForeignKinds, "remove_needs") || !slices.Contains(Kinds, "remove_needs") {
		t.Fatal(w.done, w.trials["a"])
	}
	if got := only([]Edit{{Kind: "remove_needs", Job: "test"}, {Kind: "set_timeout", Job: "test"}}, ForeignKinds); len(got) != 1 || got[0].Kind != "set_timeout" {
		t.Fatal(got)
	}
}

func TestCacheOnlyForSetupActions(t *testing.T) {
	for _, other := range []string{"some/tool@v1", "actions/setup-node@v4", "actions/setup-dotnet@v4", "actions/setup-go@v3", "actions/setup-go@v3.5.0", "actions/setup-go@0123456789012345678901234567890123456789"} {
		if _, err := Apply(strings.Replace(wf, "actions/setup-go@v5", other, 1), []Edit{{Kind: "enable_setup_cache", Job: "vet"}}); err == nil {
			t.Fatal("cache: false was removed for", other)
		}
	}
	before := strings.Replace(wf, "actions/setup-go@v5", "./local-action", 1)
	after := strings.Replace(before, "        with:\n          cache: false\n", "", 1)
	if why, ok := inspect(before, after, nil); ok {
		t.Fatal("the engineer passed it:", why)
	}
	for _, ok := range []string{"actions/setup-go@v5", "actions/setup-go@v4.1.0", "actions/setup-go@v10", "actions/setup-go@40f1582b2485089dde7abd97c1529aa768e1baff"} {
		if got, err := Apply(strings.Replace(wf, "actions/setup-go@v5", ok, 1), []Edit{{Kind: "enable_setup_cache", Job: "vet"}}); err != nil || strings.Contains(got, "cache:") {
			t.Fatal(ok, got, err)
		}
	}
}

func TestNoProposalForAFileTooLongToShow(t *testing.T) {
	w := newWood()
	w.model = `{"goal":"wait","hypothesis":"Fine as it is.","edits":[]}`
	w.file += strings.Repeat("\n", 2_500)
	w.open["a"] = "some/project"
	c, _ := w.crew(t)
	w.until(t, c, func() bool { return len(w.done) == 1 })
	if w.done["a"] != "examined" || w.trials["a"] != nil || !strings.Contains(strings.Join(w.logs, " "), "too long for a proposed change") {
		t.Fatal(w.done, w.trials, w.logs)
	}
}

func TestLimitPausesAndKeepsTheProject(t *testing.T) {
	w := newWood()
	w.open["a"] = "some/project"
	w.code["/some/project"] = 403
	c, _ := w.crew(t)
	w.until(t, c, func() bool { c.mu.Lock(); defer c.mu.Unlock(); return w.wait != "" })
	if w.errors["a"] != 0 || len(w.done) != 0 || c.take(&Audit{ID: "b", State: "examining", Repository: "x/y"}) {
		t.Fatal(w.errors, w.done)
	}
	if !c.take(&Audit{ID: "c", State: "examining", Repository: "o/r"}) {
		t.Fatal("our own project does not need the public API")
	}
}

func TestRoomForWork(t *testing.T) {
	c := &Crew{}
	if !c.take(&Audit{ID: "1", State: "measuring", Repository: "o/r"}) || c.take(&Audit{ID: "1", State: "measuring", Repository: "o/r"}) || c.take(&Audit{ID: "2", State: "measuring", Repository: "o/r"}) {
		t.Fatal("one measurement per repository")
	}
	for i := range maxMeasurements - 1 {
		if !c.take(&Audit{ID: fmt.Sprint("m", i), State: "measuring", Repository: fmt.Sprint("p/", i)}) {
			t.Fatal(i)
		}
	}
	if c.take(&Audit{ID: "more", State: "measuring", Repository: "p/more"}) || !c.take(&Audit{ID: "e", State: "examining", Repository: "o/r"}) {
		t.Fatal("room")
	}
}

func TestReaderRefuses(t *testing.T) {
	for name, change := range map[string]func(*wood){
		"private":     func(w *wood) { w.repo = `{"private":true}` },
		"unknown":     func(w *wood) { w.repo = `{}` },
		"disabled":    func(w *wood) { w.repo = `{"private":false,"disabled":true}` },
		"odd branch":  func(w *wood) { w.repo = `{"private":false,"default_branch":"x;rm -rf"}` },
		"missing":     func(w *wood) { w.code["/some/project"] = 404 },
		"no runs":     func(w *wood) { w.runs = `{"workflow_runs":[]}` },
		"odd paths":   func(w *wood) { w.runs = strings.ReplaceAll(w.runs, ".github/workflows/", "../../") },
		"odd commit":  func(w *wood) { w.runs = strings.ReplaceAll(w.runs, sha40, "main?x=") },
		"no file":     func(w *wood) { w.code["ci.yml"] = 404 },
		"empty file":  func(w *wood) { w.file = "" },
		"huge file":   func(w *wood) { w.file = strings.Repeat("x", 20_001) },
		"no jobs":     func(w *wood) { w.jobs = `{"jobs":[]}` },
		"blocked":     func(w *wood) { w.code["/actions/runs"] = 451 },
		"jobs vanish": func(w *wood) { w.code["/jobs"] = 410 },
	} {
		w := newWood()
		change(w)
		c, _ := w.crew(t)
		var r refused
		if _, err := c.Doctor.Public.Read(context.Background(), "some/project"); !errors.As(err, &r) {
			t.Fatal(name, err)
		}
	}
	c, _ := newWood().crew(t)
	for _, name := range []string{"", "a", "a/b/c", "../x", "a/..", "a/.", "a/b?c", "a/b#", "a/b c", "a/%2e"} {
		var r refused
		if _, err := c.Doctor.Public.Read(context.Background(), name); !errors.As(err, &r) {
			t.Fatal(name, err)
		}
	}
	f, err := c.Doctor.Public.Read(context.Background(), "some/project")
	if err != nil || f.RunID != 2 || f.Path != ".github/workflows/ci.yml" {
		t.Fatal("the newest run of the slowest workflow", f, err)
	}
}

func TestFindingsAreKeptOnlyIfTheApplicationAgrees(t *testing.T) {
	w := newWood()
	w.model = `{"goal":"wait","hypothesis":"x","edits":[],"findings":[{"title":"true","text":"a","advice":"b","evidence":["run"]},{"title":"invented","text":"a","advice":"b","evidence":["run"]}]}`
	w.open["a"] = "some/project"
	c, _ := w.crew(t)
	w.until(t, c, func() bool { return len(w.done) == 1 })
	if len(w.finds) != 1 || !strings.Contains(strings.Join(w.logs, " "), "1 of 2") || !strings.Contains(w.facts, "first start") {
		t.Fatal(w.finds, w.logs, w.facts)
	}
}

func TestFactsStandWithoutTheModel(t *testing.T) {
	w := newWood()
	w.broke = true
	w.open["a"] = "some/project"
	c, _ := w.crew(t)
	w.until(t, c, func() bool { return len(w.done) == 1 })
	if w.done["a"] != "examined" || w.facts == "" || len(w.trials) != 0 {
		t.Fatal(w.done, w.facts)
	}
}

func TestAFailingModelLeavesTheFacts(t *testing.T) {
	for name, change := range map[string]func(*wood){
		"no answer":  func(w *wood) { w.code["/v1/responses"] = 503 },
		"odd answer": func(w *wood) { w.model = "{" },
	} {
		w := newWood()
		change(w)
		w.open["a"] = "some/project"
		c, _ := w.crew(t)
		w.until(t, c, func() bool { return len(w.done) == 1 })
		if w.done["a"] != "examined" || w.facts == "" || len(w.finds)+len(w.trials) != 0 || !strings.Contains(strings.Join(w.logs, " "), "The model did not answer") {
			t.Fatal(name, w.done, w.logs)
		}
	}
}

func TestACouncilWithoutVotesLeavesTheFacts(t *testing.T) {
	w := newTable()
	w.finds, w.fail = []map[string]any{find("f", "x")}, "/v1/responses"
	err := w.doctor(t).council(context.Background(), au, au.Facts, "")
	if !without(context.Background(), err) || w.status["f"] != "" {
		t.Fatal(err, w.status)
	}
	ended, cancel := context.WithCancel(context.Background())
	cancel()
	if without(ended, err) || without(context.Background(), errors.New("x")) || without(context.Background(), nil) {
		t.Fatal("a stop of the agent is no failure of the model")
	}
	end := newWood()
	c, _ := end.crew(t)
	if err := c.Doctor.unfinished(context.Background(), &Audit{ID: "a"}, nil, "why"); err != nil || end.done["a"] != "examined" {
		t.Fatal(err, end.done)
	}
	end.code["/events"] = 500
	if err := c.Doctor.unfinished(context.Background(), &Audit{ID: "a"}, nil, "why"); err == nil {
		t.Fatal("must be tried again")
	}
}

func TestTroubleIsTriedAgain(t *testing.T) {
	for _, part := range []string{"/identify", "/record_facts", "/notices", "/events", "/trials", "/for_audit/a", "/budget_left", "/actions/runs", "ci.yml", "/jobs"} {
		w := newWood()
		if part == "/notices" {
			w.file = "on: pull_request_target\njobs:\n  a:\n    runs-on: x\n    steps:\n      - run: echo ${{ github.event.pull_request.title }}\n"
		}
		w.code[part] = 500
		c, _ := w.crew(t)
		var r refused
		if err := c.Doctor.foreign(context.Background(), &Audit{ID: "a", State: "examining", Repository: "some/project"}); err == nil || errors.As(err, &r) {
			t.Fatal(part, err)
		}
	}
}

func TestForeignProjectIsNeverMeasured(t *testing.T) {
	w := newWood()
	w.open["a"], w.measure["a"] = "some/project", true
	c, _ := w.crew(t)
	w.until(t, c, func() bool { return len(w.done) == 1 })
	if !strings.Contains(w.done["a"], "only be examined") {
		t.Fatal(w.done)
	}
}

func TestRedirectsStayAtHome(t *testing.T) {
	away := httptest.NewServer(http.HandlerFunc(func(res http.ResponseWriter, _ *http.Request) { io.WriteString(res, `{"private":false}`) }))
	defer away.Close()
	home := httptest.NewServer(http.HandlerFunc(func(res http.ResponseWriter, req *http.Request) {
		if req.URL.Path == "/repos/some/renamed" {
			http.Redirect(res, req, "/repositories/1", http.StatusMovedPermanently)
		} else if req.URL.Path == "/repositories/1" {
			io.WriteString(res, `{"private":true}`)
		} else {
			http.Redirect(res, req, away.URL, http.StatusFound)
		}
	}))
	defer home.Close()
	p := NewPublic(home.URL, time.Second)
	var r refused
	if _, err := p.Read(context.Background(), "some/renamed"); !errors.As(err, &r) {
		t.Fatal("followed at home and refused as private", err)
	}
	if _, err := p.Read(context.Background(), "some/away"); err == nil || errors.As(err, &r) {
		t.Fatal("must not leave", err)
	}
}

func TestUsableJobs(t *testing.T) {
	at := time.Date(2026, 11, 23, 10, 0, 0, 0, time.UTC)
	in := []Job{{Name: "skipped", Conclusion: "skipped", Started: at, Completed: at}, {Name: "backwards", Conclusion: "success", Started: at, Completed: at.Add(-time.Second)}, {Name: "no time", Conclusion: "success"}}
	for i := range 14 {
		in = append(in, Job{Name: "test <os>" + strings.Repeat("é", 70), Conclusion: "success", Started: at.Add(-time.Duration(i) * time.Minute), Completed: at})
	}
	in = append(in, Job{Name: "→", Conclusion: "failure", Started: at.Add(-time.Hour), Completed: at})
	out := usable(in, 10)
	if len(out) != 10 || out[0].Name != "job" || out[1].Name != "test os" || out[2].Name != "test os 2" || out[9].Name != "test os 9" {
		t.Fatal(out)
	}
	if !out[0].Started.Before(out[9].Started) {
		t.Fatal("in order of the start")
	}
}

func TestEditsKeepTheRestAsItIs(t *testing.T) {
	src := "# Our pipeline\non: push\n\njobs:\n    build:\n        runs-on: x   # fast\n\n        needs:\n            - test\n            - vet\n        steps: []\n"
	want := "# Our pipeline\non: push\n\njobs:\n    build:\n        runs-on: x   # fast\n\n        steps: []\n"
	if got, err := Apply(src, []Edit{{Kind: "remove_needs", Job: "build"}}); err != nil || got != want {
		t.Fatalf("%v\n%s", err, got)
	}
	// Lines alone cannot express these; the file is written anew and means the same.
	for _, s := range []string{"jobs:\n  build: {needs: test, steps: []}\n", "jobs:\n  build:\n    needs: [test,\n      vet\n    ]\n    steps: []\n"} {
		got, err := Apply(s, []Edit{{Kind: "remove_needs", Job: "build"}})
		if err != nil || strings.Contains(got, "needs") || !strings.Contains(got, "steps") {
			t.Fatalf("%v\n%s", err, got)
		}
	}
}

func TestResetIsBounded(t *testing.T) {
	now := time.Unix(1_000_000, 0)
	for _, c := range []struct {
		h    http.Header
		want time.Duration
	}{
		{http.Header{}, time.Minute},
		{http.Header{"Retry-After": {"120"}}, 2 * time.Minute},
		{http.Header{"Retry-After": {"-5"}}, time.Minute},
		{http.Header{"Retry-After": {"999999"}}, time.Hour},
		{http.Header{"X-Ratelimit-Remaining": {"0"}, "X-Ratelimit-Reset": {"1000600"}}, 10 * time.Minute},
		{http.Header{"X-Ratelimit-Remaining": {"9"}, "X-Ratelimit-Reset": {"1000600"}}, time.Minute},
	} {
		if got := reset(c.h, now).Sub(now); got != c.want {
			t.Fatal(c.h, got)
		}
	}
}
