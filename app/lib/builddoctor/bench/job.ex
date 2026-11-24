defmodule Builddoctor.Bench.Job do
  @moduledoc "One job of a workflow run, as GitHub reports it."
  use Ash.Resource, data_layer: :embedded

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  validations do
    validate compare(:completed_at, greater_than_or_equal_to: :started_at),
      message: "must not be before started_at"
  end

  attributes do
    attribute :name, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: ~r/\A[\w .,:()\/+\-]{1,60}\z/]

    attribute :conclusion, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:success, :failure, :cancelled, :skipped, :timed_out]]

    attribute :started_at, :utc_datetime, allow_nil?: false, public?: true
    attribute :completed_at, :utc_datetime, allow_nil?: false, public?: true
  end
end
