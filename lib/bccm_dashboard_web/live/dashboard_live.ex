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

  alias BccmDashboard.Semaphore

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Semaphore.subscribe()

    {:ok,
     socket
     |> assign(:page_title, "Operations")
     |> assign_sections()}
  end

  @impl true
  def handle_info({:semaphore_snapshot, _snapshot}, socket) do
    {:noreply, assign_sections(socket)}
  end

  defp assign_sections(socket) do
    sections = [Semaphore.section()]

    socket
    |> assign(:sections, sections)
    |> assign(:overall, overall_status(sections))
    |> assign(:updated_at, latest_updated_at(sections))
  end

  defp overall_status(sections) do
    items = Enum.flat_map(sections, & &1.items)

    cond do
      items == [] -> :unknown
      Enum.any?(items, &(&1.status == :failed)) -> :failed
      Enum.any?(items, &(&1.status == :running)) -> :running
      Enum.all?(items, &(&1.status in [:passed, :unknown])) -> :passed
      true -> :unknown
    end
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

  # Dot fills use the semantic palette so a row of dots reads the same as a
  # row of status badges. Running pulses to draw the eye.
  defp dot_class(:passed), do: "bg-semantic-success"
  defp dot_class(:failed), do: "bg-semantic-error"
  defp dot_class(:running), do: "bg-semantic-info animate-pulse"
  defp dot_class(:pending), do: "bg-semantic-warning"
  defp dot_class(:stopping), do: "bg-semantic-warning"
  defp dot_class(_), do: "bg-text-hint"

  # Cards split into "loud" (failed, running, pending) — fully saturated fills
  # that read from across the room — and "calm" (everything else) — neutral
  # raised surfaces with a gradient border so the loud cards pop.
  defp card_class(:failed),
    do: "bg-semantic-error text-text-light-default shadow-floating"

  defp card_class(:running),
    do: "bg-semantic-info text-text-light-default shadow-floating ring-3"

  defp card_class(:pending),
    do: "bg-semantic-warning text-text-dark-default shadow-floating"

  defp card_class(:stopping),
    do: "bg-semantic-warning text-text-dark-default shadow-floating"

  defp card_class(_),
    do: "bg-surface-raise text-text-default gradient-border shadow-resting"

  # The status label color sits on top of the card surface, so each entry
  # has to coordinate with `card_class/1` above. Loud cards inherit their
  # contrast color via `currentColor`; calm cards get a semantic accent.
  defp status_text_class(:failed), do: "text-text-light-default"
  defp status_text_class(:running), do: "text-text-light-default"
  defp status_text_class(:pending), do: "text-text-dark-default"
  defp status_text_class(:stopping), do: "text-text-dark-default"
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
    <div class="min-h-screen bg-surface-default text-text-default">
      <div
        :if={@overall == :failed}
        class="pointer-events-none fixed inset-0 z-50 border-8 border-semantic-error"
        aria-hidden="true"
      />
      <div class="p-14">
        <header class="mb-14">
          <img class="h-14" src="/images/bcc-media-logo.svg" aria-label="BCC Media" />
        </header>
        <div class="space-y-14">
          <.section :for={section <- @sections} section={section} />
        </div>
      </div>
    </div>

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
    assigns = assign(assigns, :items, sort_items(assigns.section.items))

    ~H"""
    <section id={"section-#{@section.id}"}>
      <div class="mb-6 flex flex-wrap items-baseline justify-between gap-x-8 gap-y-2 border-b border-border-1 pb-4">
        <div class="flex flex-wrap items-baseline gap-x-6 gap-y-1">
          <h2 class="text-heading-1 text-text-default">{@section.title}</h2>
          <span
            :if={@section.source}
            class="text-heading-1 text-text-hint font-normal"
          >
            {@section.source}
          </span>
        </div>
        <span class="text-heading-1 text-text-hint font-normal">
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
          <div class="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 2xl:grid-cols-5">
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
        "flex flex-col gap-6 rounded-3xl p-8",
        card_class(@item.status)
      ]}
    >
      <h3 class="truncate text-heading-2">{@item.name}</h3>

      <p class={[
        "flex items-center gap-3 text-heading-3 uppercase tracking-[0.15em]",
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

      <div :if={@item.dots != []} class="mt-auto flex h-12 items-end gap-1 pt-2">
        <span
          :for={dot <- @item.dots}
          title={dot[:label] || Atom.to_string(dot.color)}
          style={"height: #{sparkline_height_pct(dot, @sparkline_max)}%"}
          class={["block w-5 rounded-sm ring-1 ring-black/30", dot_class(dot.color)]}
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
