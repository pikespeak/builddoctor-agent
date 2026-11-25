package doctor

import "sync"

// async runs f now; the returned function waits for its answer.
func async[T any](f func() (T, error)) func() (T, error) {
	once := sync.OnceValues(f)
	go once()
	return once
}
