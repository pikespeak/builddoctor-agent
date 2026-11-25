defmodule Builddoctor.Bench.Finding do
  @moduledoc "What the model concludes from the facts of an Examination. A suspicion, never a proof."
  use Ash.Resource,
    otp_app: :builddoctor,
    domain: Builddoctor.Bench,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource],
    notifiers: [Ash.Notifier.PubSub]

  json_api do
    type "finding"
  end

  postgres do
    table "findings"
    repo Builddoctor.Repo

    references do
      reference :audit, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :record do
      description "Records a finding once; the same position again returns the stored one."
      accept [:audit_id, :position, :title, :text, :advice, :evidence, :kind]
      upsert? true
      upsert_identity :one_per_position
      upsert_fields []
      validate Builddoctor.Bench.Validations.Supported
    end

    update :decide do
      description "The chair: publishes a finding that every role passed, withholds any other."
      accept []
      require_atomic? false
      validate attribute_equals(:status, :pending)
      change {Builddoctor.Bench.Changes.Chair, key: :finding_id}
    end

    update :rate do
      description "What the outside fact-checker says about a published finding, once. The chair never reads it."
      accept [:support, :support_probability, :fit, :fit_probability, :rated_by]
      require_atomic? false
      validate attribute_equals(:status, :published)
      # In the database, so that a second word never replaces the first.
      change filter(expr(is_nil(rated_by)))

      validate fn changeset, _ ->
        [fit, probability] =
          Enum.map([:fit, :fit_probability], &Ash.Changeset.get_attribute(changeset, &1))

        if is_nil(fit) == is_nil(probability),
          do: :ok,
          else: {:error, field: :fit, message: "error.rating.incomplete"}
      end

      validate present([:support, :support_probability, :rated_by])
    end

    read :for_audit do
      argument :audit_id, :uuid, allow_nil?: false
      filter expr(audit_id == ^arg(:audit_id))
      prepare build(sort: [position: :asc])
    end
  end

  policies do
    # In the reduced mode a Visitor sees only our own project.
    policy action_type(:read) do
      authorize_if Builddoctor.Bench.Checks.FullMode
      authorize_if actor_present()
      authorize_if expr(is_nil(audit.slot) and audit.repository in ["pikespeak/ci-patient"])
    end

    # Nobody outside sees what the council has not passed.
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :agent)
      authorize_if actor_attribute_equals(:role, :requester)
      authorize_if expr(status == :published)
    end

    policy action([:record, :decide, :rate]) do
      authorize_if actor_attribute_equals(:role, :agent)
    end
  end

  pub_sub do
    module BuilddoctorWeb.Endpoint
    prefix "audit"
    publish :decide, [:audit_id]
    publish :rate, [:audit_id]
    publish :rate, "front"
  end

  attributes do
    uuid_primary_key :id

    attribute :position, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1, max: 5]

    attribute :title, :string, allow_nil?: false, public?: true, constraints: [max_length: 90]
    attribute :text, :string, allow_nil?: false, public?: true, constraints: [max_length: 600]
    attribute :advice, :string, public?: true, constraints: [max_length: 400]

    attribute :evidence, {:array, :string},
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1, max_length: 10]

    # Nullable only because the first findings were stored without it.
    attribute :kind, :atom,
      public?: true,
      constraints: [
        one_of: [
          :time,
          :waiting,
          :cost,
          :failure,
          :flaky,
          :file_error,
          :security,
          :maintenance
        ]
      ]

    attribute :status, :atom,
      allow_nil?: false,
      default: :pending,
      public?: true,
      constraints: [one_of: [:pending, :published, :withheld]]

    # The outside fact-checker: what it says about the weakest sentence and about the advice, and
    # how probable it finds that the facts support the one and that the other fits.
    attribute :support, :atom,
      public?: true,
      constraints: [one_of: [:supports, :contradicts, :says_nothing]]

    attribute :support_probability, :float, public?: true, constraints: [min: 0, max: 1]

    attribute :fit, :atom,
      public?: true,
      constraints: [one_of: [:addresses, :unrelated, :harmful]]

    attribute :fit_probability, :float, public?: true, constraints: [min: 0, max: 1]
    attribute :rated_by, :string, public?: true, constraints: [max_length: 40]

    timestamps()
  end

  relationships do
    belongs_to :audit, Builddoctor.Bench.Audit, allow_nil?: false, public?: true
  end

  identities do
    identity :one_per_position, [:audit_id, :position]
  end
end
