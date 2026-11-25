defmodule Builddoctor.Bench.ExpireTest do
  use Builddoctor.DataCase, async: false
  use Oban.Testing, repo: Builddoctor.Repo

  alias Builddoctor.Bench
  alias Builddoctor.Bench.Actor

  @agent [actor: Actor.agent()]
  @me [actor: Actor.requester()]

  defp age(audit, days) do
    at = DateTime.add(DateTime.utc_now(), -days, :day)
    id = Ecto.UUID.dump!(audit.id)
    Repo.query!("update audits set inserted_at = $1 where id = $2", [at, id])
    audit
  end

  defp examined(name, slot),
    do: name |> Bench.plant_audit!(slot, @me) |> Bench.finish_examination!(%{}, @agent)

  test "foreign results go after 90 days, everything else stays" do
    old = examined("a/old", 1) |> age(91)
    young = examined("a/young", 2) |> age(89)
    running = Bench.plant_audit!("a/running", 3, @me) |> age(91)
    own = Bench.start_audit!("pikespeak/ci-patient", String.duplicate("a", 40), @me)
    own = own |> Bench.stop_audit!("x", @me) |> age(91)

    Bench.record_ai_call!(
      %{audit_id: old.id, model: "gpt-6.2-sol", input_tokens: 1, output_tokens: 1},
      @agent
    )

    assert :ok = perform_job(Builddoctor.Expire, %{})
    assert {:error, _} = Bench.get_audit(old.id)
    for a <- [young, running, own], do: assert(Bench.get_audit!(a.id))
    assert [%{audit_id: nil}] = Ash.read!(Bench.AiCall, @agent)
    # The place is free again.
    assert Bench.plant_audit!("b/new", 1, @me)
  end

  test "an expired earlier result does not take the newer one with it" do
    old = examined("a/b", 1)
    new = old.id |> Bench.examine_again!(@me) |> Bench.finish_examination!(%{}, @agent)
    age(old, 91)
    assert {:ok, 1} = Bench.expire_audits(authorize?: false)
    assert Bench.get_audit!(new.id).slot == 1
  end

  test "nobody starts it from outside" do
    old = examined("a/b", 1)

    for actor <- [nil, Actor.agent(), Actor.requester()] do
      assert {:error, _} = Bench.expire_audits(actor: actor)

      assert {:error, _} =
               old |> Ash.Changeset.for_destroy(:expire_one, %{}, actor: actor) |> Ash.destroy()
    end
  end

  test "email addresses are not shown, action names are" do
    assert Builddoctor.Redact.emails("# by jane@x.org now") == "# by [email] now"

    assert Builddoctor.Redact.emails("  - uses: a/b@release.branch # é j@x.org") ==
             "  - uses: a/b@release.branch # é [email]"
  end
end
