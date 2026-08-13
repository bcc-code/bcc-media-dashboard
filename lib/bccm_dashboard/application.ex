defmodule BccmDashboard.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        BccmDashboardWeb.Telemetry,
        {DNSCluster, query: Application.get_env(:bccm_dashboard, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: BccmDashboard.PubSub}
      ] ++
        pollers() ++
        [BccmDashboardWeb.Endpoint]

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

  # Tests start the pollers themselves, one per test, after installing HTTP
  # stubs — a boot-time poller would fire its first fetch before any stub
  # exists and race every test that reads a snapshot. Both `Poller.snapshot/0`
  # functions tolerate the process being absent, so a test that doesn't need
  # one gets an empty section rather than a crash.
  defp pollers do
    if Application.get_env(:bccm_dashboard, :start_pollers, true) do
      [
        {BccmDashboard.Semaphore.Poller, semaphore_poller_opts()},
        {BccmDashboard.Gatus.Poller, gatus_poller_opts()}
      ]
    else
      []
    end
  end

  defp semaphore_poller_opts do
    Application.get_env(:bccm_dashboard, BccmDashboard.Semaphore.Poller, [])
  end

  defp gatus_poller_opts do
    Application.get_env(:bccm_dashboard, BccmDashboard.Gatus.Poller, [])
  end
end
