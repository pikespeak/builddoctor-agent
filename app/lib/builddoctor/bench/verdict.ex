defmodule Builddoctor.Bench.Verdict do
  @moduledoc """
  The verdict rule. A Trial names one Goal before measuring. It is accepted only if
  every run passed, the Goal's median is at least 10 % lower, the two ranges do not
  overlap and the Guard did not get more than 10 % worse.
  """

  @min_runs 3
  @margin 0.10
  @fields %{wait: :wall_seconds, bill: :billed_minutes}

  def decide(goal, baseline, candidate) when is_map_key(@fields, goal) do
    numbers = %{goal: goal, baseline: summary(baseline), candidate: summary(candidate)}

    cond do
      Enum.any?(candidate, &(not &1.succeeded)) ->
        {:failed, "A run with the change did not pass.", numbers}

      Enum.any?(baseline, &(not &1.succeeded)) ->
        {:inconclusive, "A run without the change did not pass.", numbers}

      length(baseline) < @min_runs or length(candidate) < @min_runs ->
        {:inconclusive, "Fewer than #{@min_runs} runs on one side.", numbers}

      true ->
        compare(goal, numbers)
    end
  end

  defp compare(goal, %{baseline: base, candidate: cand} = numbers) do
    {b, c} = {base[goal], cand[goal]}
    guard = if goal == :wait, do: :bill, else: :wait
    gain = gain(b.median, c.median)
    loss = -gain(base[guard].median, cand[guard].median)

    numbers =
      Map.merge(numbers, %{
        gain_percent: percent(gain),
        guard: guard,
        guard_percent: percent(loss)
      })

    cond do
      c.median >= b.median -> {:rejected, "The median did not get lower.", numbers}
      gain < @margin -> {:inconclusive, "The gain is below 10 percent.", numbers}
      c.max >= b.min -> {:inconclusive, "The measured ranges overlap.", numbers}
      loss > @margin -> {:inconclusive, "The guard got more than 10 percent worse.", numbers}
      true -> {:accepted, "Better in every run.", numbers}
    end
  end

  defp gain(b, _) when b == 0, do: 0.0
  defp gain(b, c), do: (b - c) / b
  defp percent(x), do: Float.round(x * 100.0, 1)

  def summary([]), do: nil

  def summary(runs) do
    Map.new(@fields, fn {name, field} ->
      {name, spread(Enum.map(runs, &Map.fetch!(&1, field)))}
    end)
    |> Map.put(:count, length(runs))
  end

  defp spread(values), do: %{median: median(values), min: Enum.min(values), max: Enum.max(values)}

  def median(values) do
    sorted = Enum.sort(values)
    n = length(sorted)
    mid = div(n, 2)

    if rem(n, 2) == 1,
      do: Enum.at(sorted, mid),
      else: (Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2
  end
end
