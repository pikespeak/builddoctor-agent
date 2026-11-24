defmodule Builddoctor.Bench.Audit do
  @moduledoc "One examination of a repository at a fixed commit."
  use Ash.Resource,
    otp_app: :builddoctor,
    domain: Builddoctor.Bench,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine, AshJsonApi.Resource],
    notifiers: [Ash.Notifier.PubSub]

  # Only our own demo repository may be measured; a foreign one is only examined.
  @measurable ["pikespeak/ci-patient"]
  @places 100
  @max_errors 3
  # An owner and a name as GitHub allows them, never a path.
  @name ~r/\A[A-Za-z0-9](?:[A-Za-z0-9\-]{0,38})\/(?!\.{1,2}\z)[A-Za-z0-9._\-]{1,100}\z/

  json_api do
    type "audit"
  end

  postgres do
    table "audits"
    repo Builddoctor.Repo
    identity_wheres_to_sql one_examining: "state = 'examining' AND slot IS NULL"

    references do
      reference :replaces, on_delete: :nilify
    end
  end

  state_machine do
    initial_states [:examining]
    default_initial_state :examining

    transitions do
      transition :request_approval, from: :examining, to: :awaiting_approval
      transition :approve_by_council, from: :awaiting_approval, to: :measuring
      transition :approve, from: :awaiting_approval, to: :measuring
      transition :finish_examination, from: :examining, to: :examined
      transition :finish, from: :measuring, to: :done
      transition :report_error, from: :examining, to: [:examining, :stopped]
      transition :stop, from: [:examining, :awaiting_approval, :measuring], to: :stopped
    end
  end

  actions do
    defaults [:read]

    read :open do
      description "Audits the agent still has to work on, oldest first."

      filter expr(
               state in [:examining, :measuring] or
                 (state == :awaiting_approval and not council_done)
             )

      prepare build(sort: [inserted_at: :asc], limit: 25)
    end

    create :start do
      accept [:repository, :base_sha]
      validate present(:base_sha)

      validate one_of(:repository, @measurable),
        message: "is not on the list of allowed repositories"
    end

    create :examine_own do
      description "The Requester starts our own project; the agent chooses the newest good run."
      accept []
      change set_attribute(:repository, hd(@measurable))
    end

    create :examine_again do
      accept []
      argument :audit_id, :uuid, allow_nil?: false
      change Builddoctor.Bench.Changes.Again
      change Builddoctor.Bench.Changes.VisitorLimit
    end

    update :give_way do
      description "A newer Examination takes this place; the result stays readable."
      change set_attribute(:slot, nil)
      change set_attribute(:planted_as, nil)
    end

    read :newer do
      description "The next Examination of the same project, the newest attempt first."
      argument :audit_id, :uuid, allow_nil?: false
      filter expr(replaces_id == ^arg(:audit_id))
      prepare build(sort: [inserted_at: :desc], limit: 1)
    end

    read :waiting do
      description "The Examination that waits longest for GitHub's limit."
      filter expr(state == :examining and waiting_until > now())
      prepare build(sort: [waiting_until: :desc], limit: 1)
    end

    read :place_of do
      argument :project, :string, allow_nil?: false
      get? true
      filter expr(planted_as == ^arg(:project))
    end

    create :plant do
      description "A Visitor gives a public repository one of the free places."
      accept [:slot]
      argument :project, :string, allow_nil?: false, constraints: [max_length: 200]
      validate present(:slot), message: "error.slot.invalid"
      change Builddoctor.Bench.Changes.Plant
      change Builddoctor.Bench.Changes.VisitorLimit
      validate match(:repository, @name), message: "error.repository.invalid"
    end

    read :planted do
      filter expr(not is_nil(slot))
      prepare build(sort: [slot: :asc], load: [:trials, :findings])
    end

    update :identify do
      description "The commit and the number of jobs the Examination is about."
      accept [:base_sha, :jobs_total, :workflow_path, :default_branch]
      validate attribute_equals(:state, :examining)
    end

    update :record_facts do
      description "What the agent computed without a model, and the jobs it is about."
      accept [:facts, :examined_jobs]
      validate attribute_equals(:state, :examining)
    end

    update :finish_examination do
      accept [:examined_jobs]
      require_atomic? false
      change Builddoctor.Bench.Changes.Promote
      change transition_state(:examined)
    end

    update :report_wait do
      description "GitHub lets the agent read again at this time."
      accept [:waiting_until]
      validate attribute_equals(:state, :examining)
    end

    update :report_error do
      description "The agent could not go on; the third time frees the place."
      require_atomic? false
      change Builddoctor.Bench.Changes.CountError
    end

    destroy :remove do
      description "The Maintainer asked for it; costs stay on record without the project."
      require_atomic? false
      change {Builddoctor.Bench.Changes.RemoveAll, except: @measurable}
    end

    read :own do
      description "Audits of our own project, the newest first."
      filter expr(is_nil(slot) and repository in ^@measurable and state != :stopped)
      prepare build(sort: [inserted_at: :desc], limit: 4)
    end

    update :request_approval do
      accept [:examined_jobs]
      validate one_of(:repository, @measurable), message: "may only be examined"
      change transition_state(:awaiting_approval)
    end

    update :approve do
      validate one_of(:repository, @measurable), message: "may only be examined"
      change transition_state(:measuring)
    end

    update :approve_by_council do
      description "The council starts a trial it has cleared, within the limits of the owner."
      require_atomic? false
      validate one_of(:repository, @measurable), message: "may only be examined"
      validate Builddoctor.Bench.Validations.CouncilMayApprove
      change set_attribute(:council_done, true)
      change set_attribute(:council_approved_at, &DateTime.utc_now/0)
      change transition_state(:measuring)
    end

    update :leave_to_requester do
      description "The council does not start this trial; the Requester still may."
      change set_attribute(:council_done, true)
    end

    update :report_progress do
      description "What the running workflow does right now."
      accept [:live_number, :live_side, :live_jobs]
    end

    update :finish do
      change set_attribute(:live_jobs, [])
      change transition_state(:done)
    end

    update :stop do
      argument :reason, :string, allow_nil?: false, constraints: [max_length: 200]
      change set_attribute(:stop_reason, arg(:reason))
      change set_attribute(:slot, nil)
      change set_attribute(:planted_as, nil)
      change transition_state(:stopped)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action([
             :request_approval,
             :report_progress,
             :finish,
             :identify,
             :record_facts,
             :approve_by_council,
             :leave_to_requester,
             :finish_examination,
             :report_wait,
             :report_error
           ]) do
      authorize_if actor_attribute_equals(:role, :agent)
    end

    policy action([:plant, :examine_again]) do
      authorize_if always()
    end

    # Only from within finish_examination.
    policy action(:give_way) do
      forbid_if always()
    end

    policy action([:start, :examine_own, :approve, :remove]) do
      authorize_if actor_attribute_equals(:role, :requester)
    end

    policy action(:stop) do
      authorize_if actor_attribute_equals(:role, :requester)
      authorize_if actor_attribute_equals(:role, :agent)
    end
  end

  pub_sub do
    module BuilddoctorWeb.Endpoint
    prefix "audit"
    publish_all :update, [:id]
    publish_all :update, "forest"
    publish_all :create, "forest"
    publish_all :destroy, "forest"
  end

  attributes do
    uuid_primary_key :id
    attribute :repository, :string, allow_nil?: false, public?: true

    attribute :slot, :integer,
      public?: true,
      constraints: [min: 1, max: @places]

    # The repository in lower case while it holds a place, so that it holds only one.
    attribute :planted_as, :string

    attribute :waiting_until, :utc_datetime, public?: true
    attribute :by_visitor, :boolean, allow_nil?: false, default: false
    attribute :council_done, :boolean, allow_nil?: false, default: false
    attribute :council_approved_at, :utc_datetime
    attribute :errors, :integer, allow_nil?: false, default: 0
    attribute :jobs_total, :integer, public?: true, constraints: [min: 1, max: 1000]

    # A branch name that is safe in an address and in a command.
    attribute :default_branch, :string,
      allow_nil?: false,
      default: "main",
      public?: true,
      constraints: [match: ~r/\A[A-Za-z0-9][A-Za-z0-9._\/\-]{0,99}\z/]

    attribute :workflow_path, :string,
      allow_nil?: false,
      default: ".github/workflows/ci.yml",
      public?: true,
      constraints: [match: ~r/\A\.github\/workflows\/[A-Za-z0-9._\-]{1,100}\.ya?ml\z/]

    attribute :base_sha, :string,
      public?: true,
      constraints: [match: ~r/\A[0-9a-f]{40}\z/]

    attribute :examined_jobs, {:array, Builddoctor.Bench.Job},
      public?: true,
      constraints: [max_length: 10]

    attribute :facts, {:array, Builddoctor.Bench.Fact},
      public?: true,
      default: [],
      constraints: [max_length: 50]

    attribute :live_number, :integer, public?: true, constraints: [min: 1, max: 100]
    attribute :live_side, :atom, public?: true, constraints: [one_of: [:baseline, :trial]]

    attribute :live_jobs, {:array, Builddoctor.Bench.LiveJob},
      public?: true,
      default: [],
      constraints: [max_length: 10]

    attribute :stop_reason, :string, public?: true
    timestamps()
  end

  def measurable, do: @measurable
  def places, do: @places
  def max_errors, do: @max_errors

  relationships do
    belongs_to :replaces, Builddoctor.Bench.Audit
    has_many :runs, Builddoctor.Bench.Run
    has_many :trials, Builddoctor.Bench.Trial

    has_many :findings, Builddoctor.Bench.Finding do
      sort position: :asc
    end

    has_many :events, Builddoctor.Bench.AgentEvent
  end

  identities do
    identity :one_per_slot, [:slot], message: "error.slot.taken"

    identity :one_examining, [:repository],
      where: expr(state == :examining and is_nil(slot)),
      message: "error.again.running"

    identity :one_per_project, [:planted_as], message: "error.repository.planted"
  end
end
