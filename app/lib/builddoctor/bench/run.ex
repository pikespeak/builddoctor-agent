defmodule Builddoctor.Bench.Run do
  @moduledoc """
  One measured workflow run. A run without an trial belongs to the baseline.
  Durations are computed here and never accepted from the caller.
  """
  use Ash.Resource,
    otp_app: :builddoctor,
    domain: Builddoctor.Bench,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource],
    notifiers: [Ash.Notifier.PubSub]

  json_api do
    type "run"
  end

  postgres do
    table "runs"
    repo Builddoctor.Repo

    references do
      reference :audit, on_delete: :delete
      reference :trial, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :record do
      description "Records a run once; the same GitHub run again returns the stored one."
      accept [:audit_id, :trial_id, :github_run_id, :sha, :warmup, :started_at, :jobs]
      upsert? true
      upsert_identity :one_per_github_run
      upsert_fields []
      validate Builddoctor.Bench.Validations.SameAudit
      change Builddoctor.Bench.Changes.Durations
    end

    read :for_audit do
      argument :audit_id, :uuid, allow_nil?: false
      filter expr(audit_id == ^arg(:audit_id))
      prepare build(sort: [started_at: :asc])
    end
  end

  policies do
    # In the reduced mode a Visitor sees only our own project.
    policy action_type(:read) do
      authorize_if Builddoctor.Bench.Checks.FullMode
      authorize_if actor_present()
      authorize_if expr(is_nil(audit.slot) and audit.repository in ["pikespeak/ci-patient"])
    end

    policy action(:record) do
      authorize_if actor_attribute_equals(:role, :agent)
    end
  end

  pub_sub do
    module BuilddoctorWeb.Endpoint
    prefix "audit"
    publish :record, [:audit_id]
  end

  attributes do
    uuid_primary_key :id

    attribute :github_run_id, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1]

    attribute :sha, :string,
      allow_nil?: false,
      public?: true,
      constraints: [match: ~r/\A[0-9a-f]{40}\z/]

    attribute :warmup, :boolean, allow_nil?: false, default: false, public?: true
    attribute :started_at, :utc_datetime, allow_nil?: false, public?: true

    attribute :jobs, {:array, Builddoctor.Bench.Job},
      allow_nil?: false,
      public?: true,
      constraints: [min_length: 1, max_length: 10]

    attribute :succeeded, :boolean, allow_nil?: false, public?: true, writable?: false
    attribute :wall_seconds, :integer, allow_nil?: false, public?: true, writable?: false
    attribute :billed_minutes, :integer, allow_nil?: false, public?: true, writable?: false
    attribute :runner_seconds, :integer, allow_nil?: false, public?: true, writable?: false
    timestamps()
  end

  relationships do
    belongs_to :audit, Builddoctor.Bench.Audit, allow_nil?: false, public?: true
    belongs_to :trial, Builddoctor.Bench.Trial, public?: true
  end

  identities do
    identity :one_per_github_run, [:github_run_id]
  end
end
