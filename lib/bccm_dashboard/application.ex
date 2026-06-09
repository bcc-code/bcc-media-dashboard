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
      {BccmDashboard.Semaphore.Poller, semaphore_poller_opts()},
      {BccmDashboard.Gatus.Poller, gatus_poller_opts()},
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

  defp semaphore_poller_opts do
    Application.get_env(:bccm_dashboard, BccmDashboard.Semaphore.Poller, [])
  end

  defp gatus_poller_opts do
    Application.get_env(:bccm_dashboard, BccmDashboard.Gatus.Poller, [])
  end
end
