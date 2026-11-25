defmodule BuilddoctorWeb.ReducedTest do
  use BuilddoctorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Builddoctor.{Bench, Council}
  alias Builddoctor.Bench.Actor

  @agent [actor: Actor.agent()]
  @me [actor: Actor.requester()]
  @viewer [actor: Actor.viewer()]

  setup do
    Application.put_env(:builddoctor, :public_mode, "reduced")
    on_exit(fn -> Application.delete_env(:builddoctor, :public_mode) end)
    audit = Bench.plant_audit!("gin-gonic/gin", 1, @me)
    Bench.record_facts!(audit, %{facts: [%{id: "run", text: "It took 5 s."}]}, @agent)

    [shown, hidden] =
      for i <- 1..2 do
        Bench.record_finding!(
          %{
            audit_id: audit.id,
            position: i,
            title: "Finding #{<<64 + i>>}",
            text: "x",
            evidence: ["run"]
          },
          @agent
        )
      end

    Council.pass!(shown)
    Council.decide!(hidden)
    Bench.log_event!(%{audit_id: audit.id, kind: :github, status: :ok, message: "Read."}, @agent)

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

    audit = Bench.finish_examination!(Bench.get_audit!(audit.id, @agent), %{}, @agent)

    %{
      audit: audit,
      own: Bench.start_audit!("pikespeak/ci-patient", String.duplicate("a", 40), @me)
    }
  end

  defp requester(conn),
    do:
      conn |> post(~p"/requester", %{"key" => "test-requester-key-0123456789abcdef"}) |> recycle()

  test "a Visitor gets nothing of a foreign project", %{conn: conn, audit: audit, own: own} do
    assert {:error, _} = Bench.get_audit(audit.id)
    assert Bench.planted_audits!() == []
    assert Bench.list_findings!(audit.id) == []
    assert Bench.list_trials!(audit.id) == []
    assert Bench.list_events!(audit.id) == []
    assert Bench.list_runs!(audit.id) == []
    assert {:ok, nil} = Bench.place_of("gin-gonic/gin")
    assert Bench.get_audit!(own.id)
    assert Enum.map(Bench.own_audits!(), & &1.id) == [own.id]
    assert {:error, %Ash.Error.Forbidden{}} = Bench.plant_audit("c/d", 2)
    assert {:error, %Ash.Error.Forbidden{}} = Bench.examine_again(audit.id)

    {:ok, _, html} = live(conn, ~p"/a/#{audit.id}")
    assert html =~ "No audit here" and not (html =~ "gin-gonic")

    for path <- ["change.patch", "photo/1.jpg"],
        do: assert(conn |> get("/a/#{audit.id}/#{path}") |> response(404))

    {:ok, home, html} = live(conn, ~p"/")
    assert has_element?(home, "#reduced") and has_element?(home, "#own")
    refute html =~ "gin-gonic" or has_element?(home, "#plant") or has_element?(home, "#pages")
    assert render_submit(home, "plant", %{"project" => "c/d"}) =~ "cannot start an examination"
    {:ok, how, html} = live(conn, ~p"/how-it-works")
    refute html =~ "gin-gonic" or has_element?(how, "a", "Examine a project")
    {:ok, page, _} = live(conn, ~p"/a/#{own.id}")
    assert has_element?(page, "#steps")
  end

  test "the Requester sees all projects, but only what passed", %{conn: conn, audit: audit} do
    assert [%{title: "Finding A"}] = Bench.list_findings!(audit.id, @viewer)
    assert {:error, _} = Bench.plant_audit("c/d", 2, @viewer)
    conn = requester(conn)
    {:ok, home, _} = live(conn, ~p"/")
    assert has_element?(home, "#plant") and has_element?(home, "#project-1", "gin-gonic/gin")
    {:ok, page, html} = live(conn, ~p"/a/#{audit.id}")
    assert html =~ "Finding A" and not (html =~ "Finding B")
    assert has_element?(page, "button", "Examine again")
    send(page.pid, :refresh)
    assert render(page) =~ "gin-gonic"
  end

  test "the agent still works", %{audit: audit} do
    assert [_, _] = Bench.list_findings!(audit.id, @agent)
    again = Bench.examine_again!(audit.id, @me)
    assert again.id in Enum.map(Ash.read!(Bench.Audit, [action: :open] ++ @agent), & &1.id)
    assert Bench.finish_examination!(again, %{}, @agent).slot == 1
  end

  test "any other value than full is reduced" do
    for value <- ["", "FULL", nil, "open"] do
      Application.put_env(:builddoctor, :public_mode, value)
      refute Builddoctor.Bench.Checks.FullMode.on?()
    end
  end
end
