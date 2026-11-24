defmodule BuilddoctorWeb.ForestController do
  @moduledoc "The finished picture as a file, for a README or a pull request."
  use BuilddoctorWeb, :controller

  alias Builddoctor.Bench
  alias BuilddoctorWeb.AuditView

  def patch(conn, %{"id" => id}) do
    with {:ok, audit} <- Bench.get_audit(id),
         %{trial: %{original: original} = trial} when is_binary(original) <- AuditView.load(audit) do
      conn
      |> put_resp_content_type("text/plain")
      |> put_resp_header("content-disposition", ~s(attachment; filename="change.patch"))
      |> send_resp(200, Builddoctor.Diff.patch(original, trial.patch, audit.workflow_path))
    else
      _ -> send_resp(conn, 404, "")
    end
  end

  def show(conn, %{"id" => id}) do
    case Bench.get_audit(id) do
      {:ok, audit} ->
        conn
        |> put_resp_content_type("image/svg+xml")
        |> put_resp_header(
          "content-security-policy",
          "default-src 'none'; style-src 'unsafe-inline'"
        )
        |> send_resp(
          200,
          Builddoctor.Forest.image(AuditView.load(audit) |> AuditView.plan(:after))
        )

      _ ->
        send_resp(conn, 404, "")
    end
  end
end
