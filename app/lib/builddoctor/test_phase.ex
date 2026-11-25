defmodule Builddoctor.TestPhase do
  @moduledoc """
  Until the last day of the test phase (owner, 2026-11-25) there is no daily total. The spending
  limit, the limit of an address and one Examination per project in 24 hours stay.
  """
  def on?(today \\ Date.utc_today()) do
    case Application.get_env(:builddoctor, :test_phase_until) do
      %Date{} = last -> Date.compare(today, last) != :gt
      _ -> false
    end
  end
end
