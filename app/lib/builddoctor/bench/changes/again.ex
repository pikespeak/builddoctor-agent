defmodule Builddoctor.Bench.Changes.Again do
  @moduledoc """
  A new Examination of a planted project. The old result stays until the new one is there.
  The Requester may ask at any time, a Visitor once in 24 hours and project.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Builddoctor.Bench.Audit

  @impl true
  def change(changeset, _opts, %{actor: actor}) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case Ash.get(Audit, Ash.Changeset.get_argument(changeset, :audit_id), authorize?: false) do
        {:ok, %{slot: slot, state: :examined} = old} when slot != nil ->
          take(changeset, old, actor)

        _ ->
          refuse(changeset, "error.again.notPossible")
      end
    end)
  end

  defp take(changeset, old, actor) do
    if match?(%{role: :requester}, actor) or not recent?(old.repository) do
      Ash.Changeset.force_change_attributes(changeset, %{
        repository: old.repository,
        replaces_id: old.id
      })
    else
      refuse(changeset, "error.again.tooSoon")
    end
  end

  defp recent?(repository) do
    since = DateTime.add(DateTime.utc_now(), -24, :hour)

    Audit
    |> Ash.Query.filter(repository == ^repository and inserted_at > ^since)
    |> Ash.exists?(authorize?: false)
  end

  defp refuse(changeset, message),
    do: Ash.Changeset.add_error(changeset, field: :audit_id, message: message)
end
