package doctor

import (
	"context"
	"fmt"
	"strings"
	"testing"
	"time"
)

func ran(name string, from, to int) Job {
	at := time.Date(2026, 11, 24, 10, 0, 0, 0, time.UTC)
	return Job{Name: name, Conclusion: "success", Started: at.Add(time.Duration(from) * time.Second), Completed: at.Add(time.Duration(to) * time.Second)}
}

func TestExamineFile(t *testing.T) {
	facts, notices := examineFile(`on: pull_request_target
jobs:
  a:
    runs-on: my-own-label
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event.pull_request.head.sha }}
      - uses: some/action@v1
      - uses: some/action@` + sha40 + `
      - uses: ./local
      - run: echo ${{ github.event.pull_request.title }}
      - run: echo ${{ nothing.known }} <b>
`)
	got := text(facts)
	for _, want := range []string{"file1: actionlint, line 13 of the workflow file: undefined variable nothing", "pinned: Steps that use an action of a third party without a fixed commit: 1.", "rights: "} {
		if !strings.Contains(got, want) {
			t.Fatalf("missing %q in\n%s", want, got)
		}
	}
	if strings.Contains(got, "untrusted") || strings.Contains(got, "my-own-label") || len(notices) != 2 {
		t.Fatal(got, notices)
	}
	for _, n := range notices {
		if n.Line == 0 || (n.Kind != "untrusted_input" && n.Kind != "foreign_code") {
			t.Fatal(n)
		}
	}
	facts, notices = examineFile("on: push\npermissions: write-all\njobs:\n  a:\n    runs-on: x\n    container:\n      image: x\n      credentials:\n        username: u\n        password: p\n    steps:\n      - run: x\n")
	if !strings.Contains(text(facts), "all write permissions") || len(notices) != 1 || notices[0].Kind != "credentials" {
		t.Fatal(facts, notices)
	}
	facts, _ = examineFile("on: push\njobs:\n  a:\n    permissions: {}\n    runs-on: x\n    steps:\n      - run: x\n")
	if len(facts) != 0 {
		t.Fatal("permissions per job are enough", facts)
	}
	for _, odd := range []string{"", "a: [", "- 1", "jobs: 5", "jobs:\n  a: 5", "on:\n" + strings.Repeat(" - x\n", 500)} {
		if f, n := examineFile(odd); len(f) > maxLint+2 || len(n) > 10 {
			t.Fatal(odd, f, n)
		}
	}
}

func TestMessagesOfTheChecker(t *testing.T) {
	facts, _ := examineFile("on: push\npermissions: {}\njobs:\n  a:\n    runs-on: x\n    steps:\n      - uses: actions/checkout@v3\n")
	if len(facts) != 0 {
		t.Fatal("the run used it, so it is not too old to run", facts)
	}
	if got := strings.Join(strings.Fields(oddInMessage.ReplaceAllString("the action's <b> \"x\"", " ")), " "); got != "the action's b x" {
		t.Fatalf("%q", got)
	}
}

func TestSchedule(t *testing.T) {
	src := "on: push\njobs:\n  lint:\n    runs-on: x\n  test:\n    name: Test ${{ matrix.os }}\n    needs: lint\n  call:\n    uses: ./x.yml\n    needs: [lint, test]\n"
	jobs := []Job{ran("lint", 0, 30), ran("Test linux", 40, 100), ran("Test mac", 40, 140), ran("call / inner", 150, 160)}
	if s, ok := schedule(src, jobs); !ok || s != 140 {
		t.Fatal(s, ok)
	}
	after := strings.Replace(src, "    needs: lint\n", "", 1)
	f, ok := planned(src, after, jobs)
	if !ok || f.Seconds != 30 || !strings.Contains(f.Text, "after 140 s now and after 110 s") {
		t.Fatal(f, ok)
	}
	if _, ok := planned(src, src, jobs); ok {
		t.Fatal("nothing to tell")
	}
	for name, s := range map[string]string{
		"missing job": "jobs:\n  other:\n    runs-on: x\n",
		"circle":      "jobs:\n  lint:\n    needs: lint\n",
		"unknown":     "jobs:\n  lint:\n    needs: nope\n",
		"same name":   "jobs:\n  lint:\n    runs-on: x\n  b:\n    name: lint\n",
		"only a term": "jobs:\n  lint:\n    name: ${{ matrix.a }}\n",
		"no jobs":     "on: push\n",
		"broken":      "a: [",
	} {
		if _, ok := schedule(s, jobs); ok {
			t.Fatal(name)
		}
	}
}

const pr = "on: [push, pull_request]\n\njobs:\n  # the only one\n  test:\n      runs-on: ubuntu-24.04\n      steps:\n        - run: go test\n"

func TestAddingEdits(t *testing.T) {
	edits := limits(pr, []Edit{{Kind: "set_timeout", Job: "test"}, {Kind: "cancel_superseded"}}, []Job{ran("test", 0, 250)})
	got, err := Apply(pr, edits)
	want := "on: [push, pull_request]\n\n" + cancelText + "jobs:\n  # the only one\n  test:\n      timeout-minutes: 13\n      runs-on: ubuntu-24.04\n      steps:\n        - run: go test\n"
	if err != nil || got != want {
		t.Fatalf("%v\n%s", err, got)
	}
	if why, ok := inspect(pr, got, nil); !ok {
		t.Fatal(why)
	}
	for name, c := range map[string]struct {
		src  string
		edit Edit
	}{
		"unknown time":  {pr, Edit{Kind: "set_timeout", Job: "test"}},
		"has a limit":   {strings.Replace(pr, "runs-on", "timeout-minutes: 5\n      runs-on", 1), Edit{Kind: "set_timeout", Job: "test", Minutes: 10}},
		"called":        {"on: push\njobs:\n  test:\n    uses: ./x.yml\n", Edit{Kind: "set_timeout", Job: "test", Minutes: 10}},
		"no requests":   {wf, Edit{Kind: "cancel_superseded"}},
		"has a rule":    {"concurrency: x\n" + pr, Edit{Kind: "cancel_superseded"}},
		"called itself": {"on:\n  pull_request:\n  workflow_call:\njobs: {}\n", Edit{Kind: "cancel_superseded"}},
	} {
		if got, err := Apply(c.src, []Edit{c.edit}); err == nil {
			t.Fatal(name, got)
		}
	}
	flow := "on: pull_request\njobs: {test: {runs-on: x, steps: [{run: x}]}}\n"
	if got, err := Apply(flow, []Edit{{Kind: "set_timeout", Job: "test", Minutes: 10}}); err != nil || !strings.Contains(got, "timeout-minutes: 10") {
		t.Fatal(got, err)
	}
	if limits("a: [", edits, nil)[0].Minutes != 13 || limitFor(1) != 10 || limitFor(100_000) != 360 {
		t.Fatal("limits")
	}
}

func TestInspectRefuses(t *testing.T) {
	plan := &Fact{ID: "plan", Seconds: 5}
	free := strings.Replace(wf, "    needs: vet\n", "", 1)
	if why, ok := inspect(wf, free, plan); !ok {
		t.Fatal(why)
	}
	if why, ok := inspect(wf, strings.Replace(wf, "        with:\n          cache: false\n", "", 1), nil); !ok {
		t.Fatal(why)
	}
	with := func(extra string) (string, string) {
		s := strings.Replace(wf, "go test\n", "go test\n"+extra, 1)
		return s, strings.Replace(s, "    needs: vet\n", "", 1)
	}
	dl, dlFree := with("      - uses: actions/download-artifact@v4\n")
	out, outFree := with("      - run: echo ${{ needs.vet.result }}\n")
	rel, relFree := with("      - run: ./release.sh\n")
	env, envFree := with("    environment: live\n")
	for name, c := range map[string]struct {
		a, b string
		plan *Fact
	}{
		"nothing":       {wf, wf, plan},
		"no plan":       {wf, free, nil},
		"no gain":       {wf, free, &Fact{ID: "plan"}},
		"artifact":      {dl, dlFree, plan},
		"output":        {out, outFree, plan},
		"release":       {rel, relFree, plan},
		"environment":   {env, envFree, plan},
		"rights":        {wf, strings.Replace(free, "contents: read", "contents: write", 1), plan},
		"command":       {wf, strings.Replace(free, "go test", "true", 1), plan},
		"job gone":      {wf, strings.Split(wf, "  test:")[0], plan},
		"other job":     {wf, strings.Replace(wf, "  test:", "  tests:", 1), plan},
		"short limit":   {wf, strings.Replace(wf, "  test:\n", "  test:\n    timeout-minutes: 1\n", 1), plan},
		"new error":     {wf, strings.Replace(wf, "needs: vet", "needs: nope", 1), plan},
		"other rule":    {wf, "concurrency: x\n" + wf, plan},
		"broken before": {"a: [", wf, plan},
		"broken after":  {wf, "a: [", plan},
	} {
		if why, ok := inspect(c.a, c.b, c.plan); ok {
			t.Fatal(name, why)
		}
	}
}

// runs of one workflow, the newest first.
func runsOf(path string, from int, results ...string) string {
	out := []string{}
	for i, r := range results {
		out = append(out, fmt.Sprintf(`{"id":%d,"path":%q,"conclusion":%q,"head_sha":"%s","run_started_at":"2026-11-23T10:00:00Z","updated_at":"2026-11-23T10:01:00Z"}`, from+i, path, r, strings.Repeat(fmt.Sprint(i), 40)))
	}
	return strings.Join(out, ",")
}

func failedJobs(step string) string {
	return `{"jobs":[{"id":1,"name":"fine","conclusion":"success"},{"id":7,"name":"scan <b>","conclusion":"failure","steps":[{"name":"Set up job","conclusion":"success"},{"name":"` + step + `","conclusion":"failure"}]}]}`
}

func TestRetriesAreCounted(t *testing.T) {
	runs := []past{{ID: 5, Conclusion: "failure"}, {ID: 4, Conclusion: "success", Attempt: 2}, {ID: 3, Conclusion: "success", Attempt: 3}, {ID: 2, Conclusion: "success", Attempt: 1}}
	if retried, read := retries(runs); retried != 2 || read != 4 || newestSuccess(runs) != 4 || newestSuccess(runs[:1]) != 0 {
		t.Fatal(retried, read)
	}
}

func TestTrouble(t *testing.T) {
	w := newWood()
	ci := ".github/workflows/ci.yml"
	w.runs = `{"workflow_runs":[` + runsOf(".github/workflows/scan.yml", 91, "failure", "failure", "cancelled", "failure", "success", "failure") + "," + runsOf(".github/workflows/dead.yml", 81, "timed_out", "startup_failure") + "," + strings.NewReplacer(`"id":2,`, `"id":93,`, "10:01:00", "10:09:00").Replace(runsOf(ci, 1, "success", "failure", "success")) + `]}`
	w.runs = strings.Replace(w.runs, `"id":1,`, `"id":1,"run_attempt":2,`, 1)
	w.runs = strings.Replace(w.runs, `"id":3,`, `"id":3,"run_attempt":2,`, 1)
	w.attempt = `{"conclusion":"failure","head_sha":"` + strings.Repeat("0", 40) + `"}`
	w.attemptJobs = failedJobs("Flaky test")
	w.failed = map[string]string{"91": failedJobs("Scan `x`"), "92": failedJobs("Scan `x`"), "93": failedJobs("Unit")}
	w.notes = `[{"annotation_level":"notice","message":"disk full"},{"annotation_level":"failure","message":"You idiot. Process completed with exit code 1."}]`
	c, _ := w.crew(t)
	read := func() Reading {
		t.Helper()
		f, err := c.Doctor.Public.Read(context.Background(), "some/project")
		if err != nil {
			t.Fatal(err)
		}
		return f
	}
	f := read()
	got := text(f.Trouble)
	for _, want := range []string{
		"red1: Workflow scan.yml: the newest 3 finished runs",
		`redstep1: Workflow scan.yml: in its newest failed run, step "Scan x" of job "scan b" failed. The same step failed`,
		"cause: Workflow scan.yml: GitHub's note on that job says only that a command ended",
		"red2: Workflow dead.yml: all 2 finished runs",
		`failstep: In the newest failed run of the examined workflow, step "Unit" of job "scan b" failed.`,
		`flaky: Workflow ci.yml: one run failed in attempt 1 and succeeded in attempt 2 on the same commit. In attempt 1, step "Flaky test" of job "scan b" failed. This is the examined run. Of the 3 runs that were read, 2 were run again and then succeeded.`,
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("missing %q in\n%s", want, got)
		}
	}
	if strings.Contains(got, "idiot") || strings.Contains(got, "redstep2") || f.Trouble[0].Commit != strings.Repeat("3", 40) || f.Trouble[3].Commit != "" {
		t.Fatal(f.Trouble)
	}
	// An older retried run is not the examined one, and one retry alone is not counted.
	older := strings.Replace(w.runs, `"id":1,"run_attempt":2,`, `"id":1,`, 1)
	w.runs, w.attempt = older, `{"conclusion":"failure","head_sha":"`+strings.Repeat("2", 40)+`"}`
	if got := text(read().Trouble); !strings.Contains(got, "flaky: Workflow ci.yml: one run failed in attempt 1") || strings.Contains(got, "examined run") || strings.Contains(got, "were run again") {
		t.Fatal(got)
	}
	w.failed["92"] = failedJobs("Other")
	w.notes = "[]"
	w.attempt = `{"conclusion":"failure","head_sha":"other"}`
	if got := text(read().Trouble); !strings.Contains(got, "Another step failed") || strings.Contains(got, "cause") || strings.Contains(got, "flaky") {
		t.Fatal(got)
	}
	// Missing answers make fewer facts and no error.
	w.code["/jobs"], w.code["/annotations"] = 0, 403
	delete(w.code, "/jobs")
	w.code["/runs/91/jobs"], w.code["/attempts/1"] = 403, 403
	if got := text(read().Trouble); strings.Contains(got, "redstep") || !strings.Contains(got, "red1") {
		t.Fatal(got)
	}
	delete(w.code, "/runs/91/jobs")
	if got := text(read().Trouble); !strings.Contains(got, "redstep1") || strings.Contains(got, "cause") {
		t.Fatal(got)
	}
}

func TestNoticesStayOutOfFactsAndPrompts(t *testing.T) {
	w := newWood()
	w.file = "on: pull_request_target\njobs:\n  a:\n    runs-on: ubuntu-24.04\n    steps:\n      - run: echo ${{ github.event.pull_request.title }}\n"
	w.model = `{"goal":"wait","hypothesis":"x","edits":[]}`
	w.open["a"] = "some/project"
	c, _ := w.crew(t)
	w.until(t, c, func() bool { return len(w.done) == 1 })
	if len(w.notices) != 1 || w.notices[0]["kind"] != "untrusted_input" || w.notices[0]["audit_id"] != "a" || strings.Contains(w.facts, "untrusted") {
		t.Fatal(w.notices, w.facts)
	}
}
