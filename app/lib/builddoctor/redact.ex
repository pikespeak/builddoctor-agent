defmodule Builddoctor.Redact do
  @moduledoc "Leaves email addresses out of what is shown. The name of an action stays."
  @email ~r/[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/

  def emails(line) do
    keep = List.first(Regex.run(~r/^\s*(?:-\s+)?uses:\s*\S+/, line) || [""])

    keep <>
      Regex.replace(
        @email,
        binary_part(line, byte_size(keep), byte_size(line) - byte_size(keep)),
        "[email]"
      )
  end
end
