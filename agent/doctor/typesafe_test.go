package doctor

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
)

// desk plays the application and the fact-checker.
type desk struct {
	mu                       sync.Mutex
	finds                    []map[string]any
	rated, logs, seen, spent []string
	answer                   func(n int) (int, string)
	budget                   bool
	fail                     string
}

func jevSays(choice string, p float64, want string) string {
	return fmt.Sprintf(`{"model":"jev-1.14.0","answers":{"q":{"type":"choice","choice":%q,"probabilities":{%q:%g}}},"usage":{"input_tokens":100}}`, choice, want, p)
}

func (d *desk) ServeHTTP(res http.ResponseWriter, req *http.Request) {
	d.mu.Lock()
	defer d.mu.Unlock()
	b, _ := io.ReadAll(req.Body)
	p := req.URL.Path
	if d.fail != "" && strings.Contains(req.Method+" "+p, d.fail) {
		res.WriteHeader(500)
		return
	}
	switch {
	case strings.HasSuffix(p, "/v1/systemone"):
		d.seen = append(d.seen, string(b))
		code, text := d.answer(len(d.seen))
		res.WriteHeader(code)
		io.WriteString(res, text)
	case strings.Contains(p, "/findings/for_audit/"):
		out := []any{}
		for _, f := range d.finds {
			out = append(out, map[string]any{"id": f["id"], "attributes": f})
		}
		json.NewEncoder(res).Encode(map[string]any{"data": out})
	case strings.HasSuffix(p, "/rate"):
		d.rated = append(d.rated, string(b))
		io.WriteString(res, `{"data":{}}`)
	case strings.Contains(p, "budget"):
		fmt.Fprint(res, d.budget)
	case strings.Contains(p, "ai_calls"):
		d.spent = append(d.spent, string(b))
		io.WriteString(res, `{"data":{}}`)
	case strings.Contains(p, "/audits/one/"):
		io.WriteString(res, `{"data":{"id":"a1","attributes":{"facts":[{"id":"run","text":"The jobs took 10 s."}]}}}`)
	default:
		d.logs = append(d.logs, string(b))
		io.WriteString(res, `{"data":{}}`)
	}
}

func newDesk(t *testing.T) (*desk, Doctor) {
	d := &desk{budget: true, finds: []map[string]any{{"id": "f1", "status": "published", "title": "It is slow.", "text": "The jobs took 10 s. Mail me@example.org. That is long", "advice": "Split it.", "evidence": []string{"run"}}}}
	d.answer = func(int) (int, string) { return 200, jevSays("supports", 0.5, "supports") }
	s := httptest.NewServer(d)
	t.Cleanup(s.Close)
	return d, Doctor{Ash: NewAsh(s.URL, "x", s.Client()), TypeSafe: NewTypeSafe(s.URL, s.Client())}
}

var someFacts = []Fact{{ID: "run", Text: "The jobs took 10 s."}, {ID: "other", Text: "Not cited."}}

func TestFactChecker(t *testing.T) {
	w, d := newDesk(t)
	w.answer = func(n int) (int, string) {
		if n == 5 {
			return 200, jevSays("addresses", 0.9, "addresses")
		}
		return 200, jevSays([]string{"supports", "says_nothing", "supports", "supports"}[n-1], []float64{0.8, 0.1, 0.7, 0.9}[n-1], "supports")
	}
	d.rate(context.Background(), "a1", someFacts)
	if len(w.rated) != 1 || !strings.Contains(w.rated[0], `"support":"says_nothing","support_probability":0.1,"fit":"addresses","fit_probability":0.9,"rated_by":"jev-1.14.0"`) {
		t.Fatal(w.rated)
	}
	all := strings.Join(w.seen, "\n")
	if len(w.seen) != 5 || strings.Contains(all, "Not cited") || strings.Contains(all, "example.org") || !strings.Contains(all, "The jobs took 10 s.") {
		t.Fatal(w.seen)
	}
	if len(w.spent) != 1 || !strings.Contains(w.spent[0], "500") || len(w.logs) != 1 {
		t.Fatal(w.spent, w.logs)
	}
}

func TestFactCheckerWithoutAdvice(t *testing.T) {
	w, d := newDesk(t)
	w.finds[0]["advice"] = ""
	w.finds[0]["text"] = strings.Repeat("One. ", 30)
	if d.rate(context.Background(), "a1", someFacts); len(w.seen) != 31 || len(w.rated) != 1 || strings.Contains(w.rated[0], "fit") {
		t.Fatal(len(w.seen), w.rated)
	}
	if err := d.RateAgain(context.Background(), "a1"); err != nil || len(w.rated) != 2 {
		t.Fatal(err, w.rated)
	}
	w.fail = "/audits/one/"
	if d.RateAgain(context.Background(), "a1") == nil {
		t.Fatal("an unknown edition")
	}
}

func TestFactCheckerStaysSilent(t *testing.T) {
	for name, change := range map[string]func(*desk, *Doctor){
		"off":         func(_ *desk, d *Doctor) { d.TypeSafe = NewTypeSafe("", nil) },
		"no budget":   func(w *desk, _ *Doctor) { w.budget = false },
		"no findings": func(w *desk, _ *Doctor) { w.fail = "/findings/" },
		"withheld":    func(w *desk, _ *Doctor) { w.finds[0]["status"] = "withheld" },
		"rated":       func(w *desk, _ *Doctor) { w.finds[0]["rated_by"] = jev },
	} {
		w, d := newDesk(t)
		change(w, &d)
		if d.rate(context.Background(), "a1", someFacts); len(w.seen) != 0 || len(w.rated) != 0 {
			t.Fatal(name, w.seen, w.rated)
		}
	}
}

func TestOddCountsAreStillCounted(t *testing.T) {
	for _, tokens := range []string{`"100"`, "1.5", "99999999999999999999"} {
		w, d := newDesk(t)
		w.answer = func(int) (int, string) {
			return 200, strings.Replace(jevSays("supports", 0.5, "supports"), "100", tokens, 1)
		}
		if d.rate(context.Background(), "a1", someFacts); len(w.rated) != 0 || len(w.spent) != 1 || !strings.Contains(w.spent[0], "20000") {
			t.Fatal(tokens, w.rated, w.spent)
		}
	}
}

func TestFactCheckerWithBadAnswers(t *testing.T) {
	for name, say := range map[string][2]any{
		"error":         {500, ""},
		"no json":       {200, "Sure! supports"},
		"other choice":  {200, jevSays("perfect", 0.9, "supports")},
		"too probable":  {200, jevSays("supports", 1.5, "supports")},
		"negative":      {200, jevSays("supports", -0.5, "supports")},
		"no value":      {200, jevSays("supports", 0.9, "other")},
		"no answer":     {200, `{"model":"jev-1.14.0","answers":{},"usage":{"input_tokens":5}}`},
		"another model": {200, strings.Replace(jevSays("supports", 0.9, "supports"), "jev-1.14.0", "x", 1)},
		"too long":      {200, strings.Repeat("x", 200_000)},
	} {
		w, d := newDesk(t)
		w.answer = func(int) (int, string) { return say[0].(int), say[1].(string) }
		if d.rate(context.Background(), "a1", someFacts); len(w.rated) != 0 || len(w.logs) != 1 || !strings.Contains(w.logs[0], "did not answer") {
			t.Fatal(name, w.rated, w.logs)
		}
	}
	w, d := newDesk(t)
	w.fail = "/rate"
	if d.rate(context.Background(), "a1", someFacts); len(w.logs) != 1 {
		t.Fatal(w.logs)
	}
	w, d = newDesk(t)
	w.fail = "POST /api/json/ai_calls"
	if d.rate(context.Background(), "a1", someFacts); len(w.rated) != 0 || len(w.logs) != 1 {
		t.Fatal("a call without an account", w.rated)
	}
	for _, tokens := range []string{"-5", "0", "999999999"} {
		w, d = newDesk(t)
		w.answer = func(int) (int, string) {
			return 200, strings.Replace(jevSays("supports", 0.5, "supports"), "100", tokens, 1)
		}
		w.finds[0]["advice"] = ""
		if d.rate(context.Background(), "a1", someFacts); len(w.rated) != 1 || !strings.Contains(w.spent[0], "80000") {
			t.Fatal(tokens, w.rated, w.spent)
		}
	}
}
