defmodule BuilddoctorWeb.ErrorHTML do
  @moduledoc "Error pages that say what happened and what comes next."
  use BuilddoctorWeb, :html

  def render("404.html", _),
    do:
      page(%{
        title: "No tree grows here.",
        text: "The address is wrong, or the project was removed."
      })

  def render("500.html", _),
    do:
      page(%{
        title: "The doctor tripped.",
        text: "This is our error. Stored results are not affected. Please try again."
      })

  def render(template, _),
    do:
      page(%{
        title: Phoenix.Controller.status_message_from_template(template),
        text: "This request was not possible."
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
