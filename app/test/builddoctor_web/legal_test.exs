defmodule BuilddoctorWeb.LegalTest do
  use BuilddoctorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias BuilddoctorWeb.Imprint

  @who %{
    "name" => "Jane <b>Doe</b>",
    "street" => "Main Street 1",
    "city" => "12345 Town",
    "country" => "Germany",
    "phone" => "+49 1",
    "email" => "jane@example.org",
    "notes" => ["A note."]
  }

  defp file(content) do
    path = Path.join(System.tmp_dir!(), "imprint-#{System.unique_integer([:positive])}.json")
    File.write!(path, if(is_binary(content), do: content, else: Jason.encode!(content)))
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp use_file(path) do
    Application.put_env(:builddoctor, :imprint_file, path)
    on_exit(fn -> Application.delete_env(:builddoctor, :imprint_file) end)
  end

  test "the details come from the file and are escaped", %{conn: conn} do
    use_file(file(@who))

    for path <- [~p"/imprint", ~p"/privacy"] do
      html = conn |> get(path) |> html_response(200)

      assert html =~ "Jane &lt;b&gt;Doe" and html =~ "12345 Town" and
               html =~ "mailto:jane@example.org"

      assert html =~ "Phone: +49 1"
    end

    assert conn |> get(~p"/imprint") |> html_response(200) =~ "A note."
    audit = Builddoctor.Bench.plant_audit!("a/b", 1)
    {:ok, view, _} = live(conn, ~p"/a/#{audit.id}")
    assert has_element?(view, "#maintainer a[href='mailto:jane@example.org']")
  end

  test "without a file the page says so", %{conn: conn} do
    for path <- [~p"/imprint", ~p"/privacy"],
        do:
          assert(
            conn |> get(path) |> html_response(200) =~ "has not provided contact details yet"
          )
  end

  test "odd content counts as none" do
    assert %{phone: nil, notes: []} = Imprint.load(file(Map.drop(@who, ["phone", "notes"])))

    for bad <- [
          "",
          "[]",
          "{",
          Map.delete(@who, "name"),
          %{@who | "street" => " "},
          %{@who | "city" => 5},
          %{@who | "email" => "jane"},
          %{@who | "email" => "a@b.de\" onclick=\"x"},
          %{@who | "phone" => 5},
          %{@who | "notes" => "x"},
          %{@who | "notes" => [1]},
          %{@who | "name" => String.duplicate("x", 301)}
        ] do
      assert Imprint.load(file(bad)) == nil
    end

    assert Imprint.load("/nothing/here") == nil
    assert Imprint.load(nil) == nil
  end

  test "both are linked on every page", %{conn: conn} do
    for path <- [~p"/", ~p"/how-it-works", ~p"/a/nonsense"] do
      {:ok, view, _} = live(conn, path)
      for to <- ["/imprint", "/privacy"], do: assert(has_element?(view, "a[href='#{to}']"))
      assert has_element?(view, "a[href='https://fly.io/hacksgiving/']", "Hacksgiving 2026")
    end

    for path <- ["/requester", "/imprint", "/privacy"],
        do: assert(conn |> get(path) |> html_response(200) =~ ~s(href="/privacy"))

    assert conn |> get("/nix") |> html_response(404) =~ ~s(href="/imprint")
  end
end
