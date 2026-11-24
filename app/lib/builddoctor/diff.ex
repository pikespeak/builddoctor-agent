defmodule Builddoctor.Diff do
  @moduledoc "Compares two texts line by line, with a few unchanged lines around every change."

  @context 3

  @doc "Lines as maps with kind (:same, :removed, :added or :gap), number and text."
  def lines(original, patched) do
    {rows, _, _} =
      String.split(original, "\n")
      |> List.myers_difference(String.split(patched, "\n"))
      |> Enum.flat_map(fn {kind, texts} -> Enum.map(texts, &{kind, &1}) end)
      |> Enum.reduce({[], 1, 1}, fn
        {:eq, text}, {out, old, new} -> {[row(:same, new, text) | out], old + 1, new + 1}
        {:del, text}, {out, old, new} -> {[row(:removed, old, text) | out], old + 1, new}
        {:ins, text}, {out, old, new} -> {[row(:added, new, text) | out], old, new + 1}
      end)

    rows |> Enum.reverse() |> near_changes()
  end

  @doc "The same change as a patch for git. Both texts must differ."
  def patch(original, patched, path) do
    {a, b} = {ended(original), ended(patched)}

    body =
      a
      |> lines(b)
      |> Enum.chunk_by(&(&1.kind == :gap))
      |> Enum.reject(&match?([%{kind: :gap} | _], &1))
      |> hunks()

    IO.iodata_to_binary(["--- a/", path, "\n+++ b/", path, "\n", body])
  end

  # Texts end with one line break; the part behind it is no line.
  defp ended(text), do: String.trim_trailing(text, "\n")

  defp hunks(chunks) do
    {out, _} =
      Enum.map_reduce(chunks, 0, fn rows, shift ->
        old = Enum.count(rows, &(&1.kind != :added))
        new = Enum.count(rows, &(&1.kind != :removed))

        start =
          case hd(rows) do
            %{kind: :same, number: n} -> n - shift
            %{kind: :removed, number: n} -> n
            %{kind: :added, number: n} -> n - shift
          end

        text = for r <- rows, do: [mark(r.kind), r.text, "\n"]
        {["@@ -#{start},#{old} +#{start + shift},#{new} @@\n", text], shift + new - old}
      end)

    out
  end

  defp mark(:same), do: " "
  defp mark(:removed), do: "-"
  defp mark(:added), do: "+"

  defp row(kind, number, text), do: %{kind: kind, number: number, text: text}

  defp near_changes(rows) do
    changed = for {%{kind: kind}, i} <- Enum.with_index(rows), kind != :same, do: i

    rows
    |> Enum.with_index()
    |> Enum.chunk_by(fn {_, i} -> Enum.any?(changed, &(abs(&1 - i) <= @context)) end)
    |> Enum.flat_map(fn [{_, first} | _] = chunk ->
      if Enum.any?(changed, &(abs(&1 - first) <= @context)),
        do: Enum.map(chunk, &elem(&1, 0)),
        else: [row(:gap, nil, "#{length(chunk)} unchanged #{plural(chunk)}")]
    end)
  end

  defp plural([_]), do: "line"
  defp plural(_), do: "lines"
end
