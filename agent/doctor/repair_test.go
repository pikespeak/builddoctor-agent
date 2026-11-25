package doctor

import (
	"strings"
	"testing"
	"time"
)

func took(name string, seconds int) Job {
	t := time.Date(2026, 11, 25, 10, 0, 0, 0, time.UTC)
	return Job{Name: name, Conclusion: "success", Started: t, Completed: t.Add(time.Duration(seconds) * time.Second)}
}

const twoJobs = "name: CI\non:\n  pull_request:\njobs:\n  # keep me\n  vet:\n    runs-on: ubuntu-latest\n    steps:\n      - run: go vet ./...\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - run: go test ./...\n"

func TestRepair(t *testing.T) {
	patch, text, limit, ok := repair(twoJobs, []Job{took("vet", 30), took("test", 900)})
	if !ok || strings.Count(patch, "timeout-minutes") != 2 || !strings.Contains(patch, "timeout-minutes: 10") || !strings.Contains(patch, "timeout-minutes: 45") || !strings.Contains(patch, "cancel-in-progress") || !strings.Contains(patch, "# keep me") {
		t.Fatal(patch, text, ok)
	}
	if !strings.Contains(text, "gives 2 jobs a time limit") || !strings.Contains(text, "answers what the grade takes points off for: jobs without a time limit and no concurrency rule") || !strings.Contains(text, "does not make any step faster") {
		t.Fatal(text)
	}
	if limit.ID != "limits" || limit.Text != "Longest duration of the jobs read and the limit computed from it: vet 30 s, limit 10 minutes; test 900 s, limit 45 minutes." || len(planOf([]Fact{limit, {ID: "plan"}, {ID: "run"}})) != 2 {
		t.Fatal(limit)
	}
	if why, pass := inspect(twoJobs, patch, nil); !pass {
		t.Fatal("the engineer", why)
	}
	if why, fine := rules(Statement{Title: "Proposed change", Text: text}); !fine {
		t.Fatal("the safety rules", why)
	}

	// A job whose length is not known gets no limit, and then no deduction is said to be answered.
	patch, text, limit, ok = repair(twoJobs, []Job{took("vet", 30)})
	if !ok || strings.Count(patch, "timeout-minutes") != 1 || !strings.Contains(text, "gives 1 job a") || strings.Contains(text, "without a time limit") || !strings.Contains(text, "no concurrency rule") {
		t.Fatal(patch, text, ok)
	}
	// Only limits: pushes to a branch are never ended.
	push := strings.Replace(twoJobs, "pull_request:", "push:", 1)
	if patch, text, limit, ok = repair(push, []Job{took("vet", 30), took("test", 9)}); !ok || strings.Contains(patch, "cancel-in-progress") || strings.Contains(text, "newer push") {
		t.Fatal(patch, text, ok)
	}
	// Only the rule.
	if patch, text, limit, ok = repair(twoJobs, nil); !ok || strings.Contains(patch, "timeout-minutes") || strings.Contains(text, "time limit") || limit.ID != "" {
		t.Fatal(patch, text, ok)
	}
	for name, file := range map[string]string{
		"nothing known": push, "no yaml": ":\n\t", "empty": "", "no jobs": "on: push\n", "odd jobs": "on: push\njobs: [a]\n",
		"complete": strings.ReplaceAll(push, "    runs-on", "    timeout-minutes: 5\n    runs-on"),
		"called":   "on: push\njobs:\n  a:\n    uses: o/r/.github/workflows/x.yml@v1\n",
	} {
		if patch, _, _, ok := repair(file, nil); ok {
			t.Fatal(name, patch)
		}
	}
}

func TestRepairStopsAtTenEdits(t *testing.T) {
	file, jobs := "on: push\njobs:\n", []Job{}
	for i := range 14 {
		n := string(rune('a' + i))
		file += "  " + n + "x:\n    runs-on: ubuntu-latest\n    steps:\n      - run: make\n"
		jobs = append(jobs, took(n+"x", 60))
	}
	patch, text, _, ok := repair(file, jobs)
	if !ok || strings.Count(patch, "timeout-minutes") != 10 || strings.Contains(text, "points off") {
		t.Fatal(patch, text, ok)
	}
}
