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
	d.TypeSafe = doctor.NewTypeSafe(os.Getenv("TYPESAFE_GATEWAY"), h)
	if os.Getenv("PICTURES") != "off" {
		d.Develop = doctor.WebP
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
	// Rates a finished edition: doctor rate <audit>
	if len(os.Args) == 3 && os.Args[1] == "rate" {
		if err := d.RateAgain(ctx, os.Args[2]); err != nil {
			log.Fatal(err)
		}
		return
	}
	// Prints an edition that was examined before there was an editor: doctor <audit> <owner/name>
	if len(os.Args) == 3 {
		f, err := d.Public.Read(ctx, os.Args[2])
		if err != nil {
			log.Fatal(err)
		}
		au, err := d.Ash.One(ctx, os.Args[1])
		if err != nil {
			log.Fatal(err)
		}
		if err := d.Print(ctx, au.ID, au.Facts, f.About); err != nil {
			log.Fatal(err)
		}
		return
	}
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
