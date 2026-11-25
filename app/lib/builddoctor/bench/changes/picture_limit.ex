defmodule Builddoctor.Bench.Changes.PictureLimit do
  @moduledoc "So many editions with pictures a day (UTC), and none without budget."
  use Ash.Resource.Change

  require Ash.Query

  alias Builddoctor.Bench.{AiCall, Picture}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      # Two editions at the same time must not both take the last one.
      Builddoctor.Repo.query!("select pg_advisory_xact_lock(hashtext('picture_limit'))")
      audit = Ash.Changeset.get_attribute(changeset, :audit_id)
      since = DateTime.new!(Date.utc_today(), ~T[00:00:00])

      others =
        Picture
        |> Ash.Query.filter(inserted_at >= ^since and audit_id != ^audit)
        |> Ash.Query.select([:audit_id])
        |> Ash.read!(authorize?: false)
        |> Enum.uniq_by(& &1.audit_id)

      cond do
        not Builddoctor.TestPhase.on?() and length(others) >= Picture.per_day() ->
          refuse(changeset, "error.picture.day")

        not budget?() ->
          refuse(changeset, "error.picture.budget")

        true ->
          changeset
      end
    end)
  end

  defp budget? do
    AiCall
    |> Ash.ActionInput.for_action(:budget_left, %{})
    |> Ash.run_action!(authorize?: false)
  end

  defp refuse(changeset, message),
    do: Ash.Changeset.add_error(changeset, field: :audit_id, message: message)
end
