defmodule Builddoctor.Bench.VisitorLimitTest do
  use Builddoctor.DataCase, async: false

  alias Builddoctor.Bench
  alias Builddoctor.Bench.Actor
  alias Builddoctor.Bench.Changes.VisitorLimit

  @agent [actor: Actor.agent()]
  @me [actor: Actor.requester()]

  defp message({:error, error}), do: Exception.message(error)
  defp limit, do: VisitorLimit.per_day(Date.utc_today())

  # Planted and ended, so that only the day counts.
  defp used(from, to) do
    for i <- from..to//1 do
      "a/b#{i}" |> Bench.plant_audit!(i) |> Bench.finish_examination!(%{}, @agent)
    end
  end

  test "the day is limited for Visitors, not for the Requester" do
    assert limit() in [20, 40]
    used(1, limit())
    assert message(Bench.plant_audit("x/y", 90)) =~ "error.limit.day"
    assert Bench.plant_audit!("x/y", 90, @me)

    # Yesterday does not count.
    Repo.query!(
      "update audits set inserted_at = inserted_at - interval '24 hours' where slot = 1"
    )

    assert Bench.plant_audit!("x/z", 91)
    assert message(Bench.plant_audit("x/w", 92)) =~ "error.limit.day"
  end

  test "a stopped start counts as well, a new Examination too" do
    used(1, limit() - 1)
    stopped = Bench.plant_audit!("x/y", 90)
    Bench.stop_audit!(stopped, "It is private.", @agent)
    assert message(Bench.plant_audit("x/z", 91)) =~ "error.limit.day"
    old = hd(Bench.planted_audits!())

    Repo.query!(
      "update audits set inserted_at = inserted_at - interval '25 hours' where id = $1",
      [
        Ecto.UUID.dump!(old.id)
      ]
    )

    Bench.plant_audit!("x/z", 91) |> Bench.finish_examination!(%{}, @agent)
    assert message(Bench.examine_again(old.id)) =~ "error.limit.day"
    assert Bench.examine_again!(old.id, @me)
  end

  test "three at once" do
    for i <- 1..3, do: Bench.plant_audit!("a/b#{i}", i)
    assert message(Bench.plant_audit("a/b4", 4)) =~ "error.limit.busy"
    assert Bench.plant_audit!("a/b4", 4, @me)
    Bench.finish_examination!(hd(Bench.planted_audits!()), %{}, @agent)
    assert Bench.plant_audit!("a/b5", 5)
  end

  test "the days of the jury allow more" do
    assert VisitorLimit.per_day(~D[2026-11-29]) == 20
    assert VisitorLimit.per_day(~D[2026-11-30]) == 40
    assert VisitorLimit.per_day(~D[2026-12-01]) == 40
    assert VisitorLimit.per_day(~D[2026-12-02]) == 20
  end

  test "nobody sets the mark by hand" do
    assert {:error, _} = Bench.plant_audit("a/b", 1, %{by_visitor: false})
  end
end
