defmodule BuilddoctorWeb.EditionTest do
  use BuilddoctorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Builddoctor.{Bench, Council}
  alias Builddoctor.Bench.Actor
  alias BuilddoctorWeb.{AuditView, Press}

  @agent [actor: %Actor{role: :agent}]
  @jpeg <<0xFF, 0xD8, 0xFF, 0xE0>>
  @webp <<"RIFF", 12::little-32, "WEBP", "VP8X", 1, 2, 3, 4>>
  @facts [
    %{
      id: "last",
      text: ~s(The last job to end was "mac". It started after 243 s and ran for 107 s.)
    },
    %{
      id: "queue",
      text:
        ~s(Jobs that waited at least 10 s for a runner: 10. The longest wait was 218 s, for "mac".)
    }
  ]

  defp finding(audit, position, kind, title \\ "Queued longer than running") do
    Bench.record_finding!(
      %{
        audit_id: audit.id,
        position: position,
        title: title,
        text: "It waited 218 s and ran for 107 s.",
        advice: "Look at the runners.",
        evidence: ["last", "queue"],
        kind: kind
      },
      @agent
    )
  end

  defp order(audit, place, scene \\ :queue, finding \\ nil) do
    Bench.order_picture!(
      %{
        audit_id: audit.id,
        place: place,
        figures: [:officer],
        scene: scene,
        finding_id: finding && finding.id
      },
      @agent
    )
  end

  defp develop(picture) do
    picture
    |> Bench.add_picture_still!(@jpeg, @agent)
    |> Bench.add_picture_animation!(@webp, @agent)
  end

  defp line(audit, kind, place, text, finding \\ nil, more \\ %{}) do
    Map.merge(
      %{
        audit_id: audit.id,
        kind: kind,
        place: place,
        text: text,
        finding_id: finding && finding.id
      },
      more
    )
    |> Bench.record_line!(@agent)
    |> Bench.decide_line!(%{qa: :pass, safety: :pass, reason: "x"}, @agent)
  end

  defp say(audit, kind, message) do
    Bench.log_event!(%{audit_id: audit.id, kind: kind, status: :ok, message: message}, @agent)
    Process.sleep(350)
  end

  test "an edition is written while somebody watches", %{conn: conn} do
    audit = Bench.plant_audit!("a/b", 4)
    {:ok, view, _} = live(conn, ~p"/a/#{audit.id}")
    assert has_element?(view, "#status", "on the way to GitHub")
    assert has_element?(view, "#edition .lines.huge") and has_element?(view, "#articles .lines")
    for n <- 1..3, do: assert(has_element?(view, "#dark-#{n}", "The photographer"))

    say(audit, :github, "Read the workflow and 3 jobs.")
    assert has_element?(view, "#status", "Our reporter reads")
    audit = Bench.record_facts!(audit, %{facts: @facts, examined_jobs: []}, @agent)
    say(audit, :openai, "The analyst asked: more.")
    assert has_element?(view, "#status", "The editors look")
    finding = finding(audit, 1, :waiting)
    say(audit, :openai, "1 finding.")
    assert has_element?(view, "#status", "The council tries")
    refute render(view) =~ "Queued longer"

    Council.pass!(finding)
    say(audit, :openai, "The council checked 1 statement and passed 1.")
    assert has_element?(view, "#status", "goes to print")
    assert has_element?(view, ".lines.huge") and has_element?(view, "#edition", "A suspicion")

    assert has_element?(
             view,
             "#findings [phx-hook=Typed][data-live=true]",
             "Look at the runners."
           )

    assert has_element?(view, "#seconds svg[aria-label*='218 round marks']")
    refute has_element?(view, "#articles")

    picture = order(audit, 1)
    Process.sleep(350)
    assert has_element?(view, "#status", "The editor writes")
    line(audit, :headline, 0, "218 seconds in the queue!", finding)
    line(audit, :scene, 1, "A long line of people waits behind an officer.", finding)
    line(audit, :caption, 1, "218 seconds in line.", finding)
    line(audit, :ad, 0, "Seeking runner. Must like waiting.")
    line(audit, :star, 0, "A job thinks of you.", nil, %{sign: :leo})
    Process.sleep(350)
    assert has_element?(view, ".headline [data-live=true]", "218 seconds in the queue!")
    assert has_element?(view, "#status", "in the darkroom")
    assert has_element?(view, "#dark-1", "In the darkroom")
    develop(picture)
    Process.sleep(350)

    assert has_element?(
             view,
             "#photo-#{audit.id}-1[data-live=true][data-auto=true] img[alt='A long line of people waits behind an officer.']"
           )

    refute has_element?(view, "#dark-1")

    order(audit, 2, :portrait) |> Bench.give_up_picture!(@agent)
    Process.sleep(350)
    refute has_element?(view, "#dark-2")
    Bench.finish_examination!(audit, %{}, @agent)
    Process.sleep(350)
    refute has_element?(view, "#status") or has_element?(view, "#dark-3")

    {:ok, later, _} = live(conn, ~p"/a/#{audit.id}")
    assert has_element?(later, ".headline [data-live=false]")
    {:ok, home, _} = live(conn, ~p"/")
    assert has_element?(home, "#lead h2", "218 seconds in the queue!")
    assert has_element?(home, "#lead a", "Full story on page 4")
    assert has_element?(home, "#project-4 img")
    assert has_element?(home, "#ads", "Seeking runner.") and has_element?(home, "#stars", "Leo.")
    assert has_element?(home, "#lead figcaption", "218 seconds in line.")
  end

  test "a failure leads no front page and is told soberly", %{conn: conn} do
    audit = Bench.plant_audit!("a/b", 4)
    audit = Bench.record_facts!(audit, %{facts: @facts, examined_jobs: []}, @agent)
    audit |> finding(1, :failure, "Tests fail") |> Council.pass!()
    audit |> order(1, :newsroom) |> develop()
    Bench.finish_examination!(audit, %{}, @agent)
    {:ok, home, _} = live(conn, ~p"/")
    refute has_element?(home, "#lead")
    {:ok, view, _} = live(conn, ~p"/a/#{audit.id}")
    assert has_element?(view, "#findings h3.font-bold", "Tests fail")
    refute has_element?(view, "#seconds")
  end

  test "marks are shown only for one and the same job" do
    finding = %{kind: :waiting, evidence: ["last", "queue"]}
    assert AuditView.waited(finding, %{facts: @facts}) == {218, 107}
    assert AuditView.waited(%{finding | evidence: ["last"]}, %{facts: @facts}) == nil
    assert AuditView.waited(%{finding | kind: :time}, %{facts: @facts}) == nil
    other = [hd(@facts), %{id: "queue", text: ~s(The longest wait was 218 s, for "x".)}]
    assert AuditView.waited(finding, %{facts: other}) == nil
  end

  test "a picture stands in its article, with the caption of the editor", %{conn: conn} do
    audit = Bench.plant_audit!("a/b", 4)
    audit = Bench.record_facts!(audit, %{facts: @facts, examined_jobs: []}, @agent)
    one = audit |> finding(1, :waiting) |> Council.pass!()
    two = audit |> finding(2, :waiting, "Another one") |> Council.pass!()
    audit |> order(1, :queue, one) |> develop()
    line(audit, :caption, 1, "218 seconds in line.", one)
    line(audit, :caption, 2, "The counter is closed.", two)
    {:ok, view, _} = live(conn, ~p"/a/#{audit.id}")
    order(audit, 2, :counter, two)
    Process.sleep(350)
    assert has_element?(view, "#findings li:nth-child(2) #dark-2", "In the darkroom")

    Bench.get_picture!(
      hd(Enum.filter(Bench.list_pictures!(audit.id), &(&1.place == 2))).id,
      @agent
    )
    |> develop()

    Bench.finish_examination!(audit, %{}, @agent)
    Process.sleep(350)
    assert has_element?(view, "#edition figcaption", "218 seconds in line.")
    assert has_element?(view, "#findings li:nth-child(2) figcaption", "The counter is closed.")
    refute has_element?(view, "#findings li:nth-child(1) figure")
    refute has_element?(view, "#edition > div:last-child figure")
  end

  test "every picture has words" do
    for scene <- Bench.Picture.scenes(), figure <- Bench.Picture.figures() do
      assert Press.alt(%{scene: scene, figure: figure}) =~ ~r/\A[A-Z].+\.\z/
    end
  end
end
