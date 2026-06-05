defmodule BccmDashboard.Semaphore do
  @moduledoc """
  Public API for the Semaphore CI integration.

  Exposes the most recently fetched snapshot of pipeline statuses and a PubSub
  topic that LiveViews subscribe to for live updates.
  """

  alias BccmDashboard.Semaphore.Poller

  @topic "semaphore:status"

  @type status_dot :: %{state: String.t() | nil, result: String.t() | nil, color: atom()}
  @type project_status :: %{id: String.t(), name: String.t(), dots: [status_dot()]}
  @type snapshot :: %{
          projects: [project_status()],
          updated_at: DateTime.t() | nil,
          error: term() | nil
        }

  @spec topic() :: String.t()
  def topic, do: @topic

  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(BccmDashboard.PubSub, @topic)

  @spec snapshot() :: snapshot()
  def snapshot, do: Poller.snapshot()

  @spec refresh() :: :ok
  def refresh, do: Poller.refresh()
end
