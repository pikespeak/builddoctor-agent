package spike

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"math"
	"net/http"
	"strings"
	"testing"
	"testing/iotest"
	"time"
)

type fake func(*http.Request) (*http.Response, error)

func (f fake) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

func answer(code int, body string) Client {
	return Client{"http://gh", "http://ai", &http.Client{Transport: fake(func(*http.Request) (*http.Response, error) {
		return &http.Response{StatusCode: code, Body: io.NopCloser(strings.NewReader(body))}, nil
	})}}
}

var ctx = context.Background()

func TestWorkflow(t *testing.T) {
	got, err := answer(200, `{"type":"file","encoding":"base64","content":"bmFt\nZQ=="}`).Workflow(ctx, "a/b", "x")
	if err != nil || got != "name" {
		t.Fatal(got, err)
	}
	for _, b := range []string{`{`, `{"type":"dir"}`, `{"type":"file","encoding":"base64","content":"*"}`, `{"type":"file","encoding":"base64","content":""}`} {
		if _, err := answer(200, b).Workflow(ctx, "a/b", "x"); err == nil {
			t.Fatal("accepted", b)
		}
	}
}

func TestJobs(t *testing.T) {
	ok := `{"jobs":[{"name":"vet","conclusion":"success","started_at":"2026-11-23T19:00:00Z","completed_at":"2026-11-23T19:00:10Z"}]}`
	got, err := answer(200, ok).Jobs(ctx, "a/b", 1)
	if err != nil || got[0].Seconds() != 10 {
		t.Fatal(got, err)
	}
	for _, b := range []string{`{`, `{"jobs":[]}`, strings.Replace(ok, "success", "failure", 1), strings.Replace(ok, "19:00:10", "18:00:10", 1)} {
		if _, err := answer(200, b).Jobs(ctx, "a/b", 1); err == nil {
			t.Fatal("accepted", b)
		}
	}
}

func TestAsk(t *testing.T) {
	var sent map[string]any
	c := Client{"http://gh", "http://ai", &http.Client{Transport: fake(func(r *http.Request) (*http.Response, error) {
		if err := json.NewDecoder(r.Body).Decode(&sent); err != nil {
			t.Error(err)
		}
		if r.Header.Get("Authorization") != "" {
			t.Error("the agent must not send a token")
		}
		return &http.Response{StatusCode: 200, Body: io.NopCloser(strings.NewReader(`{"status":"completed","output":[{"content":[{"type":"output_text","text":"cache"}]}],"usage":{"input_tokens":3,"output_tokens":4}}`))}, nil
	})}}
	got, err := c.Ask(ctx, "m", "w", []Job{{Name: "vet"}})
	if err != nil || got != (Hypothesis{"cache", 3, 4}) || sent["store"] != false {
		t.Fatal(got, err, sent)
	}
	for _, b := range []string{`{`, `{"status":"incomplete"}`, `{"status":"completed","output":[]}`} {
		if _, err := answer(200, b).Ask(ctx, "m", "w", nil); err == nil {
			t.Fatal("accepted", b)
		}
	}
	bad := []Job{{Started: time.Date(math.MaxInt16, 1, 1, 0, 0, 0, 0, time.UTC)}}
	if _, err := answer(200, "{}").Ask(ctx, "m", "w", bad); err == nil {
		t.Fatal("accepted an invalid time")
	}
}

func TestTransport(t *testing.T) {
	if _, err := answer(403, `{}`).Workflow(ctx, "a/b", "x"); err == nil {
		t.Fatal("accepted 403")
	}
	if _, err := answer(200, strings.Repeat("x", maxBody+1)).Workflow(ctx, "a/b", "x"); err == nil {
		t.Fatal("accepted a huge body")
	}
	boom := errors.New("boom")
	c := Client{GitHub: "http://gh", HTTP: &http.Client{Transport: fake(func(*http.Request) (*http.Response, error) { return nil, boom })}}
	if _, err := c.Workflow(ctx, "a/b", "x"); !errors.Is(err, boom) {
		t.Fatal(err)
	}
	c.HTTP.Transport = fake(func(*http.Request) (*http.Response, error) {
		return &http.Response{StatusCode: 200, Body: io.NopCloser(iotest.ErrReader(boom))}, nil
	})
	if _, err := c.Workflow(ctx, "a/b", "x"); !errors.Is(err, boom) {
		t.Fatal(err)
	}
	c.GitHub = "http://gh\x7f"
	if _, err := c.Workflow(ctx, "a/b", "x"); err == nil {
		t.Fatal("accepted a bad URL")
	}
}
