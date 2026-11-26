defmodule Builddoctor.Bench.Changes.Announce do
  @moduledoc "After a start is stored, the operator is told about it by email (Builddoctor.Announce)."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, context) do
    started_by =
      if match?(%{actor: %{role: :requester}}, context), do: "requester", else: "visitor"

    Ash.Changeset.after_action(changeset, fn _changeset, audit ->
      # A fixed id, so that a retry after a lost answer is the same mail to Resend.
      %{
        "repository" => audit.repository,
        "started_by" => started_by,
        "uuid" => Ecto.UUID.generate(),
        "at" => DateTime.to_iso8601(audit.inserted_at)
      }
      |> Builddoctor.Announce.new()
      |> Oban.insert!()

      {:ok, audit}
    end)
  end
end
