defmodule Builddoctor.Bench.Line do
  @moduledoc """
  One line the editor of the agent wrote for an edition: a headline, the scene or the caption of a
  photo, a classified ad or a horoscope. Nobody outside sees it before two roles have passed it.
  """
  use Ash.Resource,
    otp_app: :builddoctor,
    domain: Builddoctor.Bench,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource],
    notifiers: [Ash.Notifier.PubSub]

  @signs ~w(aries taurus gemini cancer leo virgo libra scorpio sagittarius capricorn aquarius pisces)a

  def signs, do: @signs

  json_api do
    type "line"
  end

  postgres do
    table "lines"
    repo Builddoctor.Repo

    references do
      reference :audit, on_delete: :delete
      reference :finding, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :record do
      description "Records a line once; the same place again returns the stored one."
      accept [:audit_id, :kind, :place, :finding_id, :sign, :text]
      upsert? true
      upsert_identity :one_per_place
      upsert_fields []
      validate Builddoctor.Bench.Validations.PassedFinding
      validate Builddoctor.Bench.Validations.Printable
    end

    update :decide do
      description "The votes of two roles; only two that pass publish the line. Anything else withholds it."
      accept [:qa, :safety, :reason]
      require_atomic? false
      validate attribute_equals(:status, :pending)

      change fn changeset, _ ->
        votes = Enum.map([:qa, :safety], &Ash.Changeset.get_attribute(changeset, &1))
        status = if votes == [:pass, :pass], do: :published, else: :withheld
        Ash.Changeset.force_change_attribute(changeset, :status, status)
      end
    end

    read :for_audit do
      argument :audit_id, :uuid, allow_nil?: false
      filter expr(audit_id == ^arg(:audit_id))
      prepare build(sort: [kind: :asc, place: :asc])
    end
  end

  policies do
    # In the reduced mode a Visitor sees only our own project.
    policy action_type(:read) do
      authorize_if Builddoctor.Bench.Checks.FullMode
      authorize_if actor_present()
      authorize_if expr(is_nil(audit.slot) and audit.repository in ["pikespeak/ci-patient"])
    end

    policy action_type(:read) do
      authorize_if actor_attribute_equals(:role, :agent)
      authorize_if actor_attribute_equals(:role, :requester)
      authorize_if expr(status == :published)
    end

    policy action([:record, :decide]) do
      authorize_if actor_attribute_equals(:role, :agent)
    end
  end

  pub_sub do
    module BuilddoctorWeb.Endpoint
    prefix "audit"
    publish :record, [:audit_id]
    publish :decide, [:audit_id]
    publish :decide, "front"
  end

  attributes do
    uuid_primary_key :id

    attribute :kind, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: [:headline, :scene, :caption, :ad, :star]]

    # The photo it belongs to; zero for the edition.
    attribute :place, :integer,
      allow_nil?: false,
      default: 0,
      public?: true,
      constraints: [min: 0, max: 3]

    attribute :sign, :atom, public?: true, constraints: [one_of: @signs]
    attribute :text, :string, allow_nil?: false, public?: true, constraints: [max_length: 260]
    attribute :qa, :atom, public?: true, constraints: [one_of: [:pass, :fail]]
    attribute :safety, :atom, public?: true, constraints: [one_of: [:pass, :fail]]
    attribute :reason, :string, public?: true, constraints: [max_length: 300]

    attribute :status, :atom,
      allow_nil?: false,
      default: :pending,
      public?: true,
      constraints: [one_of: [:pending, :published, :withheld]]

    timestamps()
  end

  relationships do
    belongs_to :audit, Builddoctor.Bench.Audit, allow_nil?: false, public?: true
    belongs_to :finding, Builddoctor.Bench.Finding, public?: true
  end

  identities do
    identity :one_per_place, [:audit_id, :kind, :place]
  end
end
