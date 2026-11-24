defmodule BuilddoctorWeb.Requester do
  @moduledoc "Whether a session belongs to the Requester. A sign-in lasts twelve hours."
  @seconds 12 * 60 * 60

  def signed_in?(session, now \\ System.system_time(:second))

  def signed_in?(%{"requester_since" => at}, now) when is_integer(at),
    do: (now - at) in 0..@seconds

  def signed_in?(_, _), do: false

  @doc "The actor of an open page, asked again before every act, because a page stays open for long."
  def actor(socket) do
    if signed_in?(socket.assigns.session), do: Builddoctor.Bench.Actor.requester()
  end
end
