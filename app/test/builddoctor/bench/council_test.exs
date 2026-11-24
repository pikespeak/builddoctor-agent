defmodule Builddoctor.Bench.CouncilTest do
  use Builddoctor.DataCase, async: true

  alias Builddoctor.Bench
  alias Builddoctor.Bench.Actor
  alias Builddoctor.Council

  @agent [actor: Actor.agent()]
  @me [actor: Actor.requester()]
  @sha String.duplicate("f", 40)

  defp finding(audit, position \\ 1) do
    Bench.record_finding!(
      %{audit_id: audit.id, position: position, title: "x", text: "x", evidence: ["run"]},
      @agent
    )
  end

  defp planted do
    audit = Bench.plant_audit!("a/b", 1)
    Bench.record_facts!(audit, %{facts: [%{id: "run", text: "It took 5 s."}]}, @agent)
  end

  defp trial(audit) do
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
  end

  defp waiting do
    audit = Bench.start_audit!("pikespeak/ci-patient", @sha, @me)
    trial = trial(audit)
    {Bench.request_approval!(audit, %{}, @agent), trial}
  end

  test "a finding is hidden until every role has passed it" do
    audit = planted()
    finding = finding(audit)
    assert Bench.list_findings!(audit.id) == []
    assert [_] = Bench.list_findings!(audit.id, @agent)
    Council.review!(finding, :qa)
    assert Bench.list_findings!(audit.id) == []
    Council.review!(finding, :safety)
    assert Bench.list_findings!(audit.id) == []
    assert Council.decide!(finding).status == :published
    assert [%{title: "x"}] = Bench.list_findings!(audit.id)
  end

  test "a refusal, a missing review and no review at all withhold it" do
    audit = planted()

    for {reviews, position} <- [
          {[{:qa, :pass}, {:safety, :fail}], 1},
          {[{:qa, :fail}, {:safety, :pass}], 2},
          {[{:safety, :pass}], 3},
          {[], 4}
        ] do
      finding = finding(audit, position)
      for {role, verdict} <- reviews, do: Council.review!(finding, role, verdict)
      decided = Council.decide!(finding)
      assert decided.status == :withheld
      assert {:error, _} = Bench.decide_finding(decided, @agent)
    end

    assert Bench.list_findings!(audit.id) == []
    assert hd(Bench.planted_audits!()).findings == []
  end

  test "a trial also needs the engineer" do
    {_, trial} = waiting()
    Council.review!(trial, :qa)
    Council.review!(trial, :safety)
    assert Council.decide!(trial).status == :withheld

    {_, trial} = waiting()
    Council.review!(trial, :qa)
    Council.review!(trial, :safety)
    Council.review!(trial, :engineer, :fail)
    assert Council.decide!(trial).status == :withheld
  end

  test "only the requester reads a weakness, and only the agent stores it" do
    audit = planted()
    input = %{audit_id: audit.id, kind: :untrusted_input, line: 3}

    for actor <- [nil, Actor.requester()],
        do: assert({:error, _} = Bench.notify(input, actor: actor))

    Bench.notify!(input, @agent)
    Bench.notify!(input, @agent)
    assert {:error, _} = Bench.notify(%{input | kind: :other}, @agent)
    assert {:error, _} = Bench.notify(%{input | line: 0}, @agent)
    assert Bench.list_notices!(audit.id) == []
    assert Bench.list_notices!(audit.id, @agent) == []
    assert [%{line: 3}] = Bench.list_notices!(audit.id, @me)
  end

  test "the first word of a role counts" do
    finding = planted() |> finding()
    Council.review!(finding, :qa, :fail)
    Council.review!(finding, :qa, :pass)
    Council.review!(finding, :safety)
    assert Council.decide!(finding).status == :withheld
  end

  test "only the agent reviews and decides, and Visitors read no reviews" do
    finding = planted() |> finding()

    input = %{finding_id: finding.id, role: :qa, verdict: :pass, model: "m", version: 1}

    for actor <- [nil, Actor.requester()] do
      assert {:error, _} = Bench.review_finding(input, actor: actor)
      assert {:error, _} = Bench.decide_finding(finding, actor: actor)
    end

    Bench.review_finding!(input, @agent)
    assert Ash.read!(Bench.Review) == []
    assert [_] = Ash.read!(Bench.Review, @me)
  end

  test "a trial is hidden until it is cleared or measured" do
    {audit, trial} = waiting()
    assert Bench.list_trials!(audit.id) == []
    assert Council.pass!(trial).status == :published
    assert [_] = Bench.list_trials!(audit.id)
  end

  test "the council starts only cleared trials of our own project, twice a day" do
    {audit, _} = waiting()
    assert {:error, error} = Bench.approve_by_council(audit, @agent)
    assert Exception.message(error) =~ "notCleared"

    for _ <- 1..2 do
      {audit, trial} = waiting()
      assert audit.id in Enum.map(Ash.read!(Bench.Audit, action: :open), & &1.id)
      Council.pass!(trial)
      assert {:error, _} = Bench.approve_by_council(audit)
      assert Bench.approve_by_council!(audit, @agent).state == :measuring
    end

    {audit, trial} = waiting()
    Council.pass!(trial)
    assert {:error, error} = Bench.approve_by_council(audit, @agent)
    assert Exception.message(error) =~ "limit"
    audit = Bench.leave_to_requester!(audit, @agent)
    refute audit.id in Enum.map(Ash.read!(Bench.Audit, action: :open), & &1.id)
    assert Bench.approve_audit!(audit, @me).state == :measuring

    foreign = planted()
    Council.pass!(trial(foreign))
    assert {:error, _} = Bench.approve_by_council(foreign, @agent)
  end
end
