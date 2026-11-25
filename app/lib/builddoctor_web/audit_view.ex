defmodule BuilddoctorWeb.AuditView do
  @moduledoc "Turns an Audit and its measured data into what the page shows."
  alias Builddoctor.Bench

  @total 8
  def total, do: @total

  def load(audit, viewer \\ nil) do
    as = [actor: viewer]
    trial = audit.id |> Bench.list_trials!(as) |> List.first()
    runs = Bench.list_runs!(audit.id, as)

    audit = Ash.load!(audit, :grade, as)

    %{
      audit: audit,
      trial: trial,
      runs: runs,
      events: Bench.list_events!(audit.id, as),
      findings: Bench.list_findings!(audit.id, as),
      pictures: audit.id |> Bench.list_pictures!(as) |> Map.new(&{&1.place, &1}),
      lines: Bench.list_lines!(audit.id, as),
      newer: audit.id |> Bench.newer_audits!(as) |> List.first(),
      waits: waits(audit, as)
    }
  end

  # GitHub's limit is the same for every foreign project.
  defp waits(%{state: :examining, slot: slot, replaces_id: old}, as)
       when slot != nil or old != nil do
    case Bench.waiting_audits!(as) do
      [%{waiting_until: at}] -> at
      [] -> nil
    end
  end

  defp waits(_, _), do: nil

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

  defp jobs(view, side) do
    own = Enum.filter(view.runs, &(not &1.warmup and side == :after == (&1.trial_id != nil)))

    case median_run(own) do
      nil -> relative(view.audit.examined_jobs || [])
      run -> relative(run.jobs, run.started_at)
    end
  end

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

  @doc "The line of the editor, if it passed."
  def line(lines, kind, place \\ 0) do
    Enum.find_value(lines, &((&1.kind == kind and &1.place == place) && &1.text))
  end

  @doc "The headline of the editor, or else the title of the first article."
  def headline(%{lines: lines, findings: findings} = audit) do
    line(lines, :headline) || plain(findings, audit)
  end

  defp plain([finding | _], _), do: finding.title
  defp plain([], %{trials: [_ | _]}), do: "We have a suspicion."
  defp plain([], _), do: "No finding passed every check."

  @doc "Seconds of waiting and of work of the last job, if the facts name the same job for both."
  def waited(%{kind: :waiting} = finding, audit) do
    texts = finding |> evidence(audit) |> Enum.map(& &1.text)

    with [_, wait, name] <- first(texts, ~r/The longest wait was (\d+) s, for "([^"]+)"/),
         [_, ^name, work] <-
           first(texts, ~r/The last job to end was "([^"]+)"\..* ran for (\d+) s/),
         {wait, work} = {String.to_integer(wait), String.to_integer(work)},
         true <- wait + work <= 900 do
      {wait, work}
    else
      _ -> nil
    end
  end

  def waited(_, _), do: nil

  defp first(texts, pattern), do: Enum.find_value(texts, &Regex.run(pattern, &1))

  @doc "What happens right now, for the line above an edition in the making."
  def status(view) do
    said = for e <- view.events, e.kind == :openai, do: e.message

    cond do
      view.pictures != %{} and view.lines == [] ->
        "The editor writes headlines and captions."

      view.pictures != %{} ->
        "The articles are written. The photos are in the darkroom."

      Enum.any?(said, &String.starts_with?(&1, "The council checked")) ->
        "The council is done. The edition goes to print."

      Enum.any?(said, &(not String.starts_with?(&1, "The analyst asked"))) ->
        "The council tries to refute every statement."

      view.audit.facts not in [nil, []] ->
        "The editors look for a story."

      view.events != [] ->
        "Our reporter reads the workflow and its jobs."

      true ->
        "Our reporter is on the way to GitHub."
    end
  end

  @doc "Another edition to read next; it changes from minute to minute."
  def teaser(view, viewer, now \\ div(System.system_time(:second), 60)) do
    others =
      for audit <- Bench.planted_audits!(actor: viewer),
          audit.state == :examined and audit.repository != view.audit.repository,
          do: audit

    if others != [],
      do: Enum.at(others, :erlang.phash2({view.audit.id, now}, length(others)))
  end

  @doc "One line for the list of projects."
  def summary(%{state: :examining}), do: "Our reporter is reading."
  def summary(%{findings: [finding | _]}), do: finding.title
  def summary(%{trials: [trial | _]}), do: shorten(trial.hypothesis)
  def summary(_), do: "No finding passed every check."

  defp shorten(text),
    do: if(String.length(text) > 160, do: String.slice(text, 0, 157) <> "…", else: text)

  def more_jobs(%{jobs_total: total, examined_jobs: [_ | _] = shown})
      when is_integer(total) and total > length(shown),
      do: "#{total} jobs ran; the longest are shown."

  def more_jobs(_), do: nil

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
  defp noun(:bill, amount) when amount == 1, do: "calculated runner minute"
  defp noun(:bill, _), do: "calculated runner minutes"

  @doc "Median before and with the change, for the goal; nil without runs on both sides."
  def before_after(%{"goal" => goal, "baseline" => %{} = base, "candidate" => %{} = cand}) do
    for side <- [base, cand], do: "#{number(side[goal]["median"])} #{unit(goal)}"
  end

  def before_after(_), do: nil

  @doc "What the outside fact-checker says, in words. Below 80 % it is not called sure (its documentation)."
  def stamp(%{support: nil}), do: nil

  def stamp(f) do
    cond do
      f.support == :supports and f.support_probability >= 0.8 -> "Supported"
      f.support == :supports -> "Uncertain"
      f.support == :contradicts -> "Disputed"
      true -> "Open"
    end
  end

  def stamp_class(f) do
    case stamp(f) do
      "Supported" -> "bg-leaf text-white"
      "Disputed" -> "bg-madder text-white"
      _ -> "bg-way"
    end
  end

  def support(f) do
    weakest = "Lowest estimated probability of support: #{percent(f.support_probability)}."

    case stamp(f) do
      "Supported" -> "The cited facts support every sentence. #{weakest}"
      "Uncertain" -> "It leans towards support, but it is not sure. #{weakest}"
      "Disputed" -> "One sentence may not agree with the cited facts. #{weakest}"
      "Open" -> "The cited facts may not settle one sentence. #{weakest}"
    end
  end

  def fit(%{fit: :addresses} = f),
    do:
      "Estimated probability that the advice works on the problem: #{percent(f.fit_probability)}."

  def fit(f),
    do:
      "It doubts that the advice works on the problem (estimated probability: #{percent(f.fit_probability)})."

  # An estimate is never shown as certain. The space does not break.
  def percent(p) when p > 0.99, do: "over 99\u00A0%"
  def percent(p) when p < 0.01, do: "under 1\u00A0%"
  def percent(p), do: "#{round(p * 100)}\u00A0%"

  def number(x) when is_float(x) and trunc(x) == x, do: trunc(x)
  def number(x), do: x

  @doc "What a goal means to a reader: a Wait lasts from the start of a run to its last job."
  def goal(goal) when goal in [:wait, "wait"], do: "Run time"
  def goal(goal) when goal in [:bill, "bill"], do: "Runner minutes (calculated)"
  def unit("wait"), do: "s"
  def unit("bill"), do: "min"
end
