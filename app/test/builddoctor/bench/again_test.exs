defmodule Builddoctor.Bench.AgainTest do
  use Builddoctor.DataCase, async: false

  alias Builddoctor.Bench
  alias Builddoctor.Bench.Actor

  @agent [actor: Actor.agent()]
  @me [actor: Actor.requester()]

  defp message({:error, error}), do: Exception.message(error)

  defp examined(name \\ "a/b", slot \\ 1),
    do: name |> Bench.plant_audit!(slot) |> Bench.finish_examination!(%{}, @agent)

  defp age(audit, hours) do
    at = DateTime.add(DateTime.utc_now(), -hours, :hour)

    Repo.query!("update audits set inserted_at = $1 where id = $2", [
      at,
      Ecto.UUID.dump!(audit.id)
    ])
  end

  test "a new Examination takes the place only when it is finished" do
    old = examined()
    new = Bench.examine_again!(old.id, @me)
    assert {new.repository, new.state, new.slot} == {"a/b", :examining, nil}
    assert [%{id: id}] = Bench.planted_audits!()
    assert id == old.id
    assert [%{id: id}] = Bench.newer_audits!(old.id)
    assert id == new.id
    new = Bench.finish_examination!(new, %{}, @agent)
    assert new.slot == 1
    assert Bench.get_audit!(old.id).slot == nil
    assert Bench.place_of!("a/b").id == new.id
    assert message(Bench.plant_audit("A/B", 2)) =~ "error.repository.planted"
    # The earlier result is readable, but no longer the one to repeat.
    assert message(Bench.examine_again(old.id, @me)) =~ "error.again.notPossible"
  end

  test "a failure keeps the earlier result" do
    old = examined()
    new = Bench.examine_again!(old.id, @me)
    Bench.stop_audit!(new, "It is private.", @agent)
    assert Bench.get_audit!(old.id).slot == 1
    assert Bench.examine_again!(old.id, @me).state == :examining
  end

  test "one at a time" do
    old = examined()
    Bench.examine_again!(old.id, @me)
    assert message(Bench.examine_again(old.id, @me)) =~ "error.again.running"
  end

  test "a Visitor waits a day, also after a failure" do
    old = examined()
    assert message(Bench.examine_again(old.id)) =~ "error.again.tooSoon"
    age(old, 25)
    new = Bench.examine_again!(old.id)
    Bench.stop_audit!(new, "It is private.", @agent)
    assert message(Bench.examine_again(old.id)) =~ "error.again.tooSoon"
  end

  test "only an examined project that has a place" do
    running = Bench.plant_audit!("a/b", 1)

    for id <- [running.id, Ash.UUID.generate()],
        do: assert(message(Bench.examine_again(id, @me)) =~ "error.again.notPossible")
  end

  test "nobody gives a place away by hand" do
    old = examined()

    for actor <- [nil, Actor.agent(), Actor.requester()] do
      assert {:error, _} =
               old |> Ash.Changeset.for_update(:give_way, %{}, actor: actor) |> Ash.update()
    end
  end

  test "a place that became free meanwhile is not taken" do
    old = examined()
    new = Bench.examine_again!(old.id, @me)

    Repo.query!("update audits set slot = null, planted_as = null where id = $1", [
      Ecto.UUID.dump!(old.id)
    ])

    assert Bench.finish_examination!(new, %{}, @agent).slot == nil
  end

  test "removing a project removes all of its Examinations, and nothing else" do
    old = examined()
    new = old.id |> Bench.examine_again!(@me) |> Bench.finish_examination!(%{}, @agent)
    other = examined("c/d", 2)
    running = Bench.examine_again!(new.id, @me)
    Bench.remove_audit!(new, @me)
    for a <- [old, new, running], do: assert({:error, _} = Bench.get_audit(a.id))
    assert Bench.get_audit!(other.id)
  end

  test "removing a planted test project keeps the measured audits" do
    own = Bench.examine_own!(@me)
    planted = examined(hd(Bench.Audit.measurable()), 3)
    Bench.remove_audit!(planted, @me)
    assert Bench.get_audit!(own.id)
  end

  test "only the Requester starts our own project, once at a time" do
    for actor <- [nil, Actor.agent()],
        do: assert({:error, %Ash.Error.Forbidden{}} = Bench.examine_own(actor: actor))

    own = Bench.examine_own!(@me)
    assert {own.repository, own.base_sha} == {"pikespeak/ci-patient", nil}
    assert message(Bench.examine_own(@me)) =~ "error.again.running"
    Bench.stop_audit!(own, "x", @me)
    assert Bench.examine_own!(@me)
  end

  test "only the agent reports a wait, and only while examining" do
    audit = Bench.plant_audit!("a/b", 1)
    later = DateTime.add(DateTime.utc_now(), 600) |> DateTime.truncate(:second)

    for actor <- [nil, Actor.requester()],
        do: assert({:error, _} = Bench.report_wait(audit, %{waiting_until: later}, actor: actor))

    audit = Bench.report_wait!(audit, %{waiting_until: later}, @agent)
    assert [%{waiting_until: ^later}] = Bench.waiting_audits!()
    done = Bench.finish_examination!(audit, %{}, @agent)
    assert Bench.waiting_audits!() == []
    assert {:error, _} = Bench.report_wait(done, %{waiting_until: later}, @agent)
  end
end
