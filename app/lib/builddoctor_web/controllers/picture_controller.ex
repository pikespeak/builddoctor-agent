defmodule BuilddoctorWeb.PictureController do
  @moduledoc "Press photos: in from the agent, out to the page. The rules are in Ash."
  use BuilddoctorWeb, :controller

  alias Builddoctor.Bench
  alias Builddoctor.Bench.Actor
  alias BuilddoctorWeb.Requester

  @actions %{"still" => :add_picture_still, "animation" => :add_picture_animation}

  def store(conn, %{"id" => id, "part" => part}) when is_map_key(@actions, part) do
    with {:ok, bytes, conn} <- read_body(conn, length: 1_000_000),
         {:ok, picture} <- Bench.get_picture(id, actor: Actor.agent()),
         {:ok, _} <- apply(Bench, @actions[part], [picture, bytes, [actor: Actor.agent()]]) do
      send_resp(conn, 204, "")
    else
      {:more, _, conn} -> send_resp(conn, 413, "")
      _ -> send_resp(conn, 422, "")
    end
  end

  def store(conn, _), do: send_resp(conn, 404, "")

  def show(conn, %{"id" => id, "file" => file}) do
    with {place, part, type} <- file(file),
         {:ok, %{} = picture} <-
           Bench.done_picture(id, place, actor: Requester.viewer(get_session(conn))) do
      conn
      |> put_resp_content_type(type, nil)
      |> put_resp_header("cache-control", "private, max-age=3600")
      |> send_resp(200, Map.fetch!(picture, part))
    else
      _ -> send_resp(conn, 404, "")
    end
  end

  for place <- 1..3 do
    defp file(unquote("#{place}.jpg")), do: {unquote(place), :still, "image/jpeg"}
    defp file(unquote("#{place}.webp")), do: {unquote(place), :animation, "image/webp"}
  end

  defp file(_), do: nil
end
