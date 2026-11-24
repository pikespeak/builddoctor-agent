defmodule Builddoctor.Bench.Changes.Chair do
  @moduledoc """
  The chair of the council. Code, not a model: published only if every role passed it.
  A missing review counts like a refusal.
  """
  use Ash.Resource.Change

  require Ash.Query

  alias Builddoctor.Bench.Review

  # A change is also checked by the engineer, which is code.
  @roles %{finding_id: [:qa, :safety], trial_id: [:qa, :safety, :engineer]}

  @impl true
  def change(changeset, opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      key = opts[:key]
      id = changeset.data.id

      verdicts =
        Review
        |> Ash.Query.filter(^ref(key) == ^id)
        |> Ash.read!(authorize?: false)
        |> Map.new(&{&1.role, &1.verdict})

      passed = Enum.all?(@roles[key], &(verdicts[&1] == :pass))

      Ash.Changeset.force_change_attribute(
        changeset,
        :status,
        if(passed, do: :published, else: :withheld)
      )
    end)
  end
end
