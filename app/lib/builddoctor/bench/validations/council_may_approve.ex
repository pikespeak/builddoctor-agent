defmodule Builddoctor.Bench.Validations.CouncilMayApprove do
  @moduledoc "The owner's limits: a trial the council has cleared, and at most two approvals a day (UTC)."
  use Ash.Resource.Validation

  require Ash.Query

  alias Builddoctor.Bench.{Audit, Trial}

  @per_day 2

  @impl true
  def validate(changeset, _opts, _context) do
    id = changeset.data.id
    today = DateTime.new!(Date.utc_today(), ~T[00:00:00])

    cleared =
      Trial
      |> Ash.Query.filter(audit_id == ^id and status == :published)
      |> Ash.exists?(authorize?: false)

    used =
      Audit |> Ash.Query.filter(council_approved_at >= ^today) |> Ash.count!(authorize?: false)

    cond do
      not cleared -> {:error, message: "error.council.notCleared"}
      used >= @per_day -> {:error, message: "error.council.limit"}
      true -> :ok
    end
  end
end
