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
      snapshot: empty_snapshot(),
      # endpoint key => DateTime it first went down, carried across refreshes
      # so the "down N" label keeps counting from the real outage start even
      # as old check results scroll out of Gatus' bounded result window.
      down_since: %{}
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
    {snapshot, down_since} = build_snapshot(state)

    Phoenix.PubSub.broadcast(
      BccmDashboard.PubSub,
      BccmDashboard.Gatus.topic(),
      {:gatus_snapshot, snapshot}
    )

    schedule_tick(state.refresh_ms)
    %{state | snapshot: snapshot, down_since: down_since}
  end

  defp schedule_tick(ms) do
    Process.send_after(self(), :tick, ms)
  end

  defp build_snapshot(state) do
    case Client.list_endpoint_statuses() do
      {:ok, endpoints} ->
        {endpoints, down_since} =
          endpoints
          |> filter_by_groups(state.groups)
          |> Enum.take(state.max_endpoints)
          |> track_downtime(state.down_since)

        snapshot = %{
          endpoints: endpoints,
          updated_at: DateTime.utc_now(),
          refresh_ms: state.refresh_ms,
          error: nil
        }

        {snapshot, down_since}

      {:error, reason} ->
        Logger.error("Gatus endpoint fetch failed: #{inspect(reason)}")

        snapshot = %{
          empty_snapshot()
          | error: reason,
            updated_at: DateTime.utc_now(),
            refresh_ms: state.refresh_ms
        }

        # Keep the existing down-since anchors across a transient fetch error;
        # the section shows the error rather than items, so they're just held.
        {snapshot, state.down_since}
    end
  end

  # Stamp each endpoint with the time it first went down and carry those
  # anchors forward. An endpoint seen down for the first time is anchored to
  # the start of its trailing failure streak (or now, if that's unknown);
  # once anchored the timestamp sticks until it recovers, so the outage clock
  # doesn't reset on every poll. Recovered endpoints drop out of the map.
  defp track_downtime(endpoints, previous) do
    Enum.map_reduce(endpoints, %{}, fn endpoint, acc ->
      key = endpoint.key || endpoint.name

      if endpoint_down?(endpoint) do
        since = Map.get(previous, key) || streak_start(endpoint.results) || DateTime.utc_now()
        {Map.put(endpoint, :down_since, since), Map.put(acc, key, since)}
      else
        {Map.put(endpoint, :down_since, nil), acc}
      end
    end)
  end

  defp endpoint_down?(%{results: results}) do
    case List.last(results) do
      %{success: false} -> true
      _ -> false
    end
  end

  # Walk back from the newest result over the contiguous run of failures and
  # return when that run began. Gatus returns results oldest-first, so the
  # streak lives at the tail of the list.
  defp streak_start(results) do
    results
    |> Enum.reverse()
    |> Enum.take_while(&(&1.success == false))
    |> List.last()
    |> case do
      %{timestamp: ts} when is_binary(ts) -> parse_timestamp(ts)
      _ -> nil
    end
  end

  defp parse_timestamp(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end

  defp filter_by_groups(endpoints, []), do: endpoints

  defp filter_by_groups(endpoints, groups) when is_list(groups) do
    allowed = MapSet.new(groups)
    Enum.filter(endpoints, fn endpoint -> MapSet.member?(allowed, endpoint.group) end)
  end

  defp empty_snapshot do
    %{endpoints: [], updated_at: nil, refresh_ms: @default_refresh_ms, error: nil}
  end
end
