defmodule Builddoctor.Bench.Changes.Durations do
  @moduledoc "Wait is run start to last job end. Billed minutes are rounded up for every job."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    start = Ash.Changeset.get_attribute(changeset, :started_at)
    jobs = Ash.Changeset.get_attribute(changeset, :jobs)

    if changeset.valid? and start != nil and is_list(jobs) and jobs != [] do
      measure(changeset, start, jobs)
    else
      changeset
    end
  end

  defp billed(job) do
    seconds = DateTime.diff(job.completed_at, job.started_at)
    max(1, ceil(seconds / 60))
  end

  defp measure(changeset, start, jobs) do
    if Enum.any?(jobs, &DateTime.before?(&1.started_at, start)) do
      Ash.Changeset.add_error(changeset, field: :jobs, message: "must not start before the run")
    else
      last = jobs |> Enum.map(& &1.completed_at) |> Enum.max(DateTime)
      held = Enum.sum_by(jobs, &DateTime.diff(&1.completed_at, &1.started_at))

      changeset
      |> Ash.Changeset.force_change_attribute(:wall_seconds, DateTime.diff(last, start))
      |> Ash.Changeset.force_change_attribute(:runner_seconds, held)
      |> Ash.Changeset.force_change_attribute(:billed_minutes, Enum.sum_by(jobs, &billed/1))
      |> Ash.Changeset.force_change_attribute(
        :succeeded,
        Enum.all?(jobs, &(&1.conclusion == :success))
      )
    end
  end
end
