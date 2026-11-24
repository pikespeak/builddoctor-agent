defmodule Builddoctor.Bench.VerdictTest do
  use ExUnit.Case, async: true

  alias Builddoctor.Bench.Verdict

  defp runs(walls, ok \\ true, bill \\ 3),
    do: Enum.map(walls, &%{wall_seconds: &1, billed_minutes: bill, succeeded: ok})

  defp verdict(b, c), do: Verdict.decide(:wait, b, c) |> elem(0)

  test "accepts a clear gain with separate ranges" do
    assert {:accepted, _, numbers} = Verdict.decide(:wait, runs([63, 70, 91]), runs([25, 30, 35]))
    assert numbers.gain_percent == 57.1
    assert numbers.baseline.wait == %{median: 70, min: 63, max: 91}
  end

  test "accepts exactly ten percent" do
    assert verdict(runs([100, 100, 100]), runs([90, 90, 90])) == :accepted
  end

  test "stays open when ranges overlap or the gain is small" do
    assert verdict(runs([60, 70, 91]), runs([50, 55, 60])) == :inconclusive
    assert verdict(runs([100, 100, 100]), runs([95, 95, 95])) == :inconclusive
  end

  test "rejects an equal, slower or zero baseline median" do
    assert verdict(runs([60, 60, 60]), runs([60, 60, 60])) == :rejected
    assert verdict(runs([60, 60, 60]), runs([70, 70, 70])) == :rejected
    assert verdict(runs([0, 0, 0]), runs([0, 0, 0])) == :rejected
  end

  test "a failed candidate is never faster" do
    assert verdict(runs([60, 60, 60]), runs([1, 1, 1], false)) == :failed
  end

  test "a failed baseline or too few runs prove nothing" do
    assert verdict(runs([60, 60, 60], false), runs([10, 10, 10])) == :inconclusive
    assert verdict(runs([60, 60]), runs([10, 10, 10])) == :inconclusive
    assert verdict([], []) == :inconclusive
  end

  test "median of an even count" do
    assert Verdict.median([4, 1, 3, 2]) == 2.5
  end

  test "fewer billed minutes are a bill goal, with wait as the guard" do
    base = runs([60, 60, 60], true, 3)
    assert {:accepted, _, n} = Verdict.decide(:bill, base, runs([62, 62, 62], true, 1))
    assert {n.guard, n.guard_percent, n.gain_percent} == {:wait, 3.3, 66.7}
    assert {:inconclusive, reason, _} = Verdict.decide(:bill, base, runs([80, 80, 80], true, 1))
    assert reason =~ "guard"
  end

  test "faster but more expensive is not accepted" do
    assert verdict(runs([60, 60, 60], true, 3), runs([20, 20, 20], true, 4)) == :inconclusive
  end
end
