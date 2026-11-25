package doctor

import (
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const workflowPath = ".github/workflows/ci.yml"

// GitHub works on one repository through the Sprites connector, without a token.
type GitHub struct {
	c    caller
	repo string
}

// NewGitHub takes the gateway base URL.
func NewGitHub(gateway, repo string, h *http.Client) GitHub {
	return GitHub{caller{base: gateway + "/repos/" + repo, media: "application/json", http: h}, repo}
}

type ghRun struct {
	ID         int64     `json:"id"`
	Status     string    `json:"status"`
	Conclusion string    `json:"conclusion"`
	Event      string    `json:"event"`
	HeadSHA    string    `json:"head_sha"`
	Started    time.Time `json:"run_started_at"`
}

// URL of a run for people.
func (g GitHub) URL(run int64) string {
	return fmt.Sprintf("https://github.com/%s/actions/runs/%d", g.repo, run)
}

// File returns the workflow and its blob id at a ref.
func (g GitHub) File(ctx context.Context, ref string) (string, string, error) {
	var f struct{ Type, Encoding, Content, SHA string }
	if err := g.c.do(ctx, "GET", "/contents/"+workflowPath+"?ref="+url.QueryEscape(ref), nil, &f); err != nil {
		return "", "", err
	}
	if f.Type != "file" || f.Encoding != "base64" {
		return "", "", errors.New("workflow is not a plain file")
	}
	b, err := base64.StdEncoding.DecodeString(strings.ReplaceAll(f.Content, "\n", ""))
	if err != nil {
		return "", "", err
	}
	if len(b) == 0 || len(b) > 20_000 {
		return "", "", errors.New("workflow is empty or too large")
	}
	return string(b), f.SHA, nil
}

// Branch makes sure a branch exists at a commit; an existing branch is kept.
func (g GitHub) Branch(ctx context.Context, name, sha string) error {
	err := g.c.do(ctx, "POST", "/git/refs", map[string]string{"ref": "refs/heads/" + name, "sha": sha}, nil)
	var s StatusError
	if errors.As(err, &s) && s.Code == http.StatusUnprocessableEntity {
		return nil
	}
	return err
}

// Put writes the workflow on a branch unless it already has this content.
func (g GitHub) Put(ctx context.Context, branch, content, message string) error {
	have, blob, err := g.File(ctx, branch)
	if err != nil || have == content {
		return err
	}
	return g.c.do(ctx, "PUT", "/contents/"+workflowPath, map[string]string{
		"message": message, "branch": branch, "sha": blob,
		"content": base64.StdEncoding.EncodeToString([]byte(content)),
	}, nil)
}

// Runs lists recent runs with a filter such as "branch=x&event=y".
func (g GitHub) Runs(ctx context.Context, filter string) ([]ghRun, error) {
	var r struct {
		Runs []ghRun `json:"workflow_runs"`
	}
	err := g.c.do(ctx, "GET", "/actions/runs?per_page=50&"+filter, nil, &r)
	return r.Runs, err
}

// DefaultBranch of the repository; an odd name is refused.
func (g GitHub) DefaultBranch(ctx context.Context) (string, error) {
	var r struct {
		Branch string `json:"default_branch"`
	}
	if err := g.c.do(ctx, "GET", "", nil, &r); err != nil {
		return "", err
	}
	if !branchName.MatchString(r.Branch) {
		return "", refused{errors.New("The name of the default branch is not supported.")}
	}
	return r.Branch, nil
}

// Successful runs of the workflow on a branch, the newest first.
func (g GitHub) Successful(ctx context.Context, branch string) ([]ghRun, error) {
	var r struct {
		Runs []ghRun `json:"workflow_runs"`
	}
	err := g.c.do(ctx, "GET", "/actions/workflows/ci.yml/runs?status=success&per_page=10&branch="+url.QueryEscape(branch), nil, &r)
	return r.Runs, err
}

// Dispatch starts the workflow on a branch.
func (g GitHub) Dispatch(ctx context.Context, branch string) error {
	return g.c.do(ctx, "POST", "/actions/workflows/ci.yml/dispatches", map[string]string{"ref": branch}, nil)
}

// Run returns one run.
func (g GitHub) Run(ctx context.Context, id int64) (ghRun, error) {
	var r ghRun
	err := g.c.do(ctx, "GET", fmt.Sprintf("/actions/runs/%d", id), nil, &r)
	return r, err
}

// Jobs returns the jobs of a completed run.
func (g GitHub) Jobs(ctx context.Context, id int64) ([]Job, error) {
	var r struct{ Jobs []Job }
	if err := g.c.do(ctx, "GET", fmt.Sprintf("/actions/runs/%d/jobs?per_page=100", id), nil, &r); err != nil {
		return nil, err
	}
	if len(r.Jobs) == 0 {
		return nil, errors.New("run has no jobs")
	}
	return r.Jobs, nil
}
