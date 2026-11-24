defmodule BuilddoctorWeb.Imprint do
  @moduledoc """
  Who is responsible for this page. The details stand in a file outside the code (IMPRINT_FILE),
  so that a copy of the code does not name anybody. Odd content counts as no content.
  """
  @needed ~w(name street city country email)
  @email ~r/\A[A-Za-z0-9._+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\z/

  def load(file \\ Application.get_env(:builddoctor, :imprint_file)) do
    with true <- is_binary(file),
         {:ok, text} <- File.read(file),
         {:ok, %{} = map} <- Jason.decode(text),
         true <- Enum.all?(@needed, &text?(map[&1])),
         true <- Regex.match?(@email, map["email"]),
         true <- is_nil(map["phone"]) or text?(map["phone"]),
         notes = map["notes"] || [],
         true <- is_list(notes) and length(notes) <= 10 and Enum.all?(notes, &text?/1) do
      %{
        lines: Enum.map(~w(name street city country), &map[&1]),
        name: map["name"],
        phone: map["phone"],
        email: map["email"],
        notes: notes
      }
    else
      _ -> nil
    end
  end

  defp text?(text), do: is_binary(text) and String.trim(text) != "" and String.length(text) <= 300
end
