package doctor

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"sync"
	"testing"
	"time"
)

// watch counts model calls that are under way at the same time.
type watch struct {
	mu       sync.Mutex
	now, top int
}

func (w *watch) RoundTrip(r *http.Request) (*http.Response, error) {
	if strings.HasSuffix(r.URL.Path, "/v1/responses") {
		w.mu.Lock()
		w.now++
		w.top = max(w.top, w.now)
		w.mu.Unlock()
		time.Sleep(50 * time.Millisecond)
		defer func() { w.mu.Lock(); w.now--; w.mu.Unlock() }()
	}
	return http.DefaultTransport.RoundTrip(r)
}

func watched(d *Doctor) *watch {
	w := &watch{}
	d.OpenAI.c.http = &http.Client{Transport: w}
	return w
}

func TestWhatMayRunAtOnceDoes(t *testing.T) {
	ctx := context.Background()

	room := newTable()
	room.finds = []map[string]any{find("f", "It waits.")}
	d := room.doctor(t)
	w := watched(&d)
	if err := d.council(ctx, au, au.Facts, ""); err != nil || w.top != 2 {
		t.Fatal("QA and Safety", err, w.top)
	}

	_, d = newDarkroom(t)
	w = watched(&d)
	list := []Finding{{ID: "1", Kind: "time", Status: "pending"}, {ID: "2", Kind: "cost", Status: "pending"}}
	if _, err := d.sketch(ctx, "a", "baker", list, facts); err != nil || w.top < 3 {
		t.Fatal("a page for every article and one for the rest", err, w.top)
	}
	w.top = 0
	if _, _, err := d.poll(ctx, "a", []ballot{{ID: "x"}}); err != nil || w.top != 2 {
		t.Fatal("votes on lines", err, w.top)
	}

	c, _ := newWood().crew(t)
	w = watched(&c.Doctor)
	if err := c.Doctor.foreign(ctx, &Audit{ID: "a", State: "examining", Repository: "some/project"}); err != nil || w.top != 2 {
		t.Fatal("the figure beside the questions", err, w.top)
	}
}

// The figure is chosen beside the Examination; a call without an account still stops it.
func TestNoCallIsLeftBehind(t *testing.T) {
	for _, fail := range []string{"/record_facts", "/ai_calls"} {
		forest := newWood()
		forest.code[fail] = 500
		c, _ := forest.crew(t)
		w := watched(&c.Doctor)
		if c.Doctor.foreign(context.Background(), &Audit{ID: "a", State: "examining", Repository: "some/project"}) == nil || w.now != 0 {
			t.Fatal(fail, w.now)
		}
		if fail == "/record_facts" { // and the figure cannot be accounted for either
			forest.code["/ai_calls"] = 500
			err := c.Doctor.foreign(context.Background(), &Audit{ID: "a", State: "examining", Repository: "some/project"})
			var no refused
			if !errors.As(err, &no) {
				t.Fatal("money without an account", err)
			}
		}
	}
}

func TestWorse(t *testing.T) {
	plain, hard := errors.New("x"), refused{errors.New("y")}
	for _, c := range [][3]error{{nil, nil, nil}, {plain, nil, plain}, {nil, plain, plain}, {plain, hard, hard}, {hard, plain, hard}} {
		if got := worse(c[0], c[1]); got != c[2] {
			t.Fatal(c, got)
		}
	}
}
