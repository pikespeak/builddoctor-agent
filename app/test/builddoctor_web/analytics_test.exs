defmodule BuilddoctorWeb.AnalyticsTest do
  use BuilddoctorWeb.ConnCase, async: false

  alias BuilddoctorWeb.Analytics

  @key "phc_abcdefghijklmnopqrstuvwxyz"
  @host "https://r.example.org"

  defp configure(key, host) do
    Application.put_env(:builddoctor, :posthog_key, key)
    Application.put_env(:builddoctor, :posthog_host, host)

    on_exit(fn ->
      for name <- [:posthog_key, :posthog_host], do: Application.delete_env(:builddoctor, name)
    end)
  end

  defp policy(conn), do: conn |> get_resp_header("content-security-policy") |> hd()
  defp box?(conn), do: conn |> html_response(200) |> String.contains?(~s(id="analytics-consent"))

  test "without a key nothing is offered", %{conn: conn} do
    assert Analytics.settings() == nil
    conn = get(conn, ~p"/")
    refute box?(conn)
    refute html_response(conn, 200) =~ "Analytics choice"
    assert policy(conn) =~ "connect-src 'self';"
  end

  test "odd settings count as none" do
    for {key, host} <- [
          {"", @host},
          {"phx_" <> String.duplicate("a", 30), @host},
          {@key <> "\"", @host},
          {@key <> "\n", @host},
          {@key, nil},
          {@key, "http://r.example.org"},
          {@key, "https://r.example.org/path"},
          {@key, "https://r.example.org; script-src *"},
          {@key, "https://localhost"}
        ] do
      configure(key, host)
      assert Analytics.settings() == nil
    end
  end

  test "visitors are asked, hidden until the script shows it", %{conn: conn} do
    configure(@key, @host)

    for path <- [
          ~p"/",
          ~p"/archive",
          ~p"/how-it-works",
          ~p"/subscribe",
          ~p"/imprint",
          ~p"/privacy"
        ] do
      conn = get(conn, path)
      assert box?(conn)
      assert policy(conn) =~ "connect-src 'self' #{@host};"
      assert policy(conn) =~ "script-src 'self';"
      html = html_response(conn, 200)
      assert [_] = Regex.scan(~r/<section[^>]* id="analytics-consent"[^>]* hidden/, html)
      assert html =~ "Analytics choice"
      assert html =~ ~s(data-site="localhost") and html =~ ~s(data-key="#{@key}")
      # Nothing of it is loaded by the page itself.
      refute html =~ ~r/<script[^>]*analytics/
    end
  end

  test "the Requester and the sign-in page are not measured", %{conn: conn} do
    configure(@key, @host)
    refute conn |> get(~p"/requester") |> box?()

    signed_in = init_test_session(conn, %{"requester_since" => System.system_time(:second)})
    asked = get(signed_in, ~p"/")
    refute box?(asked)
    assert policy(asked) =~ "connect-src 'self';"
  end

  test "the privacy notice describes it", %{conn: conn} do
    html = conn |> get(~p"/privacy") |> html_response(200)
    assert html =~ ~s(id="analytics") and html =~ "only with your consent"
    refute html =~ "advertising by others and no analytics"
  end
end
