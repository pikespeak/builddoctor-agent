defmodule BuilddoctorWeb.AuditView do
  @moduledoc "Turns an Audit and its measured data into what the page shows."
  alias Builddoctor.{Bench, Forest}

  @total 8
  def total, do: @total

  def load(audit) do
    trial = audit.id |> Bench.list_trials!() |> List.first()
    runs = Bench.list_runs!(audit.id)

    %{
      audit: audit,
      trial: trial,
      runs: runs,
      events: Bench.list_events!(audit.id),
      findings: Bench.list_findings!(audit.id),
      newer: audit.id |> Bench.newer_audits!() |> List.first(),
      waits: waits(audit)
    }
  end

  # GitHub's limit is the same for every foreign project.
  defp waits(%{state: :examining, slot: slot, replaces_id: old}) when slot != nil or old != nil do
    case Bench.waiting_audits!() do
      [%{waiting_until: at}] -> at
      [] -> nil
    end
  end

  defp waits(_), do: nil

  @doc "The steps of an Examination; a step is done only if the agent reported it."
  def steps(view) do
    kinds = MapSet.new(view.events, & &1.kind)
    said = for e <- view.events, e.kind == :openai, do: e.message
    told = &Enum.any?(said, fn m -> String.starts_with?(m, &1) end)

    [
      {"Read the workflow and its latest successful run", :github in kinds},
      {"Ask for more facts if needed and look for problems",
       Enum.any?(said, &(not String.starts_with?(&1, "The analyst asked")))},
      {"Let the council check every statement", told.("The council checked")}
    ]
  end

  @doc "Whole minutes without news while measuring, from the fourth on."
  def silent(audit, now \\ DateTime.utc_now()) do
    minutes = DateTime.diff(now, audit.updated_at, :minute)
    if audit.state == :measuring and minutes >= 4, do: minutes
  end

  @doc "Whether a Visitor may ask for a new Examination."
  def due?(audit, now \\ DateTime.utc_now()),
    do: DateTime.diff(now, audit.inserted_at, :hour) >= 24

  def mood(%{audit: %{state: :stopped}}), do: :stopped

  def mood(%{audit: %{state: :done}, trial: %{verdict: v}})
      when v in [:accepted, :rejected, :inconclusive],
      do: v

  def mood(%{trial: %{verdict: :failed}}), do: :rejected
  def mood(_), do: :measuring

  @doc "The plan of the picture; side is :before or :after."
  def plan(view, side, now \\ DateTime.utc_now()) do
    done = view.audit.state == :done
    jobs = view |> jobs(side) |> watched(view.audit, now)
    base = relative(view.audit.examined_jobs || [])
    both = max(stop(jobs(view, :before)), stop(jobs(view, :after)))

    Forest.plan(
      view.audit.repository,
      if(done and side == :before, do: :measuring, else: mood(view)),
      jobs,
      span: if(done, do: both, else: stop(base)),
      spread: spread(view.runs),
      caption: caption(view, side),
      walked: walked(view.audit),
      flowers: if(side == :after, do: view |> bloom() |> elem(0), else: 0),
      seeds: view.audit.state == :examining and jobs == []
    )
  end

  defp jobs(view, side) do
    own = Enum.filter(view.runs, &(not &1.warmup and side == :after == (&1.trial_id != nil)))

    case median_run(own) do
      nil -> relative(view.audit.examined_jobs || [])
      run -> relative(run.jobs, run.started_at)
    end
  end

  # While measuring, times come from the run that is active, never from an older one.
  defp watched(jobs, %{state: :measuring, live_jobs: live}, now) do
    for job <- jobs,
        do: Map.put(job, :live, progress(Enum.find(live || [], &(&1.name == job.name)), now))
  end

  defp watched(jobs, _, _), do: jobs

  defp progress(%{stage: :running, started_at: %DateTime{} = from}, now),
    do: {:running, seconds(from, now)}

  defp progress(%{stage: :done, started_at: %DateTime{} = from, completed_at: to}, _)
       when not is_nil(to),
       do: {:done, seconds(from, to)}

  defp progress(_, _), do: {:queued, nil}

  # GitHub gives a skipped job an end before its start.
  defp seconds(from, to), do: max(DateTime.diff(to, from), 0)

  @doc "The rows of the timelines: {title, rows} per side, all on one scale."
  def timelines(view, now \\ DateTime.utc_now())

  def timelines(%{audit: %{state: :done}} = view, _) do
    sides = [{"Before", jobs(view, :before)}, {"With the change", jobs(view, :after)}]
    span = sides |> Enum.map(fn {_, jobs} -> stop(jobs) end) |> Enum.max()
    for {title, jobs} <- sides, do: {title, rows(jobs, span)}
  end

  def timelines(%{audit: %{state: :measuring, live_jobs: [_ | _] = live}} = view, now) do
    names = Enum.map(relative(view.audit.examined_jobs || []), & &1.name)
    starts = for j <- live, j.started_at, do: j.started_at
    first = Enum.min(starts, DateTime, fn -> now end)

    jobs =
      for name <- Enum.uniq(names ++ Enum.map(live, & &1.name)) do
        job = Enum.find(live, &(&1.name == name))
        state = progress(job, now)
        start = if job && job.started_at, do: seconds(first, job.started_at), else: 0
        %{name: name, start: start, seconds: elem(state, 1) || 0, live: state}
      end

    [{"This run", rows(jobs, max(stop(jobs), stop(relative(view.audit.examined_jobs || []))))}]
  end

  def timelines(%{audit: %{state: :measuring}}, _), do: []

  def timelines(view, _) do
    case relative(view.audit.examined_jobs || []) do
      [] -> []
      jobs -> [{"Where the time goes", rows(jobs, stop(jobs))}]
    end
  end

  defp rows(jobs, span) do
    share = &Float.round(&1 * 100 / max(span, 1), 1)

    for job <- jobs do
      queued = match?(%{live: {:queued, _}}, job)

      %{
        name: job.name,
        from: if(queued, do: 0, else: share.(job.start)),
        width: if(queued, do: nil, else: max(share.(job.seconds), 0.5)),
        words: job_words(job)
      }
    end
  end

  @doc "Many jobs would cover each other in the picture; the timeline shows them."
  def picture?(plan), do: length(plan.jobs) <= 4

  @doc "The saved time of a proven change of the wait, or nil."
  def meadow(%{audit: %{state: :done}, trial: %{verdict: :accepted, goal: :wait} = trial} = view) do
    base = trial.numbers["baseline"]["wait"]["median"]
    cand = trial.numbers["candidate"]["wait"]["median"]
    {count, rule} = bloom(view)
    kept = cand * 100 / base

    %{
      kept: Float.round(kept, 1),
      words: "#{number(cand)} s",
      legend:
        "#{if count == 1, do: "1 flower", else: "#{count} flowers"}: #{rule} at the median.",
      flowers:
        for i <- 0..(count - 1)//1 do
          %{
            left: Float.round(kept + (i + 0.3) * (99 - kept) / count, 2),
            top: 4 + rem(i * 11, 23),
            color: Enum.at(~w(bg-madder bg-sun bg-paper bg-violet), rem(i, 4))
          }
        end
    }
  end

  def meadow(_), do: nil

  @doc "The facts a finding rests on."
  def evidence(finding, audit), do: Enum.filter(audit.facts || [], &(&1.id in finding.evidence))

  @doc "What kind of problem a finding is about."
  def kind(%{kind: :file_error}), do: "Error in the file"
  def kind(%{kind: nil}), do: nil
  def kind(%{kind: kind}), do: kind |> to_string() |> String.capitalize()

  @doc "A weakness in words, for the Requester."
  def notice(%{kind: :untrusted_input}), do: "Text from outside reaches a shell line."
  def notice(%{kind: :credentials}), do: "The file contains a password."

  def notice(%{kind: :foreign_code}),
    do: "Code from outside may run with the rights of the project."

  @doc "One line for the list of projects."
  def summary(%{state: :examining}), do: "The doctor is reading."
  def summary(%{findings: [finding | _]}), do: finding.title
  def summary(%{trials: [trial | _]}), do: shorten(trial.hypothesis)
  def summary(_), do: "Nothing stands out."

  defp shorten(text),
    do: if(String.length(text) > 160, do: String.slice(text, 0, 157) <> "…", else: text)

  # One flower per saved second or minute at the median; large savings use larger steps.
  defp bloom(%{audit: %{state: :done}, trial: %{verdict: :accepted} = trial}) do
    saved = saved(trial.goal, trial.numbers)

    case {trial.goal, saved} do
      {:bill, s} -> {trunc(s), "one for each saved billed minute"}
      {:wait, s} when s <= 120 -> {trunc(s), "one for each saved second"}
      {:wait, s} when s <= 1200 -> {trunc(s / 10), "one for every 10 saved seconds"}
      {:wait, s} -> {trunc(s / 60), "one for each saved minute"}
    end
  end

  defp bloom(_), do: {0, ""}

  def more_jobs(%{jobs_total: total, examined_jobs: [_ | _] = shown})
      when is_integer(total) and total > length(shown),
      do: "#{total} jobs ran; the longest are shown."

  def more_jobs(_), do: nil

  @doc "How to read the picture."
  def legend(view, side) do
    read =
      if view.audit.state == :measuring,
        do: "Each tree is a job. It grows while the job runs.",
        else: "Each tree is a job. The path is time, and the pennant marks the end of the run."

    case {side, bloom(view)} do
      {:after, {0, _}} -> read
      {:after, {1, _}} -> read <> " The flower stands for the time saved at the median."
      {:after, {count, rule}} -> read <> " #{count} flowers: #{rule} at the median."
      _ -> read
    end
  end

  # The doctor walks with the finished jobs of the active run.
  defp walked(%{state: :measuring, live_jobs: [_ | _] = live, examined_jobs: examined}) do
    total = max(length(live), length(examined || []))
    Enum.count(live, &(&1.stage == :done)) / total
  end

  defp walked(%{state: :measuring}), do: 0.0
  defp walked(_), do: 1.0

  @doc "The jobs in words, for the list below the picture."
  def job_words(%{live: {:queued, _}}), do: "not started"
  def job_words(%{live: {:running, seconds}}), do: "running, #{seconds} s"
  def job_words(%{live: {:done, seconds}}), do: "#{seconds} s"
  def job_words(job), do: "#{job.seconds} s"

  @doc "The steps of the agent, with one line per run: its last one."
  def events(view) do
    last =
      for e <- view.events, run_line?(e), into: %{}, do: {e.reference, e.id}

    Enum.filter(view.events, &(not run_line?(&1) or last[&1.reference] == &1.id))
  end

  defp run_line?(e), do: e.kind in [:run_started, :run_finished] and e.reference != nil

  @doc "Whether a job runs right now, so that its seconds must count on."
  def running?(%{audit: %{state: :measuring, live_jobs: live}}),
    do: Enum.any?(live || [], &(&1.stage == :running))

  def running?(_), do: false

  @doc "The change of a Trial, line by line."
  def change(%{original: original, patch: patch}) when is_binary(original),
    do:
      for(
        row <- Builddoctor.Diff.lines(original, patch),
        do: %{row | text: Builddoctor.Redact.emails(row.text)}
      )

  defp median_run([]), do: nil

  defp median_run(runs),
    do: runs |> Enum.sort_by(& &1.wall_seconds) |> Enum.at(div(length(runs), 2))

  # A measured run begins with its start, so that the pennant stands at the measured wait.
  defp relative(jobs, start \\ nil)
  defp relative([], _), do: []

  defp relative(jobs, start) do
    first = start || jobs |> Enum.map(& &1.started_at) |> Enum.min(DateTime)

    for j <- jobs,
        do: %{
          name: j.name,
          start: DateTime.diff(j.started_at, first),
          seconds: DateTime.diff(j.completed_at, j.started_at)
        }
  end

  defp stop(jobs), do: jobs |> Enum.map(&(&1.start + &1.seconds)) |> Enum.max(fn -> 1 end)

  defp spread(runs) do
    walls = for r <- runs, not r.warmup, is_nil(r.trial_id), do: r.wall_seconds

    if length(walls) < 2,
      do: 0.0,
      else: (Enum.max(walls) - Enum.min(walls)) / max(Enum.max(walls), 1)
  end

  defp caption(%{audit: %{state: :done}}, :before), do: "Before the change."
  defp caption(%{audit: %{state: :done}} = v, :after), do: elem(result(v), 0)
  defp caption(%{audit: %{state: :examining}}, _), do: "Listening to the pipeline."
  defp caption(%{audit: %{state: :awaiting_approval}}, _), do: "One tree waits for the next."
  defp caption(%{audit: %{state: :examined}}, _), do: "A suspicion, not proof."
  defp caption(%{audit: %{state: :stopped}}, _), do: "This audit was stopped."
  defp caption(_, _), do: "Three measurements. One would only be gossip."

  def stage(view, name) do
    live = view.audit.live_jobs || []

    case {view.audit.state, Enum.find(live, &(&1.name == name))} do
      {:measuring, %{stage: stage}} -> stage
      {:measuring, nil} when live != [] -> :queued
      _ -> :done
    end
  end

  def count(view), do: length(view.runs)

  @doc "Headline and detail of a finished audit. The result comes first and follows the goal."
  def result(%{trial: %{verdict: v, reason: reason} = trial}) do
    case v do
      :accepted -> {gain(trial.goal, trial.numbers), reason}
      :rejected -> {"No #{noun(trial.goal)} saved.", reason}
      :inconclusive -> {"We cannot prove it yet.", reason}
      :failed -> {"The change broke the build. The main branch was never touched.", reason}
      _ -> {"No verdict yet.", ""}
    end
  end

  def result(_), do: {"No verdict yet.", ""}

  # "Every run" needs the worst run with the change to save this much against the best one before.
  defp gain(goal, numbers) do
    key = to_string(goal)
    {base, cand} = {numbers["baseline"][key], numbers["candidate"][key]}
    saved = saved(goal, numbers)
    scope = if base["min"] - cand["max"] >= saved, do: ", every run.", else: " at the median."
    "#{number(saved)} #{noun(goal, saved)} back#{scope}"
  end

  defp saved(goal, %{"baseline" => base, "candidate" => cand}) do
    key = to_string(goal)
    base[key]["median"] - cand[key]["median"]
  end

  defp noun(goal, amount \\ 2)
  defp noun(:wait, amount) when amount == 1, do: "second"
  defp noun(:wait, _), do: "seconds"
  defp noun(:bill, amount) when amount == 1, do: "billed minute"
  defp noun(:bill, _), do: "billed minutes"

  @doc "Median before and with the change, for the goal; nil without runs on both sides."
  def before_after(%{"goal" => goal, "baseline" => %{} = base, "candidate" => %{} = cand}) do
    for side <- [base, cand], do: "#{number(side[goal]["median"])} #{unit(goal)}"
  end

  def before_after(_), do: nil

  def number(x) when is_float(x) and trunc(x) == x, do: trunc(x)
  def number(x), do: x

  def goal(:wait), do: "Wait"
  def goal(:bill), do: "Bill"
  def unit("wait"), do: "s"
  def unit("bill"), do: "min"
end
