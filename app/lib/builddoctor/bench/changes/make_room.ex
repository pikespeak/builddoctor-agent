defmodule Builddoctor.Bench.Changes.MakeRoom do
  @moduledoc """
  When every page is printed, a new edition takes the page of the oldest finished one. That result
  stays readable at its address and in the archive. Before, a full paper hid the form, so the jury
  could not start anything (Codex peer review, 2026-11-26).
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Builddoctor.Bench.Audit
  alias Builddoctor.Bench.Changes.OnceADay

  @impl true
  def change(changeset, _opts, context) do
    visitor? = not match?(%{actor: %{role: :requester}}, context)

    Ash.Changeset.before_action(changeset, fn changeset ->
      taken = Audit |> Ash.Query.filter(not is_nil(slot)) |> Ash.count!(authorize?: false)
      if taken < Audit.places(), do: changeset, else: take_oldest(changeset, visitor?)
    end)
  end

  # Checked again here, after the visitor lock: a project must not take a page from itself, and one
  # whose page went to the archive meanwhile waits its 24 hours (Codex review of phase B, 2026-11-26).
  defp take_oldest(changeset, visitor?) do
    name = changeset |> Ash.Changeset.get_attribute(:repository) |> to_string()

    cond do
      OnceADay.on_a_page?(String.downcase(name)) ->
        Ash.Changeset.add_error(changeset,
          field: :repository,
          message: "error.repository.planted"
        )

      visitor? and OnceADay.recent?(name) ->
        Ash.Changeset.add_error(changeset, field: :repository, message: "error.again.tooSoon")

      true ->
        evict(changeset)
    end
  end

  defp evict(changeset) do
    Audit
    |> Ash.Query.filter(not is_nil(slot) and state in [:examined, :done, :stopped])
    |> Ash.Query.sort(inserted_at: :asc, id: :asc)
    |> Ash.Query.limit(1)
    |> Ash.read!(authorize?: false)
    |> case do
      [oldest] ->
        Ash.update!(oldest, %{}, action: :give_way, authorize?: false)
        Ash.Changeset.force_change_attribute(changeset, :slot, oldest.slot)

      [] ->
        Ash.Changeset.add_error(changeset, field: :slot, message: "error.paper.busy")
    end
  end
end
