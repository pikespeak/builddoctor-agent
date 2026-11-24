package doctor

import (
	"context"
	"errors"
	"log"
	"sync"
	"time"
)

const (
	maxExaminations = 5
	maxMeasurements = 5
)

// Crew works on many audits at once: one goroutine per audit and one measurement per repository.
type Crew struct {
	Doctor Doctor
	Rest   time.Duration // after a failure

	mu     sync.Mutex
	busy   map[string]string // audit to "examining" or the measured repository
	paused time.Time         // GitHub's limit for reading without credentials
	group  sync.WaitGroup
}

// Run works until the context ends, then waits for its workers.
func (c *Crew) Run(ctx context.Context) {
	defer c.group.Wait()
	for ctx.Err() == nil {
		if err := c.round(ctx); err != nil && ctx.Err() == nil {
			log.Print(err)
		}
		pause(ctx, c.Doctor.Poll)
	}
}

func pause(ctx context.Context, d time.Duration) {
	select {
	case <-ctx.Done():
	case <-time.After(d):
	}
}

func (c *Crew) round(ctx context.Context) error {
	audits, err := c.Doctor.Ash.OpenAll(ctx)
	if err != nil {
		return err
	}
	for i := range audits {
		if au := &audits[i]; c.take(au) {
			c.group.Add(1)
			go func() {
				defer c.group.Done()
				c.work(ctx, au)
			}()
		}
	}
	return nil
}

// take reserves the audit if there is room for it.
func (c *Crew) take(au *Audit) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.busy == nil {
		c.busy = map[string]string{}
	}
	if _, ok := c.busy[au.ID]; ok {
		return false
	}
	if au.State == "examining" && au.Repository != c.Doctor.GitHub.repo && time.Now().Before(c.paused) {
		return false
	}
	kind, room, used := "examining", maxExaminations, 0
	if au.State != "examining" {
		kind, room = "measuring "+au.Repository, maxMeasurements
	}
	for _, k := range c.busy {
		if k == kind && kind != "examining" {
			return false
		}
		if (k == "examining") == (kind == "examining") {
			used++
		}
	}
	if used >= room {
		return false
	}
	c.busy[au.ID] = kind
	return true
}

func (c *Crew) work(ctx context.Context, au *Audit) {
	defer func() {
		c.mu.Lock()
		delete(c.busy, au.ID)
		c.mu.Unlock()
	}()
	err := c.Doctor.work(ctx, au)
	if err == nil || ctx.Err() != nil {
		return
	}
	log.Print(err)
	var s githubLimit
	if errors.As(err, &s) {
		c.mu.Lock()
		c.paused = s.until
		c.mu.Unlock()
		// The time is for watching only; without it the reading goes on as well.
		_ = c.Doctor.Ash.ReportWait(ctx, au.ID, s.until)
		return
	}
	if au.State == "examining" {
		if err := c.Doctor.Ash.ReportError(ctx, au.ID); err != nil {
			log.Print(err)
		}
	}
	pause(ctx, c.Rest)
}
