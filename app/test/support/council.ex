defmodule Builddoctor.Council do
  @moduledoc "Lets the council pass a finding or a trial in a test."
  alias Builddoctor.Bench
  alias Builddoctor.Bench.Actor

  @agent [actor: Actor.agent()]

  def review!(subject, role, verdict \\ :pass)

  def review!(%Bench.Finding{id: id}, role, verdict),
    do: Bench.review_finding!(Map.put(input(role, verdict), :finding_id, id), @agent)

  def review!(%Bench.Trial{id: id}, role, verdict),
    do: Bench.review_trial!(Map.put(input(role, verdict), :trial_id, id), @agent)

  def pass!(subject) do
    for role <- [:qa, :safety], do: review!(subject, role)
    if is_struct(subject, Bench.Trial), do: review!(subject, :engineer)
    decide!(subject)
  end

  def decide!(%Bench.Finding{} = f), do: Bench.decide_finding!(f, @agent)
  def decide!(%Bench.Trial{} = t), do: Bench.decide_trial!(t, @agent)

  defp input(role, verdict),
    do: %{role: role, verdict: verdict, reason: "x", model: "gpt-6.2-sol", version: 1}
end
