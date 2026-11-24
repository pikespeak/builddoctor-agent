package doctor

import (
	"net/http"
	"net/url"
	"os"
	"regexp"
	"strings"
	"sync"
)

// readToken adds a token for public repositories to requests for one address, and to nothing else.
// Reading works without it as well: a missing, odd or refused token means a request without credentials.
type readToken struct {
	home *url.URL
	file string // read for every request, so that a new token needs no restart
	next http.RoundTripper

	mu      sync.Mutex
	refused string
}

var tokenShape = regexp.MustCompile(`^github_pat_[A-Za-z0-9_]{20,240}$`)

func (r *readToken) token() string {
	b, err := os.ReadFile(r.file)
	t := strings.TrimSpace(string(b))
	r.mu.Lock()
	defer r.mu.Unlock()
	if err != nil || !tokenShape.MatchString(t) || t == r.refused {
		return ""
	}
	return t
}

func (r *readToken) RoundTrip(req *http.Request) (*http.Response, error) {
	t := ""
	if req.Method == http.MethodGet && req.URL.Scheme == r.home.Scheme && req.URL.Host == r.home.Host {
		t = r.token()
	}
	if t == "" {
		return r.next.RoundTrip(req)
	}
	with := req.Clone(req.Context())
	with.Header.Set("Authorization", "Bearer "+t)
	res, err := r.next.RoundTrip(with)
	if err != nil {
		return nil, err
	}
	switch {
	case res.StatusCode == http.StatusUnauthorized:
		r.mu.Lock()
		r.refused = t
		r.mu.Unlock()
	case res.StatusCode == http.StatusForbidden && res.Header.Get("Retry-After") == "" && res.Header.Get("X-RateLimit-Remaining") != "0":
		// An organization may refuse this kind of token for its public projects; that is not a limit.
	default:
		return res, nil
	}
	res.Body.Close()
	return r.next.RoundTrip(req)
}
