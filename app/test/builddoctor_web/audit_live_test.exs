defmodule BuilddoctorWeb.AuditLiveTest do
  use BuilddoctorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Builddoctor.Bench
  alias Builddoctor.Bench.Actor
  alias Builddoctor.Council

  @agent [actor: Actor.agent()]
  @sha String.duplicate("c", 40)
  @t ~U[2026-11-23 19:44:00Z]

  defp job(name, from, to, conclusion \\ :success),
    do: %{
      name: name,
      conclusion: conclusion,
      started_at: DateTime.add(@t, from),
      completed_at: DateTime.add(@t, to)
    }

  defp audit, do: Bench.start_audit!("pikespeak/ci-patient", @sha, actor: Actor.requester())

  defp waiting(goal \\ :wait) do
    audit = audit()

    trial =
      Bench.propose_trial!(
        %{
          audit_id: audit.id,
          attempt: 1,
          goal: goal,
          hypothesis: "Build need not wait.",
          original: "a\nb\nc\nd\ne\nneeds",
          patch: "a\nb\nc\nd\ne\nfree",
          branch: "builddoctor/x-trial"
        },
        @agent
      )
      |> Council.pass!()

    {Bench.request_approval!(
       audit,
       %{examined_jobs: [job("vet", 0, 10), job("build", 12, 30)]},
       @agent
     ), trial}
  end

  defp record(audit, trial, walls, base) do
    for {w, i} <- Enum.with_index(walls) do
      Bench.record_run!(
        %{
          audit_id: audit.id,
          trial_id: trial && trial.id,
          github_run_id: base + i,
          sha: @sha,
          started_at: @t,
          warmup: false,
          jobs: [job("vet", 0, 5), job("build", 0, w)]
        },
        @agent
      )
    end
  end

  defp requester(conn),
    do: post(conn, ~p"/requester", %{"key" => "test-requester-key-0123456789abcdef"})

  test "without an audit the page says so", %{conn: conn} do
    {:ok, _, html} = live(conn, ~p"/a/nonsense")
    assert html =~ "No audit here"
    assert conn |> get(~p"/a/#{Ash.UUID.generate()}/photo/1.jpg") |> response(404)
  end

  test "a visitor follows the audit live but cannot decide", %{conn: conn} do
    audit = audit()
    {:ok, view, html} = live(conn, ~p"/a/#{audit.id}")

    assert html =~ "This page updates by itself" and
             html =~ "measured on its own test project only"

    refute html =~ ~s(id="jobs")

    {audit, _} = with_trial(audit)
    Process.sleep(350)
    html = render(view)
    assert html =~ "Build need not wait." and html =~ "Waiting for the requester."
    refute has_element?(view, "button", "Start the trial")
    assert has_element?(view, "#change li[data-kind=removed]", "needs")
    assert has_element?(view, "#change li[data-kind=added]", "free")
    assert has_element?(view, "#change li[data-kind=same]", "e")
    assert has_element?(view, "#change li[data-kind=gap]", "2 unchanged lines")
    assert render_click(view, "approve") =~ "not possible"
    assert Bench.get_audit!(audit.id).state == :awaiting_approval
  end

  defp with_trial(audit) do
    trial =
      Bench.propose_trial!(
        %{
          audit_id: audit.id,
          attempt: 1,
          goal: :wait,
          hypothesis: "Build need not wait.",
          original: "a\nb\nc\nd\ne\nneeds",
          patch: "a\nb\nc\nd\ne\nfree",
          branch: "builddoctor/x-trial"
        },
        @agent
      )
      |> Council.pass!()

    {Bench.request_approval!(
       audit,
       %{examined_jobs: [job("vet", 0, 10), job("build", 12, 30)]},
       @agent
     ), trial}
  end

  test "only the right key unlocks the decision", %{conn: conn} do
    page = conn |> get(~p"/requester") |> html_response(200)
    assert page =~ "Requester key" and page =~ "border-2" and page =~ ~s(aria-invalid="false")
    page = conn |> post(~p"/requester", %{"key" => "wrong"}) |> html_response(403)
    assert page =~ "not right" and page =~ ~s(aria-describedby="key-error")
    assert conn |> post(~p"/requester", %{}) |> html_response(403)
    {audit, _} = waiting()
    {:ok, view, _} = conn |> requester() |> recycle() |> live(~p"/a/#{audit.id}")
    html = view |> element("button", "Start the trial") |> render_click()
    assert html =~ "0 of 8 runs finished"
    view |> element("button", "Stop") |> render_click()
    assert view |> element("button", "Keep going") |> render_click() =~ "0 of 8"
    view |> element("button", "Stop") |> render_click()
    assert has_element?(view, "#sure", "will not count")
    assert view |> element("button", "Stop it") |> render_click() =~ "Stopped by the requester."
  end

  test "unlocking leads back to the audit and nowhere else", %{conn: conn} do
    {audit, _} = waiting()
    {:ok, view, _} = live(conn, ~p"/a/#{audit.id}")
    assert has_element?(view, "a[href='/requester?audit=#{audit.id}']", "Unlock")
    key = "test-requester-key-0123456789abcdef"
    page = conn |> get(~p"/requester?audit=#{audit.id}") |> html_response(200)
    assert page =~ ~s(name="audit" value="#{audit.id}")
    sent = fn id -> conn |> post(~p"/requester", %{"key" => key, "audit" => id}) end
    assert redirected_to(sent.(audit.id)) == "/a/#{audit.id}"
    assert redirected_to(sent.("//evil.example")) == "/"
  end

  test "the queue before the first job counts as waiting", %{conn: conn} do
    {audit, trial} = waiting()
    audit = Bench.approve_audit!(audit, actor: Actor.requester())

    for {side, base} <- [{nil, 11}, {trial.id, 21}], i <- 0..2 do
      Bench.record_run!(
        %{
          audit_id: audit.id,
          trial_id: side,
          github_run_id: base + i,
          sha: @sha,
          started_at: @t,
          warmup: false,
          jobs: [job("vet", 30, 60)]
        },
        @agent
      )
    end

    Bench.evaluate_trial!(trial, @agent)
    Bench.finish_audit!(audit, @agent)
    {:ok, view, _} = live(conn, ~p"/a/#{audit.id}")
    assert has_element?(view, "#timeline-0 [style='left:50.0%;width:50.0%']")
    assert has_element?(view, "#timeline-0", "30 s")
  end

  test "one line per run, and a bill in minutes", %{conn: conn} do
    {audit, trial} = waiting(:bill)
    url = "https://github.com/pikespeak/ci-patient/actions/runs/1"

    for {kind, text} <- [run_started: "Run 1 of 8 started.", run_finished: "Run 1 of 8 finished."] do
      Bench.log_event!(
        %{audit_id: audit.id, kind: kind, status: :ok, message: text, reference: url},
        @agent
      )
    end

    audit = Bench.approve_audit!(audit, actor: Actor.requester())

    for {side, n, walls} <- [{nil, 300, [110, 115, 118]}, {trial, 400, [50, 51, 52]}] do
      record(audit, side, walls, n)
    end

    Bench.evaluate_trial!(trial, @agent)
    Bench.finish_audit!(audit, @agent)
    {:ok, _, html} = live(conn, ~p"/a/#{audit.id}")
    assert html =~ "1 calculated runner minute back, every run."
    assert html =~ "Run 1 of 8 finished." and not (html =~ "Run 1 of 8 started.")
    assert html =~ "Median runner minutes (calculated)"
  end

  test "a whole saving in every run and half seconds are named exactly", %{conn: conn} do
    {audit, trial} = waiting()
    audit = Bench.approve_audit!(audit, actor: Actor.requester())
    record(audit, nil, [70, 70, 71, 71], 500)
    record(audit, trial, [40, 40, 40, 40], 600)
    Bench.evaluate_trial!(trial, @agent)
    Bench.finish_audit!(audit, @agent)
    {:ok, _, html} = live(conn, ~p"/a/#{audit.id}")
    assert html =~ "30.5 seconds back at the median."
  end

  test "one second, every run", %{conn: conn} do
    {audit, trial} = waiting()
    audit = Bench.approve_audit!(audit, actor: Actor.requester())
    record(audit, nil, [8, 8, 8], 700)
    record(audit, trial, [7, 7, 7], 800)
    Bench.evaluate_trial!(trial, @agent)
    Bench.finish_audit!(audit, @agent)
    {:ok, _, html} = live(conn, ~p"/a/#{audit.id}")
    assert html =~ "1 second back, every run."
  end

  test "the timeline follows the running jobs", %{conn: conn} do
    {audit, trial} = waiting()
    audit = Bench.approve_audit!(audit, actor: Actor.requester())
    {:ok, view, _} = live(conn, ~p"/a/#{audit.id}")
    refute has_element?(view, "#timeline-0")

    live_jobs = [%{name: "vet", stage: :running}]

    audit =
      Bench.report_progress!(
        audit,
        %{live_number: 1, live_side: :baseline, live_jobs: live_jobs},
        @agent
      )

    Bench.log_event!(
      %{audit_id: audit.id, kind: :run_started, status: :ok, message: "Run 1 of 8 started."},
      @agent
    )

    Process.sleep(350)
    assert rows(view) == ["not started", "not started"]
    assert render(view) =~ "now without the change"

    Bench.report_progress!(audit, %{live_side: :trial, live_jobs: live_jobs}, @agent)
    record(audit, trial, [20], 1)
    Process.sleep(350)
    assert render(view) =~ "now with the change"

    assert {:error, _} =
             Bench.report_progress(audit, %{live_jobs: [%{name: "<b>", stage: :running}]}, @agent)
  end

  defp rows(view) do
    view
    |> element("#timeline-0")
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("li > span:last-child")
    |> Enum.map(&LazyHTML.text/1)
  end

  test "while measuring, no seconds of an older run are shown", %{conn: conn} do
    {audit, _} = waiting()
    audit = Bench.approve_audit!(audit, actor: Actor.requester())
    {:ok, view, html} = live(conn, ~p"/a/#{audit.id}")
    refute html =~ "10 s" or html =~ "18 s"

    now = DateTime.utc_now()

    Bench.report_progress!(
      audit,
      %{
        live_number: 1,
        live_side: :baseline,
        live_jobs: [
          %{
            name: "vet",
            stage: :done,
            started_at: DateTime.add(now, -50),
            completed_at: DateTime.add(now, -43)
          },
          %{name: "build", stage: :running, started_at: DateTime.add(now, -40)}
        ]
      },
      @agent
    )

    Process.sleep(350)
    assert ["7 s", "running, 4" <> _ = first] = rows(view)
    Process.sleep(2100)
    assert ["7 s", later] = rows(view)
    assert later != first

    Bench.report_progress!(
      audit,
      %{
        live_jobs: [
          %{
            name: "vet",
            stage: :done,
            started_at: now,
            completed_at: DateTime.add(now, -1)
          },
          %{name: "build", stage: :queued}
        ]
      },
      @agent
    )

    Process.sleep(1400)
    assert rows(view) == ["0 s", "not started"]
  end

  for {walls, text} <- [
        {[41, 42, 47], "30 seconds back at the median."},
        {[72, 73, 74], "No seconds saved."},
        {[60, 65, 71], "cannot prove it yet"}
      ] do
    test "shows the verdict and its proof: #{text}", %{conn: conn} do
      {audit, trial} = waiting()
      audit = Bench.approve_audit!(audit, actor: Actor.requester())
      record(audit, nil, [70, 72, 74], 100)
      record(audit, trial, unquote(walls), 200)
      Bench.evaluate_trial!(trial, @agent)
      Bench.finish_audit!(audit, @agent)
      {:ok, view, html} = live(conn, ~p"/a/#{audit.id}")
      assert html =~ unquote(text) and html =~ "72 s (70 to 74)"
      assert has_element?(view, "#timeline-0", "72 s") and has_element?(view, "#timeline-1")
      assert has_element?(view, "#suggestion") == (unquote(text) =~ "back")
      if unquote(text) =~ "back", do: assert(html =~ "Measured by BuildDoctor")
      assert view |> element("button", "Show the proof") |> render_click() =~ "actions/runs/100"
    end
  end

  test "a broken change is shown as such, with a bill goal", %{conn: conn} do
    {audit, trial} = waiting(:bill)
    {:ok, _, html} = live(conn, ~p"/a/#{audit.id}")
    assert html =~ "Runner minutes (calculated)"
    audit = Bench.approve_audit!(audit, actor: Actor.requester())

    Bench.record_run!(
      %{
        audit_id: audit.id,
        trial_id: trial.id,
        github_run_id: 9,
        sha: @sha,
        started_at: @t,
        jobs: [job("vet", 0, 5, :failure)]
      },
      @agent
    )

    Bench.evaluate_trial!(trial, @agent)
    Bench.finish_audit!(audit, @agent)
    {:ok, view, html} = live(conn, ~p"/a/#{audit.id}")
    assert html =~ "never touched" and html =~ "no runs"
    assert view |> element("button", "Show the proof") |> render_click() =~ "(failed)"
  end

  test "a planted project shows a suspicion or nothing, never a proof", %{conn: conn} do
    long = String.duplicate("long name ", 5)

    for {repo, slot, trial?} <- [{"a/b", 1, true}, {"c/d", 2, false}] do
      audit = Bench.plant_audit!(repo, slot)

      audit =
        Bench.identify_audit!(audit, %{workflow_path: ".github/workflows/gin.yml"}, @agent)

      if trial? do
        Bench.propose_trial!(
          %{
            audit_id: audit.id,
            attempt: 1,
            goal: :wait,
            hypothesis: "Build need not wait.",
            original: "a\nneeds",
            patch: "a",
            branch: "builddoctor/x-trial"
          },
          @agent
        )
        |> Council.pass!()
      end

      Bench.finish_examination!(audit, %{examined_jobs: [job(long, 0, 9)]}, @agent)
      {:ok, view, html} = live(conn, ~p"/a/#{audit.id}")

      assert html =~
               if(trial?, do: "We have a suspicion.", else: "No finding passed every check.")

      assert html =~ "not proof" and html =~ "long name long name"
      assert has_element?(view, "#change") == trial?
      assert html =~ "gin.yml" == trial?
      refute has_element?(view, "button", "Start the trial")
      assert has_element?(view, "#suggestion") == trial?

      if trial? do
        assert has_element?(
                 view,
                 "#suggestion a[href='https://github.com/a/b/edit/main/.github/workflows/gin.yml']"
               )

        assert html =~ "gh repo fork a/b" and html =~ "not measured"
        patch = conn |> get(~p"/a/#{audit.id}/change.patch") |> response(200)
        assert patch =~ "--- a/.github/workflows/gin.yml" and patch =~ "-needs"
      else
        assert conn |> get(~p"/a/#{audit.id}/change.patch") |> response(404)
      end
    end
  end

  test "the requester removes a project, a Visitor cannot", %{conn: conn} do
    audit = Bench.plant_audit!("a/b", 1)
    Bench.identify_audit!(audit, %{base_sha: @sha, jobs_total: 21}, @agent)
    {:ok, reading, html} = live(conn, ~p"/a/#{audit.id}")
    assert html =~ "hourly limit"

    Bench.finish_examination!(
      Bench.get_audit!(audit.id),
      %{examined_jobs: [job("vet", 0, 9)]},
      @agent
    )

    {:ok, visitor, html} = live(conn, ~p"/a/#{audit.id}")
    assert html =~ "21 jobs ran; the longest are shown."
    refute has_element?(visitor, "button", "Remove")
    assert render_click(visitor, "remove") =~ "not possible"
    {:ok, view, _} = conn |> requester() |> recycle() |> live(~p"/a/#{audit.id}")

    render_click(view, "remove")
    assert Bench.get_audit!(audit.id)
    refute has_element?(view, "#sure-remove")
    view |> element("button", "Remove this project") |> render_click()
    assert has_element?(view, "#sure-remove", "Remove a/b for good?")
    view |> element("button", "Keep it") |> render_click()
    refute has_element?(view, "#sure-remove")
    assert Bench.get_audit!(audit.id)
    view |> element("button", "Remove this project") |> render_click()

    assert {:error, {:live_redirect, %{to: "/"}}} =
             view |> element("button", "Remove it for good") |> render_click()

    assert {:error, _} = Bench.get_audit(audit.id)
    send(reading.pid, :refresh)
    assert render(reading) =~ "No audit here"
    send(reading.pid, :tick)
    assert render(reading) =~ "No audit here"
  end

  test "before the council has passed it, nothing of a proposal is shown", %{conn: conn} do
    audit = audit()

    trial =
      Bench.propose_trial!(
        %{
          audit_id: audit.id,
          attempt: 1,
          goal: :wait,
          hypothesis: "Secret so far.",
          original: "a\nneeds",
          patch: "a",
          branch: "builddoctor/x-trial"
        },
        @agent
      )

    Bench.request_approval!(audit, %{}, @agent)
    {:ok, view, html} = live(conn, ~p"/a/#{audit.id}")
    assert html =~ "The council is checking" and not (html =~ "Secret so far.")
    assert conn |> get(~p"/a/#{audit.id}/change.patch") |> response(404)
    Council.pass!(trial)
    Process.sleep(350)
    assert render(view) =~ "Secret so far."
  end

  test "findings stand first, with the facts behind them", %{conn: conn} do
    audit = Bench.plant_audit!("a/b", 1)
    facts = [%{id: "queue", text: "The longest wait was 218 s.", seconds: 218, commit: @sha}]
    audit = Bench.record_facts!(audit, %{facts: facts, examined_jobs: [job("vet", 0, 9)]}, @agent)

    Bench.record_finding!(
      %{
        audit_id: audit.id,
        position: 1,
        title: "Jobs wait for a runner",
        text: "The wait is 218 s.",
        advice: "Ask for fewer at once.",
        evidence: ["queue"],
        kind: :waiting
      },
      @agent
    )
    |> Council.pass!()

    Bench.finish_examination!(audit, %{}, @agent)
    {:ok, view, _} = live(conn, ~p"/a/#{audit.id}")
    assert has_element?(view, "h2.headline", "Jobs wait for a runner")
    assert has_element?(view, "#findings h3", "Jobs wait for a runner")
    assert has_element?(view, "#findings li li", "The longest wait was 218 s.")
    assert has_element?(view, "#findings", "Ask for fewer at once.")
    assert has_element?(view, "#facts", "longest wait")
    assert has_element?(view, "#findings", "Waiting")
    assert has_element?(view, "#facts a[href='https://github.com/a/b/commit/#{@sha}']")
    {:ok, home, _} = live(conn, ~p"/")
    assert has_element?(home, "#project-1", "Jobs wait for a runner")
    assert has_element?(home, "#project-1", "Suspicion")
  end

  test "a weakness is shown to the requester only", %{conn: conn} do
    audit = Bench.plant_audit!("a/b", 1)

    for {kind, line} <- [untrusted_input: 3, credentials: 4, foreign_code: 5],
        do: Bench.notify!(%{audit_id: audit.id, kind: kind, line: line}, @agent)

    {:ok, _, html} = live(conn, ~p"/a/#{audit.id}")
    refute html =~ "Only you see this"
    {:ok, view, _} = conn |> requester() |> recycle() |> live(~p"/a/#{audit.id}")

    for text <- [
          "Line 3: Text from outside",
          "Line 4: The file contains",
          "Line 5: Code from outside"
        ],
        do: assert(has_element?(view, "#notices li", text))
  end

  test "a finding of an earlier time and a file error have their labels" do
    assert BuilddoctorWeb.AuditView.kind(%{kind: nil}) == nil
    assert BuilddoctorWeb.AuditView.kind(%{kind: :file_error}) == "Error in the file"
  end

  test "many jobs are shown as a timeline without the picture", %{conn: conn} do
    audit = Bench.plant_audit!("a/b", 1)
    jobs = for i <- 1..6, do: job("job #{i}", i, i + 9)
    Bench.finish_examination!(audit, %{examined_jobs: jobs}, @agent)
    {:ok, view, _} = live(conn, ~p"/a/#{audit.id}")
    assert has_element?(view, "#timeline-0", "job 6")
    refute has_element?(view, "svg")
  end

  test "an audit stopped before any trial", %{conn: conn} do
    audit = Bench.stop_audit!(audit(), "The model budget is used up.", @agent)
    {:ok, _, html} = live(conn, ~p"/a/#{audit.id}")
    assert html =~ "budget is used up"
  end
end
