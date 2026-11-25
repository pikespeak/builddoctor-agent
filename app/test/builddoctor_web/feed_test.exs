defmodule BuilddoctorWeb.FeedTest do
  use BuilddoctorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Builddoctor.{Bench, Council}
  alias Builddoctor.Bench.Actor

  @agent [actor: Actor.agent()]
  @me [actor: Actor.requester()]

  defp examined(name, slot) do
    Bench.plant_audit!(name, slot, @me)
    |> Bench.record_facts!(
      %{
        facts: [
          %{id: "failed", text: "Of the last 10 finished runs of this workflow, 0 failed."},
          %{id: "f", text: "x"}
        ],
        examined_jobs: []
      },
      @agent
    )
  end

  defp finding(audit, title, n) do
    Bench.record_finding!(
      %{audit_id: audit.id, position: n, title: title, text: "t", evidence: ["f"], kind: :time},
      @agent
    )
  end

  test "lists published results of one project, the newest first, and nothing else", %{conn: conn} do
    audit = examined("acme/widget.js", 1)
    Council.pass!(finding(audit, "Jobs & <queues> \u0001wait", 1))
    finding(audit, "a secret suspicion", 2)
    Bench.finish_examination!(audit, %{}, @agent)
    new = Bench.examine_again!(audit.id, @me) |> Bench.finish_examination!(%{}, @agent)
    other = examined("other/project", 2) |> Bench.finish_examination!(%{}, @agent)

    conn = conn |> put_req_header("accept", "application/atom+xml") |> get("/feed/Acme/widget.js")
    xml = response(conn, 200)
    assert response_content_type(conn, :xml) =~ "application/atom+xml"
    assert get_resp_header(conn, "x-robots-tag") == ["noindex, nofollow"]
    assert get_resp_header(conn, "set-cookie") == []
    assert {:ok, _} = xml |> String.to_charlist() |> parse()
    assert xml =~ "Jobs &amp; &lt;queues&gt;  wait"
    refute xml =~ "secret suspicion"
    refute xml =~ other.id
    assert [_, after_new] = String.split(xml, "/a/#{new.id}</id>")
    assert after_new =~ "/a/#{audit.id}</id>"
  end

  defp parse(text) do
    {doc, _} = :xmerl_scan.string(text, quiet: true)
    {:ok, doc}
  end

  test "the reduced mode shows no project of others", %{conn: conn} do
    examined("acme/widget", 1) |> Bench.finish_examination!(%{}, @agent)
    assert conn |> get("/feed/acme/widget") |> response(200)
    Application.put_env(:builddoctor, :public_mode, "reduced")
    on_exit(fn -> Application.put_env(:builddoctor, :public_mode, "full") end)
    assert conn |> get("/feed/acme/widget") |> response(404)
  end

  test "nothing to follow, nothing to read", %{conn: conn} do
    Bench.plant_audit!("acme/reading", 1, @me)

    for path <- ["acme/reading", "nobody/nothing", "-x/y", "a/b%20c", "a/%3Cb%3E"],
        do: assert(conn |> get("/feed/" <> path) |> response(404))
  end

  test "an edition offers the feed and the waiting list", %{conn: conn} do
    audit = examined("acme/widget", 1) |> Bench.finish_examination!(%{}, @agent)
    {:ok, view, _} = live(conn, ~p"/a/#{audit.id}")
    assert has_element?(view, "#follow a[href='/feed/acme/widget']")
    assert has_element?(view, "#follow a[href='/subscribe']")
    refute has_element?(view, "#has-patch")
  end

  test "an edition with a passed patch says so at the top", %{conn: conn} do
    audit = examined("acme/widget", 1)

    trial =
      Bench.propose_trial!(
        %{
          audit_id: audit.id,
          attempt: 1,
          goal: :bill,
          hypothesis: "h",
          original: "on: push\n",
          patch: "on: pull_request\n",
          branch: "builddoctor/a-trial"
        },
        @agent
      )

    Bench.identify_audit!(
      audit,
      %{
        base_sha: String.duplicate("a", 40),
        workflow_path: ".github/workflows/ci.yml",
        default_branch: "main",
        jobs_total: 1
      },
      @agent
    )
    |> Bench.finish_examination!(%{}, @agent)

    {:ok, view, _} = live(conn, ~p"/a/#{audit.id}")
    refute has_element?(view, "#has-patch")
    Council.pass!(trial)
    {:ok, view, _} = live(conn, ~p"/a/#{audit.id}")
    assert has_element?(view, "#has-patch a[href='#suggestion']")
    assert has_element?(view, "#suggestion")
  end

  test "the advertisement stores nothing and says what does not exist", %{conn: conn} do
    {:ok, front, _} = live(conn, ~p"/")
    assert has_element?(front, "#own-ad a[href='/subscribe']")
    {:ok, _, html} = live(conn, ~p"/subscribe")
    assert html =~ "None of this exists yet"
    assert html =~ "The list is not open yet."
    refute html =~ "<form"

    path = Path.join(System.tmp_dir!(), "imprint-#{System.unique_integer([:positive])}.json")

    File.write!(
      path,
      JSON.encode!(%{name: "N", street: "S", city: "C", country: "D", email: "hello@example.com"})
    )

    Application.put_env(:builddoctor, :imprint_file, path)
    on_exit(fn -> Application.delete_env(:builddoctor, :imprint_file) end)
    {:ok, view, html} = live(conn, ~p"/subscribe")
    assert html =~ "hello@example.com"

    assert has_element?(
             view,
             "#waiting-list a[href^='mailto:hello@example.com?subject=Waiting%20list']"
           )
  end
end
