package doctor

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

const fakeToken = "github_pat_" + "0123456789abcdefghij_TEST"

// keeper answers like GitHub and remembers the credentials of every request.
type keeper struct {
	auth   []string
	answer func(auth string, res http.ResponseWriter)
}

func (k *keeper) ServeHTTP(res http.ResponseWriter, req *http.Request) {
	a := req.Header.Get("Authorization")
	k.auth = append(k.auth, a)
	k.answer(a, res)
}

func fine(_ string, res http.ResponseWriter) { io.WriteString(res, `{}`) }

func tokenFile(t *testing.T, content string) string {
	f := filepath.Join(t.TempDir(), "token")
	if err := os.WriteFile(f, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	return f
}

func reader(t *testing.T, k *keeper, file string) Public {
	s := httptest.NewServer(k)
	t.Cleanup(s.Close)
	p, err := NewPublic(s.URL, time.Second).WithToken(file)
	if err != nil {
		t.Fatal(err)
	}
	return p
}

func (p Public) get() error { return p.c.do(context.Background(), "GET", "/x", nil, nil) }

func TestTokenIsSentToTheBaseOnly(t *testing.T) {
	k := &keeper{answer: fine}
	p := reader(t, k, tokenFile(t, fakeToken+"\n"))
	if err := p.get(); err != nil || k.auth[0] != "Bearer "+fakeToken {
		t.Fatal(err, k.auth)
	}
	other := &keeper{answer: fine}
	s := httptest.NewServer(other)
	defer s.Close()
	if _, err := p.c.http.Get(s.URL); err != nil || other.auth[0] != "" {
		t.Fatal("another address got the token", err)
	}
	if _, err := p.c.http.Post(p.c.base, "", strings.NewReader("x")); err != nil || k.auth[1] != "" {
		t.Fatal("only reading uses the token", err)
	}
}

func TestTokenDoesNotFollowARedirect(t *testing.T) {
	away := &keeper{answer: fine}
	s := httptest.NewServer(away)
	defer s.Close()
	k := &keeper{answer: func(_ string, res http.ResponseWriter) {
		res.Header().Set("Location", s.URL)
		res.WriteHeader(http.StatusFound)
	}}
	if err := reader(t, k, tokenFile(t, fakeToken)).get(); err == nil || len(away.auth) != 0 || strings.Contains(err.Error(), "github_pat_") {
		t.Fatal(err, away.auth)
	}
}

func TestWithoutAUsableTokenReadingGoesOn(t *testing.T) {
	for name, file := range map[string]string{
		"missing": filepath.Join(t.TempDir(), "none"), "empty": tokenFile(t, ""), "classic": tokenFile(t, "ghp_"+"0123456789abcdefghij0123"),
		"two lines": tokenFile(t, fakeToken+"\nX: y"), "odd": tokenFile(t, "github_pat_ä"),
	} {
		k := &keeper{answer: fine}
		if err := reader(t, k, file).get(); err != nil || len(k.auth) != 1 || k.auth[0] != "" {
			t.Fatal(name, err, k.auth)
		}
	}
}

func TestARefusedTokenIsNotUsedAgain(t *testing.T) {
	k := &keeper{answer: func(a string, res http.ResponseWriter) {
		if a == "Bearer "+fakeToken {
			res.WriteHeader(http.StatusUnauthorized)
			return
		}
		fine(a, res)
	}}
	file := tokenFile(t, fakeToken)
	p := reader(t, k, file)
	for range 2 {
		if err := p.get(); err != nil {
			t.Fatal(err)
		}
	}
	if len(k.auth) != 3 || k.auth[1] != "" || k.auth[2] != "" {
		t.Fatal(k.auth)
	}
	if err := os.WriteFile(file, []byte(fakeToken+"2"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := p.get(); err != nil || k.auth[3] != "Bearer "+fakeToken+"2" {
		t.Fatal("a new token is used without a restart", err, k.auth)
	}
}

func TestARefusingOrganizationIsReadWithoutTheToken(t *testing.T) {
	k := &keeper{answer: func(a string, res http.ResponseWriter) {
		if a != "" {
			res.Header().Set("X-RateLimit-Remaining", "4000")
			res.WriteHeader(http.StatusForbidden)
			return
		}
		fine(a, res)
	}}
	p := reader(t, k, tokenFile(t, fakeToken))
	if err := p.get(); err != nil || len(k.auth) != 2 {
		t.Fatal(err, k.auth)
	}
	if p.get(); k.auth[2] == "" {
		t.Fatal("other projects still use it")
	}
}

func TestALimitStaysALimit(t *testing.T) {
	for _, h := range []http.Header{{"X-Ratelimit-Remaining": {"0"}}, {"Retry-After": {"60"}}} {
		k := &keeper{answer: func(_ string, res http.ResponseWriter) {
			for n, v := range h {
				res.Header()[n] = v
			}
			res.WriteHeader(http.StatusForbidden)
		}}
		err := reader(t, k, tokenFile(t, fakeToken)).get()
		if _, ok := limited(err); !ok || len(k.auth) != 1 || strings.Contains(err.Error(), "github_pat_") {
			t.Fatal(err, k.auth)
		}
	}
}

func TestPrivateIsRefusedWithATokenToo(t *testing.T) {
	k := &keeper{answer: func(_ string, res http.ResponseWriter) {
		io.WriteString(res, `{"private":true,"default_branch":"main"}`)
	}}
	if _, err := reader(t, k, tokenFile(t, fakeToken)).Read(context.Background(), "a/b"); err == nil || !strings.Contains(err.Error(), "public") || len(k.auth) != 1 {
		t.Fatal(err, k.auth)
	}
}

func TestErrorsOfTheNetworkNameNoToken(t *testing.T) {
	p, _ := NewPublic("http://127.0.0.1:1", time.Second).WithToken(tokenFile(t, fakeToken))
	if err := p.get(); err == nil || strings.Contains(err.Error(), "github_pat_") {
		t.Fatal(err)
	}
	if _, err := NewPublic("://", time.Second).WithToken(""); err == nil {
		t.Fatal("an odd address")
	}
}
