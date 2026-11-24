defmodule Builddoctor.Bench.Actor do
  @moduledoc "Who acts: the agent in the Sprite or the Requester. Visitors have no actor."
  @enforce_keys [:role]
  defstruct [:role]

  def agent, do: %__MODULE__{role: :agent}
  def requester, do: %__MODULE__{role: :requester}
end
