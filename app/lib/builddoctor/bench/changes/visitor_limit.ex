defmodule Builddoctor.Bench.Changes.VisitorLimit do
  @moduledoc """
  The owner's limits for Visitors: so many Examinations a day (UTC), and few at once.
  Every start counts, also one that stopped. The Requester has no limit.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Builddoctor.Bench.Audit
  alias Builddoctor.TestPhase

  @per_day 20
  # The days of the jury (owner, 2026-11-24).
  @jury [~D[2026-11-30], ~D[2026-12-01]]
  @jury_per_day 40

  @doc "An atom is greater than every number, so :infinity never is reached."
  def per_day(day) do
    cond do
      TestPhase.on?(day) -> :infinity
      day in @jury -> @jury_per_day
      true -> @per_day
    end
  end

  # The agent works on five at once.
  def at_once(day), do: if(TestPhase.on?(day), do: 5, else: 3)
  def per_visitor(day), do: if(TestPhase.on?(day), do: 20, else: 5)

  @impl true
  def change(changeset, _opts, %{actor: %{role: :requester}}), do: changeset

  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      # Two starts at the same time must not both take the last one.
      Builddoctor.Repo.query!("select pg_advisory_xact_lock(hashtext('visitor_limit'))")
      today = Date.utc_today()
      since = DateTime.new!(today, ~T[00:00:00])

      started =
        Audit
        |> Ash.Query.filter(by_visitor and inserted_at >= ^since)
        |> Ash.count!(authorize?: false)

      running =
        Audit
        |> Ash.Query.filter(by_visitor and state == :examining)
        |> Ash.count!(authorize?: false)

      cond do
        started >= per_day(today) -> refuse(changeset, "error.limit.day")
        running >= at_once(today) -> refuse(changeset, "error.limit.busy")
        not mine?(changeset, today) -> refuse(changeset, "error.limit.visitor")
        true -> Ash.Changeset.force_change_attribute(changeset, :by_visitor, true)
      end
    end)
  end

  # Without a known address only the limits for all apply.
  defp mine?(changeset, today) do
    case Ash.Changeset.get_argument(changeset, :visitor) do
      nil -> true
      key -> not changeset.valid? or Builddoctor.VisitorCount.take(key, per_visitor(today))
    end
  end

  defp refuse(changeset, message),
    do: Ash.Changeset.add_error(changeset, field: :by_visitor, message: message)
end
