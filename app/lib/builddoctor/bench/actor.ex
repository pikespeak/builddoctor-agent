defmodule Builddoctor.Bench.Actor do
  @moduledoc """
  Who acts: the agent in the Sprite or the Requester. Visitors have no actor.
  The viewer is the Requester who looks at the page: all projects, but only what passed.
  """
  @enforce_keys [:role]
  defstruct [:role]

  def agent, do: %__MODULE__{role: :agent}
  def viewer, do: %__MODULE__{role: :viewer}
  def requester, do: %__MODULE__{role: :requester}
end
