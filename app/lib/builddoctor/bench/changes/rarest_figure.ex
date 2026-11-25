defmodule Builddoctor.Bench.Changes.RarestFigure do
  @moduledoc """
  An edition keeps its figure; a new one takes the fitting figure that the fewest other editions use.
  Runs after the limit, which holds the lock.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Builddoctor.Bench.Picture

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      audit = Ash.Changeset.get_attribute(changeset, :audit_id)
      fitting = Ash.Changeset.get_argument(changeset, :figures)
      Ash.Changeset.force_change_attribute(changeset, :figure, figure(audit, fitting))
    end)
  end

  @doc "The figure of an edition, also before its first picture is ordered."
  def figure(audit, fitting) do
    used =
      Picture
      |> Ash.Query.filter(audit_id == ^audit or not is_nil(audit.slot))
      |> Ash.Query.select([:audit_id, :figure])
      |> Ash.read!(authorize?: false)
      |> Enum.uniq_by(&{&1.audit_id, &1.figure})

    own = Enum.find(used, &(&1.audit_id == audit))
    if own, do: own.figure, else: rarest(fitting, Enum.frequencies_by(used, & &1.figure))
  end

  defp rarest(fitting, counts), do: Enum.min_by(fitting, &Map.get(counts, &1, 0))
end
