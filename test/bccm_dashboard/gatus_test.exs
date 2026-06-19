defmodule BccmDashboard.GatusTest do
  use ExUnit.Case, async: true

  alias BccmDashboard.Dashboard.Section
  alias BccmDashboard.Gatus

  defp result(opts) do
    %{
      success: Keyword.get(opts, :success, true),
      timestamp: Keyword.get(opts, :timestamp, "2026-06-09T07:00:00Z"),
      duration: Keyword.get(opts, :duration),
      errors: Keyword.get(opts, :errors, [])
    }
  end

  defp endpoint(opts) do
    %{
      key: Keyword.get(opts, :key, "core_api"),
      name: Keyword.get(opts, :name, "API"),
      group: Keyword.get(opts, :group, "core"),
      results: Keyword.get(opts, :results, [])
    }
  end

  defp snapshot(endpoints) do
    %{endpoints: endpoints, updated_at: DateTime.utc_now(), error: nil}
  end

  describe "from_snapshot/1" do
    test "passes through section metadata" do
      section =
        Gatus.from_snapshot(%{endpoints: [], updated_at: nil, error: :missing_base_url})

      assert %Section{
               id: :service_health,
               title: "Service health",
               source: "Gatus",
               error: :missing_base_url,
               items: []
             } = section
    end

    test "successful latest result maps to HEALTHY / :passed" do
      ep = endpoint(results: [result(success: true, duration: 120_000_000)])
      [item] = Gatus.from_snapshot(snapshot([ep])).items

      assert item.status == :passed
      assert item.status_label == "HEALTHY"
    end

    test "failed latest result maps to DOWN / :failed" do
      ep = endpoint(results: [result(success: false, errors: ["timeout"])])
      [item] = Gatus.from_snapshot(snapshot([ep])).items

      assert item.status == :failed
      assert item.status_label == "DOWN"
    end

    test "uses the newest result (last in Gatus' chronological order), not the oldest" do
      # Gatus returns results oldest-first. A recovered endpoint has an old
      # failure followed by a recent success; the card must reflect the success.
      ep =
        endpoint(
          results: [
            result(success: false, errors: ["timeout"]),
            result(success: true, duration: 120_000_000)
          ]
        )

      [item] = Gatus.from_snapshot(snapshot([ep])).items

      assert item.status == :passed
      assert item.status_label == "HEALTHY"
    end

    test "no results yields UNKNOWN" do
      ep = endpoint(results: [])
      [item] = Gatus.from_snapshot(snapshot([ep])).items

      assert item.status == :unknown
      assert item.status_label == "UNKNOWN"
    end

    test "detail surfaces the response time on success" do
      ep =
        endpoint(group: "core", results: [result(success: true, duration: 250_000_000)])

      [item] = Gatus.from_snapshot(snapshot([ep])).items
      assert item.detail == "250ms"
    end

    test "response time under 1ms renders as <1ms" do
      ep = endpoint(results: [result(success: true, duration: 500_000)])
      [item] = Gatus.from_snapshot(snapshot([ep])).items
      assert item.detail =~ "<1ms"
    end

    test "response time >= 1s renders with one decimal" do
      ep = endpoint(results: [result(success: true, duration: 1_500_000_000)])
      [item] = Gatus.from_snapshot(snapshot([ep])).items
      assert item.detail =~ "1.5s"
    end

    test "detail surfaces the first error message on failure" do
      ep = endpoint(results: [result(success: false, errors: ["connection refused"])])
      [item] = Gatus.from_snapshot(snapshot([ep])).items
      assert item.detail == "connection refused"
    end

    test "long error message is truncated to 80 chars + ellipsis" do
      long = String.duplicate("x", 200)
      ep = endpoint(results: [result(success: false, errors: [long])])
      [item] = Gatus.from_snapshot(snapshot([ep])).items

      # detail is the error message truncated to 80 chars + "…"
      assert item.detail == String.duplicate("x", 80) <> "…"
    end

    test "detail is unaffected by the endpoint group" do
      ep =
        endpoint(group: nil, results: [result(success: true, duration: 100_000_000)])

      [item] = Gatus.from_snapshot(snapshot([ep])).items
      assert item.detail == "100ms"
    end

    test "name falls back to key when name is nil" do
      ep = endpoint(key: "fallback_key", name: nil, results: [])
      [item] = Gatus.from_snapshot(snapshot([ep])).items
      assert item.name == "fallback_key"
    end

    test "no dots are emitted for service-health cards" do
      ep =
        endpoint(
          results: [
            result(success: true, duration: 100_000_000),
            result(success: true, duration: 90_000_000)
          ]
        )

      [item] = Gatus.from_snapshot(snapshot([ep])).items
      assert item.dots == []
    end
  end
end
