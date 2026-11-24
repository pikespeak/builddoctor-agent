// Command spike runs the connector proof inside a Sprite.
package main

import (
	"context"
	"flag"
	"fmt"
	"net/http"
	"os"
	"time"

	"github.com/pikespeak/builddoctor/agent/spike"
)

func main() {
	gh := flag.String("github", "", "GitHub gateway base URL")
	ai := flag.String("openai", "", "OpenAI gateway base URL")
	model := flag.String("model", "gpt-6.2-astra", "model name")
	run := flag.Int64("run", 0, "workflow run id")
	flag.Parse()
	if *gh == "" || *ai == "" || *run <= 0 {
		flag.Usage()
		os.Exit(2)
	}
	if err := prove(*gh, *ai, *model, *run); err != nil {
		fmt.Fprintln(os.Stderr, "spike:", err)
		os.Exit(1)
	}
}

func prove(gh, ai, model string, run int64) error {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	c := spike.Client{GitHub: gh, OpenAI: ai, HTTP: &http.Client{}}
	const repo = "pikespeak/ci-patient"
	wf, err := c.Workflow(ctx, repo, ".github/workflows/ci.yml")
	if err != nil {
		return fmt.Errorf("github workflow: %w", err)
	}
	jobs, err := c.Jobs(ctx, repo, run)
	if err != nil {
		return fmt.Errorf("github jobs: %w", err)
	}
	fmt.Printf("github ok: workflow %d bytes\n", len(wf))
	for _, j := range jobs {
		fmt.Printf("  %s %.0f s\n", j.Name, j.Seconds())
	}
	h, err := c.Ask(ctx, model, wf, jobs)
	if err != nil {
		return fmt.Errorf("openai: %w", err)
	}
	fmt.Printf("openai ok: %s, %d input and %d output tokens\n%s\n", model, h.InputTokens, h.OutputTokens, h.Text)
	return nil
}
