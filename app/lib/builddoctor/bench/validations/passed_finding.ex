defmodule Builddoctor.Bench.Validations.PassedFinding do
  @moduledoc "A picture belongs to a published article of the same edition, or to none."
  use Ash.Resource.Validation

  alias Builddoctor.Bench.Finding

  @impl true
  def validate(changeset, _opts, _context) do
    audit = Ash.Changeset.get_attribute(changeset, :audit_id)

    with id when id != nil <- Ash.Changeset.get_attribute(changeset, :finding_id),
         {:ok, %{audit_id: ^audit, status: :published}} <-
           Ash.get(Finding, id, authorize?: false) do
      :ok
    else
      nil -> :ok
      _ -> {:error, field: :finding_id, message: "error.picture.finding"}
    end
  end
end
