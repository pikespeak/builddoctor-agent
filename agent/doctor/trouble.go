package doctor

import (
	"context"
	"fmt"
	"path"
	"regexp"
	"slices"
)

// past is one earlier run of a workflow on the default branch, the newest first.
type past struct {
	ID         int64
	Conclusion string
	Seconds    int
	SHA        string
	Attempt    int
}

const maxRed = 2 // workflows whose failures are looked at; every look costs a request

// trouble tells which workflows fail and where. It needs up to six more requests. Every answer is
// optional: without it there are fewer facts, never wrong ones.
func (p Public) trouble(ctx context.Context, base string, all map[string][]past, examined string) []Fact {
	type red struct {
		path     string
		runs     []past // the failed ones at the top
		all      bool
		readable int
	}
	list, paths, out := []red{}, []string{}, []Fact{}
	for path := range all {
		paths = append(paths, path)
	}
	slices.Sort(paths)
	for _, path := range paths {
		r, stopped := red{path: path}, false
		for _, run := range all[path] {
			switch run.Conclusion {
			case "failure", "timed_out", "startup_failure":
				r.readable++
				if !stopped {
					r.runs = append(r.runs, run)
				}
			case "success":
				r.readable++
				stopped = true
			}
		}
		r.all = !stopped
		if len(r.runs) >= 2 { // one red run says little
			list = append(list, r)
		}
	}
	slices.SortStableFunc(list, func(a, b red) int { return len(b.runs) - len(a.runs) })
	looked := []func() ([]Fact, error){}
	for i, r := range list[:min(maxRed, len(list))] {
		looked = append(looked, async(func() (facts []Fact, _ error) {
			n, name, first := i+1, plainName(path.Base(r.path)), r.runs[len(r.runs)-1]
			f := Fact{ID: fmt.Sprint("red", n), Text: fmt.Sprintf("Workflow %s: the newest %d finished runs on the default branch failed. Canceled runs are left out. The run before them succeeded.", name, len(r.runs)), Commit: first.SHA}
			if r.all {
				f.Text, f.Commit = fmt.Sprintf("Workflow %s: all %d finished runs on the default branch that were read failed.", name, r.readable), ""
			}
			facts = append(facts, f)
			newest, ok := p.failed(ctx, base, r.runs[0].ID)
			if !ok {
				return facts, nil
			}
			f = Fact{ID: fmt.Sprint("redstep", n), Text: fmt.Sprintf("Workflow %s: in its newest failed run, step %q of job %q failed.", name, newest.step, newest.job)}
			if i == 0 {
				if before, ok := p.failed(ctx, base, r.runs[1].ID); ok {
					if before.step == newest.step && before.job == newest.job {
						f.Text += " The same step failed in the failed run before it."
					} else {
						f.Text += " Another step failed in the failed run before it."
					}
				}
			}
			facts = append(facts, f)
			if i == 0 {
				if why := p.cause(ctx, base, newest.id); why != "" {
					facts = append(facts, Fact{ID: "cause", Text: fmt.Sprintf("Workflow %s: GitHub's note on that job says %s.", name, why)})
				}
			}
			return facts, nil
		}))
	}
	for _, wait := range looked {
		facts, _ := wait()
		out = append(out, facts...)
	}
	// The examined workflow may be green now and still fail now and then.
	if !slices.ContainsFunc(list[:min(maxRed, len(list))], func(r red) bool { return r.path == examined }) {
		for _, run := range all[examined] {
			if run.Conclusion != "failure" && run.Conclusion != "timed_out" {
				continue
			}
			if f, ok := p.failed(ctx, base, run.ID); ok {
				out = append(out, Fact{ID: "failstep", Text: fmt.Sprintf("In the newest failed run of the examined workflow, step %q of job %q failed.", f.step, f.job), Commit: run.SHA})
			}
			break
		}
	}
	for _, at := range paths {
		for _, run := range all[at] {
			if run.Attempt < 2 || run.Conclusion != "success" {
				continue
			}
			var r struct {
				Conclusion string
				SHA        string `json:"head_sha"`
			}
			if p.c.do(ctx, "GET", fmt.Sprintf("%s/actions/runs/%d/attempts/1", base, run.ID), nil, &r) == nil && r.Conclusion == "failure" && r.SHA == run.SHA {
				text := fmt.Sprintf("Workflow %s: one run failed in attempt 1 and succeeded in attempt %d on the same commit.", plainName(path.Base(at)), run.Attempt)
				// Which step failed the first time, so that a pass on retry does not hide it (feedback, 2026-11-26).
				if f, ok := p.failedIn(ctx, base, fmt.Sprintf("%d/attempts/1", run.ID)); ok {
					text += fmt.Sprintf(" In attempt 1, step %q of job %q failed.", f.step, f.job)
				}
				if at == examined && newestSuccess(all[at]) == run.ID {
					text += " This is the examined run."
				}
				if retried, read := retries(all[at]); retried > 1 {
					text += fmt.Sprintf(" Of the %d runs that were read, %d were run again and then succeeded.", read, retried)
				}
				out = append(out, Fact{ID: "flaky", Text: text, Commit: run.SHA})
			}
			return out // one look is enough
		}
	}
	return out
}

// newestSuccess is the ID of the newest successful run, the one that is examined for its workflow.
func newestSuccess(runs []past) int64 {
	for _, r := range runs {
		if r.Conclusion == "success" {
			return r.ID
		}
	}
	return 0
}

// retries counts the successful runs that were run again (attempt 2 or later), among the runs that were read.
// A rerun of a run that had already succeeded counts too; GitHub's list shows only the last attempt.
func retries(runs []past) (retried, read int) {
	for _, r := range runs {
		if r.Attempt >= 2 && r.Conclusion == "success" {
			retried++
		}
	}
	return retried, len(runs)
}

type failure struct {
	id        int64
	job, step string
}

// failed finds the first failed step of a run, in its latest attempt.
func (p Public) failed(ctx context.Context, base string, run int64) (failure, bool) {
	return p.failedIn(ctx, base, fmt.Sprint(run))
}

// failedIn finds the first failed step in "<run>" or "<run>/attempts/<n>".
func (p Public) failedIn(ctx context.Context, base, run string) (failure, bool) {
	var r struct {
		Jobs []struct {
			ID         int64
			Name       string
			Conclusion string
			Steps      []struct{ Name, Conclusion string }
		}
	}
	if p.c.do(ctx, "GET", fmt.Sprintf("%s/actions/runs/%s/jobs?per_page=100", base, run), nil, &r) != nil {
		return failure{}, false
	}
	for _, j := range r.Jobs {
		if j.Conclusion != "failure" && j.Conclusion != "timed_out" {
			continue
		}
		for _, s := range j.Steps {
			if s.Conclusion == "failure" || s.Conclusion == "timed_out" {
				return failure{j.ID, plainName(j.Name), plainName(s.Name)}, true
			}
		}
	}
	return failure{}, false
}

// Notes of foreign projects are sorted into known causes; their words are never repeated.
var causes = []struct {
	found *regexp.Regexp
	says  string
}{
	{regexp.MustCompile(`(?i)no space left|disk.{0,20}full`), "that the disk was full"},
	{regexp.MustCompile(`(?i)out of memory|exit code 137`), "that memory may have run out"},
	{regexp.MustCompile(`(?i)exceeded the maximum execution time|timed? ?out`), "that a time limit was reached"},
	{regexp.MustCompile(`(?i)rate limit|too many requests|\b429\b`), "that a request limit was reached"},
	{regexp.MustCompile(`(?i)lost communication|runner has received a shutdown`), "that the runner was lost"},
	{regexp.MustCompile(`(?i)unable to resolve action|deprecated version`), "that an action could not be used"},
	{regexp.MustCompile(`(?i)could not resolve host|connection (refused|reset)`), "that the network failed"},
	{regexp.MustCompile(`(?i)exit code`), "only that a command ended with an error code"},
}

func (p Public) cause(ctx context.Context, base string, job int64) string {
	var notes []struct {
		Level   string `json:"annotation_level"`
		Message string
	}
	if p.c.do(ctx, "GET", fmt.Sprintf("%s/check-runs/%d/annotations?per_page=20", base, job), nil, &notes) != nil {
		return ""
	}
	for _, c := range causes {
		for _, n := range notes {
			if n.Level == "failure" && c.found.MatchString(n.Message) {
				return c.says
			}
		}
	}
	return ""
}
