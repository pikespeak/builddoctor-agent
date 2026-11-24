defmodule Builddoctor.Bench.FindingTest do
  use Builddoctor.DataCase, async: true

  alias Builddoctor.Bench
  alias Builddoctor.Bench.Actor

  @agent [actor: Actor.agent()]
  @facts [
    %{id: "queue", text: "The longest wait was 218 s, for job 3.", seconds: 218},
    %{id: "step1", text: "Step Tests with Go 1.27: 580 s in total.", seconds: 580}
  ]

  setup do
    audit = Bench.plant_audit!("a/b", 1)
    %{audit: Bench.record_facts!(audit, %{facts: @facts}, @agent)}
  end

  defp finding(audit, extra) do
    Bench.record_finding(
      Map.merge(
        %{
          audit_id: audit.id,
          position: 1,
          title: "Jobs wait 218 s for a runner",
          text: "The wait comes before the work.",
          advice: "Use fewer runners at once.",
          evidence: ["queue"]
        },
        extra
      ),
      @agent
    )
  end

  test "a supported finding is stored once", %{audit: audit} do
    assert {:ok, first} = finding(audit, %{})
    assert {:ok, again} = finding(audit, %{title: "Other"})
    assert again.id == first.id
    assert [%{title: "Jobs wait 218 s for a runner"}] = Bench.list_findings!(audit.id, @agent)

    assert {:ok, _} =
             finding(audit, %{
               kind: :failure,
               position: 2,
               text: "Go 1.27 tests take 580 s.",
               evidence: ["step1", "queue"]
             })
  end

  test "invented numbers and unknown facts are refused", %{audit: audit} do
    for bad <- [
          %{title: "Saves 99 s"},
          %{text: "It takes 580 s."},
          %{advice: "You gain 21.8 s."},
          %{text: "About 1.2 s."},
          %{evidence: ["nope"]},
          %{evidence: ["queue", "nope"]},
          %{evidence: []},
          %{position: 6},
          %{kind: :invented},
          %{audit_id: Ash.UUID.generate()}
        ] do
      assert {:error, %Ash.Error.Invalid{}} = finding(audit, bad)
    end
  end

  test "only the agent records, and facts only while examining", %{audit: audit} do
    assert {:error, _} =
             Bench.record_finding(%{
               audit_id: audit.id,
               position: 1,
               title: "x",
               text: "x",
               evidence: ["queue"]
             })

    assert {:error, _} = Bench.record_facts(audit, %{facts: []})
    assert {:error, _} = Bench.record_facts(audit, %{facts: [%{id: "<b>", text: "x"}]}, @agent)

    assert {:error, _} =
             Bench.record_facts(
               audit,
               %{facts: [%{id: "red1", text: "x", commit: "main"}]},
               @agent
             )

    done = Bench.finish_examination!(audit, %{}, @agent)
    assert {:error, _} = Bench.record_facts(done, %{facts: []}, @agent)
  end
end
