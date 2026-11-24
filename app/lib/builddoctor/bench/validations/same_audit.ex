defmodule Builddoctor.Bench.Validations.SameAudit do
  @moduledoc "A candidate run must belong to the audit of its trial."
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    audit_id = Ash.Changeset.get_attribute(changeset, :audit_id)

    case Ash.Changeset.get_attribute(changeset, :trial_id) do
      nil ->
        :ok

      id ->
        case Ash.get(Builddoctor.Bench.Trial, id, authorize?: false) do
          {:ok, %{audit_id: ^audit_id}} -> :ok
          _ -> {:error, field: :trial_id, message: "does not belong to this audit"}
        end
    end
  end
end
