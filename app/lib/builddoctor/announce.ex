defmodule Builddoctor.Announce do
  @moduledoc """
  Emails the operator when an examination starts (owner, 2026-11-26), through the Resend connector
  of the Sprite: the gateway holds the Resend key, so the Sprite never sees it. Only the project
  name, who started it and the time are sent. Without a gateway or a recipient nothing is sent.
  """
  use Oban.Worker, queue: :default, max_attempts: 5

  @recipient ~r/\A[^@\s<>",]+@[^@\s<>",]+\.[a-z]{2,}\z/i

  @doc "The body Resend's POST /emails takes."
  def body(from, to, %{"repository" => repository, "started_by" => started_by} = args) do
    %{
      from: from,
      to: [to],
      subject: "BuildDoctor: #{repository} (#{started_by})",
      text:
        "An examination started on builddoctor.app.\n\nProject: #{repository}\nStarted by: #{started_by}\nTime: #{args["at"]}\n\nhttps://builddoctor.app/archive\n"
    }
  end

  @doc "Whether the configured address is the Resend gateway of the Sprite, so the mail goes nowhere else."
  def gateway?(url) when is_binary(url),
    do:
      String.starts_with?(url, Application.fetch_env!(:builddoctor, :notice_gateway_prefix)) and
        not String.contains?(url, ["?", "#", " "])

  def gateway?(_), do: false

  @impl true
  def perform(%Oban.Job{args: args}) do
    gateway = Application.get_env(:builddoctor, :resend_gateway)
    to = Application.get_env(:builddoctor, :notice_to)

    if gateway?(gateway) and is_binary(to) and to =~ @recipient,
      do: send_mail(gateway, to, args),
      else: :ok
  end

  defp send_mail(gateway, to, args) do
    from =
      case Application.get_env(:builddoctor, :notice_from) do
        from when is_binary(from) and from != "" -> from
        _ -> "BuildDoctor <onboarding@resend.dev>"
      end

    url = String.to_charlist(String.trim_trailing(gateway, "/") <> "/emails")
    # The same key on a retry: within 24 hours and with the same content, Resend sends it once,
    # even if its first answer got lost.
    headers = [{~c"idempotency-key", String.to_charlist("start-" <> to_string(args["uuid"]))}]
    request = {url, headers, ~c"application/json", Jason.encode!(body(from, to, args))}

    case :httpc.request(
           :post,
           request,
           [timeout: 10_000, autoredirect: false, ssl: ssl_options(url)],
           []
         ) do
      {:ok, {{_, status, _}, _, _}} when status in 200..299 -> :ok
      {:ok, {{_, status, _}, _, _}} -> {:error, "Resend answered #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "TLS with a checked certificate and host name for https; nothing for local http in tests."
  def ssl_options(~c"https" ++ _),
    do: [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

  def ssl_options(_), do: []
end
