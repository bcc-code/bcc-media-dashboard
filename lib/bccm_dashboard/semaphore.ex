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
  def section do
    snapshot = Poller.snapshot()

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
      dots: Enum.map(project.dots, &to_dot/1)
    }
  end

  defp project_status(%{dots: [%{color: color} | _]}), do: color
  defp project_status(_), do: :unknown

  defp detail_for(%{dots: []}), do: "no recent runs"
  defp detail_for(_), do: nil

  defp to_dot(dot) do
    %{color: dot.color, label: humanize_dot(dot)}
  end

  defp humanize_status(status) do
    status |> Atom.to_string() |> String.upcase()
  end

  defp humanize_dot(%{state: "DONE", result: result}) when is_binary(result), do: result
  defp humanize_dot(%{state: state}) when is_binary(state), do: state
  defp humanize_dot(_), do: "UNKNOWN"
end
