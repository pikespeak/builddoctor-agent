defmodule BuilddoctorWeb.HealthTest do
  use BuilddoctorWeb.ConnCase, async: false

  alias BuilddoctorWeb.Health

  defp silent_for(seconds),
    do:
      :atomics.put(
        :persistent_term.get(Health),
        1,
        System.monotonic_time(:second) - seconds
      )

  defp agent(conn) do
    %{conn | host: "localhost"}
    |> put_req_header("authorization", "Bearer test-agent-token-0123456789abcdef")
    |> put_req_header("accept", "application/vnd.api+json")
  end

  test "an outside check sees whether the agent works" do
    silent_for(120)
    assert Health.agent_silent_for() >= 120
    silent = get(build_conn(), "/health")
    assert {silent.status, silent.resp_body} == {503, "agent silent"}
    assert get_resp_header(silent, "set-cookie") == []
    assert get_resp_header(silent, "cache-control") == ["no-store"]

    # Any request of the agent counts as a sign of life.
    assert build_conn() |> agent() |> get("/api/json/audits/open") |> response(200)
    assert Health.agent_silent_for() <= 1
    alive = get(build_conn(), "/health")
    assert {alive.status, alive.resp_body} == {200, "ok"}

    # A wrong secret is no sign of life.
    silent_for(120)

    assert build_conn()
           |> Map.put(:host, "localhost")
           |> get("/api/json/audits/open")
           |> response(401)

    assert get(build_conn(), "/health").status == 503
  end

  test "before the first request of the agent, it counts as silent" do
    :atomics.put(:persistent_term.get(Health), 1, 0)
    assert Health.agent_silent_for() == nil
    assert get(build_conn(), "/health").resp_body == "agent silent"
  end
end
