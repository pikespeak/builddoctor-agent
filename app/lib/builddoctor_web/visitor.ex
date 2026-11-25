defmodule BuilddoctorWeb.Visitor do
  @moduledoc """
  Gives a Visitor a keyed hash of the address that the proxy of the Sprite reports, for one day.
  Other address headers can be forged and are not read.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _) do
    case hash(get_req_header(conn, "sprite-client-ip"), conn.secret_key_base) do
      nil ->
        conn

      hash ->
        if get_session(conn, "visitor") == hash,
          do: conn,
          else: put_session(conn, "visitor", hash)
    end
  end

  def hash(header, secret, today \\ Date.utc_today())

  def hash([text], secret, today) when is_binary(secret) do
    case text |> String.to_charlist() |> :inet.parse_address() do
      {:ok, address} ->
        :hmac
        |> :crypto.mac(:sha256, secret, "visitor #{today} #{inspect(network(address))}")
        |> binary_part(0, 12)
        |> Base.url_encode64()

      _ ->
        nil
    end
  end

  def hash(_, _, _), do: nil

  # One household has many IPv6 addresses.
  defp network({a, b, c, d, _, _, _, _}), do: {a, b, c, d}
  defp network(address), do: address
end
