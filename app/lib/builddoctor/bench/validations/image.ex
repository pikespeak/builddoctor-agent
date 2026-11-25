defmodule Builddoctor.Bench.Validations.Image do
  @moduledoc "The bytes are what they claim to be and not too many. Nothing else is ever served."
  use Ash.Resource.Validation

  @impl true
  def validate(changeset, opts, _context) do
    bytes = Ash.Changeset.get_argument(changeset, :bytes)

    if byte_size(bytes) <= opts[:max] and kind?(opts[:kind], bytes),
      do: :ok,
      else: {:error, field: :bytes, message: "error.picture.invalid"}
  end

  defp kind?(:jpeg, <<0xFF, 0xD8, 0xFF, _::binary>>), do: true

  defp kind?(:webp, <<"RIFF", size::little-32, "WEBP", _::binary>> = bytes),
    do: byte_size(bytes) == size + 8

  defp kind?(_, _), do: false
end
