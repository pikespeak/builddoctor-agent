package doctor

import (
	"bytes"
	"errors"
	"fmt"
	"reflect"
	"slices"
	"strings"

	"gopkg.in/yaml.v3"
)

// Edit is one change from a closed list. The model chooses edits; it never writes YAML,
// so it cannot add permissions, secrets, triggers, actions or commands.
type Edit struct {
	Kind string `json:"kind"`
	Job  string `json:"job"`
	// Minutes is computed here from the job times; the model cannot set it.
	Minutes int `json:"-"`
}

// Kinds the agent may use. Only the first group changes how long a run takes, so only it can be measured.
var (
	measurable = []string{"remove_needs", "enable_setup_cache"}
	Kinds      = append(slices.Clone(measurable), "set_timeout", "cancel_superseded")
)

// cancelRule is the only concurrency rule that is ever added. Runs of other events keep their own group.
var cancelRule = map[string]any{
	"group":              "${{ github.workflow }}-${{ github.event.pull_request.number || github.run_id }}",
	"cancel-in-progress": "${{ github.event_name == 'pull_request' }}",
}

const cancelText = "concurrency:\n  group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.run_id }}\n  cancel-in-progress: ${{ github.event_name == 'pull_request' }}\n\n"

// limits gives every time limit its minutes, from the longest run of the job.
func limits(workflow string, edits []Edit, jobs []Job) []Edit {
	out := slices.Clone(edits)
	var doc yaml.Node
	if yaml.Unmarshal([]byte(workflow), &doc) != nil || len(doc.Content) != 1 {
		return out
	}
	list := value(doc.Content[0], "jobs")
	for i, e := range out {
		if job := value(list, e.Job); e.Kind == "set_timeout" && job != nil {
			if longest, ok := duration(e.Job, job, list, jobs); ok {
				out[i].Minutes = limitFor(longest)
			}
		}
	}
	return out
}

// Apply changes the workflow and refuses edits without an effect.
func Apply(workflow string, edits []Edit) (string, error) {
	if len(edits) == 0 || len(edits) > 10 {
		return "", errors.New("between 1 and 10 edits are allowed")
	}
	var doc yaml.Node
	if err := yaml.Unmarshal([]byte(workflow), &doc); err != nil {
		return "", err
	}
	if len(doc.Content) != 1 {
		return "", errors.New("workflow is not one document")
	}
	root := doc.Content[0]
	jobs := value(root, "jobs")
	gone := map[int]bool{}   // lines of the original that the edits remove
	more := map[int]string{} // text that the edits add before a line
	for _, e := range edits {
		if e.Kind == "cancel_superseded" {
			if !cancel(root, more) {
				return "", fmt.Errorf("edit %s is not possible here", e.Kind)
			}
			continue
		}
		job := value(jobs, e.Job)
		if job == nil {
			return "", fmt.Errorf("no job %q", cut(e.Job, 40))
		}
		done := false
		switch e.Kind {
		case "remove_needs":
			done = remove(job, "needs", gone)
		case "enable_setup_cache":
			done = enableCache(job, gone)
		case "set_timeout":
			done = limit(job, e.Minutes, more)
		default:
			return "", fmt.Errorf("edit %q is not allowed", cut(e.Kind, 40))
		}
		if !done {
			return "", fmt.Errorf("edit %s has no effect on job %q", e.Kind, cut(e.Job, 40))
		}
	}
	var b bytes.Buffer
	enc := yaml.NewEncoder(&b)
	enc.SetIndent(2)
	if err := enc.Encode(&doc); err != nil {
		return "", err
	}
	return plain(workflow, b.String(), gone, more), nil
}

// plain removes and adds only the lines of the edits, so that everything else stays as its authors wrote it.
// If that does not mean exactly the same, the newly written file is used.
func plain(original, written string, gone map[int]bool, more map[int]string) string {
	keep := []string{}
	for i, line := range strings.SplitAfter(original, "\n") {
		keep = append(keep, more[i+1])
		if !gone[i+1] {
			keep = append(keep, line)
		}
	}
	text := strings.Join(keep, "")
	var a, b any
	if yaml.Unmarshal([]byte(text), &a) != nil || yaml.Unmarshal([]byte(written), &b) != nil || !reflect.DeepEqual(a, b) {
		return written
	}
	return text
}

// limit adds a time limit to a job that has none; a called workflow cannot have one.
func limit(job *yaml.Node, minutes int, more map[int]string) bool {
	if job.Kind != yaml.MappingNode || len(job.Content) == 0 || minutes == 0 || value(job, "timeout-minutes") != nil || value(job, "uses") != nil {
		return false
	}
	first := job.Content[0]
	more[first.Line] = fmt.Sprintf("%stimeout-minutes: %d\n", strings.Repeat(" ", first.Column-1), minutes)
	add(job, "timeout-minutes", &yaml.Node{Kind: yaml.ScalarNode, Tag: "!!int", Value: fmt.Sprint(minutes)})
	return true
}

// cancel adds the rule that a newer push to a pull request ends the older run.
func cancel(root *yaml.Node, more map[int]string) bool {
	if value(root, "concurrency") != nil || !triggered(root, "pull_request") || triggered(root, "workflow_call") {
		return false
	}
	for i := 0; i+1 < len(root.Content); i += 2 {
		if root.Content[i].Value == "jobs" {
			more[root.Content[i].Line] = cancelText
		}
	}
	var rule yaml.Node
	if yaml.Unmarshal([]byte(cancelText), &rule) != nil {
		return false
	}
	add(root, "concurrency", rule.Content[0].Content[1])
	return true
}

func add(m *yaml.Node, key string, v *yaml.Node) {
	m.Content = append(m.Content, &yaml.Node{Kind: yaml.ScalarNode, Tag: "!!str", Value: key}, v)
}

func lastLine(n *yaml.Node) int {
	line := n.Line
	for _, c := range n.Content {
		line = max(line, lastLine(c))
	}
	return line
}

func value(m *yaml.Node, key string) *yaml.Node {
	if m == nil || m.Kind != yaml.MappingNode {
		return nil
	}
	for i := 0; i+1 < len(m.Content); i += 2 {
		if m.Content[i].Value == key {
			return m.Content[i+1]
		}
	}
	return nil
}

func remove(m *yaml.Node, key string, gone map[int]bool) bool {
	if value(m, key) == nil {
		return false
	}
	for i := 0; i+1 < len(m.Content); i += 2 {
		if m.Content[i].Value == key {
			for l := m.Content[i].Line; l <= lastLine(m.Content[i+1]); l++ {
				gone[l] = true
			}
			m.Content = append(m.Content[:i], m.Content[i+2:]...)
			break
		}
	}
	return true
}

// enableCache removes "cache: false", so that the setup action uses its own default.
func enableCache(job *yaml.Node, gone map[int]bool) bool {
	steps := value(job, "steps")
	if steps == nil {
		return false
	}
	done := false
	for _, s := range steps.Content {
		with := value(s, "with")
		if c := value(with, "cache"); c != nil && c.Value == "false" {
			remove(with, "cache", gone)
			done = true
		}
	}
	return done
}
