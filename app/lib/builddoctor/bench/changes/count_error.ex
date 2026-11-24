defmodule Builddoctor.Bench.Changes.CountError do
  @moduledoc "Counts failures of the agent; too many end the Examination and free the place."
  use Ash.Resource.Change

  alias Builddoctor.Bench.Audit

  @impl true
  def change(changeset, _opts, _context) do
    errors = changeset.data.errors + 1
    changeset = Ash.Changeset.force_change_attribute(changeset, :errors, errors)

    if errors < Audit.max_errors() do
      AshStateMachine.transition_state(changeset, :examining)
    else
      changeset
      |> Ash.Changeset.force_change_attributes(%{
        stop_reason: "The project could not be read.",
        slot: nil,
        planted_as: nil
      })
      |> AshStateMachine.transition_state(:stopped)
    end
  end
end
