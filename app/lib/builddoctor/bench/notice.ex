defmodule Builddoctor.Bench.Notice do
  @moduledoc """
  A weakness in a workflow file that somebody could use. Only the Requester sees it, so that
  the Maintainer can be told first. It is never a fact and never reaches a model.
  """
  use Ash.Resource,
    otp_app: :builddoctor,
    domain: Builddoctor.Bench,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  json_api do
    type "notice"
  end

  postgres do
    table "notices"
    repo Builddoctor.Repo

    references do
      reference :audit, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :notify do
      description "Stores a weakness once."
      accept [:audit_id, :kind, :line]
      upsert? true
      upsert_identity :one_per_place
      upsert_fields []
    end

    read :for_audit do
      argument :audit_id, :uuid, allow_nil?: false
      filter expr(audit_id == ^arg(:audit_id))
      prepare build(sort: [line: :asc])
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :requester)
    end

    policy action(:notify) do
      authorize_if actor_attribute_equals(:role, :agent)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:untrusted_input, :credentials, :foreign_code]]

    attribute :line, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1, max: 20_000]

    timestamps()
  end

  relationships do
    belongs_to :audit, Builddoctor.Bench.Audit, allow_nil?: false, public?: true
  end

  identities do
    identity :one_per_place, [:audit_id, :kind, :line]
  end
end
