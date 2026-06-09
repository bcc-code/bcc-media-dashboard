defmodule BccmDashboard.Dashboard do
  @moduledoc ~S"""
  Shared shapes the operations dashboard renders.

  A page is a list of `%Section{}`s. Each section is one source of truth
  (Semaphore, service health, deployments, ...) and contains a list of
  `%Item{}`s. `BccmDashboardWeb.DashboardLive` only knows how to paint these
  shapes, so adding a new source means writing a builder that yields a
  `%Section{}` — no template changes required.

  ## Adding a new section

  Use the Semaphore integration (`BccmDashboard.Semaphore` +
  `BccmDashboard.Semaphore.Poller`) as the canonical reference. The pattern is:

  ### 1. Fetch + cache the data

  Most external APIs are too slow to call on every page load, so wrap the
  fetch in a `GenServer` that polls on an interval, holds the latest snapshot
  in its state, and broadcasts on PubSub when it changes. Anything cheap and
  in-process can skip the GenServer and build the section inline.

      defmodule BccmDashboard.MySource.Poller do
        use GenServer

        @topic "my_source:status"

        def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
        def snapshot, do: GenServer.call(__MODULE__, :snapshot)
        def refresh, do: GenServer.cast(__MODULE__, :refresh)

        @impl true
        def init(_), do: {:ok, %{snapshot: nil}, {:continue, :fetch}}

        @impl true
        def handle_continue(:fetch, state), do: {:noreply, do_fetch(state)}

        # ...handle_call(:snapshot, ...), handle_cast(:refresh, ...), handle_info(:tick, ...)

        defp do_fetch(state) do
          snapshot = build_snapshot()
          Phoenix.PubSub.broadcast(BccmDashboard.PubSub, @topic, {:my_source_snapshot, snapshot})
          Process.send_after(self(), :tick, 60_000)
          %{state | snapshot: snapshot}
        end
      end

  Wrap `GenServer.call/2` with `catch :exit, _ -> empty_snapshot()` so the
  LiveView can mount before the poller is up (matters during boot + dev
  hot-reload, which doesn't restart the supervision tree).

  ### 2. Build a `%Section{}`

  Add a context module that converts the cached data into the shape the
  LiveView renders. Keep all source-specific UI knowledge (status labels,
  fallback text, dot meanings) here so the LiveView stays generic.

      defmodule BccmDashboard.MySource do
        alias BccmDashboard.Dashboard.{Item, Section}
        alias BccmDashboard.MySource.Poller

        @topic "my_source:status"

        def subscribe, do: Phoenix.PubSub.subscribe(BccmDashboard.PubSub, @topic)
        def refresh, do: Poller.refresh()

        def section do
          snapshot = Poller.snapshot()

          %Section{
            id: :my_source,
            title: "My source",
            source: "Provider name",
            updated_at: snapshot.updated_at,
            error: snapshot.error,
            items: Enum.map(snapshot.things, &to_item/1)
          }
        end

        defp to_item(thing) do
          %Item{
            id: thing.id,
            name: thing.name,
            status: status_for(thing),  # one of Item.status() atoms
            detail: "optional secondary line",
            dots: []                    # optional run-history dots
          }
        end
      end

  Item status atoms map to colors in `BccmDashboardWeb.DashboardLive` (see
  `dot_class/1`, `card_class/1`, `badge_class/1`). Use the existing atoms
  (`:passed`, `:failed`, `:running`, `:pending`, `:stopped`, `:canceled`,
  `:unknown`) so new sections inherit the established palette; add a new
  atom + class entry only if the existing ones don't fit.

  ### 3. Supervise the poller

  Add the GenServer to `BccmDashboard.Application`'s child list so it starts
  with the app and restarts on crash:

      {BccmDashboard.MySource.Poller, my_source_opts()}

  ### 4. Wire it into the LiveView

  In `BccmDashboardWeb.DashboardLive`:

    * subscribe in `mount/3`: `if connected?(socket), do: MySource.subscribe()`
    * add a `handle_info/2` clause for the broadcast message that calls
      `assign_sections(socket)`
    * append `MySource.section()` to the list built by `assign_sections/1`

  The order of the list is the visual order on the page.
  """

  @doc """
  Rolls a list of sections up into a single traffic-light atom for the page
  chrome (red border, header tone). Failure dominates everything — a single
  `:failed` item across any section flips the dashboard. With no items at
  all, the result is `:unknown` rather than `:passed`, so a still-loading
  dashboard doesn't pretend to be green.
  """
  @spec overall_status([__MODULE__.Section.t()]) :: __MODULE__.Item.status()
  def overall_status(sections) do
    items = Enum.flat_map(sections, & &1.items)

    cond do
      items == [] -> :unknown
      Enum.any?(items, &(&1.status == :failed)) -> :failed
      Enum.any?(items, &(&1.status == :running)) -> :running
      Enum.all?(items, &(&1.status in [:passed, :unknown])) -> :passed
      true -> :unknown
    end
  end

  defmodule Item do
    @moduledoc """
    A single status card. `status` is the canonical traffic-light atom used
    everywhere in the UI; `detail` is an optional short line under the title;
    `dots` is an optional run history (newest first).
    """
    @enforce_keys [:id, :name, :status]
    defstruct [:id, :name, :status, :status_label, :detail, :detail_tone, dots: []]

    @type status ::
            :passed | :failed | :running | :pending | :stopping | :stopped | :canceled | :unknown

    @type tone :: :warning | nil

    @type dot :: %{
            required(:color) => status(),
            optional(:label) => String.t(),
            optional(:duration_seconds) => non_neg_integer() | nil
          }

    @type t :: %__MODULE__{
            id: String.t() | atom(),
            name: String.t(),
            status: status(),
            status_label: String.t() | nil,
            detail: String.t() | nil,
            detail_tone: tone(),
            dots: [dot()]
          }
  end

  defmodule Section do
    @moduledoc """
    A titled block of items. `source` is a short string under the title
    (e.g. "Semaphore CI"). `error` carries a fetch-time failure to surface
    in the UI without blowing the whole page away.
    """
    @enforce_keys [:id, :title]
    defstruct [:id, :title, :source, :updated_at, :error, items: []]

    @type t :: %__MODULE__{
            id: atom(),
            title: String.t(),
            source: String.t() | nil,
            updated_at: DateTime.t() | nil,
            error: term() | nil,
            items: [BccmDashboard.Dashboard.Item.t()]
          }
  end
end
