defmodule Builddoctor.Bench.Trial do
  @moduledoc "One optimization attempt. The verdict comes from measurements only."
  use Ash.Resource,
    otp_app: :builddoctor,
    domain: Builddoctor.Bench,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource],
    notifiers: [Ash.Notifier.PubSub]

  json_api do
    type "trial"
  end

  postgres do
    table "trials"
    repo Builddoctor.Repo

    references do
      reference :audit, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :propose do
      accept [:audit_id, :attempt, :goal, :hypothesis, :original, :patch, :branch]
      validate present(:original), message: "is needed to show the change before approval"
    end

    update :decide do
      description "The chair: clears a trial that every role passed, withholds any other."
      accept []
      require_atomic? false
      validate attribute_equals(:status, :pending)
      change {Builddoctor.Bench.Changes.Chair, key: :trial_id}
    end

    read :for_audit do
      argument :audit_id, :uuid, allow_nil?: false
      filter expr(audit_id == ^arg(:audit_id))
      prepare build(sort: [attempt: :asc])
    end

    update :evaluate do
      description "Compares the measured runs and stores verdict, reason and numbers."
      accept []
      require_atomic? false
      change Builddoctor.Bench.Changes.Evaluate
    end
  end

  policies do
    # In the reduced mode a Visitor sees only our own project.
    policy action_type(:read) do
      authorize_if Builddoctor.Bench.Checks.FullMode
      authorize_if actor_present()
      authorize_if expr(is_nil(audit.slot) and audit.repository in ["pikespeak/ci-patient"])
    end

    # A measured trial is public; before that only what the council has passed.
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :agent)
      authorize_if actor_attribute_equals(:role, :requester)
      authorize_if expr(status == :published or not is_nil(verdict))
    end

    policy action([:propose, :evaluate, :decide]) do
      authorize_if actor_attribute_equals(:role, :agent)
    end
  end

  pub_sub do
    module BuilddoctorWeb.Endpoint
    prefix "audit"
    publish :evaluate, [:audit_id]
    publish :decide, [:audit_id]
  end

  attributes do
    uuid_primary_key :id

    attribute :attempt, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1, max: 3]

    attribute :goal, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:wait, :bill]]

    attribute :hypothesis, :string,
      allow_nil?: false,
      public?: true,
      constraints: [max_length: 1000]

    # The workflow before the change. Nullable only because the first Trial was stored without it.
    attribute :original, :string,
      public?: true,
      constraints: [max_length: 20_000, trim?: false]

    attribute :patch, :string,
      allow_nil?: false,
      public?: true,
      constraints: [max_length: 20_000, trim?: false]

    attribute :branch, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: ~r/\Abuilddoctor\/[a-z0-9\-]{1,60}\z/]

    attribute :status, :atom,
      allow_nil?: false,
      default: :pending,
      public?: true,
      constraints: [one_of: [:pending, :published, :withheld]]

    attribute :verdict, :atom,
      public?: true,
      constraints: [one_of: [:accepted, :rejected, :failed, :inconclusive]]

    attribute :reason, :string, public?: true
    attribute :numbers, :map, public?: true
    timestamps()
  end

  relationships do
    belongs_to :audit, Builddoctor.Bench.Audit, allow_nil?: false, public?: true
    has_many :runs, Builddoctor.Bench.Run
  end

  identities do
    identity :attempt_per_audit, [:audit_id, :attempt]
  end
end
