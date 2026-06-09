defmodule BccmDashboard.Semaphore do
  @moduledoc """
  Public API for the Semaphore CI source.

  Exposes the latest snapshot as a `%Dashboard.Section{}` plus a PubSub topic
  the dashboard subscribes to for live updates.
  """

  alias BccmDashboard.Dashboard.{Item, Section}
  alias BccmDashboard.Semaphore.Poller

  @topic "semaphore:status"
  @section_id :build_pipelines
  @section_title "Build pipelines"
  @section_source "Semaphore"

  @spec topic() :: String.t()
  def topic, do: @topic

  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(BccmDashboard.PubSub, @topic)

  @spec refresh() :: :ok
  def refresh, do: Poller.refresh()

  @doc """
  Returns the current Semaphore snapshot wrapped as a dashboard section.
  """
  @spec section() :: Section.t()
  def section, do: from_snapshot(Poller.snapshot())

  @doc """
  Builds a `%Section{}` from a raw snapshot map. Split from `section/0` so
  the mapping logic is testable without a running poller.
  """
  @spec from_snapshot(map()) :: Section.t()
  def from_snapshot(snapshot) do
    %Section{
      id: @section_id,
      title: @section_title,
      source: @section_source,
      updated_at: snapshot.updated_at,
      error: snapshot.error,
      items: Enum.map(snapshot.projects, &to_item/1)
    }
  end

  defp to_item(project) do
    status = project_status(project)

    %Item{
      id: project.id || project.name,
      name: project.name,
      status: status,
      status_label: humanize_status(status),
      detail: detail_for(project),
      detail_tone: detail_tone_for(project),
      dots: Enum.map(project.dots, &to_dot/1)
    }
  end

  defp project_status(%{dots: [%{color: color} | _]}), do: color
  defp project_status(_), do: :unknown

  defp detail_for(%{dots: []}), do: "no recent runs"

  defp detail_for(project) do
    latest = project[:latest]
    current_seconds = current_seconds(latest)

    [
      current_label(latest, current_seconds),
      avg_label(current_seconds, project[:avg_run_seconds])
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      parts -> Enum.join(parts, " · ")
    end
  end

  defp current_seconds(%{state: "RUNNING", running_at: started}) when is_integer(started),
    do: System.system_time(:second) - started

  defp current_seconds(%{running_at: started, done_at: finished})
       when is_integer(started) and is_integer(finished),
       do: finished - started

  defp current_seconds(_), do: nil

  defp current_label(%{state: "RUNNING"}, seconds) when is_integer(seconds),
    do: "Running " <> format_duration(seconds)

  defp current_label(%{}, seconds) when is_integer(seconds),
    do: "Ran " <> format_duration(seconds)

  defp current_label(_, _), do: nil

  # Hide avg when it's within ~25% of current — at that point the second
  # number is just noise. Showing it only when divergent trains the eye to
  # read "avg appearing = off-pace".
  defp avg_label(current, avg)
       when is_integer(current) and is_integer(avg) and avg > 0 do
    if abs(current - avg) * 4 > avg, do: "avg " <> format_duration(avg)
  end

  defp avg_label(nil, avg) when is_integer(avg) and avg > 0,
    do: "avg " <> format_duration(avg)

  defp avg_label(_, _), do: nil

  # Warn when the current run is meaningfully slower than the avg — same 25%
  # threshold as the avg label, so the tint and the second number appear
  # together. A run finishing *under* avg is good news, not a warning.
  defp detail_tone_for(project) do
    case {current_seconds(project[:latest]), project[:avg_run_seconds]} do
      {current, avg} when is_integer(current) and is_integer(avg) and avg > 0 ->
        if current * 4 > avg * 5, do: :warning

      _ ->
        nil
    end
  end

  defp format_duration(seconds) when seconds < 0, do: "0s"
  defp format_duration(seconds) when seconds < 60, do: "#{seconds}s"

  defp format_duration(seconds) when seconds < 3600 do
    "#{div(seconds, 60)}m"
  end

  defp format_duration(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    "#{hours}h #{minutes}m"
  end

  defp to_dot(dot) do
    %{
      color: dot.color,
      label: humanize_dot(dot),
      duration_seconds: dot.duration_seconds
    }
  end

  defp humanize_status(status) do
    status |> Atom.to_string() |> String.upcase()
  end

  defp humanize_dot(%{state: "DONE", result: result, duration_seconds: s})
       when is_binary(result) and is_integer(s),
       do: "#{result} (#{format_duration(s)})"

  defp humanize_dot(%{state: "DONE", result: result}) when is_binary(result), do: result
  defp humanize_dot(%{state: state}) when is_binary(state), do: state
  defp humanize_dot(_), do: "UNKNOWN"
end
