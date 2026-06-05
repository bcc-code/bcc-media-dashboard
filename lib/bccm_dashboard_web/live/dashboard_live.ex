defmodule BccmDashboardWeb.DashboardLive do
  @moduledoc """
  Operations dashboard. Renders a list of `%Section{}`s, one per data source.

  Designed for a TV-style wall display: full width, bold type, and items
  sorted within each section so anything in the red lands in the top-left
  where the eye naturally enters.

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

  # Highest priority (lowest number) sorts first. Tuning this changes the
  # whole "where does the eye land" story for the wall display: failures
  # have to win every tie.
  defp status_priority(:failed), do: 0
  defp status_priority(:running), do: 1
  defp status_priority(:pending), do: 2
  defp status_priority(:stopping), do: 3
  defp status_priority(:canceled), do: 4
  defp status_priority(:stopped), do: 5
  defp status_priority(:unknown), do: 6
  defp status_priority(:passed), do: 7
  defp status_priority(_), do: 99

  defp sort_items(items) do
    Enum.sort_by(items, &{status_priority(&1.status), &1.name})
  end

  defp dot_class(:passed), do: "bg-green-400"
  defp dot_class(:failed), do: "bg-red-300"
  defp dot_class(:running), do: "bg-sky-300 animate-pulse"
  defp dot_class(:pending), do: "bg-amber-300"
  defp dot_class(:stopping), do: "bg-amber-400"
  defp dot_class(:stopped), do: "bg-neutral-400"
  defp dot_class(:canceled), do: "bg-neutral-500"
  defp dot_class(_), do: "bg-neutral-600"

  # Card surfaces. Failed and running are loud — fully saturated fills with
  # white type that read from across the room. Passed is calm so it doesn't
  # compete for attention. Everything else is muted neutrals.
  defp card_class(:failed),
    do: "bg-red-600 border-red-300 text-white shadow-lg shadow-red-900/40"

  defp card_class(:running),
    do: "bg-sky-600 border-sky-300 text-white shadow-lg shadow-sky-900/40"

  defp card_class(:pending),
    do: "bg-amber-400 border-amber-200 text-amber-950"

  defp card_class(:stopping),
    do: "bg-amber-500 border-amber-300 text-amber-950"

  defp card_class(:passed),
    do: "bg-neutral-900 border-green-500/40 text-neutral-100"

  defp card_class(:stopped),
    do: "bg-neutral-900 border-neutral-700 text-neutral-300"

  defp card_class(:canceled),
    do: "bg-neutral-900 border-neutral-700 text-neutral-400"

  defp card_class(_),
    do: "bg-neutral-900 border-neutral-700 text-neutral-400"

  # The status label color sits on top of the card surface, so each entry
  # has to coordinate with `card_class/1` above.
  defp status_text_class(:failed), do: "text-white"
  defp status_text_class(:running), do: "text-white"
  defp status_text_class(:pending), do: "text-amber-950"
  defp status_text_class(:stopping), do: "text-amber-950"
  defp status_text_class(:passed), do: "text-green-400"
  defp status_text_class(:stopped), do: "text-neutral-400"
  defp status_text_class(:canceled), do: "text-neutral-500"
  defp status_text_class(_), do: "text-neutral-500"

  defp banner_class(:passed), do: "bg-green-500/15 text-green-300 border-green-500/40"
  defp banner_class(:failed), do: "bg-red-600 text-white border-red-300"
  defp banner_class(:running), do: "bg-sky-600 text-white border-sky-300"
  defp banner_class(_), do: "bg-neutral-800 text-neutral-400 border-neutral-700"

  defp banner_text(:passed), do: "ALL GREEN"
  defp banner_text(:failed), do: "FAILING"
  defp banner_text(:running), do: "IN FLIGHT"
  defp banner_text(_), do: "NO DATA"

  defp format_updated_at(nil), do: "never"

  defp format_updated_at(%DateTime{} = dt) do
    dt
    |> DateTime.truncate(:second)
    |> Calendar.strftime("%H:%M:%S UTC")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-neutral-950 text-neutral-100">
      <div class="px-10 py-8 2xl:px-16">
        <header class="flex flex-wrap items-center justify-between gap-6 pb-10">
          <div class="flex flex-wrap items-baseline gap-x-8 gap-y-1">
            <h1 class="text-3xl font-bold tracking-tight text-neutral-200">BCCM Operations</h1>
            <span class="text-base text-neutral-500">updated {format_updated_at(@updated_at)}</span>
          </div>
          <span class={[
            "border-2 px-8 py-3 text-3xl font-extrabold uppercase tracking-[0.25em]",
            banner_class(@overall)
          ]}>
            {banner_text(@overall)}
          </span>
        </header>

        <div class="space-y-14">
          <.section :for={section <- @sections} section={section} />
        </div>
      </div>
    </div>
    """
  end

  attr :section, BccmDashboard.Dashboard.Section, required: true

  defp section(assigns) do
    assigns = assign(assigns, :items, sort_items(assigns.section.items))

    ~H"""
    <section id={"section-#{@section.id}"}>
      <div class="mb-6 flex flex-wrap items-baseline justify-between gap-x-8 gap-y-2 border-b border-neutral-800 pb-4">
        <div class="flex flex-wrap items-baseline gap-x-5 gap-y-1">
          <h2 class="text-4xl font-bold tracking-tight text-neutral-100">{@section.title}</h2>
          <span :if={@section.source} class="text-base uppercase tracking-[0.25em] text-neutral-500">
            {@section.source}
          </span>
        </div>
        <span class="text-base text-neutral-500">
          updated {format_updated_at(@section.updated_at)}
        </span>
      </div>

      <%= cond do %>
        <% @section.error -> %>
          <div class="border-2 border-red-500/60 bg-red-500/15 px-6 py-5 text-xl font-semibold text-red-200">
            Couldn't reach {@section.source || "source"}: {inspect(@section.error)}
          </div>
        <% @items == [] -> %>
          <div class="border border-neutral-800 bg-neutral-900/40 px-6 py-14 text-center text-lg text-neutral-500">
            No items.
          </div>
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
    ~H"""
    <article
      id={"item-#{@item.id}"}
      class={[
        "flex flex-col gap-4 border-2 p-6",
        card_class(@item.status)
      ]}
    >
      <h3 class="truncate text-3xl font-bold tracking-tight">{@item.name}</h3>

      <p class={[
        "text-2xl font-extrabold uppercase tracking-[0.15em]",
        status_text_class(@item.status)
      ]}>
        {@item.status_label || String.upcase(Atom.to_string(@item.status))}
      </p>

      <p :if={@item.detail} class="text-base opacity-70">{@item.detail}</p>

      <div :if={@item.dots != []} class="mt-auto flex flex-wrap gap-2 pt-1">
        <span
          :for={{dot, idx} <- Enum.with_index(@item.dots)}
          title={"##{idx + 1}: #{dot[:label] || dot.color}"}
          class={["block size-5 ring-1 ring-black/40", dot_class(dot.color)]}
        />
      </div>
    </article>
    """
  end
end
