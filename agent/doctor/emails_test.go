package doctor

import (
	"strings"
	"testing"
)

func TestModelsGetNoEmailAddresses(t *testing.T) {
	got := withoutEmails("on: push\n# ask jane.doe+ci@mail.example.org\n  - uses: some/action@release.branch # by me@z.org\n  - run: git config user.email 'x@y.de'\n")
	if strings.Contains(got, "jane") || strings.Contains(got, "x@y") || strings.Contains(got, "me@z") || strings.Count(got, "[email]") != 3 || !strings.Contains(got, "action@release.branch") {
		t.Fatal(got)
	}
	if got := removed(withoutEmails("  - uses: a/b@old.branch\n# c@d.org"), withoutEmails("  - uses: a/b@new.branch")); !strings.Contains(got, "-   - uses: a/b@old.branch") || strings.Contains(got, "c@d") {
		t.Fatal(got)
	}
	w := curious()
	w.file = strings.Replace(wf, "on: push", "# owner: boss@corp.example\non: push", 1)
	c, _ := w.crew(t)
	w.until(t, c, func() bool { return len(w.done) == 1 })
	if len(w.rounds) != 1 || strings.Contains(w.rounds[0]+w.final, "boss@") || !strings.Contains(w.rounds[0]+w.final, "[email]") {
		t.Fatal(w.rounds, w.final)
	}
	if w.trials["a"]["original"] != w.file {
		t.Fatal("the stored file stays exact, so that the patch fits")
	}
}
