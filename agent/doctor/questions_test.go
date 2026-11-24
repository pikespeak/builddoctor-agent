package doctor

import (
	"context"
	"fmt"
	"strings"
	"testing"
)

func curious(asks ...string) *wood {
	w := newWood()
	w.asks, w.asked = asks, 5
	w.open["a"] = "some/project"
	w.jobs = `{"total_count":1,"jobs":[{"name":"vet","conclusion":"success","started_at":"2026-11-23T10:00:00Z","completed_at":"2026-11-23T10:00:09Z","steps":[{"name":"Run <b>vet</b>","started_at":"2026-11-23T10:00:01Z","completed_at":"2026-11-23T10:00:08Z"},{"name":"no end","started_at":"2026-11-23T10:00:01Z"}]}]}`
	return w
}

func round(qs ...string) string {
	out := []string{}
	for _, q := range qs {
		kind, subject, _ := strings.Cut(q, "|")
		out = append(out, fmt.Sprintf(`{"kind":%q,"subject":%q}`, kind, subject))
	}
	return `{"questions":[` + strings.Join(out, ",") + `]}`
}

func TestTheAnalystAsksAndCitesTheAnswers(t *testing.T) {
	w := curious(round("job_steps|vet", "workflow_history|ci.yml", "workflow_file|fast.yml"), round("workflow_failure|fast.yml", "job_history|vet"))
	c, _ := w.crew(t)
	w.until(t, c, func() bool { return len(w.done) == 1 })
	for _, want := range []string{
		`Longest steps of job "vet": "Run b vet /b" 7 s.`,
		"Workflow ci.yml: of the runs that were read, 2 succeeded and 0 failed.",
		"Workflow file fast.yml: recognized triggers: push; jobs written: 2; no concurrency rule at the top; checker notes: 0.",
		"Workflow fast.yml: none of its runs that were read failed.",
		`Job "vet" took 9 s in an earlier successful run.`,
		"ask5",
	} {
		if !strings.Contains(w.facts, want) {
			t.Fatalf("missing %q in %s", want, w.facts)
		}
	}
	logs := strings.Join(w.logs, "\n")
	if w.done["a"] != "examined" || w.recorded != 2 || len(w.rounds) != 3 || !strings.Contains(w.final, "ask5") || !strings.Contains(logs, "The analyst asked: the steps of job vet.") || strings.Contains(logs, "<") {
		t.Fatal(w.done, w.recorded, len(w.rounds), logs)
	}
	if !strings.Contains(w.rounds[1], "ask1") || strings.Contains(w.rounds[0], "ask1") {
		t.Fatal("the second round knows the first answers")
	}
}

func TestQuestionsEnd(t *testing.T) {
	again := round("job_steps|vet")
	for name, c := range map[string]struct {
		w      *wood
		rounds int
	}{
		"nothing to ask":   {curious(), 1},
		"the same again":   {curious(again, again, again), 2},
		"unknown names":    {curious(round("job_steps|../x", "workflow_file|https://evil.example", "workflow_history|", "run_shell|ls")), 1},
		"three rounds":     {curious(again, round("workflow_history|ci.yml"), round("workflow_history|fast.yml"), round("workflow_failure|ci.yml")), 3},
		"too many tokens":  {func() *wood { w := curious(again, round("workflow_history|ci.yml")); w.asked = 30_000; return w }(), 1},
		"an odd answer":    {curious("{"), 1},
		"a long wish list": {curious(round("workflow_history|ci.yml", "workflow_history|fast.yml", "job_steps|vet", "workflow_failure|ci.yml")), 2},
	} {
		cr, _ := c.w.crew(t)
		c.w.until(t, cr, func() bool { return len(c.w.done) == 1 })
		if c.w.done["a"] != "examined" || len(c.w.rounds) != c.rounds || strings.Contains(c.w.facts, "evil") || strings.Contains(c.w.facts, "ask4") {
			t.Fatal(name, c.w.done, len(c.w.rounds), c.w.facts)
		}
	}
}

func TestQuestionsStopWithTheBudgetAndReportTrouble(t *testing.T) {
	w := curious(round("job_steps|vet"))
	w.broke = true
	c, _ := w.crew(t)
	w.until(t, c, func() bool { return len(w.done) == 1 })
	if len(w.rounds) != 0 || w.done["a"] != "examined" {
		t.Fatal(w.rounds, w.done)
	}
	f := Reading{All: []Job{{Name: "vet"}}, Runs: map[string][]past{}}
	for _, part := range []string{"/budget_left", "/ai_calls", "/events"} {
		w := curious(round("workflow_failure|ci.yml"))
		f.Runs[".github/workflows/ci.yml"] = []past{{Conclusion: "success"}}
		w.code[part] = 500
		c, _ := w.crew(t)
		if _, err := c.Doctor.wonder(context.Background(), &Audit{ID: "a"}, f, nil); err == nil {
			t.Fatal(part)
		}
	}
	w = curious()
	w.code["/v1/responses"] = 503
	c, _ = w.crew(t)
	if got, err := c.Doctor.wonder(context.Background(), &Audit{ID: "a"}, f, []Fact{{ID: "run"}}); err != nil || len(got) != 1 {
		t.Fatal("a model that fails ends only the questions", got, err)
	}
}

func TestAnswers(t *testing.T) {
	w := newWood()
	w.failed = map[string]string{"91": failedJobs("Unit")}
	c, s := w.crew(t)
	p, ctx := c.Doctor.Public, context.Background()
	ci := ".github/workflows/ci.yml"
	f := Reading{Path: ci, SHA: sha40, RunID: 1, base: "/repos/some/project", All: []Job{{Name: "vet"}}, Runs: map[string][]past{
		ci:                          {{ID: 1, Conclusion: "success", Seconds: 9}, {ID: 91, Conclusion: "failure"}, {ID: 2, Conclusion: "success", Seconds: 8}, {ID: 3, Conclusion: "success", Seconds: 7}, {ID: 4, Conclusion: "success", Seconds: 7}},
		".github/workflows/odd.yml": {{Conclusion: "cancelled"}},
	}}
	ask := func(kind, subject string, looks int) (string, bool) {
		return p.answer(ctx, f, Question{kind, subject}, &looks)
	}
	for kind, want := range map[string]string{
		"workflow_failure": `Workflow ci.yml: in its newest failed run, step "Unit" of job "scan b" failed.`,
		"workflow_history": "4 succeeded and 1 failed. The median of the successful runs, rounded, is 8 s.",
	} {
		if got, ok := ask(kind, "ci.yml", 0); !ok || !strings.Contains(got, want) {
			t.Fatal(kind, got)
		}
	}
	if got, ok := ask("job_history", "vet", 0); !ok || !strings.HasSuffix(got, "first: 9 s, 9 s.") {
		t.Fatal(got)
	}
	for name, q := range map[string]Question{
		"no steps": {"job_steps", "vet"}, "nothing finished": {"workflow_history", "odd.yml"}, "unknown kind": {"x", "ci.yml"}, "no file": {"workflow_file", "no.yml"},
	} {
		if got, ok := ask(q.Kind, q.Subject, 0); ok {
			t.Fatal(name, got)
		}
	}
	for _, kind := range []string{"workflow_failure", "workflow_file"} {
		if got, ok := ask(kind, "ci.yml", maxLooks); ok {
			t.Fatal("too many looks", kind, got)
		}
	}
	if got, ok := ask("job_history", "vet", maxLooks); ok {
		t.Fatal(got)
	}
	w.file = "on: pull_request_target\nconcurrency: x\njobs:\n  a:\n    runs-on: x\n    steps:\n      - run: echo ${{ github.event.pull_request.title }}\n"
	if got, ok := ask("workflow_file", "ci.yml", 0); !ok || !strings.Contains(got, "a concurrency rule") || !strings.Contains(got, "checker notes: 0") || !strings.Contains(got, "none of the common ones") || strings.Contains(got, "untrusted") {
		t.Fatal("what could be used is not told", got)
	}
	for _, odd := range []string{"", "a: [", strings.Repeat("x", 20_001)} {
		w.file = odd
		if got, ok := ask("workflow_file", "ci.yml", 0); ok {
			t.Fatal(got)
		}
	}
	w.jobs = `{"jobs":[{"name":"other","conclusion":"success","started_at":"2026-11-23T10:00:00Z","completed_at":"2026-11-23T10:00:09Z"}]}`
	if got, ok := ask("job_history", "vet", 0); ok {
		t.Fatal("the job is not in the earlier run", got)
	}
	s.Close()
	for _, kind := range []string{"job_history", "workflow_failure", "workflow_file"} {
		subject := "ci.yml"
		if kind == "job_history" {
			subject = "vet"
		}
		if got, ok := ask(kind, subject, 0); ok {
			t.Fatal(kind, got)
		}
	}
}

func TestMedian(t *testing.T) {
	for _, c := range []struct {
		in   []int
		want int
	}{{[]int{5}, 5}, {[]int{9, 1}, 5}, {[]int{3, 1, 2}, 2}, {[]int{4, 1, 2, 9}, 3}} {
		if got := median(c.in); got != c.want {
			t.Fatal(c.in, got)
		}
	}
	if got, _ := workflowHistory("x", []past{{Conclusion: "success", Seconds: 7}}); !strings.HasSuffix(got, "The successful run took 7 s.") {
		t.Fatal(got)
	}
}

func TestAfterARestartTheStoredFactsStay(t *testing.T) {
	w := newTable()
	w.finds = []map[string]any{find("f", "x")}
	w.status["f"] = "pending"
	wd := newWood()
	c, _ := wd.crew(t)
	d := c.Doctor
	d.Ash = w.doctor(t).Ash
	d.OpenAI = w.doctor(t).OpenAI
	if err := d.foreign(context.Background(), &Audit{ID: "a", State: "examining", Repository: "some/project", Facts: []Fact{{ID: "run", Text: "It took 5 s."}, {ID: "ask1", Text: "Stored before."}}}); err != nil {
		t.Fatal(err)
	}
	if len(wd.rounds) != 0 || !strings.Contains(strings.Join(w.calls, " "), "Stored before.") {
		t.Fatal(wd.rounds, w.calls)
	}
}
