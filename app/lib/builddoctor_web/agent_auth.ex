defmodule BuilddoctorWeb.AgentAuth do
  @moduledoc """
  Lets only the agent use the API, with a shared secret of at least 32 bytes. The agent runs in the
  same Sprite, so a request that came through the proxy is refused before the secret is compared.
  """
  import Plug.Conn

  alias Builddoctor.Bench.Actor

  def init(opts), do: opts

  def call(conn, _opts) do
    with true <- conn.host in ["localhost", "127.0.0.1"],
         [] <- get_req_header(conn, "x-forwarded-for"),
         [] <- get_req_header(conn, "x-forwarded-proto"),
         secret when is_binary(secret) and byte_size(secret) >= 32 <-
           Application.get_env(:builddoctor, :agent_token),
         ["Bearer " <> given] <- get_req_header(conn, "authorization"),
         true <- Plug.Crypto.secure_compare(given, secret) do
      BuilddoctorWeb.Health.agent_seen()
      Ash.PlugHelpers.set_actor(conn, Actor.agent())
    else
      _ -> conn |> send_resp(401, "") |> halt()
    end
  end
end
