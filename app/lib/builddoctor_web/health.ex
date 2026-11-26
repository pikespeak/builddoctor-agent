defmodule BuilddoctorWeb.Health do
  @moduledoc """
  Answers an outside check whether the page, the database and the agent work (peer review B6,
  2026-11-26). The agent asks for work every five seconds; a minute of silence means it stopped.
  Nothing about projects or visitors is shown.
  """
  import Plug.Conn

  @silence 60

  @doc "Called on every request of the agent."
  def agent_seen, do: :persistent_term.get(__MODULE__) |> :atomics.put(1, now())

  @doc "Seconds since the agent was last seen, or nil before its first request."
  def agent_silent_for do
    case :atomics.get(:persistent_term.get(__MODULE__), 1) do
      0 -> nil
      seen -> now() - seen
    end
  end

  @doc "Run once at the start of the application."
  def setup, do: :persistent_term.put(__MODULE__, :atomics.new(1, signed: true))

  def init(opts), do: opts

  def call(conn, _opts) do
    {status, text} =
      cond do
        not database?() -> {503, "database not answering"}
        silent?(agent_silent_for()) -> {503, "agent silent"}
        true -> {200, "ok"}
      end

    conn
    |> put_resp_content_type("text/plain")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(status, text)
    |> halt()
  end

  defp silent?(nil), do: true
  defp silent?(seconds), do: seconds > @silence

  defp database? do
    match?({:ok, _}, Builddoctor.Repo.query("select 1", [], timeout: 2_000))
  rescue
    _ -> false
  end

  defp now, do: System.monotonic_time(:second)
end
