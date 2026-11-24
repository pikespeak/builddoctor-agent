defmodule Builddoctor.Bench.LiveJob do
  @moduledoc "A job of the run that is active right now."
  use Ash.Resource, data_layer: :embedded

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    attribute :name, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: ~r/\A[\w .,:()\/+\-]{1,60}\z/]

    attribute :stage, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:queued, :running, :done]]

    attribute :started_at, :utc_datetime, public?: true
    attribute :completed_at, :utc_datetime, public?: true
  end
end
