defmodule Builddoctor.AnnounceTest do
  use Builddoctor.DataCase, async: false
  use Oban.Testing, repo: Builddoctor.Repo

  alias Builddoctor.{Announce, Bench}
  alias Builddoctor.Bench.Actor

  # Plays the Resend connector of the Sprite and hands every request to the test.
  defmodule Gateway do
    @behaviour Plug
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, %{test: test, status: status}) do
      {:ok, body, conn} = read_body(conn)
      key = conn |> get_req_header("idempotency-key") |> List.first()
      send(test, {:sent, conn.request_path, key, Jason.decode!(body)})
      send_resp(conn, status, ~s({"id":"x"}))
    end
  end

  @args %{
    "repository" => "a/b",
    "started_by" => "visitor",
    "uuid" => "6f1c3c3e-0000-4000-8000-000000000001",
    "at" => "2026-11-26T08:00:00Z"
  }

  setup do
    on_exit(fn ->
      for name <- [:resend_gateway, :notice_to, :notice_from],
          do: Application.delete_env(:builddoctor, name)
    end)
  end

  defp gateway(status) do
    {:ok, server} =
      start_supervised(
        {Bandit, plug: {Gateway, %{test: self(), status: status}}, port: 0, ip: :loopback},
        id: status
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(server)

    Application.put_env(
      :builddoctor,
      :resend_gateway,
      "http://127.0.0.1:#{port}/v1/gateway/resend/c1"
    )

    Application.put_env(:builddoctor, :notice_to, "me@example.org")
  end

  test "every start is announced once, with who started it" do
    planted = Bench.plant_audit!("a/b", 1)
    Bench.finish_examination!(planted, %{}, actor: Actor.agent())
    Bench.examine_again!(planted.id, actor: Actor.requester())
    own = Bench.examine_own!(actor: Actor.requester())
    Bench.stop_audit!(own, "Stopped for the test.", actor: Actor.agent())

    Bench.start_audit!("pikespeak/ci-patient", String.duplicate("a", 40),
      actor: Actor.requester()
    )

    jobs = all_enqueued(worker: Announce)

    assert jobs |> Enum.map(&{&1.args["repository"], &1.args["started_by"]}) |> Enum.sort() == [
             {"a/b", "requester"},
             {"a/b", "visitor"},
             {"pikespeak/ci-patient", "requester"},
             {"pikespeak/ci-patient", "requester"}
           ]

    assert jobs |> Enum.map(& &1.args["uuid"]) |> Enum.uniq() |> length() == 4
    assert Announce.__opts__()[:max_attempts] == 5
  end

  test "a failed start is not announced" do
    Bench.plant_audit!("a/b", 1)
    assert {:error, _} = Bench.plant_audit("c/d", 1)
    refute_enqueued(worker: Announce, args: %{"repository" => "c/d"})
  end

  test "the mail names the project and nothing about the visitor" do
    gateway(200)
    assert :ok = perform_job(Announce, @args)
    assert_received {:sent, "/v1/gateway/resend/c1/emails", key, body}
    assert key == "start-" <> @args["uuid"]

    assert body == %{
             "from" => "BuildDoctor <onboarding@resend.dev>",
             "to" => ["me@example.org"],
             "subject" => "BuildDoctor: a/b (visitor)",
             "text" =>
               "An examination started on builddoctor.app.\n\nProject: a/b\nStarted by: visitor\nTime: 2026-11-26T08:00:00Z\n\nhttps://builddoctor.app/archive\n"
           }

    # An empty file gives an empty sender; the default stays.
    Application.put_env(:builddoctor, :notice_from, "")
    assert :ok = perform_job(Announce, %{@args | "uuid" => "u2"})
    assert_received {:sent, _, "start-u2", %{"from" => "BuildDoctor <onboarding@resend.dev>"}}
    Application.put_env(:builddoctor, :notice_from, "BuildDoctor <notice@builddoctor.app>")
    assert :ok = perform_job(Announce, %{@args | "uuid" => "u3"})
    assert_received {:sent, _, "start-u3", %{"from" => "BuildDoctor <notice@builddoctor.app>"}}
  end

  test "only a gateway of the Sprite and a real address get a mail" do
    gateway(200)
    Application.put_env(:builddoctor, :resend_gateway, "https://evil.example/emails")
    assert :ok = perform_job(Announce, @args)
    Application.delete_env(:builddoctor, :resend_gateway)
    assert :ok = perform_job(Announce, @args)
    refute_received {:sent, _, _, _}
    assert Announce.gateway?("https://evil.example") == false
    assert Announce.gateway?("http://127.0.0.1:1/v1/gateway/resend/c1?to=x") == false

    gateway(201)
    Application.put_env(:builddoctor, :notice_to, "not an address")
    assert :ok = perform_job(Announce, @args)
    refute_received {:sent, _, _, _}
  end

  test "Resend is reached only with a checked certificate" do
    options = Announce.ssl_options(~c"https://api.sprites.dev/v1/gateway/resend/c1/emails")
    assert options[:verify] == :verify_peer and options[:cacerts] != []
    assert Announce.ssl_options(~c"http://127.0.0.1:1/") == []
  end

  test "a refusal or an unreachable gateway is retried" do
    gateway(500)
    assert {:error, "Resend answered 500"} = perform_job(Announce, @args)
    assert_received {:sent, _, _, _}
    Application.put_env(:builddoctor, :resend_gateway, "http://127.0.0.1:1/v1/gateway/resend/c1")
    assert {:error, _} = perform_job(Announce, @args)
  end
end
