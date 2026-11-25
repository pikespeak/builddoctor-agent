defmodule BuilddoctorWeb.Analytics do
  @moduledoc """
  Offers PostHog to Visitors, who must accept it in the browser first (assets/js/consent.js). Only
  a site with a key offers it; the Requester and the sign-in page are never measured.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(%{path_info: ["requester" | _]} = conn, _), do: conn

  def call(conn, _) do
    settings = settings()

    if settings == nil or BuilddoctorWeb.Requester.signed_in?(get_session(conn)),
      do: conn,
      else: conn |> assign(:analytics, settings) |> allow(settings.host)
  end

  @doc "The public key and the address for events, or nil if either is missing or odd."
  def settings do
    with key when is_binary(key) <- Application.get_env(:builddoctor, :posthog_key),
         host when is_binary(host) <- Application.get_env(:builddoctor, :posthog_host),
         true <- key =~ ~r/\Aphc_[A-Za-z0-9]{20,80}\z/,
         true <- host =~ ~r/\Ahttps:\/\/[a-z0-9-]+(\.[a-z0-9-]+)+\z/ do
      %{key: key, host: host, site: BuilddoctorWeb.Endpoint.host()}
    else
      _ -> nil
    end
  end

  # The browser may talk to this one address besides our own.
  defp allow(conn, host) do
    update_resp_header(
      conn,
      "content-security-policy",
      "",
      &String.replace(&1, "connect-src 'self'", "connect-src 'self' " <> host)
    )
  end
end
