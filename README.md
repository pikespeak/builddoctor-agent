# BuildDoctor

An agent on a [Fly.io Sprite](https://docs.fly.io/sprites) that runs a 1950s tabloid about your CI. It examines public GitHub Actions pipelines, names what costs time or keeps failing, and prints one newspaper per project while you watch, with moving press photos. Changes are measured on our own test project before we claim an improvement.

Live: https://builddoctor.app

Built for Fly.io Hacksgiving 2026 (November 23 to 29).

## How it works

1. **Read.** Go code reads the workflow, the newest good run and recent failures, and computes facts.
2. **Suspect.** A model may ask for more facts in up to three rounds, from a closed list that code answers. Then it names problems. Every finding must cite facts and may use only numbers from those facts. Ash checks that.
3. **Check.** A council tries to refute each finding: QA (another model), Safety (rules, then a model), Engineer (code) for changes. Code decides; a missing vote is a refusal.
4. **Print.** While the council votes, an editor model drafts a page for each finding on its own, from that finding and its facts. Lines about a refused finding are dropped. It writes the headline, captions, an ad and a horoscope and invents photo scenes. Code checks numbers, names and plain words; QA and Safety vote on every line. GPT Image 2.6 makes up to three GIFs through the OpenAI connector. Failures and weaknesses get no joke.
5. **Grade.** Code computes a grade from A++ to F and shows every deduction. Duration and waiting for a runner do not count.
6. **Measure.** On [ci-patient](https://github.com/pikespeak/ci-patient), the old and the new workflow take turns, eight runs in total.
7. **Verdict.** Code compares the runs: accepted, rejected, not proven or failed.

Other projects are only read. Their code is never run, and nothing is written to them.

## Parts

| Folder | Content |
|---|---|
| `agent/` | The agent in Go: facts, process errors, edits, council, editor, photos, measurement |
| `app/` | Phoenix LiveView, Ash and Postgres: rules, verdicts, pages, agent API |
| `demo/` | The test project |
| `ops/` | Deployment in the Sprite, backup, network rules, audit |

Connectors: GitHub (only our test project) and OpenAI (only two paths). The Sprite holds no key for either. Public projects are read without credentials or with a token that GitHub limits to public data.

## Run the tests

```sh
(cd agent && go vet ./... && go test -race ./...)
(cd app && mix deps.get && mix test)  # needs Postgres on localhost, user and password "postgres"
ops/audit.sh  # known holes and secret patterns
```

## Limits

We do not read build logs, so we can say which step fails, but often not why. The council was tried with 32 planted errors and 11 good findings that we wrote or chose ourselves: none of the planted errors passed, 7 good findings did. That is no guarantee. The editor's lines were not part of that test.
