package doctor

import (
	"fmt"
	"io"
	"math"
	"reflect"
	"regexp"
	"slices"
	"strings"

	"github.com/rhysd/actionlint"
	"gopkg.in/yaml.v3"
)

// The engineer is code only. It reads a workflow as data, runs no foreign program and opens no address.

const maxLint = 5

// Notice is a weakness that somebody could use. It never becomes a fact, so no model and no visitor
// sees it; the application shows it to the requester only.
type Notice struct {
	AuditID string `json:"audit_id"`
	Kind    string `json:"kind"`
	Line    int    `json:"line"`
}

type lintError struct {
	Kind, Message string
	Line          int
}

// lint checks a workflow with actionlint as a library, without shellcheck, pyflakes or files of a project.
func lint(workflow string) (out []lintError, err error) {
	defer func() { // the file is foreign, and a bug in the checker must not end the agent
		if r := recover(); r != nil {
			out, err = nil, fmt.Errorf("the checker failed: %v", r)
		}
	}()
	l, err := actionlint.NewLinter(io.Discard, &actionlint.LinterOptions{LogWriter: io.Discard, WorkingDir: "/"})
	if err != nil {
		return nil, err
	}
	found, err := l.Lint("workflow.yml", []byte(workflow), nil)
	if err != nil {
		return nil, err
	}
	for _, e := range found {
		// Labels of own runners and new labels are unknown to the checker, not wrong.
		// The run that is read used these actions, so "too old to run" is contradicted by it.
		if e.Kind != "runner-label" && !strings.Contains(e.Message, "too old to run") {
			out = append(out, lintError{e.Kind, e.Message, e.Line})
		}
	}
	return out, nil
}

// A message is a sentence, so it keeps its apostrophes.
var oddInMessage = regexp.MustCompile(`[^A-Za-z0-9_ .,:()/+'-]+`)

// examineFile tells what is wrong in the file itself, and separately what somebody could use.
func examineFile(workflow string) ([]Fact, []Notice) {
	facts, notices := []Fact{}, []Notice{}
	found, err := lint(workflow)
	if err != nil {
		return facts, notices
	}
	for _, e := range found {
		switch {
		case strings.Contains(e.Message, "potentially untrusted"):
			notices = append(notices, Notice{Kind: "untrusted_input", Line: e.Line})
		case e.Kind == "credentials":
			notices = append(notices, Notice{Kind: "credentials", Line: e.Line})
		case len(facts) < maxLint:
			m := strings.Join(strings.Fields(oddInMessage.ReplaceAllString(e.Message, " ")), " ")
			facts = append(facts, Fact{ID: fmt.Sprint("file", len(facts)+1), Text: fmt.Sprintf("actionlint, line %d of the workflow file: %s.", e.Line, strings.TrimRight(cut(m, 200), ". "))})
		}
	}
	var doc yaml.Node
	if yaml.Unmarshal([]byte(workflow), &doc) != nil || len(doc.Content) != 1 {
		return facts, notices
	}
	root := doc.Content[0]
	loose, jobs := 0, value(root, "jobs")
	open := value(root, "permissions") == nil
	covered := jobs != nil && jobs.Kind == yaml.MappingNode && len(jobs.Content) > 0
	each(jobs, func(_ string, job *yaml.Node) {
		covered = covered && value(job, "permissions") != nil
		for _, s := range children(value(job, "steps")) {
			u := value(s, "uses")
			if u == nil || strings.HasPrefix(u.Value, "./") || strings.HasPrefix(u.Value, "docker://") {
				continue
			}
			name, ref, _ := strings.Cut(u.Value, "@")
			owner, _, _ := strings.Cut(name, "/")
			if owner != "actions" && owner != "github" && !shaName.MatchString(ref) {
				loose++
			}
			if strings.HasPrefix(name, "actions/checkout") && triggered(root, "pull_request_target") {
				if r := value(value(s, "with"), "ref"); r != nil && strings.Contains(r.Value, "head") {
					notices = append(notices, Notice{Kind: "foreign_code", Line: r.Line})
				}
			}
		}
	})
	if loose > 0 {
		facts = append(facts, Fact{ID: "pinned", Text: fmt.Sprintf("Steps that use an action of a third party without a fixed commit: %d.", loose)})
	}
	if p := value(root, "permissions"); p != nil && p.Value == "write-all" {
		facts = append(facts, Fact{ID: "rights", Text: "The workflow file gives every job all write permissions."})
	} else if open && !covered {
		facts = append(facts, Fact{ID: "rights", Text: "The workflow file does not set permissions for every job, so the default of the repository applies."})
	}
	return facts, notices[:min(len(notices), 10)]
}

type yamlNode = yaml.Node

// rootOf returns the top of a file that is one document.
func rootOf(text string) (*yaml.Node, bool) {
	var doc yaml.Node
	if yaml.Unmarshal([]byte(text), &doc) != nil || len(doc.Content) != 1 {
		return nil, false
	}
	return doc.Content[0], true
}

func each(m *yaml.Node, f func(string, *yaml.Node)) {
	if m == nil || m.Kind != yaml.MappingNode {
		return
	}
	for i := 0; i+1 < len(m.Content); i += 2 {
		f(m.Content[i].Value, m.Content[i+1])
	}
}

func children(n *yaml.Node) []*yaml.Node {
	if n == nil || n.Kind != yaml.SequenceNode {
		return nil
	}
	return n.Content
}

// triggered tells whether an event starts the workflow.
func triggered(root *yaml.Node, event string) bool {
	on := value(root, "on")
	if on == nil {
		return false
	}
	if on.Value == event || value(on, event) != nil {
		return true
	}
	return slices.ContainsFunc(children(on), func(n *yaml.Node) bool { return n.Value == event })
}

// schedule computes when the last job ends if every job starts as soon as its needs are done.
// It fails if a job of the file cannot be found among the jobs of the run.
func schedule(workflow string, jobs []Job) (int, bool) {
	var doc yaml.Node
	if yaml.Unmarshal([]byte(workflow), &doc) != nil || len(doc.Content) != 1 {
		return 0, false
	}
	took, needs, ok := map[string]int{}, map[string][]string{}, true
	list := value(doc.Content[0], "jobs")
	each(list, func(id string, job *yaml.Node) {
		d, found := duration(id, job, list, jobs)
		ok = ok && found
		took[id] = d
		if n := value(job, "needs"); n != nil && n.Kind == yaml.ScalarNode {
			needs[id] = []string{n.Value}
		} else {
			for _, c := range children(n) {
				needs[id] = append(needs[id], c.Value)
			}
		}
	})
	if !ok || len(took) == 0 {
		return 0, false
	}
	ends := map[string]int{}
	var end func(string, int) int
	end = func(id string, depth int) int {
		if e, done := ends[id]; done {
			return e
		}
		if _, known := took[id]; !known || depth > len(took) { // unknown job or a circle
			ok = false
			return 0
		}
		start := 0
		for _, n := range needs[id] {
			start = max(start, end(n, depth+1))
		}
		ends[id] = start + took[id]
		return ends[id]
	}
	last := 0
	for id := range took {
		last = max(last, end(id, 0))
	}
	return last, ok
}

var expression = regexp.MustCompile(`\$\{\{.*`)

// duration is the longest run of a job; a matrix has several.
func duration(id string, job, all *yaml.Node, jobs []Job) (int, bool) {
	shown := func(id string, job *yaml.Node) string {
		if n := value(job, "name"); n != nil {
			return n.Value
		}
		return id
	}
	clean := func(s string) string {
		return strings.Join(strings.Fields(oddInName.ReplaceAllString(s, " ")), " ")
	}
	name := shown(id, job)
	prefix := clean(expression.ReplaceAllString(name, ""))
	if prefix == "" {
		return 0, false
	}
	// Two jobs that share a beginning cannot be told apart.
	same := 0
	each(all, func(id string, other *yaml.Node) {
		if clean(expression.ReplaceAllString(shown(id, other), "")) == prefix {
			same++
		}
	})
	if same > 1 {
		return 0, false
	}
	longest, found := 0, false
	for _, j := range timed(jobs) {
		n := clean(j.Name)
		if n == prefix || strings.HasPrefix(n, prefix+" (") || strings.HasPrefix(n, prefix+" / ") || (name != prefix && strings.Contains(name, "${{") && strings.HasPrefix(n, prefix)) {
			longest, found = max(longest, length(j)), true
		}
	}
	return longest, found
}

// planned is the fact about a change of the order of jobs.
func planned(before, after string, jobs []Job) (Fact, bool) {
	a, ok := schedule(before, jobs)
	b, also := schedule(after, jobs)
	if !ok || !also || a == b {
		return Fact{}, false
	}
	return Fact{ID: "plan", Text: fmt.Sprintf("Recomputed with the job times of this run and a free runner for every job: the last job ends after %d s now and after %d s with the proposed change.", a, b), Seconds: max(0, a-b)}, true
}

var delivers = regexp.MustCompile(`(?i)(deploy|release|publish|upload-pages|docker/build-push)`)

// inspect is the engineer's word about a proposed change. Only differences that the closed list of
// edits can make are allowed, and a job may stop waiting only if nothing in it uses what it waited for.
func inspect(before, after string, plan *Fact) (string, bool) {
	var a, b map[string]any
	if yaml.Unmarshal([]byte(before), &a) != nil || yaml.Unmarshal([]byte(after), &b) != nil {
		return "The file cannot be read.", false
	}
	was, err := lint(before)
	if err != nil {
		return "The file could not be checked.", false
	}
	is, err := lint(after)
	if err != nil {
		return "The changed file could not be checked.", false
	}
	count := map[string]int{}
	for _, e := range was {
		count[e.Kind+e.Message]++
	}
	for _, e := range is {
		if count[e.Kind+e.Message]--; count[e.Kind+e.Message] < 0 {
			return "actionlint finds a new error in the changed file.", false
		}
	}
	changed, reordered := false, false
	ja, _ := a["jobs"].(map[string]any)
	jb, _ := b["jobs"].(map[string]any)
	delete(a, "jobs")
	delete(b, "jobs")
	if _, had := a["concurrency"]; !had && reflect.DeepEqual(b["concurrency"], cancelRule) {
		delete(b, "concurrency")
		changed = true
	}
	if !reflect.DeepEqual(a, b) || len(ja) != len(jb) || len(ja) == 0 {
		return "The change touches more than the allowed parts.", false
	}
	for id, v := range ja {
		x, _ := v.(map[string]any)
		y, _ := jb[id].(map[string]any)
		if x == nil || y == nil {
			return "The change touches more than the allowed parts.", false
		}
		if _, waits := x["needs"]; waits && y["needs"] == nil {
			text, err := yaml.Marshal(x)
			if err != nil || strings.Contains(string(text), "needs.") || strings.Contains(string(text), "download-artifact") {
				return "A job would stop waiting although it uses results of others.", false
			}
			if delivers.MatchString(id+" "+string(text)) || x["environment"] != nil {
				return "A job that delivers something would stop waiting for checks.", false
			}
			delete(x, "needs")
			changed, reordered = true, true
		}
		if _, had := x["timeout-minutes"]; !had {
			if n, is := y["timeout-minutes"].(int); is && n >= 10 && n <= 360 {
				delete(y, "timeout-minutes")
				changed = true
			}
		}
		changed = allowCache(x, y) || changed
		if !reflect.DeepEqual(x, y) {
			return "The change touches more than the allowed parts.", false
		}
	}
	if !changed {
		return "The change has no effect.", false
	}
	if reordered {
		if plan == nil || plan.Seconds <= 0 {
			return "Recomputing from the job times shows no earlier end.", false
		}
	}
	return "Only allowed parts change, and actionlint finds no new error.", true
}

// allowCache takes "cache: false" out of the old steps where the new ones do without it.
func allowCache(x, y map[string]any) bool {
	sx, _ := x["steps"].([]any)
	sy, _ := y["steps"].([]any)
	done := false
	for i := range min(len(sx), len(sy)) {
		a, _ := sx[i].(map[string]any)
		b, _ := sy[i].(map[string]any)
		if uses, _ := a["uses"].(string); !setupActions.MatchString(uses) {
			continue
		}
		wa, _ := a["with"].(map[string]any)
		wb, _ := b["with"].(map[string]any)
		_, kept := wb["cache"]
		if c, had := wa["cache"]; had && !kept && fmt.Sprint(c) == "false" {
			delete(wa, "cache")
			if len(wa) == 0 && len(wb) == 0 { // "with:" without entries is read as nothing
				delete(a, "with")
				delete(b, "with")
			}
			done = true
		}
	}
	return done
}

// limitFor is a time limit in minutes: three times the longest job, at least 10.
func limitFor(longest int) int {
	return min(360, max(10, int(math.Ceil(float64(longest)*3/60))))
}
