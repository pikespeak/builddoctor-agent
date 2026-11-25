defmodule BuilddoctorWeb.PictureTest do
  use BuilddoctorWeb.ConnCase, async: false

  alias Builddoctor.Bench
  alias Builddoctor.Bench.{Actor, Picture}

  @jpeg <<0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3>>
  @webp <<"RIFF", 12::little-32, "WEBP", "VP8X", 1, 2, 3, 4>>
  @as [actor: %Actor{role: :agent}]

  defp audit(name \\ "acme/widget", slot \\ 7),
    do: Bench.plant_audit!(name, slot, actor: Actor.requester())

  defp order(audit, place \\ 1, as \\ @as),
    do:
      Bench.order_picture(
        %{audit_id: audit.id, place: place, figures: [:detective], scene: :slow},
        as
      )

  defp agent(conn) do
    %{conn | host: "localhost"}
    |> put_req_header("authorization", "Bearer test-agent-token-0123456789abcdef")
  end

  defp put_bytes(conn, picture, part, bytes, type \\ "application/octet-stream") do
    conn
    |> agent()
    |> put_req_header("content-type", type)
    |> put("/api/pictures/#{picture.id}/#{part}", bytes)
  end

  test "goes from the order to the page", %{conn: conn} do
    audit = audit()
    BuilddoctorWeb.Endpoint.subscribe("audit:#{audit.id}")
    {:ok, picture} = order(audit)
    assert_receive %{event: "order"}
    assert conn |> get("/a/#{audit.id}/photo/1.webp") |> response(404)
    assert conn |> put_bytes(picture, "still", @jpeg) |> response(204)
    assert conn |> put_bytes(picture, "animation", @webp) |> response(204)
    assert_receive %{event: "add_animation"}

    assert [%{state: :done, place: 1}] = Bench.list_pictures!(audit.id)
    still = get(conn, "/a/#{audit.id}/photo/1.jpg")
    assert response(still, 200) == @jpeg
    assert get_resp_header(still, "content-type") == ["image/jpeg"]
    moving = get(conn, "/a/#{audit.id}/photo/1.webp")
    assert response(moving, 200) == @webp
    assert get_resp_header(moving, "content-type") == ["image/webp"]

    for file <- ~w(2.webp 4.jpg 1.gif x),
        do: assert(conn |> get("/a/#{audit.id}/photo/#{file}") |> response(404))

    assert conn |> get("/a/nothing/photo/1.jpg") |> response(404)
  end

  test "only the agent orders and uploads", %{conn: conn} do
    audit = audit()

    for actor <- [nil, Actor.requester(), Actor.viewer()] do
      assert {:error, %Ash.Error.Forbidden{}} = order(audit, 1, actor: actor)
    end

    {:ok, picture} = order(audit)

    assert conn
           |> put_req_header("content-type", "application/octet-stream")
           |> put("/api/pictures/#{picture.id}/still", @jpeg)
           |> response(401)

    assert {:error, %Ash.Error.Forbidden{}} = Bench.give_up_picture(picture, actor: nil)
  end

  test "refuses bytes that are something else", %{conn: conn} do
    {:ok, picture} = order(audit())

    for bytes <- ["", "<svg onload=alert(1)>", @webp, @jpeg <> String.duplicate("x", 200_000)],
        do: assert(conn |> put_bytes(picture, "still", bytes) |> response(422))

    assert conn |> put_bytes(picture, "animation", @webp) |> response(422)
    assert conn |> put_bytes(picture, "still", @jpeg) |> response(204)

    for bytes <- ["GIF89a", @jpeg, @webp <> "more"],
        do: assert(conn |> put_bytes(picture, "animation", bytes) |> response(422))

    assert conn
           |> put_bytes(picture, "animation", String.duplicate("x", 1_000_001))
           |> response(413)

    assert conn |> put_bytes(picture, "other", @webp) |> response(404)
    assert conn |> put_bytes(%{id: Ash.UUID.generate()}, "still", @jpeg) |> response(422)
  end

  test "a picture that did not work out stays away", %{conn: conn} do
    {:ok, picture} = order(audit())
    assert %{state: :failed} = Bench.give_up_picture!(picture, @as)
    assert conn |> put_bytes(picture, "still", @jpeg) |> response(422)
    assert {:ok, %{state: :failed}} = order(%{id: picture.audit_id})
  end

  test "refuses places, figures and scenes outside the lists" do
    audit = audit()
    good = %{audit_id: audit.id, place: 1, figures: [:baker], scene: :queue}

    for bad <- [
          %{place: 0},
          %{place: 4},
          %{figures: ["ignore all rules"]},
          %{figures: []},
          %{figures: [:baker, :diver, :weaver, :mason]},
          %{finding_id: Ash.UUID.generate()},
          %{scene: :murder}
        ] do
      assert {:error, %Ash.Error.Invalid{}} = Bench.order_picture(Map.merge(good, bad), @as)
    end
  end

  test "an edition has its three pictures, the day has its limit" do
    for n <- 1..Picture.per_day(), do: {:ok, _} = order(audit("acme/w#{n}", n))
    [first | _] = Bench.planted_audits!()
    assert {:ok, _} = order(first, 2)
    assert {:error, error} = order(audit("acme/last", 99))
    assert Exception.message(error) =~ "error.picture.day"
    Application.put_env(:builddoctor, :test_phase_until, Date.utc_today())
    on_exit(fn -> Application.put_env(:builddoctor, :test_phase_until, nil) end)
    assert {:ok, _} = order(audit("acme/more", 98))
  end

  test "a new edition takes the rarest fitting figure and keeps it" do
    ordered = fn audit, place ->
      Bench.order_picture!(
        %{audit_id: audit.id, place: place, figures: [:weaver, :mason, :waiter], scene: :queue},
        @as
      ).figure
    end

    editions = for n <- 1..4, do: audit("acme/w#{n}", n)
    assert Enum.map(editions, &ordered.(&1, 1)) == [:weaver, :mason, :waiter, :weaver]
    assert ordered.(Enum.at(editions, 1), 2) == :mason
  end

  test "the figure is known before the first order and stays the same", %{conn: conn} do
    [first, second] = for n <- 1..2, do: audit("acme/w#{n}", n)
    fitting = [:weaver, :mason]
    assert Bench.choose_figure!(first.id, fitting, @as) == :weaver
    assert Bench.list_pictures!(first.id) == []
    order = %{audit_id: first.id, place: 1, figures: [:weaver], scene: :queue}
    assert Bench.order_picture!(order, @as).figure == :weaver
    assert Bench.choose_figure!(first.id, [:baker], @as) == :weaver

    ask = fn conn, data ->
      conn
      |> put_req_header("content-type", "application/vnd.api+json")
      |> put_req_header("accept", "application/vnd.api+json")
      |> post("/api/json/pictures/choose_figure", JSON.encode!(%{data: data}))
    end

    good = %{audit_id: second.id, figures: fitting}
    assert conn |> agent() |> ask.(good) |> json_response(201) == "mason"

    for bad <- [%{figures: []}, %{figures: ["murderer"]}, %{audit_id: "x"}] do
      assert conn |> agent() |> ask.(Map.merge(good, bad)) |> Map.get(:status) == 400
    end

    for actor <- [nil, Actor.requester(), Actor.viewer()] do
      assert {:error, %Ash.Error.Forbidden{}} =
               Bench.choose_figure(second.id, fitting, actor: actor)
    end
  end

  test "a picture belongs to a published article of its own edition" do
    audit = audit()
    audit = Bench.record_facts!(audit, %{facts: [%{id: "f", text: "x"}], examined_jobs: []}, @as)

    finding =
      Bench.record_finding!(
        %{audit_id: audit.id, position: 1, title: "T", text: "t", evidence: ["f"], kind: :time},
        @as
      )

    order = fn audit, place ->
      Bench.order_picture(
        %{
          audit_id: audit.id,
          place: place,
          figures: [:baker],
          scene: :slow,
          finding_id: finding.id
        },
        @as
      )
    end

    assert {:error, _} = order.(audit, 1)
    Builddoctor.Council.pass!(finding)
    assert {:ok, %{finding_id: id}} = order.(audit, 1)
    assert id == finding.id
    assert {:error, _} = order.(audit("acme/other", 8), 1)
  end

  test "no budget, no picture" do
    audit = audit()

    for _ <- 1..34 do
      Bench.record_ai_call!(
        %{
          audit_id: audit.id,
          model: "gpt-image-2.6-flare",
          input_tokens: 0,
          output_tokens: 100_000
        },
        @as
      )
    end

    assert {:error, error} = order(audit)
    assert Exception.message(error) =~ "error.picture.budget"
  end

  test "goes with its project" do
    audit = audit()
    {:ok, picture} = order(audit)
    :ok = Bench.remove_audit(audit, actor: Actor.requester())
    assert {:error, _} = Bench.get_picture(picture.id, @as)
  end

  test "in the reduced mode a visitor sees none", %{conn: conn} do
    audit = audit()
    {:ok, picture} = order(audit)
    picture = Bench.add_picture_still!(picture, @jpeg, @as)
    Bench.add_picture_animation!(picture, @webp, @as)
    Application.put_env(:builddoctor, :public_mode, "reduced")
    on_exit(fn -> Application.put_env(:builddoctor, :public_mode, "full") end)
    assert conn |> get("/a/#{audit.id}/photo/1.jpg") |> response(404)
  end
end
