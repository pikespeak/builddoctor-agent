// Command council measures how many planted errors the council catches and how many good
// findings it blocks. It writes nothing and needs only the OpenAI connector.
package main

import (
	"context"
	_ "embed"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"regexp"
	"sort"
	"time"

	"github.com/pikespeak/builddoctor/agent/doctor"
)

//go:embed cases.json
var raw []byte

var number = regexp.MustCompile(`\d+(?:[.,]\d+)*`)

func main() {
	var d struct {
		Facts map[string][]doctor.Fact
		Cases []struct {
			Repo, ID, Kind, Title, Text, Advice string
			Evidence                            []string
		}
	}
	if err := json.Unmarshal(raw, &d); err != nil {
		log.Fatal(err)
	}
	ai := doctor.NewOpenAI(os.Getenv("OPENAI_GATEWAY"), "", &http.Client{Timeout: 3 * time.Minute})
	lists, kinds, gate := map[string][]doctor.Statement{}, map[string]string{}, map[string]string{}
	for _, c := range d.Cases {
		cited, known := []doctor.Fact{}, map[string]bool{}
		for _, f := range d.Facts[c.Repo] {
			for _, e := range c.Evidence {
				if f.ID == e {
					cited = append(cited, f)
					for _, n := range number.FindAllString(f.Text, -1) {
						known[n] = true
					}
				}
			}
		}
		for _, n := range number.FindAllString(c.Title+" "+c.Text+" "+c.Advice, -1) {
			if !known[n] {
				gate[c.ID] = "numbers" // the application refuses it before the council sees it
			}
		}
		kinds[c.ID] = c.Kind
		lists[c.Repo] = append(lists[c.Repo], doctor.Statement{ID: c.ID, Title: c.Title, Text: c.Text, Advice: c.Advice, Facts: cited})
	}
	qa, safe, in, out := map[string]doctor.Vote{}, map[string]doctor.Vote{}, 0, 0
	for repo, list := range lists {
		a, i, o, err := ai.QA(context.Background(), list, d.Facts[repo], "")
		if err != nil {
			log.Fatal(err)
		}
		b, k, l, err := ai.Safety(context.Background(), list)
		if err != nil {
			log.Fatal(err)
		}
		for _, s := range list {
			qa[s.ID], safe[s.ID] = a[s.ID], b[s.ID]
		}
		in, out = in+i+k, out+o+l
	}
	type row struct{ total, numbers, qa, safety, published int }
	sum, ids := map[string]*row{}, []string{}
	for id := range kinds {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	for _, id := range ids {
		r := sum[kinds[id]]
		if r == nil {
			r = &row{}
			sum[kinds[id]] = r
		}
		r.total++
		ok := true
		if gate[id] != "" {
			r.numbers++
			ok = false
		}
		if !qa[id].Pass {
			r.qa++
			ok = false
		}
		if !safe[id].Pass {
			r.safety++
			ok = false
		}
		if ok {
			r.published++
		}
		if ok != (kinds[id] == "good") {
			fmt.Printf("UNEXPECTED %s %s published=%v | qa %s | safety %s\n", kinds[id], id, ok, qa[id].Reason, safe[id].Reason)
		}
	}
	for k, r := range sum {
		fmt.Printf("%-7s total %2d, refused by numbers %2d, qa %2d, safety %2d, published %2d\n", k, r.total, r.numbers, r.qa, r.safety, r.published)
	}
	fmt.Printf("tokens %d in, %d out, about $%.3f\n", in, out, float64(in*2+out*10)/1e6)
}
