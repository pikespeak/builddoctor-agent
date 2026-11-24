defmodule Builddoctor.Bench.Changes.Promote do
  @moduledoc "A finished new Examination takes the place of the one it replaces."
  use Ash.Resource.Change

  alias Builddoctor.Bench.Audit

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      with id when id != nil <- changeset.data.replaces_id,
           {:ok, %{slot: slot} = old} when slot != nil <- Ash.get(Audit, id, authorize?: false) do
        old |> Ash.Changeset.for_update(:give_way) |> Ash.update!(authorize?: false)

        Ash.Changeset.force_change_attributes(changeset, %{
          slot: slot,
          planted_as: String.downcase(old.repository)
        })
      else
        _ -> changeset
      end
    end)
  end
end
