defmodule Builddoctor.Bench.Checks.FullMode do
  @moduledoc "Visitors see and start everything only in the full mode; any other value means reduced."
  use Ash.Policy.SimpleCheck

  def on?, do: Application.get_env(:builddoctor, :public_mode, "full") == "full"

  @impl true
  def describe(_), do: "the page is in full mode"

  @impl true
  def match?(_, _, _), do: on?()
end
