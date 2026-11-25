defmodule BuilddoctorWeb.HowLiveTest do
  use BuilddoctorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Builddoctor.{Bench, Council}
  alias Builddoctor.Bench.Actor

  @agent [actor: Actor.agent()]
  @me [actor: Actor.requester()]
  @sha String.duplicate("b", 40)
  @t ~U[2026-11-24 10:06:00Z]

  defp measured(walls_before, walls_after, base) do
    audit = Bench.start_audit!("pikespeak/ci-patient", @sha, @me)

    trial =
      Bench.propose_trial!(
        %{
          audit_id: audit.id,
          attempt: 1,
          goal: :wait,
          hypothesis: "x",
          original: "a\nneeds",
          patch: "a",
          branch: "builddoctor/x-trial"
        },
        @agent
      )
      |> Council.pass!()

    audit = audit |> Bench.request_approval!(%{}, @agent) |> Bench.approve_audit!(@me)

    for {id, walls, n} <- [{nil, walls_before, base}, {trial.id, walls_after, base + 50}],
        {wall, i} <- Enum.with_index(walls) do
      job = %{
        name: "vet",
        conclusion: :success,
        started_at: @t,
        completed_at: DateTime.add(@t, wall)
      }

      Bench.record_run!(
        %{
          audit_id: audit.id,
          trial_id: id,
          github_run_id: n + i,
          sha: @sha,
          started_at: @t,
          jobs: [job]
        },
        @agent
      )
    end

    Bench.evaluate_trial!(trial, @agent)
    Bench.finish_audit!(audit, @agent)
  end

  defp planted(name, slot, publish) do
    audit = Bench.plant_audit!(name, slot)
    Bench.record_facts!(audit, %{facts: [%{id: "run", text: "It took 5 s."}]}, @agent)

    finding =
      Bench.record_finding!(
        %{
          audit_id: audit.id,
          position: 1,
          title: "It keeps waiting",
          text: "x",
          evidence: ["run"]
        },
        @agent
      )

    if publish, do: Council.pass!(finding), else: Council.decide!(finding)
    Bench.finish_examination!(Bench.get_audit!(audit.id), %{}, @agent)
  end

  test "without data it explains and claims no result", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/how-it-works")
    assert html =~ "Facts first, proof where we can measure"

    for id <- ~w(steps council probe limits parts), do: assert(has_element?(view, "##{id}"))
    for id <- ~w(numbers proof examples), do: refute(has_element?(view, "##{id}"))
    assert has_element?(view, "a[href='/']", "Examine a project")
    {:ok, home, _} = live(conn, ~p"/")
    assert has_element?(home, "header a[href='/how-it-works']", "How it works")
  end

  test "the newest accepted trial is the proof, and it arrives live", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/how-it-works")
    refute has_element?(view, "#proof")
    old = measured([72, 72, 72], [42, 42, 42], 100)
    new = measured([70, 70, 70], [26, 26, 26], 300)
    measured([70, 70, 70], [70, 70, 70], 500)
    render(view)
    assert has_element?(view, "#numbers", "70 s")
    assert has_element?(view, "#numbers", "26 s")
    assert has_element?(view, "#proof a[href='/a/#{new.id}']")
    refute has_element?(view, "#proof a[href='/a/#{old.id}']")
    assert has_element?(view, "#how-1", "vet")
  end

  test "only chosen projects with a published finding are examples", %{conn: conn} do
    good = planted("gin-gonic/gin", 1, true)
    planted("caddyserver/caddy", 2, false)
    planted("other/project", 3, true)
    {:ok, view, html} = live(conn, ~p"/how-it-works")
    assert has_element?(view, "#examples a[href='/a/#{good.id}']", "It keeps waiting")
    refute html =~ "caddyserver" or html =~ "other/project"
  end
end
