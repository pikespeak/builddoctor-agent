defmodule Builddoctor.Bench.Picture do
  @moduledoc """
  One moving press photo of an edition. The figure and the scene come from closed lists;
  the bytes are checked here and go with the Audit when it is removed.
  """
  use Ash.Resource,
    otp_app: :builddoctor,
    domain: Builddoctor.Bench,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource],
    notifiers: [Ash.Notifier.PubSub]

  @figures [
    :reporter,
    :detective,
    :officer,
    :waiter,
    :operator,
    :printer,
    :librarian,
    :chemist,
    :gardener,
    :tailor,
    :conductor,
    :locksmith,
    :postman,
    :baker,
    :engineer,
    :teacher,
    :architect,
    :astronomer,
    :beekeeper,
    :blacksmith,
    :cartographer,
    :clockmaker,
    :diver,
    :fisher,
    :juggler,
    :keeper,
    :mason,
    :mechanic,
    :photographer,
    :pianist,
    :shepherd,
    :weaver
  ]
  @scenes [
    :queue,
    :counter,
    :bench,
    :slow,
    :marathon,
    :snail,
    :cost,
    :meter,
    :flaky,
    :coin,
    :upkeep,
    :cobweb,
    :newsroom,
    :shelves,
    :telegraph,
    :council,
    :empty,
    :portrait
  ]
  @per_day 25

  def per_day, do: @per_day
  def figures, do: @figures
  def scenes, do: @scenes

  json_api do
    type "picture"
    default_fields [:audit_id, :place, :figure, :scene, :state]
  end

  postgres do
    table "pictures"
    repo Builddoctor.Repo

    references do
      reference :audit, on_delete: :delete
      reference :finding, on_delete: :nilify
    end
  end

  actions do
    defaults [:read]

    create :order do
      description "Asks for a picture once; the same place again returns the stored one."
      accept [:audit_id, :place, :scene, :finding_id]

      argument :figures, {:array, :atom},
        allow_nil?: false,
        constraints: [min_length: 1, max_length: 3, items: [one_of: @figures]]

      upsert? true
      upsert_identity :one_per_place
      upsert_fields []
      validate Builddoctor.Bench.Validations.PassedFinding
      change Builddoctor.Bench.Changes.PictureLimit
      change Builddoctor.Bench.Changes.RarestFigure
    end

    action :choose_figure, :atom do
      description "The figure an order would take; asked before the articles are decided."
      constraints one_of: @figures
      argument :audit_id, :uuid, allow_nil?: false

      argument :figures, {:array, :atom},
        allow_nil?: false,
        constraints: [min_length: 1, max_length: 3, items: [one_of: @figures]]

      run fn input, _ ->
        %{audit_id: audit, figures: fitting} = input.arguments
        {:ok, Builddoctor.Bench.Changes.RarestFigure.figure(audit, fitting)}
      end
    end

    update :add_still do
      argument :bytes, :binary, allow_nil?: false
      require_atomic? false
      validate attribute_equals(:state, :developing)
      validate {Builddoctor.Bench.Validations.Image, kind: :jpeg, max: 200_000}
      change set_attribute(:still, arg(:bytes))
      change set_attribute(:state, :still)
    end

    update :add_animation do
      argument :bytes, :binary, allow_nil?: false
      require_atomic? false
      validate attribute_equals(:state, :still)
      validate {Builddoctor.Bench.Validations.Image, kind: :webp, max: 1_000_000}
      change set_attribute(:animation, arg(:bytes))
      change set_attribute(:state, :done)
    end

    update :give_up do
      description "The picture did not work out; the edition appears without it."
      accept []
      validate attribute_in(:state, [:developing, :still])
      change set_attribute(:state, :failed)
    end

    read :for_audit do
      argument :audit_id, :uuid, allow_nil?: false
      filter expr(audit_id == ^arg(:audit_id))
      prepare build(sort: [place: :asc])
    end

    read :done do
      description "One finished picture with its bytes."
      get? true
      argument :audit_id, :uuid, allow_nil?: false
      argument :place, :integer, allow_nil?: false
      filter expr(audit_id == ^arg(:audit_id) and place == ^arg(:place) and state == :done)
      prepare build(ensure_selected: [:still, :animation])
    end
  end

  policies do
    # In the reduced mode a Visitor sees only our own project.
    policy action_type(:read) do
      authorize_if Builddoctor.Bench.Checks.FullMode
      authorize_if actor_present()
      authorize_if expr(is_nil(audit.slot) and audit.repository in ["pikespeak/ci-patient"])
    end

    policy action([:order, :choose_figure, :add_still, :add_animation, :give_up]) do
      authorize_if actor_attribute_equals(:role, :agent)
    end
  end

  pub_sub do
    module BuilddoctorWeb.Endpoint
    prefix "audit"
    publish_all :create, [:audit_id]
    publish_all :update, [:audit_id]
    publish :add_animation, "front"
  end

  attributes do
    uuid_primary_key :id

    attribute :place, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 1, max: 3]

    attribute :figure, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: @figures]

    attribute :scene, :atom,
      allow_nil?: false,
      public?: true,
      constraints: [one_of: @scenes]

    attribute :state, :atom,
      allow_nil?: false,
      default: :developing,
      public?: true,
      constraints: [one_of: [:developing, :still, :done, :failed]]

    attribute :still, :binary, select_by_default?: false
    attribute :animation, :binary, select_by_default?: false
    timestamps()
  end

  relationships do
    belongs_to :audit, Builddoctor.Bench.Audit, allow_nil?: false, public?: true
    # The article the picture belongs to, if any.
    belongs_to :finding, Builddoctor.Bench.Finding, public?: true
  end

  identities do
    identity :one_per_place, [:audit_id, :place]
  end
end
