package doctor

import (
	"strings"
	"testing"
	"time"
)

func text(facts []Fact) string {
	out := []string{}
	for _, f := range facts {
		out = append(out, f.ID+": "+f.Text)
	}
	return strings.Join(out, "\n")
}

func TestFacts(t *testing.T) {
	at := func(s int) time.Time {
		return time.Date(2026, 11, 24, 10, 0, 0, 0, time.UTC).Add(time.Duration(s) * time.Second)
	}
	jobs := []Job{
		{Name: "lint", Conclusion: "success", Created: at(0), Started: at(2), Completed: at(27), Steps: []Step{{"Set up job", at(2), at(4)}, {"Run lint", at(4), at(26)}}},
		{Name: "mac <b>", Conclusion: "success", Created: at(28), Started: at(246), Completed: at(320), Steps: []Step{{"Set up job", at(246), at(250)}, {"Run Tests", at(250), at(318)}, {"no end", at(318), time.Time{}}, {"backwards", at(319), at(318)}}},
		{Name: "win", Conclusion: "failure", Created: at(28), Started: at(40), Completed: at(60)},
		{Name: "never", Conclusion: "skipped", Started: at(1), Completed: at(1)},
		{Name: "broken", Conclusion: "success", Started: at(9), Completed: at(1)},
	}
	history := []past{{Conclusion: "success", Seconds: 300}, {Conclusion: "failure", Seconds: 20}, {Conclusion: "success", Seconds: 320}, {Conclusion: "success", Seconds: 310}, {Conclusion: "cancelled", Seconds: 1}}
	got := text(Facts("on: push\njobs:\n  lint:\n    steps: []\n  mac:\n    needs: lint\n    timeout-minutes: 5\n", jobs, history))
	for _, want := range []string{
		"run: The jobs took 318 s from the first start to the last end. Jobs read: 3.",
		`last: The last job to end was "mac b". It started after 244 s and ran for 74 s.`,
		`queue: Jobs that waited at least 10 s for a runner: 2. The longest wait was 218 s, for "mac b".`,
		`step1: Step "Run Tests": 68 s in total. Jobs that ran it: 1 of 3. The longest took 68 s.`,
		"setup: Setup, checkout, cache and cleanup steps: 6 s, 6% of all step time.",
		"failed: Of the last 5 finished runs of this workflow, 1 failed.",
		"history: Successful runs in that list: 3. Median, rounded, 310 s, fastest 300 s, slowest 320 s.",
		"concurrency: ", "timeout: Jobs without timeout-minutes: lint.", "needs: Jobs that use needs to wait for other jobs: mac.",
	} {
		if !strings.Contains(got, want) {
			t.Fatalf("missing %q in\n%s", want, got)
		}
	}
	if strings.Contains(got, "<") {
		t.Fatal(got)
	}
}

func TestFactsWithLittleData(t *testing.T) {
	if len(Facts("", nil, nil)) != 0 {
		t.Fatal("nothing is nothing")
	}
	at := time.Now()
	got := text(Facts("a: [", []Job{{Name: "→", Conclusion: "success", Started: at, Completed: at}}, []past{{Conclusion: "failure", Seconds: 1}, {Conclusion: "failure", Seconds: 1}, {Conclusion: "failure", Seconds: 1}}))
	if !strings.Contains(got, `"unnamed"`) || !strings.Contains(got, "3 failed") || strings.Contains(got, "history") || strings.Contains(got, "setup") || !strings.Contains(got, "No job is known") {
		t.Fatal(got)
	}
	for _, w := range []string{"concurrency: x\njobs: []", "concurrency: x\njobs:\n  a:\n    uses: ./x.yml\n"} {
		if len(written(w)) != 0 {
			t.Fatal(written(w))
		}
	}
}
