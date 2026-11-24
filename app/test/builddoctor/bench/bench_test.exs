defmodule Builddoctor.BenchTest do
  use Builddoctor.DataCase, async: true

  alias Builddoctor.Bench
  alias Builddoctor.Bench.Actor

  @sha String.duplicate("a", 40)
  @agent [actor: Actor.agent()]
  @me [actor: Actor.requester()]
  @start ~U[2026-11-23 19:44:02Z]

  defp audit, do: Bench.start_audit!("pikespeak/ci-patient", @sha, @me)

  defp job(name, from, to, conclusion \\ :success) do
    %{
      name: name,
      conclusion: conclusion,
      started_at: DateTime.add(@start, from),
      completed_at: DateTime.add(@start, to)
    }
  end

  defp run(audit, id, jobs, extra \\ %{}) do
    Map.merge(
      %{audit_id: audit.id, github_run_id: id, sha: @sha, started_at: @start, jobs: jobs},
      extra
    )
  end

  defp trial(audit, attempt \\ 1) do
    Bench.propose_trial!(
      %{
        audit_id: audit.id,
        attempt: attempt,
        goal: :wait,
        hypothesis: "Run the jobs side by side.",
        original: "old",
        patch: "jobs: {}\n",
        branch: "builddoctor/attempt-#{attempt}"
      },
      @agent
    )
  end

  test "only allowed repositories and real commits" do
    assert {:error, %Ash.Error.Invalid{}} = Bench.start_audit("evil/repo", @sha, @me)
    assert {:error, %Ash.Error.Invalid{}} = Bench.start_audit("pikespeak/ci-patient", "main", @me)
  end

  test "an audit measures only after approval" do
    audit = audit()
    assert audit.state == :examining
    assert {:error, _} = Bench.approve_audit(audit, @me)

    audit = audit |> Bench.request_approval!(@agent) |> Bench.approve_audit!(@me)
    assert audit.state == :measuring
    audit = Bench.finish_audit!(audit, @agent)
    assert Bench.get_audit!(audit.id).state == :done
    assert {:error, _} = Bench.stop_audit(audit, "too late", @me)
  end

  test "an audit can be stopped with a reason" do
    assert %{state: :stopped, stop_reason: "budget"} =
             Bench.stop_audit!(audit(), "budget", @agent)
  end

  test "durations are computed from the jobs" do
    audit = audit()
    jobs = [job("vet", 4, 14), job("test", 17, 37), job("build", 41, 63)]
    saved = Bench.record_run!(run(audit, 45_251_982_358, jobs), @agent)

    assert {saved.wall_seconds, saved.runner_seconds, saved.billed_minutes, saved.succeeded} ==
             {63, 52, 3, true}

    failed = Bench.record_run!(run(audit, 2, [job("vet", 0, 5, :failure)]), @agent)
    refute failed.succeeded
  end

  test "the same GitHub run is stored once and not changed" do
    audit = audit()
    first = Bench.record_run!(run(audit, 7, [job("vet", 0, 10)]), @agent)
    again = Bench.record_run!(run(audit, 7, [job("vet", 0, 99)]), @agent)
    assert again.id == first.id
    assert [%{wall_seconds: 10}] = Bench.list_runs!(audit.id)
  end

  test "malformed runs are refused" do
    audit = audit()

    for bad <- [
          run(audit, 1, []),
          run(audit, 1, [job("vet", -5, 3)]),
          run(audit, 1, [job("vet", 9, 3)]),
          run(audit, 1, [job("<script>", 0, 3)]),
          run(audit, 1, [job("vet", 0, 3, :hacked)]),
          run(audit, 0, [job("vet", 0, 3)]),
          run(audit, 1, [job("vet", 0, 3)], %{wall_seconds: 1}),
          run(audit, 1, [job("vet", 0, 3)], %{trial_id: Ash.UUID.generate()})
        ] do
      assert {:error, %Ash.Error.Invalid{}} = Bench.record_run(bad, @agent)
    end
  end

  test "the verdict uses measured runs only, without warm-ups and other trials" do
    audit = audit()
    mine = trial(audit)
    other = trial(audit, 2)

    record = fn id, wall, extra ->
      Bench.record_run!(run(audit, id, [job("vet", 0, wall)], extra), @agent)
    end

    for {wall, id} <- Enum.with_index([63, 70, 91], 1), do: record.(id, wall, %{})

    for {wall, id} <- Enum.with_index([25, 26, 30], 11),
        do: record.(id, wall, %{trial_id: mine.id})

    record.(21, 1, %{warmup: true})
    record.(22, 500, %{trial_id: other.id})

    done = Bench.evaluate_trial!(mine, @agent)
    assert done.verdict == :accepted
    assert done.numbers["gain_percent"] == 62.9
    assert Bench.evaluate_trial!(other, @agent).verdict == :inconclusive
  end

  test "a trial without the original cannot be shown before approval and is refused" do
    audit = audit()

    input = %{
      audit_id: audit.id,
      attempt: 1,
      goal: :wait,
      hypothesis: "Run the jobs side by side.",
      patch: "new\n",
      branch: "builddoctor/attempt-1"
    }

    assert {:error, %Ash.Error.Invalid{}} = Bench.propose_trial(input, @agent)
    trial = Bench.propose_trial!(Map.put(input, :original, "old\n"), @agent)
    assert trial.original == "old\n"
  end

  test "attempts and branches are limited" do
    audit = audit()
    assert trial(audit).patch == "jobs: {}\n"
    assert_raise Ash.Error.Invalid, fn -> trial(audit) end
    assert_raise Ash.Error.Invalid, fn -> trial(audit, 4) end
  end

  test "events are ordered, limited and broadcast" do
    audit = audit()
    BuilddoctorWeb.Endpoint.subscribe("audit:#{audit.id}")

    log =
      &Bench.log_event(
        Map.merge(%{audit_id: audit.id, kind: :github, status: :ok, message: "Read"}, &1),
        @agent
      )

    {:ok, _} = log.(%{reference: "https://github.com/pikespeak/ci-patient/actions/runs/1"})
    {:ok, _} = log.(%{kind: :verdict, message: "Done"})
    assert_receive %{topic: "audit:" <> _}
    assert ["Read", "Done"] = Enum.map(Bench.list_events!(audit.id), & &1.message)
    assert {:error, _} = log.(%{reference: "javascript:alert(1)"})
    assert {:error, _} = log.(%{message: String.duplicate("x", 301)})
  end

  test "visitors read, the agent works, the requester decides" do
    audit = audit()
    assert Bench.get_audit!(audit.id).id == audit.id
    assert {:error, %Ash.Error.Forbidden{}} = Bench.start_audit("pikespeak/ci-patient", @sha)
    assert {:error, %Ash.Error.Forbidden{}} = Bench.record_run(run(audit, 9, [job("vet", 0, 3)]))
    waiting = Bench.request_approval!(audit, @agent)
    assert {:error, %Ash.Error.Forbidden{}} = Bench.approve_audit(waiting, @agent)
    assert {:error, %Ash.Error.Forbidden{}} = Bench.stop_audit(waiting, "no")
  end

  test "model calls are priced here and stop at the budget" do
    audit = audit()
    call = %{audit_id: audit.id, model: "gpt-6.2-astra", input_tokens: 585, output_tokens: 116}
    assert Bench.record_ai_call!(call, @agent).micro_dollars == 9320
    assert Bench.budget_left!(@agent)
    assert {:error, _} = Bench.record_ai_call(%{call | model: "unknown"}, @agent)
    assert {:error, %Ash.Error.Forbidden{}} = Bench.record_ai_call(call)
    for _ <- 1..7, do: Bench.record_ai_call!(%{call | output_tokens: 100_000}, @agent)
    refute Bench.budget_left!(@agent)
  end
end
