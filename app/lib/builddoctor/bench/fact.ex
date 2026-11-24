defmodule Builddoctor.Bench.Fact do
  @moduledoc "One computed sentence about a run. Findings cite it by its id."
  use Ash.Resource, data_layer: :embedded

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    attribute :id, :string,
      allow_nil?: false,
      public?: true,
      primary_key?: true,
      constraints: [match: ~r/\A[a-z]{1,20}[0-9]{0,2}\z/]

    attribute :text, :string, allow_nil?: false, public?: true, constraints: [max_length: 300]
    # Where something began, for a link.
    attribute :commit, :string, public?: true, constraints: [match: ~r/\A[0-9a-f]{40}\z/]
    attribute :seconds, :integer, public?: true, default: 0, constraints: [min: 0]
  end
end
