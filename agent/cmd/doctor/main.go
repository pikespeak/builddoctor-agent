// Command doctor is the agent that runs on the Fly.io Sprite.
package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/pikespeak/builddoctor/agent/doctor"
)

func main() {
	get := func(k string) string {
		v := os.Getenv(k)
		if v == "" {
			log.Fatalf("%s is not set", k)
		}
		return v
	}
	h := &http.Client{Timeout: 2 * time.Minute}
	d := doctor.Doctor{
		Ash:    doctor.NewAsh(get("APP_URL"), get("AGENT_TOKEN"), h),
		GitHub: doctor.NewGitHub(get("GITHUB_GATEWAY"), get("REPOSITORY"), h),
		Public: doctor.NewPublic("https://api.github.com", 30*time.Second),
		OpenAI: doctor.NewOpenAI(get("OPENAI_GATEWAY"), get("OPENAI_MODEL"), h),
		Poll:   5 * time.Second,
		RunMax: 20 * time.Minute,
	}
	if file := os.Getenv("GITHUB_READ_TOKEN_FILE"); file != "" {
		public, err := d.Public.WithToken(file)
		if err != nil {
			log.Fatal(err)
		}
		d.Public = public
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	if os.Getenv("ONCE") == "" {
		(&doctor.Crew{Doctor: d, Rest: time.Minute}).Run(ctx)
		return
	}
	for ctx.Err() == nil {
		worked, err := d.Step(ctx)
		if err != nil {
			log.Print(err)
		}
		if !worked || err != nil {
			return
		}
	}
}
