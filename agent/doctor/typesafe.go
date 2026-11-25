package doctor

import (
	"context"
	"errors"
	"net/http"
	"regexp"
	"strings"
	"time"
)

// The outside fact-checker: Jev, a decision model of TypeSafe. It has no vote. The questions follow
// "Double-checking citations" of its documentation; agent/cmd/council/typesafe_probe.py measured them.
const jev = "jev-1.14.0"

// Choices keep the order of the documentation by the names; the model reads name and description.
type question struct {
	Type         string            `json:"type"`
	Instructions string            `json:"instructions"`
	Criteria     map[string]string `json:"criteria"`
}

var relation = question{"choice", "How does the section relate to the claim?", map[string]string{
	"supports":     "The section states the claim or directly implies that it is true",
	"contradicts":  "The section states the opposite of the claim or implies it is false",
	"says_nothing": "The section does not address what the claim asserts, either way",
}}

var fit = question{"choice", "How does the advice relate to the problem?", map[string]string{
	"addresses": "The advice is a concrete step that works on the problem",
	"unrelated": "The advice has nothing to do with the problem or is too vague to act on",
	"harmful":   "The advice removes or weakens tests, checks, jobs or security, or blames people",
}}

// Rating is what the fact-checker says about a finding.
type Rating struct {
	Support            string   `json:"support"`
	SupportProbability float64  `json:"support_probability"`
	Fit                *string  `json:"fit,omitempty"`
	FitProbability     *float64 `json:"fit_probability,omitempty"`
	RatedBy            string   `json:"rated_by"`
}

// TypeSafe asks through the connector; without an address nothing is rated.
type TypeSafe struct{ c caller }

func NewTypeSafe(gateway string, h *http.Client) *TypeSafe {
	if gateway == "" {
		return nil
	}
	return &TypeSafe{caller{base: gateway, media: "application/json", max: 100_000, http: h}}
}

// ask returns the choice and the probability of one wanted answer.
func (t TypeSafe) ask(ctx context.Context, state map[string]string, q question, want string) (string, float64, int, error) {
	var r struct {
		Model   string
		Answers map[string]struct {
			Choice        string
			Probabilities map[string]float64
		}
		Usage struct {
			Input int `json:"input_tokens"`
		}
	}
	err := t.c.do(ctx, "POST", "/v1/systemone", map[string]any{"model": jev, "state": state, "questions": map[string]any{"q": q}}, &r)
	var refusedCall StatusError
	if errors.As(err, &refusedCall) {
		return "", 0, 0, err // not paid
	}
	// A count that is missing or odd is counted as a large one.
	if err != nil || r.Usage.Input < 1 || r.Usage.Input > 20_000 {
		r.Usage.Input = 20_000
	}
	if err != nil {
		return "", 0, r.Usage.Input, err
	}
	a, p := r.Answers["q"], -1.0
	if v, ok := a.Probabilities[want]; ok {
		p = v
	}
	if _, known := q.Criteria[a.Choice]; !known || p < 0 || p > 1 || r.Model != jev {
		return "", 0, r.Usage.Input, errors.New("answer of the fact-checker is not valid")
	}
	return a.Choice, p, r.Usage.Input, nil
}

var sentence = regexp.MustCompile(`[.!?]\s+`)

// claims are the title and every sentence of the text.
func claims(f Finding) []string {
	list := []string{f.Title}
	rest := f.Text
	for rest != "" {
		at := sentence.FindStringIndex(rest)
		if at == nil {
			list = append(list, rest)
			break
		}
		list, rest = append(list, strings.TrimSpace(rest[:at[1]])), rest[at[1]:]
	}
	return list
}

// Rate compares every claim with the cited facts; the weakest one counts.
func (t TypeSafe) Rate(ctx context.Context, f Finding, facts []Fact) (Rating, int, error) {
	cited := []string{}
	for _, fact := range facts {
		for _, id := range f.Evidence {
			if fact.ID == id {
				cited = append(cited, withoutEmails(fact.Text))
			}
		}
	}
	section := strings.Join(cited, "\n")
	r, total := Rating{SupportProbability: 2, RatedBy: jev}, 0
	for _, claim := range claims(f) {
		choice, p, n, err := t.ask(ctx, map[string]string{"claim": withoutEmails(claim), "section": section}, relation, "supports")
		total += n
		if err != nil {
			return r, total, err
		}
		if p < r.SupportProbability {
			r.Support, r.SupportProbability = choice, p
		}
	}
	if f.Advice == "" {
		return r, total, nil
	}
	choice, p, n, err := t.ask(ctx, map[string]string{"problem": withoutEmails(f.Title + " " + f.Text), "advice": withoutEmails(f.Advice)}, fit, "addresses")
	r.Fit, r.FitProbability = &choice, &p
	return r, total + n, err
}

// rate asks about every published finding while the photos are made. Whatever happens here, the
// edition goes on: without a budget, an account or an answer it only stays unrated.
func (d Doctor) rate(parent context.Context, audit string, facts []Fact) {
	if d.TypeSafe == nil {
		return
	}
	after, stop := context.WithTimeout(parent, 25*time.Second) // for the account and the log
	defer stop()
	ctx, cancel := context.WithTimeout(after, 20*time.Second)
	defer cancel()
	findings, err := d.Ash.Findings(ctx, audit)
	if err != nil {
		return
	}
	done := 0
	for _, f := range findings {
		if f.Status != "published" || f.RatedBy != "" {
			continue
		}
		if ok, err := d.Ash.BudgetLeft(ctx); err != nil || !ok {
			return
		}
		r, tokens, err := d.TypeSafe.Rate(ctx, f, facts)
		if d.pay(after, audit, jev, tokens, 0) != nil || err != nil || d.Ash.Rate(ctx, f.ID, r) != nil {
			d.Ash.Log(after, audit, "typesafe", "The outside fact-checker did not answer. Nothing else depends on it.", "")
			return
		}
		done++
	}
	if done > 0 {
		d.Ash.Log(after, audit, "typesafe", "The outside fact-checker compared the published findings with their facts.", "")
	}
}

// RateAgain rates a finished edition that has no ratings yet.
func (d Doctor) RateAgain(ctx context.Context, audit string) error {
	au, err := d.Ash.One(ctx, audit)
	if err != nil {
		return err
	}
	d.rate(ctx, au.ID, au.Facts)
	return nil
}
