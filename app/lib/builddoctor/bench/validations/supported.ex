defmodule Builddoctor.Bench.Validations.Supported do
  @moduledoc """
  A finding must cite facts of its audit and may use only numbers that stand in them.
  So the model can interpret, but not invent a measurement.
  """
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, _opts, _context) do
    get = &Ash.Changeset.get_attribute(changeset, &1)
    cited = get.(:evidence) || []

    with {:ok, audit} <- Ash.get(Builddoctor.Bench.Audit, get.(:audit_id), authorize?: false),
         facts = Enum.filter(audit.facts || [], &(&1.id in cited)),
         true <- cited != [] and length(facts) == length(Enum.uniq(cited)),
         true <-
           MapSet.subset?(
             numbers([get.(:title), get.(:text), get.(:advice)]),
             numbers(Enum.map(facts, & &1.text))
           ) do
      :ok
    else
      _ -> {:error, field: :evidence, message: "error.finding.unsupported"}
    end
  end

  defp numbers(texts) do
    for text <- texts,
        is_binary(text),
        [n] <- Regex.scan(~r/\d+(?:[.,]\d+)*/, text),
        into: MapSet.new(),
        do: n
  end
end
