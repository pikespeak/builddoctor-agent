defmodule Builddoctor.Bench.Changes.Plant do
  @moduledoc "Takes a name or a GitHub address. The name is checked afterwards."
  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    name = name(Ash.Changeset.get_argument(changeset, :project) || "")

    Ash.Changeset.force_change_attributes(changeset, %{
      repository: name,
      planted_as: String.downcase(name)
    })
  end

  @doc "The project in what somebody typed."
  def name(text) do
    text
    |> String.trim()
    |> String.replace(~r{\A(https?://)?(www\.)?github\.com/}i, "")
    |> String.trim_trailing("/")
    |> String.replace(~r/\.git\z/i, "")
  end
end
