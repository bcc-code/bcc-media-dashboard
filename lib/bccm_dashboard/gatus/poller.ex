defmodule BccmDashboard.Gatus.Poller do
  @moduledoc """
  Periodically refreshes the Gatus endpoint snapshot and broadcasts it over
  PubSub. Same pattern as `BccmDashboard.Semaphore.Poller`: the GenServer is
  the single source of truth, the LiveView reads the current snapshot on
  mount and reacts to broadcasts thereafter.

  One HTTP call returns every endpoint, so there's no fan-out — just a
  filter + trim before the snapshot is shipped.
  """

  use GenServer

  require Logger

  alias BccmDashboard.Gatus.Client

  @default_refresh_ms 30_000
  @default_max_endpoints 24

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the latest snapshot. Wrapped to tolerate the poller not yet being
  up (boot, dev hot-reload) — the dashboard mounts on an empty snapshot and
  self-heals on the next tick.
  """
  def snapshot do
    GenServer.call(__MODULE__, :snapshot)
  catch
    :exit, _ -> empty_snapshot()
  end

  @doc "Trigger an out-of-band refresh. No-op if the poller isn't running."
  def refresh do
    GenServer.cast(__MODULE__, :refresh)
  catch
    :exit, _ -> :ok
  end

  @impl true
  def init(opts) do
    state = %{
      refresh_ms: Keyword.get(opts, :refresh_ms, @default_refresh_ms),
      groups: Keyword.get(opts, :groups, []),
      max_endpoints: Keyword.get(opts, :max_endpoints, @default_max_endpoints),
      snapshot: empty_snapshot()
    }

    {:ok, state, {:continue, :first_fetch}}
  end

  @impl true
  def handle_continue(:first_fetch, state) do
    {:noreply, do_refresh(state)}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, state.snapshot, state}
  end

  @impl true
  def handle_cast(:refresh, state) do
    {:noreply, do_refresh(state)}
  end

  @impl true
  def handle_info(:tick, state) do
    {:noreply, do_refresh(state)}
  end

  defp do_refresh(state) do
    snapshot = build_snapshot(state)

    Phoenix.PubSub.broadcast(
      BccmDashboard.PubSub,
      BccmDashboard.Gatus.topic(),
      {:gatus_snapshot, snapshot}
    )

    schedule_tick(state.refresh_ms)
    %{state | snapshot: snapshot}
  end

  defp schedule_tick(ms) do
    Process.send_after(self(), :tick, ms)
  end

  defp build_snapshot(state) do
    case Client.list_endpoint_statuses() do
      {:ok, endpoints} ->
        endpoints =
          endpoints
          |> filter_by_groups(state.groups)
          |> Enum.take(state.max_endpoints)

        %{endpoints: endpoints, updated_at: DateTime.utc_now(), error: nil}

      {:error, reason} ->
        Logger.error("Gatus endpoint fetch failed: #{inspect(reason)}")
        %{empty_snapshot() | error: reason, updated_at: DateTime.utc_now()}
    end
  end

  defp filter_by_groups(endpoints, []), do: endpoints

  defp filter_by_groups(endpoints, groups) when is_list(groups) do
    allowed = MapSet.new(groups)
    Enum.filter(endpoints, fn endpoint -> MapSet.member?(allowed, endpoint.group) end)
  end

  defp empty_snapshot do
    %{endpoints: [], updated_at: nil, error: nil}
  end
end
