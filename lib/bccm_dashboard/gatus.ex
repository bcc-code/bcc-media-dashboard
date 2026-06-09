defmodule BccmDashboard.Gatus do
  @moduledoc """
  Public API for the Gatus service-health source.

  Exposes the latest snapshot as a `%Dashboard.Section{}` plus a PubSub topic
  the dashboard subscribes to for live updates.
  """

  alias BccmDashboard.Dashboard.{Item, Section}
  alias BccmDashboard.Gatus.Poller

  @topic "gatus:status"
  @section_id :service_health
  @section_title "Service health"
  @section_source "Gatus"

  @spec topic() :: String.t()
  def topic, do: @topic

  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Phoenix.PubSub.subscribe(BccmDashboard.PubSub, @topic)

  @spec refresh() :: :ok
  def refresh, do: Poller.refresh()

  @doc """
  Returns the current Gatus snapshot wrapped as a dashboard section.
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
      items: Enum.map(snapshot.endpoints, &to_item/1)
    }
  end

  defp to_item(endpoint) do
    latest = List.first(endpoint.results)
    status = status_for(latest)

    %Item{
      id: endpoint.key || endpoint.name,
      name: endpoint.name || endpoint.key || "?",
      status: status,
      status_label: status_label(status),
      detail: latest_label(latest),
      detail_tone: nil,
      dots: []
    }
  end

  defp status_for(nil), do: :unknown
  defp status_for(%{success: true}), do: :passed
  defp status_for(%{success: false}), do: :failed

  defp status_label(:passed), do: "HEALTHY"
  defp status_label(:failed), do: "DOWN"
  defp status_label(_), do: "UNKNOWN"

  defp latest_label(nil), do: nil

  defp latest_label(%{success: false, errors: [first | _]}) when is_binary(first),
    do: truncate(first, 80)

  defp latest_label(%{duration: ns}) when is_integer(ns) and ns > 0,
    do: format_response_time(ns)

  defp latest_label(_), do: nil

  defp truncate(text, max) when byte_size(text) > max,
    do: binary_part(text, 0, max) <> "…"

  defp truncate(text, _), do: text

  defp format_response_time(ns) do
    ms = div(ns, 1_000_000)

    cond do
      ms < 1 -> "<1ms"
      ms < 1000 -> "#{ms}ms"
      true -> :io_lib.format("~.1fs", [ms / 1000]) |> IO.iodata_to_binary()
    end
  end
end
