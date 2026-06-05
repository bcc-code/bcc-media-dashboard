defmodule BccmDashboard.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BccmDashboardWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:bccm_dashboard, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: BccmDashboard.PubSub},
      # Start a worker by calling: BccmDashboard.Worker.start_link(arg)
      # {BccmDashboard.Worker, arg},
      # Start to serve requests, typically the last entry
      BccmDashboardWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BccmDashboard.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BccmDashboardWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
