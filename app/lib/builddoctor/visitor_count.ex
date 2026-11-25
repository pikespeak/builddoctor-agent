defmodule Builddoctor.VisitorCount do
  @moduledoc """
  How often a Visitor started something today. Only in memory, by a keyed hash and never by an
  address; yesterday is forgotten with the first count of a new day.
  """
  use Agent

  def start_link(_), do: Agent.start_link(fn -> {nil, %{}} end, name: __MODULE__)

  @doc "Counts one start; false if the limit of today is reached."
  def take(key, limit, today \\ Date.utc_today()) do
    Agent.get_and_update(__MODULE__, fn {day, counts} ->
      counts = if day == today, do: counts, else: %{}
      n = Map.get(counts, key, 0)

      if n < limit,
        do: {true, {today, Map.put(counts, key, n + 1)}},
        else: {false, {today, counts}}
    end)
  end
end
