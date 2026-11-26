defmodule BuilddoctorWeb.AgentApiTest do
  use BuilddoctorWeb.ConnCase, async: true

  alias Builddoctor.Bench
  alias Builddoctor.Bench.Actor

  @sha String.duplicate("b", 40)

  defp agent(conn) do
    %{conn | host: "localhost"}
    |> put_req_header("authorization", "Bearer test-agent-token-0123456789abcdef")
    |> put_req_header("content-type", "application/vnd.api+json")
    |> put_req_header("accept", "application/vnd.api+json")
  end

  defp body(type, attributes, id \\ nil) do
    data = %{type: type, attributes: attributes}
    Jason.encode!(%{data: if(id, do: Map.put(data, :id, id), else: data)})
  end

  test "refuses a missing or wrong secret", %{conn: conn} do
    assert conn |> get("/api/json/audits/open") |> response(401)

    assert conn
           |> put_req_header("authorization", "Bearer wrong")
           |> get("/api/json/audits/open")
           |> response(401)
  end

  test "refuses the right secret from outside the Sprite", %{conn: conn} do
    assert conn |> agent() |> get("/api/json/audits/open") |> response(200)

    for name <- ["x-forwarded-for", "x-forwarded-proto"] do
      assert conn
             |> agent()
             |> put_req_header(name, "https")
             |> get("/api/json/audits/open")
             |> response(401)
    end

    assert %{agent(conn) | host: "builddoctor.example"}
           |> get("/api/json/audits/open")
           |> response(401)
  end

  test "refuses a body that is too large", %{conn: conn} do
    assert_error_sent 413, fn ->
      conn |> agent() |> post("/api/json/events", String.duplicate("x", 500_001))
    end
  end

  test "carries an audit from examination to a verdict", %{conn: conn} do
    audit = Bench.start_audit!("pikespeak/ci-patient", @sha, actor: Actor.requester())

    # The agent compares the stored commit and file with what it reads after a restart.
    assert [%{"id" => id, "attributes" => %{"base_sha" => @sha, "workflow_path" => path}}] =
             conn
             |> agent()
             |> get("/api/json/audits/open")
             |> json_response(200)
             |> Map.get("data")

    assert id == audit.id and path =~ ".github/workflows/"
    assert conn |> agent() |> get("/api/json/ai_calls/budget_left") |> json_response(200) == true

    trial =
      conn
      |> agent()
      |> post(
        "/api/json/trials",
        body("trial", %{
          audit_id: id,
          attempt: 1,
          goal: "wait",
          hypothesis: "Run the jobs side by side.",
          original: "old",
          patch: "-    needs: vet",
          branch: "builddoctor/x-trial"
        })
      )
      |> json_response(201)

    conn
    |> agent()
    |> patch("/api/json/audits/#{id}/request_approval", body("audit", %{}, id))
    |> json_response(200)

    Bench.get_audit!(id) |> Bench.approve_audit!(actor: Actor.requester())

    for {wall, trial_id, n} <- [
          {63, nil, 1},
          {70, nil, 2},
          {91, nil, 3},
          {25, 1, 4},
          {26, 1, 5},
          {30, 1, 6}
        ] do
      conn
      |> agent()
      |> post(
        "/api/json/runs",
        body("run", %{
          audit_id: id,
          trial_id: trial_id && trial["data"]["id"],
          github_run_id: 900 + n,
          sha: @sha,
          warmup: false,
          started_at: "2026-11-23T19:44:00Z",
          jobs: [
            %{
              name: "vet",
              conclusion: "success",
              started_at: "2026-11-23T19:44:00Z",
              completed_at: DateTime.add(~U[2026-11-23 19:44:00Z], wall)
            }
          ]
        })
      )
      |> json_response(201)
    end

    runs = conn |> agent() |> get("/api/json/runs/for_audit/#{id}") |> json_response(200)
    assert length(runs["data"]) == 6

    done =
      conn
      |> agent()
      |> patch(
        "/api/json/trials/#{trial["data"]["id"]}/evaluate",
        body("trial", %{}, trial["data"]["id"])
      )
      |> json_response(200)

    assert done["data"]["attributes"]["verdict"] == "accepted"
  end
end
