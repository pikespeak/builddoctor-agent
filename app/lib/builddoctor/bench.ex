defmodule Builddoctor.Bench do
  @moduledoc "Audits, measured workflow runs, trials and agent events."
  use Ash.Domain, otp_app: :builddoctor, extensions: [AshJsonApi.Domain]

  alias Builddoctor.Bench.{
    AgentEvent,
    AiCall,
    Audit,
    Finding,
    Line,
    Notice,
    Picture,
    Review,
    Run,
    Trial
  }

  json_api do
    prefix "/api/json"

    routes do
      base_route "/audits", Audit do
        index :open, route: "/open"
        get :read, route: "/one/:id"
        patch :request_approval, route: "/:id/request_approval"
        patch :report_progress, route: "/:id/report_progress"
        patch :identify, route: "/:id/identify"
        patch :record_facts, route: "/:id/record_facts"
        patch :finish_examination, route: "/:id/finish_examination"
        patch :report_wait, route: "/:id/report_wait"
        patch :report_error, route: "/:id/report_error"
        patch :approve_by_council, route: "/:id/approve_by_council"
        patch :leave_to_requester, route: "/:id/leave_to_requester"
        patch :finish, route: "/:id/finish"
        patch :stop, route: "/:id/stop"
      end

      base_route "/trials", Trial do
        index :for_audit, route: "/for_audit/:audit_id"
        post :propose
        patch :evaluate, route: "/:id/evaluate"
        patch :decide, route: "/:id/decide"
      end

      base_route "/runs", Run do
        index :for_audit, route: "/for_audit/:audit_id"
        post :record
      end

      base_route "/findings", Finding do
        index :for_audit, route: "/for_audit/:audit_id"
        post :record
        patch :decide, route: "/:id/decide"
        patch :rate, route: "/:id/rate"
      end

      base_route "/reviews", Review do
        post :review_finding, route: "/finding"
        post :review_trial, route: "/trial"
      end

      base_route "/notices", Notice do
        post :notify
      end

      base_route "/lines", Line do
        index :for_audit, route: "/for_audit/:audit_id"
        post :record
        patch :decide, route: "/:id/decide"
      end

      base_route "/pictures", Picture do
        post :order
        route :post, "/choose_figure", :choose_figure
        patch :give_up, route: "/:id/give_up"
      end

      base_route "/events", AgentEvent do
        post :log
      end

      base_route "/ai_calls", AiCall do
        post :record
        route :get, "/budget_left", :budget_left
      end
    end
  end

  resources do
    resource Audit do
      define :start_audit, action: :start, args: [:repository, :base_sha]
      define :examine_own
      define :examine_again, args: [:audit_id]
      define :newer_audits, action: :newer, args: [:audit_id]
      define :place_of, args: [:project], not_found_error?: false
      define :report_wait
      define :expire_audits, action: :expire
      define :waiting_audits, action: :waiting
      define :plant_audit, action: :plant, args: [:project, :slot]
      define :planted_audits, action: :planted
      define :archived_audits, action: :archive
      define :audits_of_project, action: :of_project, args: [:repository]
      define :identify_audit, action: :identify
      define :record_facts, action: :record_facts
      define :finish_examination, action: :finish_examination
      define :report_audit_error, action: :report_error
      define :remove_audit, action: :remove
      define :get_audit, action: :read, get_by: [:id]
      define :own_audits, action: :own
      define :report_progress, action: :report_progress
      define :request_approval, action: :request_approval
      define :approve_audit, action: :approve
      define :approve_by_council
      define :leave_to_requester
      define :finish_audit, action: :finish
      define :stop_audit, action: :stop, args: [:reason]
    end

    resource Run do
      define :record_run, action: :record
      define :list_runs, action: :for_audit, args: [:audit_id]
    end

    resource Trial do
      define :propose_trial, action: :propose
      define :list_trials, action: :for_audit, args: [:audit_id]
      define :decide_trial, action: :decide
      define :evaluate_trial, action: :evaluate
    end

    resource AiCall do
      define :record_ai_call, action: :record
      define :budget_left, action: :budget_left
    end

    resource Finding do
      define :decide_finding, action: :decide
      define :rate_finding, action: :rate
      define :record_finding, action: :record
      define :list_findings, action: :for_audit, args: [:audit_id]
    end

    resource Review do
      define :review_finding
      define :review_trial
    end

    resource Notice do
      define :notify
      define :list_notices, action: :for_audit, args: [:audit_id]
    end

    resource Line do
      define :record_line, action: :record
      define :decide_line, action: :decide
      define :list_lines, action: :for_audit, args: [:audit_id]
    end

    resource Picture do
      define :order_picture, action: :order
      define :choose_figure, action: :choose_figure, args: [:audit_id, :figures]
      define :get_picture, action: :read, get_by: [:id]
      define :add_picture_still, action: :add_still, args: [:bytes]
      define :add_picture_animation, action: :add_animation, args: [:bytes]
      define :give_up_picture, action: :give_up
      define :list_pictures, action: :for_audit, args: [:audit_id]
      define :done_picture, action: :done, args: [:audit_id, :place], not_found_error?: false
    end

    resource AgentEvent do
      define :log_event, action: :log
      define :list_events, action: :for_audit, args: [:audit_id]
    end
  end
end
