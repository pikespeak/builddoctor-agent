defmodule Builddoctor.Bench.Changes.OnceADay do
  @moduledoc """
  A Visitor gets one Examination per project in 24 hours, also after one that stopped or whose
  page went to a newer edition.
  A project that holds a page is refused elsewhere, with a link to its result.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Builddoctor.Bench.Audit

  @impl true
  def change(changeset, _opts, %{actor: %{role: :requester}}), do: changeset

  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      if recent?(Ash.Changeset.get_attribute(changeset, :repository)),
        do:
          Ash.Changeset.add_error(changeset, field: :repository, message: "error.again.tooSoon"),
        else: changeset
    end)
  end

  @doc "Whether a Visitor must wait before this project is examined again."
  def recent?(repository) do
    since = DateTime.add(DateTime.utc_now(), -24, :hour)
    name = String.downcase(repository || "")

    Audit
    |> Ash.Query.filter(
      fragment("lower(?)", repository) == ^name and is_nil(slot) and inserted_at > ^since and
        state in [:stopped, :examined, :done]
    )
    |> Ash.exists?(authorize?: false) and not on_a_page?(name)
  end

  # A project with a page is refused by its identity, with a link to its result.
  @doc "Whether the project holds a page, in lower case."
  def on_a_page?(name),
    do: Audit |> Ash.Query.filter(planted_as == ^name) |> Ash.exists?(authorize?: false)
end
