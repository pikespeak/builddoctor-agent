defmodule Builddoctor.Bench.PlantTest do
  use Builddoctor.DataCase, async: true

  alias Builddoctor.Bench
  alias Builddoctor.Bench.Actor

  @agent [actor: Actor.agent()]
  @me [actor: Actor.requester()]
  @sha String.duplicate("d", 40)

  defp message({:error, error}), do: Exception.message(error)

  test "a name and an address plant the same project" do
    for {text, name, slot} <- [
          {"elixir-lang/elixir", "elixir-lang/elixir", 1},
          {" https://github.com/golang/go/ ", "golang/go", 2},
          {"github.com/rust-lang/rust.git", "rust-lang/rust", 3}
        ] do
      audit = Bench.plant_audit!(text, slot)
      assert {audit.repository, audit.slot, audit.state} == {name, slot, :examining}
    end

    assert Bench.Audit.places() == 100
    assert Enum.map(Bench.planted_audits!(), & &1.slot) == [1, 2, 3]
  end

  test "nothing but an owner and a name is accepted" do
    for text <- [
          "",
          "x",
          "a/b/c",
          "../etc",
          "a/..",
          "a/.",
          "a/b?x=1",
          "a/b#c",
          "a b/c",
          "-a/b",
          "a/b\nc",
          "https://evil.example/a/b",
          "a/%2e%2e",
          String.duplicate("a", 40) <> "/b",
          "a/" <> String.duplicate("b", 101)
        ] do
      assert message(Bench.plant_audit(text, 1)) =~ ~r/error.repository.invalid|is required/
    end
  end

  test "a place and a project are given once" do
    Bench.plant_audit!("a/b", 7)
    assert message(Bench.plant_audit("c/d", 7)) =~ "error.slot.taken"
    assert message(Bench.plant_audit("A/B", 8)) =~ "error.repository.planted"
    for slot <- [0, 101, nil], do: assert({:error, _} = Bench.plant_audit("e/f", slot))
  end

  test "a foreign project is examined and never measured" do
    audit = Bench.plant_audit!("a/b", 1)

    audit =
      Bench.identify_audit!(
        audit,
        %{base_sha: @sha, jobs_total: 40, workflow_path: ".github/workflows/x.yaml"},
        @agent
      )

    for path <- ["../x.yml", ".github/workflows/../x.yml", ".github/workflows/x.sh"],
        do: assert({:error, _} = Bench.identify_audit(audit, %{workflow_path: path}, @agent))

    assert {:error, _} = Bench.request_approval(audit, %{}, @agent)
    audit = Bench.finish_examination!(audit, %{}, @agent)
    assert audit.state == :examined
    assert {:error, _} = Bench.approve_audit(audit, @me)
    assert {:error, _} = Bench.identify_audit(audit, %{base_sha: @sha}, @agent)
    assert {:error, _} = Bench.start_audit("a/b", @sha, @me)
  end

  test "three errors free the place, a stop does too" do
    audit = Bench.plant_audit!("a/b", 1)
    audit = Bench.report_audit_error!(audit, @agent)
    audit = Bench.report_audit_error!(audit, @agent)
    assert {audit.state, audit.slot} == {:examining, 1}
    audit = Bench.report_audit_error!(audit, @agent)
    assert {audit.state, audit.slot} == {:stopped, nil}
    assert {:error, _} = Bench.report_audit_error(audit, @agent)
    again = Bench.plant_audit!("a/b", 1)
    assert Bench.stop_audit!(again, "It is private.", @agent).slot == nil
    assert Bench.planted_audits!() == []
  end

  test "only the Requester removes a project, and its costs stay counted" do
    audit = Bench.plant_audit!("a/b", 1)

    Bench.record_ai_call!(
      %{audit_id: audit.id, model: "gpt-6.2-astra", input_tokens: 1000, output_tokens: 100},
      @agent
    )

    Bench.log_event!(%{audit_id: audit.id, kind: :github, status: :ok, message: "Read."}, @agent)

    for actor <- [nil, Actor.agent()],
        do: assert({:error, _} = Bench.remove_audit(audit, actor: actor))

    :ok = Bench.remove_audit!(audit, @me)
    assert {:error, _} = Bench.get_audit(audit.id)
    assert [%{audit_id: nil, micro_dollars: 12_000}] = Ash.read!(Bench.AiCall, @agent)
  end

  test "a Visitor can plant but do nothing else" do
    audit = Bench.plant_audit!("a/b", 1)
    assert {:error, _} = Bench.identify_audit(audit, %{base_sha: @sha})
    assert {:error, _} = Bench.finish_examination(audit, %{})
    assert {:error, _} = Bench.report_audit_error(audit)
    assert {:error, _} = Bench.stop_audit(audit, "x")
  end

  test "several audits are open at once, the oldest first" do
    ids = for slot <- 1..3, do: Bench.plant_audit!("a/b#{slot}", slot).id
    assert ids == Bench.Audit |> Ash.read!(action: :open) |> Enum.map(& &1.id)
  end
end
