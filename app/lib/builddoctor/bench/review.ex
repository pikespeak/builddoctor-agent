defmodule Builddoctor.Bench.Review do
  @moduledoc "What one role of the council says about a finding or a trial. The first word counts."
  use Ash.Resource,
    otp_app: :builddoctor,
    domain: Builddoctor.Bench,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  json_api do
    type "review"
  end

  postgres do
    table "reviews"
    repo Builddoctor.Repo

    references do
      reference :finding, on_delete: :delete
      reference :trial, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :review_finding do
      accept [:finding_id, :role, :verdict, :reason, :model, :version]
      upsert? true
      upsert_identity :one_per_finding
      upsert_fields []
      validate present(:finding_id)
    end

    create :review_trial do
      accept [:trial_id, :role, :verdict, :reason, :model, :version]
      upsert? true
      upsert_identity :one_per_trial
      upsert_fields []
      validate present(:trial_id)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :agent)
      authorize_if actor_attribute_equals(:role, :requester)
    end

    policy action_type(:create) do
      authorize_if actor_attribute_equals(:role, :agent)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :role, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:qa, :safety, :engineer]]

    attribute :verdict, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:pass, :fail]]

    attribute :reason, :string, public?: true, constraints: [max_length: 300]
    attribute :model, :string, allow_nil?: false, public?: true, constraints: [max_length: 40]
    attribute :version, :integer, allow_nil?: false, public?: true, constraints: [min: 1]
    timestamps()
  end

  relationships do
    belongs_to :finding, Builddoctor.Bench.Finding, public?: true
    belongs_to :trial, Builddoctor.Bench.Trial, public?: true
  end

  identities do
    identity :one_per_finding, [:finding_id, :role]
    identity :one_per_trial, [:trial_id, :role]
  end
end
