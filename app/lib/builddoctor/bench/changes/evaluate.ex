defmodule Builddoctor.Bench.Changes.Evaluate do
  @moduledoc "Reads the measured runs of the audit and applies the verdict rule."
  use Ash.Resource.Change

  alias Builddoctor.Bench
  alias Builddoctor.Bench.Verdict

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      %{id: id, audit_id: audit_id, goal: goal} = changeset.data
      runs = audit_id |> Bench.list_runs!() |> Enum.reject(& &1.warmup)

      {verdict, reason, numbers} =
        Verdict.decide(
          goal,
          Enum.filter(runs, &is_nil(&1.trial_id)),
          Enum.filter(runs, &(&1.trial_id == id))
        )

      Ash.Changeset.force_change_attributes(changeset, %{
        verdict: verdict,
        reason: reason,
        numbers: numbers
      })
    end)
  end
end
