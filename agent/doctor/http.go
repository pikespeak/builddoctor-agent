// Package doctor is the agent: it examines a repository, proposes one change and
// measures it. Rules, verdicts and budgets live in Ash; this package only works.
package doctor

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"time"
)

const maxBody = 4 << 20

// StatusError is an unexpected HTTP status.
type StatusError struct {
	Method string
	Code   int
	Reset  time.Time // when GitHub's limit ends, if it was sent
}

func (e StatusError) Error() string { return fmt.Sprintf("%s: status %d", e.Method, e.Code) }

// reset is at least a minute and at most an hour away, whatever the header says.
func reset(h http.Header, now time.Time) time.Time {
	at := now.Add(time.Minute)
	if s, err := strconv.ParseInt(h.Get("Retry-After"), 10, 32); err == nil {
		at = now.Add(time.Duration(s) * time.Second)
	} else if s, err := strconv.ParseInt(h.Get("X-RateLimit-Reset"), 10, 64); err == nil && h.Get("X-RateLimit-Remaining") == "0" {
		at = time.Unix(s, 0)
	}
	if at.Before(now.Add(time.Minute)) {
		return now.Add(time.Minute)
	}
	if at.After(now.Add(time.Hour)) {
		return now.Add(time.Hour)
	}
	return at
}

type caller struct {
	base, token, media string
	files              string // where bytes go, if not to the base
	max                int64  // of an answer, if not maxBody
	http               *http.Client
}

func (c caller) do(ctx context.Context, method, path string, in, out any) error {
	var body io.Reader
	if in != nil {
		b, ok := in.([]byte)
		if !ok {
			var err error
			if b, err = json.Marshal(in); err != nil {
				return err
			}
		}
		body = bytes.NewReader(b)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.base+path, body)
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", c.media)
	req.Header.Set("Accept", c.media)
	if c.token != "" {
		req.Header.Set("Authorization", "Bearer "+c.token)
	}
	res, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	most := c.max
	if most == 0 {
		most = maxBody
	}
	b, err := io.ReadAll(io.LimitReader(res.Body, most+1))
	if err != nil {
		return err
	}
	if int64(len(b)) > most {
		return errors.New("response too large")
	}
	if res.StatusCode < 200 || res.StatusCode > 299 {
		return StatusError{method, res.StatusCode, reset(res.Header, time.Now())}
	}
	if out == nil || len(b) == 0 {
		return nil
	}
	return json.Unmarshal(b, out)
}
