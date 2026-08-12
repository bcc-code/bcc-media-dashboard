defmodule BccmDashboard.SemaphoreTest do
  use ExUnit.Case, async: true

  alias BccmDashboard.Dashboard.Section
  alias BccmDashboard.Semaphore

  defp passed_dot(duration \\ 60),
    do: %{state: "DONE", result: "PASSED", color: :passed, duration_seconds: duration}

  defp failed_dot, do: %{state: "DONE", result: "FAILED", color: :failed, duration_seconds: 30}

  defp running_dot,
    do: %{state: "RUNNING", result: nil, color: :running, duration_seconds: 45}

  defp pipeline(state, result, running_at, done_at) do
    %{state: state, result: result, branch_name: "main", running_at: running_at, done_at: done_at}
  end

  defp snapshot(projects) do
    %{projects: projects, updated_at: DateTime.utc_now(), error: nil}
  end

  describe "from_snapshot/1" do
    test "passes through section metadata" do
      section = Semaphore.from_snapshot(%{projects: [], updated_at: nil, error: :missing_token})

      assert %Section{
               id: :build_pipelines,
               title: "Build pipelines",
               source: "Semaphore",
               error: :missing_token,
               items: []
             } = section
    end

    test "status comes from the most recent dot" do
      project = %{
        id: "p1",
        name: "alpha",
        dots: [passed_dot(), failed_dot()],
        latest: pipeline("DONE", "PASSED", 100, 160),
        avg_run_seconds: 60,
        error: nil
      }

      [item] = Semaphore.from_snapshot(snapshot([project])).items
      assert item.status == :passed
      assert item.status_label == "PASSED"
    end

    test "running status surfaces the RUNNING color" do
      project = %{
        id: "p1",
        name: "alpha",
        dots: [running_dot(), passed_dot()],
        latest: pipeline("RUNNING", nil, System.system_time(:second) - 10, nil),
        avg_run_seconds: 60,
        error: nil
      }

      [item] = Semaphore.from_snapshot(snapshot([project])).items
      assert item.status == :running
    end

    test "empty dots yields unknown status and 'no recent runs' detail" do
      project = %{
        id: "p1",
        name: "alpha",
        dots: [],
        latest: nil,
        avg_run_seconds: nil,
        error: nil
      }

      [item] = Semaphore.from_snapshot(snapshot([project])).items
      assert item.status == :unknown
      assert item.detail == "no recent runs"
    end

    test "detail includes 'Ran' duration; avg hidden when within ~25%" do
      project = %{
        id: "p1",
        name: "alpha",
        dots: [passed_dot()],
        # Ran for 60s, avg 60s — avg should be suppressed.
        latest: pipeline("DONE", "PASSED", 1000, 1060),
        avg_run_seconds: 60,
        error: nil
      }

      [item] = Semaphore.from_snapshot(snapshot([project])).items
      assert item.detail == "Ran 1m"
      assert item.detail_tone == nil
    end

    test "warning tone when current run is meaningfully slower than avg" do
      project = %{
        id: "p1",
        name: "alpha",
        dots: [passed_dot()],
        # Ran 100s vs avg 60s — 25% threshold tripped, warning + avg shown.
        latest: pipeline("DONE", "PASSED", 1000, 1100),
        avg_run_seconds: 60,
        error: nil
      }

      [item] = Semaphore.from_snapshot(snapshot([project])).items
      assert item.detail == "Ran 1m · avg 1m"
      assert item.detail_tone == :warning
    end

    test "no warning when current is faster than avg" do
      project = %{
        id: "p1",
        name: "alpha",
        dots: [passed_dot()],
        # Ran 30s, avg 120s — under-pace shouldn't warn.
        latest: pipeline("DONE", "PASSED", 1000, 1030),
        avg_run_seconds: 120,
        error: nil
      }

      [item] = Semaphore.from_snapshot(snapshot([project])).items
      assert item.detail_tone == nil
    end

    test "dots carry humanized labels with duration" do
      project = %{
        id: "p1",
        name: "alpha",
        dots: [passed_dot(75), failed_dot()],
        latest: pipeline("DONE", "PASSED", 0, 75),
        avg_run_seconds: 60,
        error: nil
      }

      [item] = Semaphore.from_snapshot(snapshot([project])).items
      assert [first, second] = item.dots
      assert first.label == "PASSED (1m)"
      assert second.label == "FAILED (30s)"
    end

    test "projects are ordered most recently run first" do
      projects =
        for {name, running_at} <- [{"old", 100}, {"newest", 900}, {"middle", 500}] do
          %{
            id: name,
            name: name,
            dots: [passed_dot()],
            latest: pipeline("DONE", "PASSED", running_at, running_at + 60),
            avg_run_seconds: 60,
            error: nil
          }
        end

      items = Semaphore.from_snapshot(snapshot(projects)).items
      assert Enum.map(items, & &1.name) == ["newest", "middle", "old"]
    end

    test "ordering follows run time, not when the pipeline was queued" do
      # "queued" was created most recently but has been sitting in the queue;
      # "ran" was created earlier and has since finished. The one that actually
      # ran should come first.
      queued = %{
        id: "queued",
        name: "queued",
        dots: [],
        latest: %{
          state: "QUEUING",
          result: nil,
          branch_name: "main",
          created_at: 900,
          running_at: nil,
          done_at: nil
        },
        avg_run_seconds: nil,
        error: nil
      }

      ran = %{
        id: "ran",
        name: "ran",
        dots: [passed_dot()],
        latest: %{
          state: "DONE",
          result: "PASSED",
          branch_name: "main",
          created_at: 100,
          running_at: 950,
          done_at: 1000
        },
        avg_run_seconds: 50,
        error: nil
      }

      items = Semaphore.from_snapshot(snapshot([queued, ran])).items
      assert Enum.map(items, & &1.name) == ["ran", "queued"]
    end

    test "projects with no runs sort last" do
      idle = %{id: "idle", name: "idle", dots: [], latest: nil, avg_run_seconds: nil, error: nil}

      active = %{
        id: "active",
        name: "active",
        dots: [passed_dot()],
        latest: pipeline("DONE", "PASSED", 100, 160),
        avg_run_seconds: 60,
        error: nil
      }

      items = Semaphore.from_snapshot(snapshot([idle, active])).items
      assert Enum.map(items, & &1.name) == ["active", "idle"]
    end

    test "at most six projects are rendered, keeping the most recent" do
      projects =
        for i <- 1..9 do
          %{
            id: "p#{i}",
            name: "project-#{i}",
            dots: [passed_dot()],
            latest: pipeline("DONE", "PASSED", i * 100, i * 100 + 60),
            avg_run_seconds: 60,
            error: nil
          }
        end

      items = Semaphore.from_snapshot(snapshot(projects)).items

      assert length(items) == 6

      assert Enum.map(items, & &1.name) == [
               "project-9",
               "project-8",
               "project-7",
               "project-6",
               "project-5",
               "project-4"
             ]
    end

    test "name falls back to id when name is nil" do
      # Mirrors what the poller emits for a project that errored out.
      project = %{
        id: nil,
        name: "?",
        dots: [],
        latest: nil,
        avg_run_seconds: nil,
        error: :timeout
      }

      [item] = Semaphore.from_snapshot(snapshot([project])).items
      assert item.name == "?"
    end
  end
end
