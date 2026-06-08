defmodule BccmDashboard.Semaphore.Poller do
  @moduledoc """
  Periodically refreshes the Semaphore CI pipeline snapshot and broadcasts it
  over PubSub. LiveViews read the current snapshot on mount and then react to
  the broadcasts; the GenServer is the single source of truth.

  Per-project pipeline fetches run concurrently via `Task.async_stream/3` so a
  full refresh costs roughly one round-trip rather than `n` sequential ones.
  """

  use GenServer

  require Logger

  alias BccmDashboard.Semaphore.Client

  @default_refresh_ms 60_000
  @default_window_days 7
  @default_max_projects 12
  @default_max_pipelines 16
  @http_concurrency 8
  @branches ["main", "master"]

  # Map (state, result) -> a coarse semantic color used by the UI. The Go
  # service emits palette indices for a tiny LED matrix; here we have a real
  # display, so we surface meaningful atoms instead.
  @result_color %{
    "PASSED" => :passed,
    "FAILED" => :failed,
    "STOPPED" => :stopped,
    "CANCELED" => :canceled
  }

  @state_color %{
    "RUNNING" => :running,
    "QUEUING" => :pending,
    "PENDING" => :pending,
    "STOPPING" => :stopping
  }

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the latest snapshot. Safe to call before the first fetch, and also
  before the poller process itself has started (returns an empty snapshot in
  that case so the dashboard can mount and self-heal once the supervisor
  catches up).
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

  @doc "Compute the semantic color for a (state, result) tuple."
  def color_for("DONE", result), do: Map.get(@result_color, result, :unknown)
  def color_for(state, _result), do: Map.get(@state_color, state, :unknown)

  @impl true
  def init(opts) do
    state = %{
      refresh_ms: Keyword.get(opts, :refresh_ms, @default_refresh_ms),
      window_days: Keyword.get(opts, :window_days, @default_window_days),
      max_projects: Keyword.get(opts, :max_projects, @default_max_projects),
      max_pipelines: Keyword.get(opts, :max_pipelines, @default_max_pipelines),
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
      BccmDashboard.Semaphore.topic(),
      {:semaphore_snapshot, snapshot}
    )

    schedule_tick(state.refresh_ms)
    %{state | snapshot: snapshot}
  end

  defp schedule_tick(ms) do
    Process.send_after(self(), :tick, ms)
  end

  defp build_snapshot(state) do
    case Client.list_projects() do
      {:ok, projects} ->
        cutoff = unix_now() - state.window_days * 24 * 60 * 60

        projects
        |> Enum.take(state.max_projects)
        |> fetch_pipelines(state.max_pipelines, cutoff)
        |> then(fn project_statuses ->
          %{projects: project_statuses, updated_at: DateTime.utc_now(), error: nil}
        end)

      {:error, reason} ->
        Logger.error("Semaphore project list failed: #{inspect(reason)}")
        %{empty_snapshot() | error: reason, updated_at: DateTime.utc_now()}
    end
  end

  defp fetch_pipelines(projects, max_pipelines, cutoff) do
    projects
    |> Task.async_stream(
      fn project ->
        case fetch_default_branch_pipelines(project.id, cutoff) do
          {:ok, pipelines} ->
            pipelines = Enum.take(pipelines, max_pipelines)

            %{
              id: project.id,
              name: project.name,
              dots: Enum.map(pipelines, &to_dot/1),
              latest: List.first(pipelines),
              avg_run_seconds: average_passed_duration(pipelines),
              error: nil
            }

          {:error, reason} ->
            Logger.warning("Semaphore pipelines failed for #{project.name}: #{inspect(reason)}")

            %{
              id: project.id,
              name: project.name,
              dots: [],
              latest: nil,
              avg_run_seconds: nil,
              error: reason
            }
        end
      end,
      max_concurrency: @http_concurrency,
      timeout: 30_000,
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:ok, result} ->
        result

      {:exit, reason} ->
        %{
          id: nil,
          name: "?",
          dots: [],
          latest: nil,
          avg_run_seconds: nil,
          error: reason
        }
    end)
  end

  defp average_passed_duration(pipelines) do
    durations =
      pipelines
      |> Enum.filter(fn p ->
        p.state == "DONE" and p.result == "PASSED" and
          is_integer(p.running_at) and is_integer(p.done_at)
      end)
      |> Enum.map(fn p -> p.done_at - p.running_at end)

    case durations do
      [] -> nil
      _ -> div(Enum.sum(durations), length(durations))
    end
  end

  # Probe `main`, then `master`. Semaphore's project list doesn't tell us which
  # one a given repo uses, and projects that don't push to either (forks, CI
  # sandbox projects) just show up empty rather than as noise from feature
  # branches.
  defp fetch_default_branch_pipelines(project_id, cutoff) do
    Enum.reduce_while(@branches, {:ok, []}, fn branch, acc ->
      case Client.list_pipelines(project_id, created_after: cutoff, branch_name: branch) do
        {:ok, []} -> {:cont, acc}
        {:ok, pipelines} -> {:halt, {:ok, pipelines}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp to_dot(pipeline) do
    %{
      state: pipeline.state,
      result: pipeline.result,
      color: color_for(pipeline.state, pipeline.result),
      duration_seconds: dot_duration(pipeline)
    }
  end

  defp dot_duration(%{state: "RUNNING", running_at: started}) when is_integer(started),
    do: System.system_time(:second) - started

  defp dot_duration(%{running_at: started, done_at: finished})
       when is_integer(started) and is_integer(finished),
       do: finished - started

  defp dot_duration(_), do: nil

  defp empty_snapshot do
    %{projects: [], updated_at: nil, error: nil}
  end

  defp unix_now, do: System.system_time(:second)
end
