defmodule BuilddoctorWeb.ErrorHTMLTest do
  use BuilddoctorWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  test "renders 404.html" do
    html = render_to_string(BuilddoctorWeb.ErrorHTML, "404", "html", [])
    assert html =~ "This page is not available." and html =~ "Back to the front page"
  end

  test "renders 500.html" do
    assert render_to_string(BuilddoctorWeb.ErrorHTML, "500", "html", []) =~
             "Something went wrong."

    assert render_to_string(BuilddoctorWeb.ErrorHTML, "400", "html", []) =~ "Bad Request"
  end
end
