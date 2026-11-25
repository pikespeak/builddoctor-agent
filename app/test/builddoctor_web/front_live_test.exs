defmodule BuilddoctorWeb.FrontLiveTest do
  use BuilddoctorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Builddoctor.Bench
  alias Builddoctor.Bench.Actor
  alias Builddoctor.Council

  @agent [actor: Actor.agent()]
  @sha String.duplicate("e", 40)

  defp submit(view, project),
    do: view |> form("#plant", %{project: project}) |> render_submit()

  test "from a blank page to an edition", %{conn: conn} do
    {:ok, other, html} = live(conn, ~p"/")
    assert html =~ "0 of 100 pages printed."
    {:ok, view, _} = live(conn, ~p"/")
    assert view |> element("button#place-7") |> render_click() =~ "Project for page 7"
    assert {:error, {:live_redirect, %{to: to}}} = submit(view, "https://github.com/a/b")
    assert [%{slot: 7, repository: "a/b"} = audit] = Bench.planted_audits!()
    assert to == "/a/#{audit.id}"

    Process.sleep(350)

    assert has_element?(
             other,
             "button#place-8[title='Page 8 is free. Print a project here.'] small",
             "Free"
           )

    assert has_element?(other, "a#place-7 small")
    refute has_element?(other, "a#place-7 small", "Free")

    assert has_element?(other, "a#place-7[aria-label*='Being read']") and
             has_element?(other, "#project-7", "Being read")

    assert has_element?(other, "#count", "1 of 100")
    Bench.finish_examination!(audit, %{}, @agent)
    Process.sleep(350)
    assert has_element?(other, "#project-7 a[href='/a/#{audit.id}']", "Nothing found")

    Bench.remove_audit!(audit, actor: Actor.requester())
    Process.sleep(350)
    assert has_element?(other, "button#place-7")
  end

  test "without a choice the first free place is taken", %{conn: conn} do
    Bench.plant_audit!("a/one", 1)
    {:ok, view, _} = live(conn, ~p"/")
    submit(view, "a/two")
    assert Enum.map(Bench.planted_audits!(), & &1.slot) == [1, 2]
  end

  test "errors are explained and nothing is lost", %{conn: conn} do
    Bench.plant_audit!("a/b", 1)
    {:ok, view, _} = live(conn, ~p"/")
    assert (html = submit(view, "what is this")) =~ "owner/name or as its GitHub address"
    assert html =~ ~s(value="what is this") and html =~ ~s(aria-invalid="true")
    assert submit(view, "A/B") =~ "already has its edition"
    view |> element("button#place-9") |> render_click()
    Bench.plant_audit!("c/d", 9)
    assert submit(view, "e/f") =~ "Somebody was faster"
    refute render(view) =~ "Project for page 9"
    assert render_click(view, "choose", %{"slot" => "x"}) =~ "Public project"
  end

  test "a full paper says so", %{conn: conn} do
    for slot <- 1..100,
        do: Bench.plant_audit!("a/b#{slot}", slot, actor: Actor.requester())

    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ "The paper is full. All 100 pages are printed."
    refute has_element?(view, "#plant")
    assert render_submit(view, "plant", %{"project" => "x/y"}) =~ "choose a blank page"
  end

  test "our own project stands apart with its result", %{conn: conn} do
    me = [actor: Actor.requester()]
    audit = Bench.start_audit!("pikespeak/ci-patient", @sha, me)
    words = fn -> conn |> live(~p"/") |> elem(1) |> element("#own") |> render() end
    assert words.() =~ "reading our own"

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

    audit = Bench.request_approval!(audit, %{}, @agent)
    assert words.() =~ "waits for the requester"
    audit = Bench.approve_audit!(audit, me)
    assert words.() =~ "being measured"

    for {id, walls, base} <- [{nil, [70, 72, 74], 1}, {trial.id, [41, 42, 47], 9}],
        {wall, i} <- Enum.with_index(walls) do
      at = ~U[2026-11-23 19:44:00Z]

      Bench.record_run!(
        %{
          audit_id: audit.id,
          trial_id: id,
          github_run_id: base + i,
          sha: @sha,
          started_at: at,
          jobs: [
            %{
              name: "vet",
              conclusion: :success,
              started_at: at,
              completed_at: DateTime.add(at, wall)
            }
          ]
        },
        @agent
      )
    end

    Bench.evaluate_trial!(trial, @agent)
    Bench.finish_audit!(audit, @agent)
    assert words.() =~ "30 seconds back at the median. 72 s → 42 s"
    assert conn |> live(~p"/") |> elem(1) |> has_element?("a#extra", "30 seconds back")
  end

  test "our own project without a proof says so", %{conn: conn} do
    me = [actor: Actor.requester()]
    audit = Bench.start_audit!("pikespeak/ci-patient", @sha, me)

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

    audit = audit |> Bench.request_approval!(%{}, @agent) |> Bench.approve_audit!(me)
    Bench.evaluate_trial!(trial, @agent)
    Bench.finish_audit!(audit, @agent)
    {:ok, view, _} = live(conn, ~p"/")
    assert has_element?(view, "#own", "Not proven")
    refute has_element?(view, "#extra")
  end

  test "a long suspicion is shortened in the list", %{conn: conn} do
    audit = Bench.plant_audit!("a/b", 5)

    Bench.propose_trial!(
      %{
        audit_id: audit.id,
        attempt: 1,
        goal: :wait,
        hypothesis: String.duplicate("word ", 60),
        original: "a\nneeds",
        patch: "a",
        branch: "builddoctor/x-trial"
      },
      @agent
    )
    |> Council.pass!()

    Bench.finish_examination!(audit, %{}, @agent)
    {:ok, view, _} = live(conn, ~p"/")
    assert has_element?(view, "#project-5", "Suspicion") and has_element?(view, "#project-5", "…")
  end
end
