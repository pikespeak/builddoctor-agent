defmodule BuilddoctorWeb.RequesterTest do
  use BuilddoctorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Builddoctor.Bench
  alias BuilddoctorWeb.Requester

  test "a sign-in lasts twelve hours" do
    session = %{"requester_since" => 1_000_000}
    assert Requester.signed_in?(session, 1_000_000)
    assert Requester.signed_in?(session, 1_000_000 + 43_200)
    refute Requester.signed_in?(session, 1_000_000 + 43_201)
    refute Requester.signed_in?(session, 999_999)

    for bad <- [%{}, %{"requester" => true}, %{"requester_since" => "1"}],
        do: refute(Requester.signed_in?(bad))
  end

  test "an open page loses the rights when the sign-in ends", %{conn: conn} do
    me = [actor: Builddoctor.Bench.Actor.requester()]
    audit = Bench.start_audit!("pikespeak/ci-patient", String.duplicate("a", 40), me)

    conn =
      Plug.Test.init_test_session(conn, %{
        "requester_since" => System.system_time(:second) - 43_199
      })

    {:ok, view, _} = live(conn, ~p"/a/#{audit.id}")
    {:ok, home, _} = live(conn, ~p"/")
    assert has_element?(view, "button", "Stop") and has_element?(home, "#own-start")
    Process.sleep(2100)
    render_click(view, "stop")
    assert Bench.get_audit!(audit.id).state == :examining
    assert render_click(home, "own") =~ "not possible right now"
    send(view.pid, :refresh)
    refute has_element?(view, "button", "Stop")
  end

  test "every page forbids content from elsewhere", %{conn: conn} do
    for path <- [~p"/", ~p"/how-it-works", ~p"/requester", ~p"/a/nonsense"] do
      conn = get(conn, path)
      [policy] = get_resp_header(conn, "content-security-policy")
      assert policy =~ "default-src 'none'" and policy =~ "script-src 'self';"
      assert policy =~ "frame-ancestors 'none'"
      assert [_] = get_resp_header(conn, "permissions-policy")
      refute html_response(conn, 200) =~ ~r/<script(?![^>]*src=)/
      refute html_response(conn, 200) =~ ~r/\son[a-z]+=/
    end
  end

  test "the page explains the limits", %{conn: conn} do
    for i <- 1..3, do: Bench.plant_audit!("a/b#{i}", i)
    {:ok, view, _} = live(conn, ~p"/")
    html = view |> form("#plant", %{project: "c/d"}) |> render_submit()
    assert html =~ "Please try again in a minute" and html =~ ~s(value="c/d")
  end
end
