defmodule Builddoctor.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    BuilddoctorWeb.Health.setup()

    children = [
      BuilddoctorWeb.Telemetry,
      Builddoctor.Repo,
      Builddoctor.VisitorCount,
      {Oban,
       AshOban.config(
         Application.fetch_env!(:builddoctor, :ash_domains),
         Application.fetch_env!(:builddoctor, Oban)
       )},
      # Start a worker by calling: Builddoctor.Worker.start_link(arg)
      # {Builddoctor.Worker, arg},
      # Start to serve requests, typically the last entry
      {DNSCluster, query: Application.get_env(:builddoctor, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Builddoctor.PubSub},
      BuilddoctorWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Builddoctor.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BuilddoctorWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
