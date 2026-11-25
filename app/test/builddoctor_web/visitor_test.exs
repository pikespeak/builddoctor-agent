defmodule BuilddoctorWeb.VisitorTest do
  use BuilddoctorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Builddoctor.{Bench, VisitorCount}
  alias Builddoctor.Bench.Actor
  alias BuilddoctorWeb.Visitor

  @agent [actor: Actor.agent()]
  @day ~D[2026-11-24]

  defp from(conn, ip), do: put_req_header(conn, "sprite-client-ip", ip)
  defp hash(text, day \\ @day), do: Visitor.hash([text], "secret", day)

  test "an address becomes a hash of the day" do
    assert hash("203.0.113.7") == hash("203.0.113.7")
    assert hash("203.0.113.7") != hash("203.0.113.8")
    assert hash("203.0.113.7") != hash("203.0.113.7", ~D[2026-11-25])
    assert hash("203.0.113.7") != Visitor.hash(["203.0.113.7"], "other", @day)
    assert hash("2001:db8:1:2::1") == hash("2001:db8:1:2:ffff::9")
    assert hash("2001:db8:1:2::1") != hash("2001:db8:1:3::1")
    refute hash("203.0.113.7") =~ "203"

    for bad <- [[], ["x"], ["203.0.113.7, 1.2.3.4"], ["1.2.3.4", "5.6.7.8"]],
        do: assert(Visitor.hash(bad, "secret") == nil)

    assert Visitor.hash(["1.2.3.4"], nil) == nil
  end

  test "counts per key and day" do
    key = "k#{System.unique_integer()}"
    assert VisitorCount.take(key, 2, @day) and VisitorCount.take(key, 2, @day)
    refute VisitorCount.take(key, 2, @day)
    assert VisitorCount.take(key <> "x", 2, @day)
    assert VisitorCount.take(key, 2, ~D[2026-11-25])
  end

  defp start(conn, project) do
    {:ok, view, _} = live(conn, ~p"/")
    view |> form("#plant", %{project: project}) |> render_submit()
  end

  defp done,
    do:
      for(
        a <- Bench.planted_audits!(),
        a.state == :examining,
        do: Bench.finish_examination!(a, %{}, @agent)
      )

  test "the sixth start of one address is refused, another address goes on", %{conn: conn} do
    ip = "198.51.100.#{System.unique_integer([:positive]) |> rem(200)}"

    for i <- 1..5 do
      assert {:error, {:live_redirect, _}} = start(from(conn, ip), "a/b#{i}")
      done()
    end

    # Forged headers change nothing, and an invalid name costs nothing.
    forged =
      conn
      |> from(ip)
      |> put_req_header("x-forwarded-for", "203.0.113.99")
      |> put_req_header("x-real-ip", "203.0.113.99")

    assert start(forged, "a/b6") =~ "You have started five examinations today"
    old = hd(Bench.planted_audits!())

    Builddoctor.Repo.query!(
      "update audits set inserted_at = inserted_at - interval '25 hours' where id = $1",
      [Ecto.UUID.dump!(old.id)]
    )

    {:ok, view, _} = live(from(conn, ip), ~p"/a/#{old.id}")
    assert view |> element("button", "Examine again") |> render_click() =~ "You have started five"
    assert {:error, {:live_redirect, _}} = start(from(conn, "198.51.100.250"), "a/b7")
  end

  test "only our own door may report another address", %{conn: conn} do
    visitor = fn headers ->
      Enum.reduce(headers, from(conn, "203.0.113.7"), fn {k, v}, c ->
        %{c | req_headers: c.req_headers ++ [{k, v}]}
      end)
      |> get(~p"/how-it-works")
      |> Plug.Conn.get_session("visitor")
    end

    secret = {"x-builddoctor-edge", "test-edge-secret-0123456789abcdefgh"}
    client = {"x-builddoctor-client", "198.51.100.9"}
    door = visitor.([])
    real = visitor.([secret, client])

    assert real == Visitor.hash(["198.51.100.9"], conn_secret())
    assert real != door
    assert visitor.([secret, {"x-builddoctor-client", "198.51.100.8"}]) != real

    for forged <- [
          [client],
          [{"x-builddoctor-edge", "wrong"}, client],
          [{"x-builddoctor-edge", ""}, client],
          [secret, secret, client],
          [secret],
          [secret, client, client]
        ],
        do: assert(visitor.(forged) == door)

    # An address that is none gives no key instead of somebody else's.
    assert visitor.([secret, {"x-builddoctor-client", "x"}]) == nil

    for weak <- [nil, "", "short"] do
      before = Application.get_env(:builddoctor, :edge_secret)
      Application.put_env(:builddoctor, :edge_secret, weak)
      on_exit(fn -> Application.put_env(:builddoctor, :edge_secret, before) end)
      assert visitor.([{"x-builddoctor-edge", weak || ""}, client]) == door
      Application.put_env(:builddoctor, :edge_secret, before)
    end
  end

  defp conn_secret, do: BuilddoctorWeb.Endpoint.config(:secret_key_base)

  test "results about projects are not listed by search engines", %{conn: conn} do
    assert ["noindex, nofollow"] = conn |> get(~p"/a/nonsense") |> get_resp_header("x-robots-tag")
    assert [] = conn |> get(~p"/how-it-works") |> get_resp_header("x-robots-tag")
    assert conn |> get("/robots.txt") |> response(200) =~ "Disallow: /a/"
  end
end
