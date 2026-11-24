defmodule Builddoctor.Bench.Changes.RemoveAll do
  @moduledoc "Removing a planted project removes its other Examinations as well."
  use Ash.Resource.Change

  require Ash.Query

  alias Builddoctor.Bench.Audit

  @impl true
  def change(changeset, opts, _context) do
    %{id: id, repository: repository, slot: slot} = changeset.data

    if slot == nil or repository in opts[:except] do
      changeset
    else
      Ash.Changeset.before_action(changeset, fn changeset ->
        Audit
        |> Ash.Query.filter(repository == ^repository and id != ^id and is_nil(slot))
        |> Ash.read!(authorize?: false)
        |> Enum.each(&Ash.destroy!(&1, action: :remove, authorize?: false))

        changeset
      end)
    end
  end
end
