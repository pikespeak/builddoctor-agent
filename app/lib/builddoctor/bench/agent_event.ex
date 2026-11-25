defmodule Builddoctor.Bench.AgentEvent do
  @moduledoc "A visible step of the agent. Actions and results, no model reasoning."
  use Ash.Resource,
    otp_app: :builddoctor,
    domain: Builddoctor.Bench,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource],
    notifiers: [Ash.Notifier.PubSub]

  json_api do
    type "agent_event"
  end

  postgres do
    table "agent_events"
    repo Builddoctor.Repo

    references do
      reference :audit, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :log do
      accept [:audit_id, :kind, :status, :message, :reference]
    end

    read :for_audit do
      argument :audit_id, :uuid, allow_nil?: false
      filter expr(audit_id == ^arg(:audit_id))
      prepare build(sort: [inserted_at: :asc, id: :asc])
    end
  end

  policies do
    # In the reduced mode a Visitor sees only our own project.
    policy action_type(:read) do
      authorize_if Builddoctor.Bench.Checks.FullMode
      authorize_if actor_present()
      authorize_if expr(is_nil(audit.slot) and audit.repository in ["pikespeak/ci-patient"])
    end

    policy action(:log) do
      authorize_if actor_attribute_equals(:role, :agent)
    end
  end

  pub_sub do
    module BuilddoctorWeb.Endpoint
    prefix "audit"
    publish :log, [:audit_id]
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :kind, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [
        one_of: [
          :github,
          :openai,
          :typesafe,
          :patch,
          :run_started,
          :run_finished,
          :verdict,
          :stopped
        ]
      ]

    attribute :status, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:ok, :error]]

    attribute :message, :string, allow_nil?: false, public?: true, constraints: [max_length: 300]

    attribute :reference, :string,
      public?: true,
      constraints: [match: ~r/\Ahttps:\/\/github\.com\/[\w.\/\-]{1,200}\z/]

    timestamps()
  end

  relationships do
    belongs_to :audit, Builddoctor.Bench.Audit, allow_nil?: false, public?: true
  end
end
