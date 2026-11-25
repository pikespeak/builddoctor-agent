defmodule BuilddoctorWeb.ArchiveTest do
  use BuilddoctorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Builddoctor.Bench
  alias Builddoctor.Bench.Actor
  alias BuilddoctorWeb.AuditView

  @agent [actor: Actor.agent()]
  @me [actor: Actor.requester()]
  @facts [
    %{id: "failed", text: "Of the last 10 finished runs of this workflow, 0 failed."},
    %{id: "timeout", text: "Jobs without timeout-minutes: test."}
  ]

  defp examined(name, slot, facts \\ @facts) do
    Bench.plant_audit!(name, slot, @me)
    |> Bench.record_facts!(%{facts: facts, examined_jobs: []}, @agent)
    |> Bench.finish_examination!(%{}, @agent)
  end

  test "holds old and new results, but nothing unfinished or removed", %{conn: conn} do
    {:ok, _, html} = live(conn, ~p"/archive")
    assert html =~ "Nothing here."
    old = examined("a/b", 1)
    new = Bench.examine_again!(old.id, @me) |> Bench.finish_examination!(%{}, @agent)
    reading = Bench.plant_audit!("c/d", 2, @me)
    {:ok, view, _} = live(conn, ~p"/archive")
    assert has_element?(view, "#archive a[href='/a/#{old.id}'] [aria-label='Grade A+']")
    assert has_element?(view, "#archive a[href='/a/#{new.id}'] [aria-label='No grade']")
    refute has_element?(view, "a[href='/a/#{reading.id}']")
    Bench.remove_audit!(Bench.get_audit!(new.id), @me)
    {:ok, view, _} = live(conn, ~p"/archive")
    refute has_element?(view, "#archive li")
  end

  test "has pages, and odd numbers lead to the first one", %{conn: conn} do
    for n <- 1..26, do: examined("a/b#{n}", n)
    {:ok, view, _} = live(conn, ~p"/archive")
    refute has_element?(view, "a", "Newer")
    html = view |> element("a", "Older editions") |> render_click()
    assert html =~ "a/b1<" and html =~ "a/b2<" and not (html =~ "a/b26<")
    refute has_element?(view, "a", "Older")
    assert view |> element("a", "Newer editions") |> render_click() =~ "a/b26<"

    for odd <- ["0", "-1", "1001", "x", "1x", ""] do
      {:ok, _, html} = live(conn, "/archive?page=#{odd}")
      assert html =~ "a/b26<"
    end

    {:ok, _, html} = live(conn, "/archive?page[]=2")
    assert html =~ "a/b26<"
  end

  test "in the reduced mode it holds only our own project", %{conn: conn} do
    examined("a/b", 1)
    Application.put_env(:builddoctor, :public_mode, "reduced")
    on_exit(fn -> Application.put_env(:builddoctor, :public_mode, "full") end)
    {:ok, _, html} = live(conn, ~p"/archive")
    refute html =~ "a/b"
  end

  test "every edition links to the archive, explains its grade and teases another one", %{
    conn: conn
  } do
    one = examined("a/one", 1)
    {:ok, view, _} = live(conn, ~p"/a/#{one.id}")
    assert has_element?(view, "header a[href='/archive']", "Archive")
    assert has_element?(view, "#grade", "Grade A+: 95 of 100 points")
    assert has_element?(view, "#grade li", "Jobs without an explicit timeout-minutes setting")
    refute has_element?(view, "#teaser")

    two = examined("a/two", 2, [hd(@facts)])
    Bench.plant_audit!("a/three", 3, @me)
    {:ok, view, _} = live(conn, ~p"/a/#{one.id}")
    assert has_element?(view, "#teaser a[href='/a/#{two.id}']", "Also in print: a/two")
    assert has_element?(view, "#teaser [aria-label='Grade A++']")
    {:ok, view, _} = live(conn, ~p"/a/#{two.id}")
    assert has_element?(view, "#grade", "Nothing was taken off.")
    {:ok, home, _} = live(conn, ~p"/")
    assert has_element?(home, "#project-2 [aria-label='Grade A++']")
  end

  test "the teaser changes with time" do
    one = examined("a/one", 1)
    for n <- 2..6, do: examined("a/p#{n}", n)
    seen = for now <- 1..60, do: AuditView.teaser(%{audit: one}, nil, now).repository
    assert length(Enum.uniq(seen)) == 5 and "a/one" not in seen
  end
end
