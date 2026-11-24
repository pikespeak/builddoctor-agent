defmodule BuilddoctorWeb.SelfServiceTest do
  use BuilddoctorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Builddoctor.Bench
  alias Builddoctor.Bench.Actor
  alias BuilddoctorWeb.AuditView

  @agent [actor: Actor.agent()]
  @me [actor: Actor.requester()]
  @sha String.duplicate("e", 40)

  defp requester(conn),
    do:
      conn
      |> post(~p"/requester", %{"key" => "test-requester-key-0123456789abcdef"})
      |> recycle()

  defp examined,
    do: "a/b" |> Bench.plant_audit!(1) |> Bench.finish_examination!(%{}, @agent)

  defp age(audit),
    do:
      Builddoctor.Repo.query!(
        "update audits set inserted_at = inserted_at - interval '25 hours' where id = $1",
        [Ecto.UUID.dump!(audit.id)]
      )

  test "the requester signs in, starts our project and signs out", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    assert has_element?(view, "footer a[href='/requester']")
    refute has_element?(view, "#own-start")
    render_click(view, "own", %{})
    assert Bench.own_audits!() == []

    conn = requester(conn)
    {:ok, view, _} = live(conn, ~p"/")
    assert has_element?(view, "#own-start", "8 runs on GitHub")
    button = element(view, "#own-start button")
    assert {:error, {:live_redirect, %{to: to}}} = render_click(button)
    assert [%{id: id}] = Bench.own_audits!()
    assert to == "/a/#{id}"

    {:ok, view, _} = live(conn, ~p"/")
    assert view |> element("#own-start button") |> render_click() =~ "being read already"

    conn = conn |> post(~p"/requester/leave") |> recycle()
    {:ok, view, _} = live(conn, ~p"/")
    refute has_element?(view, "#own-start")
  end

  test "without the key there is a way back", %{conn: conn} do
    id = Ash.UUID.generate()
    assert conn |> get(~p"/requester") |> html_response(200) =~ ~s(href="/")
    assert conn |> get(~p"/requester?audit=#{id}") |> html_response(200) =~ ~s(href="/a/#{id}")
  end

  test "the requester examines again and follows it", %{conn: conn} do
    old = examined()
    {:ok, visitor, _} = live(conn, ~p"/a/#{old.id}")
    refute has_element?(visitor, "button", "Examine again")
    assert has_element?(visitor, "#calm")
    assert render_click(visitor, "again", %{}) =~ "last 24 hours"

    {:ok, view, _} = conn |> requester() |> live(~p"/a/#{old.id}")
    button = element(view, "button", "Examine again")
    assert {:error, {:live_redirect, %{to: to}}} = render_click(button)
    new = old.id |> Bench.newer_audits!() |> hd()
    assert to == "/a/#{new.id}"

    {:ok, page, _} = live(conn, to)
    assert has_element?(page, "#older a[href='/a/#{old.id}']")
    {:ok, view, _} = conn |> requester() |> live(~p"/a/#{old.id}")
    assert has_element?(view, "#newer", "being examined again")
    assert render_click(view, "again", %{}) =~ "being examined again already"

    Bench.stop_audit!(new, "It is private.", @agent)
    {:ok, view, _} = live(conn, ~p"/a/#{old.id}")
    assert has_element?(view, "#newer", "stopped: It is private.")
    refute has_element?(view, "#newer a")
    {:ok, page, _} = live(conn, to)
    assert has_element?(page, "#older")
    refute has_element?(page, "a", "Try again")

    new = Bench.examine_again!(old.id, @me)
    Bench.finish_examination!(new, %{}, @agent)
    {:ok, view, _} = live(conn, ~p"/a/#{old.id}")
    assert has_element?(view, "#newer a", "Open it")
    assert has_element?(view, "#newer", "newer result")
    refute has_element?(view, "button", "Examine again")
    assert render_click(view, "again", %{}) =~ "not possible right now"
  end

  test "after a day a visitor may ask", %{conn: conn} do
    old = examined()
    age(old)
    {:ok, view, _} = live(conn, ~p"/a/#{old.id}")
    button = element(view, "button", "Examine again")
    assert {:error, {:live_redirect, _}} = render_click(button)
  end

  test "a stopped project can be tried again", %{conn: conn} do
    audit = Bench.plant_audit!("a/b", 1)
    Bench.stop_audit!(audit, "No successful workflow run.", @agent)
    {:ok, view, _} = live(conn, ~p"/a/#{audit.id}")
    assert has_element?(view, "p", "place in the forest is free")
    assert has_element?(view, "a[href='/?project=a%2Fb']", "Try again")
    {:ok, home, html} = live(conn, ~p"/?project=a/b")
    assert html =~ ~s(value="a/b")
    assert {:error, {:live_redirect, _}} = home |> form("#plant") |> render_submit()
  end

  test "reading shows its real steps and the time of a wait", %{conn: conn} do
    audit = Bench.plant_audit!("a/b", 1)
    {:ok, view, _} = live(conn, ~p"/a/#{audit.id}")
    refute has_element?(view, "#steps li[data-done=true]")
    refute has_element?(view, "#waits")
    assert has_element?(view, "button", "Copy the link")

    Bench.log_event!(
      %{audit_id: audit.id, kind: :openai, status: :ok, message: "The analyst asked: x."},
      @agent
    )

    Process.sleep(350)
    refute has_element?(view, "#steps li[data-done=true]")

    for {kind, text} <- [
          github: "Read.",
          openai: "The council checked 1 statement and passed 1."
        ] do
      Bench.log_event!(
        %{audit_id: audit.id, kind: kind, status: :ok, message: text},
        @agent
      )
    end

    at = DateTime.utc_now() |> DateTime.add(600) |> DateTime.truncate(:second)
    Bench.report_wait!(audit, %{waiting_until: at}, @agent)
    Process.sleep(350)
    assert has_element?(view, "#steps li[data-done=true]", "council")
    assert has_element?(view, "#waits", Calendar.strftime(at, "%H:%M"))
    # Another project waits for the same limit; our own does not.
    other = Bench.plant_audit!("c/d", 2)
    assert AuditView.load(other).waits == at
    assert AuditView.load(Bench.examine_own!(@me)).waits == nil
  end

  test "preparing, silence and the question before a stop", %{conn: conn} do
    audit = Bench.start_audit!("pikespeak/ci-patient", @sha, @me)
    {:ok, view, _} = conn |> requester() |> live(~p"/a/#{audit.id}")
    view |> element("button", "Stop") |> render_click()
    assert has_element?(view, "#sure", "Stop this audit?")

    audit = audit |> Bench.request_approval!(%{}, @agent) |> Bench.approve_audit!(@me)
    {:ok, view, _} = live(conn, ~p"/a/#{audit.id}")
    assert has_element?(view, "#preparing")
    refute has_element?(view, "#silent")
    send(view.pid, :tick)
    assert has_element?(view, "#preparing")

    Builddoctor.Repo.query!(
      "update audits set updated_at = updated_at - interval '5 minutes' where id = $1",
      [Ecto.UUID.dump!(audit.id)]
    )

    {:ok, view, _} = live(conn, ~p"/a/#{audit.id}")
    assert has_element?(view, "#silent", "No news for 5 minutes")
  end

  test "a planted project leads to its result, and a seed can be given back", %{conn: conn} do
    audit = Bench.plant_audit!("a/b", 1)
    {:ok, view, _} = live(conn, ~p"/")
    view |> form("#plant", %{project: "https://github.com/A/B"}) |> render_submit()
    assert has_element?(view, "#known[href='/a/#{audit.id}']", "Open its result")
    view |> element("#place-7.seed") |> render_click()
    refute has_element?(view, "#known")
    view |> element("button", "Choose another place") |> render_click()
    refute has_element?(view, "label", "place 7")
    view |> element("#place-7.seed") |> render_click()
    view |> element("#place-7.seed") |> render_click()
    refute has_element?(view, "label", "place 7")
  end

  test "a wrong address and a lost connection are explained", %{conn: conn} do
    {:ok, _, html} = live(conn, ~p"/")
    assert html =~ ~s(id="offline")
    assert conn |> get("/nothing/here") |> html_response(404) =~ "No tree grows here."
  end

  test "the suggestion fits added lines and names its age", %{conn: conn} do
    audit =
      "a/b"
      |> Bench.plant_audit!(1)
      |> Bench.identify_audit!(%{base_sha: @sha}, @agent)

    Bench.propose_trial!(
      %{
        audit_id: audit.id,
        attempt: 1,
        goal: :wait,
        hypothesis: "x",
        original: "a",
        patch: "a\nb",
        branch: "builddoctor/x-trial"
      },
      @agent
    )
    |> Builddoctor.Council.pass!()

    Bench.finish_examination!(audit, %{}, @agent)
    {:ok, view, _} = live(conn, ~p"/a/#{audit.id}")
    assert has_element?(view, "#suggestion", "Make the marked changes")
    assert has_element?(view, "#suggestion", "at commit eeeeeee")
    assert has_element?(view, "#maintainer", "Is this your project?")
    refute has_element?(view, "#maintainer a[href^=mailto]")
    assert has_element?(view, "#suggestion button", "Copy the command")
  end
end
