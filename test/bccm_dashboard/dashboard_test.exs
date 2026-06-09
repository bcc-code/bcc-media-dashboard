defmodule BccmDashboard.DashboardTest do
  use ExUnit.Case, async: true

  alias BccmDashboard.Dashboard
  alias BccmDashboard.Dashboard.{Item, Section}

  defp section(items) do
    %Section{id: :test, title: "Test", items: items}
  end

  defp item(status) do
    %Item{id: "x", name: "x", status: status}
  end

  describe "overall_status/1" do
    test "no sections → :unknown" do
      assert Dashboard.overall_status([]) == :unknown
    end

    test "sections with no items → :unknown" do
      assert Dashboard.overall_status([section([])]) == :unknown
    end

    test "all passed → :passed" do
      assert Dashboard.overall_status([section([item(:passed), item(:passed)])]) == :passed
    end

    test "passed + unknown still counts as :passed" do
      assert Dashboard.overall_status([section([item(:passed), item(:unknown)])]) == :passed
    end

    test "any single failed item flips the whole dashboard" do
      sections = [
        section([item(:passed), item(:passed)]),
        section([item(:passed), item(:failed)])
      ]

      assert Dashboard.overall_status(sections) == :failed
    end

    test "failed beats running (failure dominates)" do
      sections = [section([item(:running), item(:failed)])]
      assert Dashboard.overall_status(sections) == :failed
    end

    test "running with no failures → :running" do
      assert Dashboard.overall_status([section([item(:passed), item(:running)])]) == :running
    end

    test "pending without running or failed → :unknown (not :passed)" do
      # Pending isn't in the passed/unknown set, so the green branch doesn't fire.
      assert Dashboard.overall_status([section([item(:pending)])]) == :unknown
    end

    test "items aggregate across sections" do
      sections = [section([item(:passed)]), section([item(:failed)])]
      assert Dashboard.overall_status(sections) == :failed
    end
  end
end
