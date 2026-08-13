defmodule BccmDashboardWeb.DashboardLive do
  @moduledoc """
  Operations dashboard. Renders a list of `%Section{}`s, one per data source.

  Designed for a TV-style wall display: full width, bold type, and stable
  alphabetical ordering so each card stays in the same spot between renders.
  Failures are signaled by a red viewport border (see `render/1`), not by
  reshuffling cards to the top.

  Surface, text, and semantic colors come from the design system tokens
  defined in `assets/css/app.css`. The app is dark-only — there's no theme
  toggle, so the tokens render the same on every wall display.

  See `BccmDashboard.Dashboard` for the step-by-step guide to adding a new
  section. In short: build a `%Section{}`, subscribe to its topic in
  `mount/3`, add a `handle_info/2` clause, and append it to the list returned
  by `assign_sections/1`. The template doesn't care which source produced the
  section.
  """
  use BccmDashboardWeb, :live_view

  alias BccmDashboard.{BuildInfo, Dashboard, Gatus, Semaphore}

  # Re-render on a slow timer even when no broadcast arrives. This is what
  # lets a section flip to "stale" when its poller goes silent (a silent
  # poller sends nothing), and what keeps the "down N" outage counters
  # ticking up between polls.
  @ui_tick_ms 5_000

  # A section is stale once it hasn't refreshed for several poll cycles —
  # long enough that a slow fetch won't trip it, short enough to notice a
  # wedged poller. An erroring poller still ticks `updated_at`, so it shows
  # its error rather than going stale.
  @stale_cycles 3

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Semaphore.subscribe()
      Gatus.subscribe()
      schedule_ui_tick()
    end

    {:ok,
     socket
     |> assign(:page_title, "Operations")
     |> assign_sections()}
  end

  @impl true
  def handle_info({:semaphore_snapshot, _snapshot}, socket) do
    {:noreply, assign_sections(socket)}
  end

  def handle_info({:gatus_snapshot, _snapshot}, socket) do
    {:noreply, assign_sections(socket)}
  end

  def handle_info(:ui_tick, socket) do
    schedule_ui_tick()
    {:noreply, assign_sections(socket)}
  end

  defp schedule_ui_tick, do: Process.send_after(self(), :ui_tick, @ui_tick_ms)

  defp assign_sections(socket) do
    sections = [Semaphore.section(), Gatus.section()]

    socket
    |> assign(:sections, sections)
    |> assign(:overall, Dashboard.overall_status(sections))
    |> assign(:updated_at, latest_updated_at(sections))
  end

  defp latest_updated_at(sections) do
    sections
    |> Enum.map(& &1.updated_at)
    |> Enum.reject(&is_nil/1)
    |> Enum.max(DateTime, fn -> nil end)
  end

  defp sort_items(items) do
    Enum.sort_by(items, & &1.name)
  end

  # True when a section's data is older than @stale_cycles of its own refresh
  # interval — i.e. the poller stopped delivering. A section that's never
  # updated (updated_at nil) is "loading", not stale, and a section without a
  # known cadence can't be judged.
  defp stale?(%{updated_at: %DateTime{} = updated_at, refresh_ms: refresh_ms})
       when is_integer(refresh_ms) and refresh_ms > 0 do
    DateTime.diff(DateTime.utc_now(), updated_at, :millisecond) > refresh_ms * @stale_cycles
  end

  defp stale?(_), do: false

  # Dot fills use the semantic palette so a row of dots reads the same as a
  # row of status badges. Running pulses to draw the eye.
  defp dot_class(:passed), do: "bg-semantic-success"
  defp dot_class(:failed), do: "bg-semantic-error"
  defp dot_class(:running), do: "bg-semantic-info animate-pulse"
  defp dot_class(:pending), do: "bg-semantic-warning"
  defp dot_class(:stopping), do: "bg-semantic-warning"
  defp dot_class(_), do: "bg-text-hint"

  # Only :failed gets a fully saturated fill — that's the one state that has
  # to read from across the room. Every other "noteworthy" state (running,
  # pending, stopping) sits on the calm surface with a colored ring, so
  # failures stay the loudest signal on the wall.
  defp card_class(:failed),
    do: "bg-semantic-error text-text-light-default shadow-floating"

  defp card_class(:running),
    do:
      "bg-surface-raise text-text-default gradient-border shadow-resting ring-4 ring-semantic-info"

  defp card_class(:pending),
    do:
      "bg-surface-raise text-text-default gradient-border shadow-resting ring-4 ring-semantic-warning"

  defp card_class(:stopping),
    do:
      "bg-surface-raise text-text-default gradient-border shadow-resting ring-4 ring-semantic-warning"

  defp card_class(_),
    do: "bg-surface-raise text-text-default gradient-border shadow-resting"

  # The status label color sits on top of the card surface. Only :failed
  # uses the white-on-red contrast pair; every other accent picks the
  # semantic color directly since the card itself stays calm.
  defp status_text_class(:failed), do: "text-text-light-default"
  defp status_text_class(:running), do: "text-semantic-info"
  defp status_text_class(:pending), do: "text-semantic-warning"
  defp status_text_class(:stopping), do: "text-semantic-warning"
  defp status_text_class(:passed), do: "text-semantic-success"
  defp status_text_class(:stopped), do: "text-text-hint"
  defp status_text_class(:canceled), do: "text-text-hint"
  defp status_text_class(_), do: "text-text-hint"

  defp format_updated_at(%DateTime{} = dt) do
    dt
    |> DateTime.truncate(:second)
    |> Calendar.strftime("%H:%M:%S")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-surface-default text-text-default tabular-nums">
      <div
        :if={@overall == :failed}
        class="pointer-events-none fixed inset-0 z-50 border-24 border-semantic-error"
        aria-hidden="true"
      />
      <div class="p-6 lg:p-10">
        <header class="mb-12 flex items-center justify-between gap-6">
          <img class="h-12" src="/images/bcc-media-logo.svg" aria-label="BCC Media" />
          <time
            id="clock"
            phx-hook=".Clock"
            class="text-heading-1 font-normal leading-0"
            aria-label="Current time"
          />
        </header>
        <div class="space-y-12">
          <.section :for={section <- @sections} section={section} />
        </div>
      </div>

      <span
        :if={BuildInfo.short_sha()}
        title={BuildInfo.sha()}
        class="pointer-events-none fixed bottom-8 right-8 z-40 font-mono text-body-1 text-text-hint opacity-60"
        aria-label="Build commit"
      >
        {BuildInfo.short_sha()}
      </span>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".Clock">
      export default {
        mounted() {
          this.tick()
          this.timer = setInterval(() => this.tick(), 1000)
        },
        destroyed() { clearInterval(this.timer) },
        tick() {
          this.el.textContent = new Date().toLocaleTimeString(undefined, {
            hour: "2-digit", minute: "2-digit", second: "2-digit"
          })
        }
      }
    </script>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".LocalTime">
      export default {
        mounted() { this.format() },
        updated() { this.format() },
        format() {
          const dt = new Date(this.el.getAttribute("datetime"))
          if (isNaN(dt)) return
          this.el.textContent = dt.toLocaleTimeString(undefined, {
            hour: "2-digit", minute: "2-digit", second: "2-digit"
          })
        }
      }
    </script>
    """
  end

  attr :section, BccmDashboard.Dashboard.Section, required: true

  defp section(assigns) do
    assigns =
      assigns
      |> assign(:items, sort_items(assigns.section.items))
      |> assign(:stale?, stale?(assigns.section))

    ~H"""
    <section id={"section-#{@section.id}"}>
      <div class="mb-6 flex flex-wrap items-baseline justify-between gap-x-8 gap-y-2 border-b border-border-1 pb-4">
        <div class="flex flex-wrap items-baseline gap-x-6 gap-y-1">
          <h2 class="text-heading-2 text-text-default">{@section.title}</h2>
          <span
            :if={@section.source}
            class="text-heading-2 text-text-hint font-normal"
          >
            {@section.source}
          </span>
        </div>
        <span class={[
          "text-heading-2 font-normal flex items-center gap-3",
          if(@stale?, do: "text-semantic-warning", else: "text-text-hint")
        ]}>
          <span
            :if={@stale?}
            class="rounded-md bg-semantic-warning px-2 py-0.5 text-heading-3 uppercase tracking-widest text-text-light-default"
          >
            Stale
          </span>
          Last updated
          <%= if @section.updated_at do %>
            <time
              id={"updated-#{@section.id}"}
              phx-hook=".LocalTime"
              datetime={DateTime.to_iso8601(@section.updated_at)}
            >
              {format_updated_at(@section.updated_at)}
            </time>
          <% else %>
            never
          <% end %>
        </span>
      </div>

      <%= cond do %>
        <% @section.error -> %>
          <.error_state
            title={"Couldn't reach #{@section.source || "source"}"}
            description={inspect(@section.error)}
          />
        <% @items == [] -> %>
          <.empty_state title="No items" />
        <% true -> %>
          <div class="grid grid-cols-[repeat(auto-fit,minmax(16rem,1fr))] gap-6">
            <.item :for={item <- @items} item={item} />
          </div>
      <% end %>
    </section>
    """
  end

  attr :item, BccmDashboard.Dashboard.Item, required: true

  defp item(assigns) do
    assigns = assign(assigns, :sparkline_max, sparkline_max(assigns.item.dots))

    ~H"""
    <article
      id={"item-#{@item.id}"}
      class={[
        "flex flex-col gap-2 rounded-2xl p-6",
        card_class(@item.status)
      ]}
    >
      <h3 class="truncate text-heading-2">{@item.name}</h3>

      <p class={[
        "flex items-center gap-3 text-heading-3 uppercase tracking-widest",
        status_text_class(@item.status)
      ]}>
        {@item.status_label || String.upcase(Atom.to_string(@item.status))}
        <svg
          :if={@item.status == :running}
          class="size-6 spinner-rotate"
          viewBox="0 0 24 24"
          fill="none"
          aria-hidden="true"
        >
          <circle
            class="spinner-segment"
            cx="12"
            cy="12"
            r="10"
            stroke="currentColor"
            stroke-width="2.5"
            stroke-linecap="round"
          />
        </svg>
      </p>

      <p :if={@item.detail} class={detail_class(@item.detail_tone)}>{@item.detail}</p>

      <div :if={@item.dots != []} class="mt-3 h-14 items-end gap-2 grid grid-cols-16">
        <span
          :for={dot <- @item.dots}
          title={dot[:label] || Atom.to_string(dot.color)}
          style={"height: #{sparkline_height_pct(dot, @sparkline_max)}%"}
          class={["block rounded-sm ring-1 ring-black/30", dot_class(dot.color)]}
        />
      </div>
    </article>
    """
  end

  defp detail_class(:warning), do: "text-heading-3 font-normal text-semantic-warning"
  defp detail_class(_), do: "text-heading-3 font-normal opacity-70"

  defp sparkline_max(dots) do
    dots
    |> Enum.map(& &1[:duration_seconds])
    |> Enum.reject(&is_nil/1)
    |> Enum.max(fn -> 0 end)
  end

  # Bars scale to the longest run in the window, but every bar gets a 15%
  # floor so a one-bar-equals-one-build read stays possible — even an
  # aborted-in-seconds failure should be visible as a red stub.
  defp sparkline_height_pct(dot, max_seconds) do
    case dot[:duration_seconds] do
      n when is_integer(n) and n > 0 and max_seconds > 0 ->
        max(round(n / max_seconds * 100), 15)

      _ ->
        15
    end
  end
end
