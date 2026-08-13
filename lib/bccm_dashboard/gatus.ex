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
      refresh_ms: Map.get(snapshot, :refresh_ms),
      error: snapshot.error,
      # Sorted here rather than in the template: the section carries its items
      # in display order, and each source decides what that order is.
      # Alphabetical (after name fallbacks resolve) keeps every endpoint in the
      # same spot on the wall between polls — Gatus's own response order isn't
      # stable enough to rely on, and unlike build pipelines there's no useful
      # recency to sort by, since a healthy check that just ran is no more
      # interesting than one that ran a minute ago. Failures are called out by
      # the card fill and the viewport border, not by moving to the front.
      items:
        snapshot.endpoints
        |> Enum.map(&to_item/1)
        |> Enum.sort_by(& &1.name)
    }
  end

  defp to_item(endpoint) do
    latest = List.last(endpoint.results)
    status = status_for(latest)

    %Item{
      id: endpoint.key || endpoint.name,
      name: endpoint.name || endpoint.key || "?",
      status: status,
      status_label: status_label(status),
      detail: detail_for(status, endpoint, latest),
      detail_tone: nil,
      dots: []
    }
  end

  # A down endpoint leads with how long it's been down so triage starts with
  # "since when", then the error. The poller stamps `:down_since` once the
  # endpoint first goes red (see `BccmDashboard.Gatus.Poller`); a snapshot
  # built without it (e.g. in tests) just falls back to the error line.
  defp detail_for(:failed, endpoint, latest) do
    [down_label(Map.get(endpoint, :down_since)), latest_label(latest)]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      parts -> Enum.join(parts, " · ")
    end
  end

  defp detail_for(_status, _endpoint, latest), do: latest_label(latest)

  defp down_label(%DateTime{} = since) do
    seconds = DateTime.diff(DateTime.utc_now(), since)
    "down " <> format_duration(seconds)
  end

  defp down_label(_), do: nil

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

  # Coarse, human-readable elapsed time for a "down N" label. Only the
  # largest unit (plus minutes for the hour range) is shown — on a wall a
  # downtime counter reads better as "down 2h 5m" than "down 7521s".
  defp format_duration(seconds) when seconds < 60, do: "#{max(seconds, 0)}s"
  defp format_duration(seconds) when seconds < 3600, do: "#{div(seconds, 60)}m"

  defp format_duration(seconds) when seconds < 86_400 do
    "#{div(seconds, 3600)}h #{div(rem(seconds, 3600), 60)}m"
  end

  defp format_duration(seconds),
    do: "#{div(seconds, 86_400)}d #{div(rem(seconds, 86_400), 3600)}h"

  defp format_response_time(ns) do
    ms = div(ns, 1_000_000)

    cond do
      ms < 1 -> "<1ms"
      ms < 1000 -> "#{ms}ms"
      true -> :io_lib.format("~.1fs", [ms / 1000]) |> IO.iodata_to_binary()
    end
  end
end
