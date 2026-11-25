defmodule BuilddoctorWeb.ErrorHTML do
  @moduledoc "Error pages that say what happened and what comes next."
  use BuilddoctorWeb, :html

  def render("404.html", _),
    do:
      page(%{
        title: "This page is not available.",
        text: "The address is wrong, or the project was removed."
      })

  def render("500.html", _),
    do:
      page(%{
        title: "Something went wrong.",
        text: "This is our error. Please try again."
      })

  def render(template, _),
    do:
      page(%{
        title: Phoenix.Controller.status_message_from_template(template),
        text: "We could not process this request."
      })

  defp page(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{@title}</title>
        <link rel="stylesheet" href={~p"/assets/css/app.css"} />
      </head>
      <body class="bg-paper text-bark"><Layouts.nothing title={@title} text={@text} /></body>
    </html>
    """
  end
end
