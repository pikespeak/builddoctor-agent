package doctor

import (
	"fmt"
	"math"
	"regexp"
	"slices"
	"sort"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

// Fact is computed here from GitHub's answers; no model is involved. Findings must cite facts.
type Fact struct {
	ID      string `json:"id"`
	Text    string `json:"text"`
	Seconds int    `json:"seconds"`
	Commit  string `json:"commit,omitempty"` // where something began, for a link
}

const (
	maxFacts = 50
	maxSteps = 60
)

var setupStep = regexp.MustCompile(`(?i)^(set up job|complete job|post |run actions/(checkout|setup-|cache)|set up |setup |checkout|initialize containers|stop containers)`)

// Facts describes a run in plain sentences with numbers.
func Facts(workflow string, jobs []Job, history []past) []Fact {
	out := []Fact{}
	add := func(id string, seconds int, format string, a ...any) {
		if len(out) < maxFacts {
			out = append(out, Fact{id, cut(fmt.Sprintf(format, a...), 300), seconds, ""})
		}
	}
	jobs = timed(jobs)
	if len(jobs) == 0 {
		return out
	}
	first, last := jobs[0], jobs[0]
	for _, j := range jobs {
		if j.Started.Before(first.Started) {
			first = j
		}
		if j.Completed.After(last.Completed) {
			last = j
		}
	}
	span := secs(first.Started, last.Completed)
	add("run", span, "The jobs took %d s from the first start to the last end. Jobs read: %d.", span, len(jobs))
	add("last", secs(last.Started, last.Completed), "The last job to end was %q. It started after %d s and ran for %d s.", plainName(last.Name), secs(first.Started, last.Started), secs(last.Started, last.Completed))

	longest := slices.Clone(jobs)
	sort.SliceStable(longest, func(a, b int) bool { return length(longest[a]) > length(longest[b]) })
	for i, j := range longest[:min(3, len(longest))] {
		add(fmt.Sprint("job", i+1), length(j), "Job %q ran for %d s.", plainName(j.Name), length(j))
	}

	waited := []Job{}
	for _, j := range jobs {
		if !j.Created.IsZero() && secs(j.Created, j.Started) >= 10 {
			waited = append(waited, j)
		}
	}
	sort.SliceStable(waited, func(a, b int) bool {
		return secs(waited[a].Created, waited[a].Started) > secs(waited[b].Created, waited[b].Started)
	})
	if len(waited) > 0 {
		w := secs(waited[0].Created, waited[0].Started)
		add("queue", w, "Jobs that waited at least 10 s for a runner: %d. The longest wait was %d s, for %q.", len(waited), w, plainName(waited[0].Name))
	} else {
		add("queue", 0, "No job is known to have waited 10 s or more for a runner.")
	}

	type total struct {
		name         string
		sum, n, most int
	}
	steps, all, setup := map[string]*total{}, 0, 0
	for _, j := range jobs {
		for _, s := range j.Steps[:min(maxSteps, len(j.Steps))] {
			d := secs(s.Started, s.Completed)
			if s.Started.IsZero() || s.Completed.IsZero() || d <= 0 {
				continue
			}
			name := plainName(s.Name)
			t := steps[name]
			if t == nil {
				t = &total{name: name}
				steps[name] = t
			}
			t.sum, t.n, t.most, all = t.sum+d, t.n+1, max(t.most, d), all+d
			if setupStep.MatchString(s.Name) {
				setup += d
			}
		}
	}
	list := []*total{}
	for _, t := range steps {
		list = append(list, t)
	}
	sort.Slice(list, func(a, b int) bool {
		if list[a].sum != list[b].sum {
			return list[a].sum > list[b].sum
		}
		return list[a].name < list[b].name
	})
	for i, t := range list[:min(8, len(list))] {
		add(fmt.Sprint("step", i+1), t.sum, "Step %q: %d s in total. Jobs that ran it: %d of %d. The longest took %d s.", t.name, t.sum, t.n, len(jobs), t.most)
	}
	if all > 0 {
		add("setup", setup, "Setup, checkout, cache and cleanup steps: %d s, %d%% of all step time.", setup, int(math.Round(float64(setup)*100/float64(all))))
	}

	if len(history) >= 3 {
		times, failed := []int{}, 0
		for _, p := range history {
			switch p.Conclusion {
			case "success":
				times = append(times, p.Seconds)
			case "failure", "timed_out":
				failed++
			}
		}
		add("failed", 0, "Of the last %d finished runs of this workflow, %d failed.", len(history), failed)
		if len(times) >= 3 {
			slices.Sort(times)
			add("history", median(times), "Successful runs in that list: %d. Median, rounded, %d s, fastest %d s, slowest %d s.", len(times), median(times), times[0], times[len(times)-1])
		}
	}
	for _, f := range written(workflow) {
		add(f.ID, 0, "%s", f.Text)
	}
	return out
}

// written tells what the workflow file says about time.
func written(workflow string) []Fact {
	var doc yaml.Node
	if yaml.Unmarshal([]byte(workflow), &doc) != nil || len(doc.Content) != 1 {
		return nil
	}
	root, out := doc.Content[0], []Fact{}
	if value(root, "concurrency") == nil {
		out = append(out, Fact{"concurrency", "The workflow file has no concurrency rule at the top, so a new push does not cancel an older run there.", 0, ""})
	}
	jobs := value(root, "jobs")
	if jobs == nil || jobs.Kind != yaml.MappingNode {
		return out
	}
	open, needs := []string{}, []string{}
	for i := 0; i+1 < len(jobs.Content); i += 2 {
		name, job := plainName(jobs.Content[i].Value), jobs.Content[i+1]
		if value(job, "timeout-minutes") == nil && value(job, "uses") == nil {
			open = append(open, name)
		}
		if n := value(job, "needs"); n != nil {
			needs = append(needs, name)
		}
	}
	if len(open) > 0 {
		out = append(out, Fact{"timeout", cut("Jobs without timeout-minutes: "+strings.Join(open, ", ")+".", 300), 0, ""})
	}
	if len(needs) > 0 {
		out = append(out, Fact{"needs", cut("Jobs that use needs to wait for other jobs: "+strings.Join(needs, ", ")+".", 300), 0, ""})
	}
	return out
}

func timed(in []Job) []Job {
	out := []Job{}
	for _, j := range in {
		if !j.Started.IsZero() && !j.Completed.Before(j.Started) && j.Conclusion != "skipped" {
			out = append(out, j)
		}
	}
	return out
}

func secs(a, b time.Time) int { return max(0, int(b.Sub(a).Seconds())) }
func length(j Job) int        { return secs(j.Started, j.Completed) }

// plainName keeps a name from a foreign project readable and harmless.
func plainName(s string) string {
	s = cut(strings.Join(strings.Fields(oddInName.ReplaceAllString(s, " ")), " "), 60)
	if s == "" {
		return "unnamed"
	}
	return s
}

// word is the singular for one and the plural for any other count.
func word(n int, one string) string {
	if n == 1 {
		return one
	}
	return one + "s"
}
