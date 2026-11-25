defmodule Builddoctor.Bench.Grade do
  @moduledoc """
  The grade of a pipeline, from A++ to F. Code only: it starts at 100 and takes points off for what
  the facts show. Duration and waiting for a runner do not count; they follow from size and GitHub.
  Without at least three finished runs, or before the end of an Examination, there is no grade.
  """
  use Ash.Resource.Calculation

  @grades [{"A++", 100}, {"A+", 95}, {"A", 85}, {"B", 70}, {"C", 55}, {"D", 40}, {"F", 0}]
  @fewest_runs 3
  # Earlier Examinations computed fewer facts, so nothing could be taken off for them.
  @since ~U[2026-11-24 13:50:00Z]

  def grades, do: @grades

  @rules [
    {"Failed runs: some, 20% or more, 40% or more", "5, 15 or 25"},
    {"A workflow whose newest runs all failed", "15"},
    {"A run that failed and then passed on the same commit", "10"},
    {"Errors that actionlint finds in the file", "10 each, at most 20"},
    {"The workflow allows all write permissions, or does not set permissions for every job",
     "15 or 5"},
    {"Actions of third parties without a fixed commit", "10"},
    {"Jobs without an explicit timeout-minutes setting", "5"},
    {"No concurrency rule at the top of the file", "5"},
    {"Setup steps: 15% or more, 30% or more of all step time", "5 or 10"}
  ]

  def rules, do: @rules

  @impl true
  def load(_, _, _), do: [:facts, :state, :inserted_at]

  @impl true
  def calculate(audits, _, _), do: Enum.map(audits, &of/1)

  @doc "The letter, the points and every deduction; nil if the facts do not carry a grade."
  def of(%{state: state, facts: facts, inserted_at: at})
      when state in [:examined, :done] and is_list(facts) do
    enough = DateTime.compare(at, @since) != :lt

    case runs(facts) do
      {total, failed} when total >= @fewest_runs and enough ->
        off = Enum.reject([failures(total, failed) | others(facts)], &is_nil/1)
        points = max(100 - Enum.sum_by(off, &elem(&1, 0)), 0)
        %{letter: letter(points), points: points, off: off}

      _ ->
        nil
    end
  end

  def of(_), do: nil

  def letter(points), do: Enum.find_value(@grades, fn {l, from} -> points >= from && l end)

  defp runs(facts) do
    case numbers(
           facts,
           "failed",
           ~r/\AOf the last (\d+) finished runs of this workflow, (\d+) failed/
         ) do
      [total, failed] when failed <= total -> {total, failed}
      _ -> nil
    end
  end

  defp failures(_, 0), do: nil
  defp failures(total, n) when n * 10 >= total * 4, do: {25, "#{n} of #{total} runs failed"}
  defp failures(total, n) when n * 5 >= total, do: {15, "#{n} of #{total} runs failed"}
  defp failures(total, n), do: {5, "#{n} of #{total} runs failed"}

  defp others(facts) do
    [
      some(facts, ~r/\Ared\d*\z/, 15, "A workflow's newest runs all failed"),
      some(facts, ~r/\Aflaky\z/, 10, "A run failed and then passed on the same commit"),
      errors(Enum.count(facts, &(&1.id =~ ~r/\Afile\d+\z/))),
      rights(text(facts, "rights")),
      pinned(numbers(facts, "pinned", ~r/fixed commit: (\d+)/)),
      some(facts, ~r/\Atimeout\z/, 5, "Jobs without an explicit timeout-minutes setting"),
      some(facts, ~r/\Aconcurrency\z/, 5, "No concurrency rule at the top of the file"),
      setup(numbers(facts, "setup", ~r/(\d+)% of all step time/))
    ]
  end

  defp some(facts, id, points, words),
    do: if(Enum.any?(facts, &(&1.id =~ id)), do: {points, words})

  defp errors(0), do: nil
  defp errors(1), do: {10, "actionlint finds an error in the file"}
  defp errors(n), do: {20, "actionlint finds #{n} errors in the file"}

  defp rights(nil), do: nil

  defp rights(text) do
    if text =~ "all write permissions",
      do: {15, "The workflow file sets all write permissions at the top"},
      else: {5, "Permissions are not set for every job"}
  end

  defp pinned([n]) when n > 0, do: {10, "Actions of third parties without a fixed commit"}
  defp pinned(_), do: nil

  defp setup([n]) when n >= 30, do: {10, "Setup steps take #{n}% of all step time"}
  defp setup([n]) when n >= 15, do: {5, "Setup steps take #{n}% of all step time"}
  defp setup(_), do: nil

  defp text(facts, id), do: Enum.find_value(facts, &(&1.id == id && &1.text))

  defp numbers(facts, id, pattern) do
    case Regex.run(pattern, text(facts, id) || "") do
      [_ | found] -> Enum.map(found, &String.to_integer/1)
      nil -> nil
    end
  end
end
