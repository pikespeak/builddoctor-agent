defmodule Builddoctor.Bench.AiCall do
  @moduledoc "One paid model call. Costs are computed here from the reported tokens."
  use Ash.Resource,
    otp_app: :builddoctor,
    domain: Builddoctor.Bench,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshJsonApi.Resource]

  # Micro-dollars per token, read from the OpenAI pages on 2026-11-23 and 2026-11-24.
  @prices %{"gpt-6.2-astra" => {8, 40}, "gpt-6.2-sol" => {2, 10}}
  @limit 27_000_000

  json_api do
    type "ai_call"
  end

  postgres do
    table "ai_calls"
    repo Builddoctor.Repo

    references do
      reference :audit, on_delete: :nilify
    end
  end

  actions do
    defaults [:read]

    create :record do
      accept [:audit_id, :model, :input_tokens, :output_tokens]
      validate present(:audit_id)

      change fn changeset, _ ->
        get = &Ash.Changeset.get_attribute(changeset, &1)

        with {input, output} <- @prices[get.(:model)],
             i when is_integer(i) <- get.(:input_tokens),
             o when is_integer(o) <- get.(:output_tokens) do
          Ash.Changeset.force_change_attribute(changeset, :micro_dollars, i * input + o * output)
        else
          _ -> Ash.Changeset.add_error(changeset, field: :model, message: "has no known price")
        end
      end
    end

    action :budget_left, :boolean do
      run fn _, _ ->
        spent = Ash.sum!(__MODULE__, :micro_dollars, authorize?: false) || 0
        {:ok, spent < @limit}
      end
    end
  end

  policies do
    policy always() do
      authorize_if actor_attribute_equals(:role, :agent)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :model, :string, allow_nil?: false, public?: true

    attribute :input_tokens, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 0, max: 1_000_000]

    attribute :output_tokens, :integer,
      allow_nil?: false,
      public?: true,
      constraints: [min: 0, max: 100_000]

    attribute :micro_dollars, :integer, allow_nil?: false, public?: true, writable?: false
    timestamps()
  end

  relationships do
    belongs_to :audit, Builddoctor.Bench.Audit, public?: true
  end
end
