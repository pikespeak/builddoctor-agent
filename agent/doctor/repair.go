package doctor

import (
	"fmt"
	"strings"

	"gopkg.in/yaml.v3"
)

// repair makes a change from what the grade takes points off for, without a model: a time limit for
// jobs whose length is known, and the rule that a newer push to a pull request ends the older run.
// The council votes on it like on any other change.
func repair(workflow string, jobs []Job) (patch, text string, limit Fact, ok bool) {
	none := Fact{}
	var doc yaml.Node
	if yaml.Unmarshal([]byte(workflow), &doc) != nil || len(doc.Content) != 1 {
		return "", "", none, false
	}
	root, edits, limited, sized := doc.Content[0], []Edit{}, 0, []string{}
	if _, err := Apply(workflow, []Edit{{Kind: "cancel_superseded"}}); err == nil {
		edits = append(edits, Edit{Kind: "cancel_superseded"})
	}
	list := value(root, "jobs")
	if list == nil || list.Kind != yaml.MappingNode {
		return "", "", none, false
	}
	for i := 0; i+1 < len(list.Content) && len(edits) < 10; i += 2 {
		one := limits(workflow, []Edit{{Kind: "set_timeout", Job: list.Content[i].Value}}, jobs)
		if _, err := Apply(workflow, one); err == nil {
			edits = append(edits, one[0])
			limited++
			longest, _ := duration(one[0].Job, list.Content[i+1], list, jobs)
			sized = append(sized, fmt.Sprintf("%s %d s, limit %d minutes", plainName(one[0].Job), longest, one[0].Minutes))
		}
	}
	patch, err := Apply(workflow, edits)
	if err != nil {
		return "", "", none, false
	}
	parts, risks := []string{}, []string{}
	if limited > 0 {
		parts = append(parts, fmt.Sprintf("gives %s its own time limit: three times its longest recorded duration in this run, rounded up to whole minutes, with a minimum of 10 and a maximum of 360 minutes", perJob(limited)))
		risks = append(risks, "a job that needs longer than its limit is stopped")
	}
	if limited < len(edits) {
		parts = append(parts, "lets a newer push to a pull request end the older run")
		risks = append(risks, "the older run of a pull request does not finish")
	}
	text = "This change " + strings.Join(parts, ", and ") + ". It does not make any step faster. The risk: " + strings.Join(risks, ", and ") + "."
	if limited > 0 {
		limit = Fact{ID: "limits", Text: cut("Longest duration of the jobs read and the limit computed from it: "+strings.Join(sized, "; ")+".", 300)}
	}
	return patch, text, limit, true
}

func perJob(n int) string {
	if n == 1 {
		return "1 job"
	}
	return fmt.Sprintf("each of %d jobs", n)
}
