defmodule Builddoctor.Bench.Validations.Printable do
  @moduledoc """
  What code can check about a line before anybody votes. A number must stand in the article and in
  its facts. A scene becomes part of an image request, so it has plain words only, and none for a
  failure or a weakness. A joke that belongs to no article names no project.
  """
  use Ash.Resource.Validation

  alias Builddoctor.Bench.{Audit, Finding}

  @longest %{headline: 70, caption: 140, scene: 260, ad: 120, star: 120}
  @serious [:failure, :file_error, :security, nil]

  @impl true
  def validate(changeset, _opts, _context) do
    get = &Ash.Changeset.get_attribute(changeset, &1)
    {kind, text} = {get.(:kind), get.(:text) || ""}

    with {:ok, audit} <- Ash.get(Audit, get.(:audit_id), authorize?: false),
         finding = finding(get.(:finding_id)),
         true <- String.length(text) <= Map.get(@longest, kind, 0),
         true <- text =~ words(kind),
         true <- place?(kind, get.(:place), get.(:sign)),
         true <- MapSet.subset?(numbers([text]), allowed(kind, finding, audit)),
         true <- kind == :headline or kind == :caption or nameless?(text, audit.repository),
         false <- kind == :scene and finding != nil and finding.kind in @serious do
      :ok
    else
      _ -> {:error, field: :text, message: "error.line.notPrintable"}
    end
  end

  defp finding(nil), do: nil
  defp finding(id), do: Ash.get!(Finding, id, authorize?: false)

  defp words(:scene), do: ~r/\A[A-Z][A-Za-z ,.;'\-]+\.\z/
  defp words(_), do: ~r/\A[A-Z0-9“"][^<>{}`@\\\n\r\/]+\z/u

  defp place?(kind, place, nil) when kind in [:scene, :caption], do: place in 1..3
  defp place?(:star, 0, sign), do: sign != nil
  defp place?(kind, 0, nil) when kind in [:headline, :ad], do: true
  defp place?(_, _, _), do: false

  defp allowed(kind, %{} = finding, audit) when kind in [:headline, :caption] do
    facts = for f <- audit.facts || [], f.id in finding.evidence, do: f.text
    MapSet.intersection(numbers([finding.title, finding.text]), numbers(facts))
  end

  defp allowed(_, _, _), do: MapSet.new()

  defp nameless?(text, repository) do
    low = String.downcase(text)

    repository
    |> String.downcase()
    |> String.split(~r/[^a-z0-9]+/, trim: true)
    |> Enum.filter(&(String.length(&1) > 2))
    |> Enum.all?(&(not (low =~ ~r/\b#{&1}\b/)))
  end

  defp numbers(texts) do
    for text <- texts,
        is_binary(text),
        [n] <- Regex.scan(~r/\d+(?:[.,]\d+)*/, text),
        into: MapSet.new(),
        do: n
  end
end
