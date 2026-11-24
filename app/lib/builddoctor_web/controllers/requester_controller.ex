defmodule BuilddoctorWeb.RequesterController do
  @moduledoc "Lets the Requester unlock approve and stop with a key of at least 32 bytes."
  use BuilddoctorWeb, :controller

  def new(conn, params), do: page(conn, 200, "", params)

  def create(conn, %{"key" => given} = params) when is_binary(given) do
    key = Application.get_env(:builddoctor, :requester_key)

    if is_binary(key) and byte_size(key) >= 32 and Plug.Crypto.secure_compare(given, key) do
      conn
      |> configure_session(renew: true)
      |> put_session("requester_since", System.system_time(:second))
      |> redirect(to: back(audit(params)))
    else
      page(conn, 403, "That key is not right.", params)
    end
  end

  def create(conn, params), do: page(conn, 403, "That key is not right.", params)

  def leave(conn, _params) do
    conn |> configure_session(drop: true) |> redirect(to: ~p"/")
  end

  # Only an audit id is taken, never a path, so that nobody is sent elsewhere.
  defp audit(%{"audit" => id}) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> id
      :error -> nil
    end
  end

  defp audit(_), do: nil

  defp back(nil), do: ~p"/"
  defp back(id), do: ~p"/a/#{id}"

  defp page(conn, status, message, params) do
    conn
    |> put_status(status)
    |> put_view(BuilddoctorWeb.RequesterHTML)
    |> render(:new, message: message, audit: audit(params))
  end
end
