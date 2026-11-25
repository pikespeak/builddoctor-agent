defmodule BuilddoctorWeb.LegalController do
  @moduledoc "Imprint and privacy notice, without a script of anybody else unless analytics is accepted."
  use BuilddoctorWeb, :controller

  def imprint(conn, _), do: page(conn, :imprint, "Imprint")
  def privacy(conn, _), do: page(conn, :privacy, "Privacy")

  defp page(conn, template, title) do
    conn
    |> put_view(BuilddoctorWeb.LegalHTML)
    |> render(template, page_title: title, who: BuilddoctorWeb.Imprint.load())
  end
end
