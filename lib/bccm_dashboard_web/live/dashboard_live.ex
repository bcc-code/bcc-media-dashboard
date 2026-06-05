defmodule BccmDashboardWeb.DashboardLive do
  @moduledoc """
  Operations dashboard. Renders a list of `%Section{}`s, one per data source.

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

  @impl true
  def handle_event("refresh", _params, socket) do
    Semaphore.refresh()
    {:noreply, socket}
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

  defp dot_class(:passed), do: "bg-emerald-500"
  defp dot_class(:failed), do: "bg-rose-500"
  defp dot_class(:running), do: "bg-sky-500 animate-pulse"
  defp dot_class(:pending), do: "bg-amber-400"
  defp dot_class(:stopping), do: "bg-amber-500"
  defp dot_class(:stopped), do: "bg-zinc-500"
  defp dot_class(:canceled), do: "bg-zinc-600"
  defp dot_class(_), do: "bg-zinc-700/40"

  defp card_class(:passed), do: "border-emerald-500/40 hover:border-emerald-500/60"
  defp card_class(:failed), do: "border-rose-500/40 hover:border-rose-500/60"
  defp card_class(:running), do: "border-sky-500/40 hover:border-sky-500/60"
  defp card_class(:pending), do: "border-amber-400/40 hover:border-amber-400/60"
  defp card_class(:stopping), do: "border-amber-500/40 hover:border-amber-500/60"
  defp card_class(:stopped), do: "border-zinc-500/40 hover:border-zinc-500/60"
  defp card_class(:canceled), do: "border-zinc-600/40 hover:border-zinc-600/60"
  defp card_class(_), do: "border-zinc-700/60 hover:border-zinc-600"

  defp badge_class(:passed), do: "bg-emerald-500/10 text-emerald-300"
  defp badge_class(:failed), do: "bg-rose-500/10 text-rose-300"
  defp badge_class(:running), do: "bg-sky-500/10 text-sky-300"
  defp badge_class(:pending), do: "bg-amber-400/10 text-amber-200"
  defp badge_class(:stopping), do: "bg-amber-500/10 text-amber-200"
  defp badge_class(:stopped), do: "bg-zinc-500/10 text-zinc-300"
  defp badge_class(:canceled), do: "bg-zinc-600/10 text-zinc-300"
  defp badge_class(_), do: "bg-zinc-800 text-zinc-400"

  defp overall_banner(:passed), do: {"All green", "text-emerald-300"}
  defp overall_banner(:failed), do: {"Failing builds", "text-rose-300"}
  defp overall_banner(:running), do: {"Builds in flight", "text-sky-300"}
  defp overall_banner(_), do: {"No data", "text-zinc-400"}

  defp format_updated_at(nil), do: "never"

  defp format_updated_at(%DateTime{} = dt) do
    dt
    |> DateTime.truncate(:second)
    |> Calendar.strftime("%H:%M:%S UTC")
  end

  @impl true
  def render(assigns) do
    {banner_text, banner_class} = overall_banner(assigns.overall)
    assigns = assign(assigns, banner_text: banner_text, banner_class: banner_class)

    ~H"""
    <div class="min-h-screen bg-zinc-950 text-zinc-100">
      <div class="mx-auto max-w-7xl px-6 py-10 sm:px-10 lg:py-14">
        <header class="flex flex-wrap items-end justify-between gap-6 pb-12">
          <div>
            <p class="text-xs uppercase tracking-[0.3em] text-zinc-500">BCCM Operations</p>
            <h1 class={["mt-2 text-4xl font-semibold tracking-tight sm:text-5xl", @banner_class]}>
              {@banner_text}
            </h1>
            <p class="mt-2 text-sm text-zinc-400">
              updated {format_updated_at(@updated_at)}
            </p>
          </div>
          <button
            type="button"
            id="refresh-btn"
            phx-click="refresh"
            class="rounded-full border border-zinc-700 bg-zinc-900 px-4 py-2 text-sm font-medium text-zinc-200 transition hover:border-zinc-500 hover:bg-zinc-800 active:scale-[0.98]"
          >
            <.icon name="hero-arrow-path-micro" class="mr-1 size-4 align-[-2px]" /> Refresh
          </button>
        </header>

        <div class="space-y-12">
          <.section :for={section <- @sections} section={section} />
        </div>
      </div>
    </div>
    """
  end

  attr :section, BccmDashboard.Dashboard.Section, required: true

  defp section(assigns) do
    ~H"""
    <section id={"section-#{@section.id}"}>
      <div class="mb-5 flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1 border-b border-zinc-800 pb-3">
        <div class="flex items-baseline gap-3">
          <h2 class="text-xl font-semibold tracking-tight text-zinc-100">{@section.title}</h2>
          <span :if={@section.source} class="text-xs uppercase tracking-wider text-zinc-500">
            {@section.source}
          </span>
        </div>
        <span class="text-xs text-zinc-500">
          updated {format_updated_at(@section.updated_at)}
        </span>
      </div>

      <%= cond do %>
        <% @section.error -> %>
          <div class="rounded-lg border border-rose-500/30 bg-rose-500/10 px-4 py-3 text-sm text-rose-200">
            Couldn't reach {@section.source || "source"}: {inspect(@section.error)}
          </div>
        <% @section.items == [] -> %>
          <div class="rounded-2xl border border-zinc-800 bg-zinc-900/40 px-6 py-10 text-center text-sm text-zinc-500">
            No items.
          </div>
        <% true -> %>
          <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
            <.item :for={item <- @section.items} item={item} />
          </div>
      <% end %>
    </section>
    """
  end

  attr :item, BccmDashboard.Dashboard.Item, required: true

  defp item(assigns) do
    ~H"""
    <article
      id={"item-#{@item.id}"}
      class={[
        "rounded-2xl border bg-zinc-900/60 p-5 shadow-sm shadow-black/30 transition hover:bg-zinc-900",
        card_class(@item.status)
      ]}
    >
      <header class="flex items-start justify-between gap-3">
        <h3 class="truncate text-base font-semibold tracking-tight text-zinc-100">{@item.name}</h3>
        <span class={[
          "shrink-0 rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider",
          badge_class(@item.status)
        ]}>
          {@item.status_label || String.upcase(Atom.to_string(@item.status))}
        </span>
      </header>

      <p :if={@item.detail} class="mt-1 text-xs text-zinc-500">{@item.detail}</p>

      <div :if={@item.dots != []} class="mt-4 flex flex-wrap gap-2">
        <span
          :for={{dot, idx} <- Enum.with_index(@item.dots)}
          title={"##{idx + 1}: #{dot[:label] || dot.color}"}
          class={["block size-3 rounded-full ring-1 ring-black/40", dot_class(dot.color)]}
        />
      </div>
    </article>
    """
  end
end
