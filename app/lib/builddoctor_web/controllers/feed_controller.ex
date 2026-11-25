defmodule BuilddoctorWeb.FeedController do
  @moduledoc "The editions of one project as an Atom feed. Nobody has to leave an address."
  use BuilddoctorWeb, :controller

  alias Builddoctor.Bench
  alias BuilddoctorWeb.AuditView

  def show(conn, %{"owner" => owner, "name" => name}) do
    case Bench.audits_of_project(owner <> "/" <> name) do
      {:ok, [newest | _] = audits} ->
        conn
        |> put_resp_content_type("application/atom+xml")
        |> put_resp_header("x-robots-tag", "noindex, nofollow")
        |> put_resp_header("cache-control", "no-store")
        |> send_resp(200, feed(newest, audits))

      _ ->
        send_resp(conn, 404, "")
    end
  end

  defp feed(newest, audits) do
    own = url(~p"/feed/#{owner(newest)}/#{name(newest)}")

    IO.iodata_to_binary([
      ~s(<?xml version="1.0" encoding="utf-8"?>\n<feed xmlns="http://www.w3.org/2005/Atom">),
      tag("title", "Build! on #{newest.repository}"),
      tag("id", own),
      ~s(<link rel="self" href="),
      escape(own),
      ~s("/>),
      tag(
        "updated",
        audits |> Enum.map(& &1.updated_at) |> Enum.max(DateTime) |> DateTime.to_iso8601()
      ),
      "<author>",
      tag("name", "BuildDoctor"),
      "</author>",
      Enum.map(audits, &entry/1),
      "</feed>"
    ])
  end

  defp entry(audit) do
    page = url(~p"/a/#{audit.id}")

    [
      "<entry>",
      tag("title", grade(audit) <> AuditView.headline(audit)),
      tag("id", page),
      ~s(<link href="),
      escape(page),
      ~s("/>),
      tag("updated", DateTime.to_iso8601(audit.updated_at)),
      tag("summary", AuditView.summary(audit)),
      "</entry>"
    ]
  end

  defp grade(%{grade: %{letter: letter}}), do: "Grade #{letter}: "
  defp grade(_), do: ""

  defp owner(%{repository: r}), do: r |> String.split("/") |> hd()
  defp name(%{repository: r}), do: r |> String.split("/") |> List.last()

  defp tag(tag, text), do: ["<", tag, ">", escape(text), "</", tag, ">"]

  # XML forbids control characters, also as entities.
  defp escape(text) do
    text
    |> String.replace(~r/[\x00-\x08\x0B\x0C\x0E-\x1F\x{FFFE}\x{FFFF}]/u, " ")
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end
end
