defmodule BccmDashboardWeb.DashboardLive do
  @moduledoc """
  Operations dashboard. Currently shows the Semaphore CI pipeline status for
  every project in the configured org as a column of dots — newest pipeline on
  top, oldest at the bottom — with a single roll-up status colour for the
  project header.
  """
  use BccmDashboardWeb, :live_view

  alias BccmDashboard.Semaphore

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Semaphore.subscribe()

    {:ok,
     socket
     |> assign(:page_title, "Operations")
     |> assign_snapshot(Semaphore.snapshot())}
  end

  @impl true
  def handle_info({:semaphore_snapshot, snapshot}, socket) do
    {:noreply, assign_snapshot(socket, snapshot)}
  end

  @impl true
  def handle_event("refresh", _params, socket) do
    Semaphore.refresh()
    {:noreply, socket}
  end

  defp assign_snapshot(socket, snapshot) do
    socket
    |> assign(:projects, snapshot.projects)
    |> assign(:updated_at, snapshot.updated_at)
    |> assign(:error, snapshot.error)
    |> assign(:overall, overall_status(snapshot.projects))
  end

  defp overall_status([]), do: :unknown

  defp overall_status(projects) do
    cond do
      Enum.any?(projects, &project_failing?/1) -> :failed
      Enum.any?(projects, &project_running?/1) -> :running
      Enum.all?(projects, &project_passing?/1) -> :passed
      true -> :unknown
    end
  end

  defp project_failing?(%{dots: [%{color: :failed} | _]}), do: true
  defp project_failing?(_), do: false

  defp project_running?(%{dots: [%{color: :running} | _]}), do: true
  defp project_running?(_), do: false

  defp project_passing?(%{dots: [%{color: :passed} | _]}), do: true
  defp project_passing?(%{dots: []}), do: true
  defp project_passing?(_), do: false

  defp project_status(%{dots: [%{color: color} | _]}), do: color
  defp project_status(_), do: :unknown

  # Map semantic colors to the Tailwind classes that paint each dot / header.
  defp dot_class(:passed), do: "bg-emerald-500"
  defp dot_class(:failed), do: "bg-rose-500"
  defp dot_class(:running), do: "bg-sky-500 animate-pulse"
  defp dot_class(:pending), do: "bg-amber-400"
  defp dot_class(:stopping), do: "bg-amber-500"
  defp dot_class(:stopped), do: "bg-zinc-500"
  defp dot_class(:canceled), do: "bg-zinc-600"
  defp dot_class(_), do: "bg-zinc-700/40"

  defp header_class(:passed), do: "border-emerald-500/40 bg-emerald-500/10 text-emerald-200"
  defp header_class(:failed), do: "border-rose-500/40 bg-rose-500/10 text-rose-200"
  defp header_class(:running), do: "border-sky-500/40 bg-sky-500/10 text-sky-200"
  defp header_class(:pending), do: "border-amber-400/40 bg-amber-400/10 text-amber-200"
  defp header_class(:stopping), do: "border-amber-500/40 bg-amber-500/10 text-amber-200"
  defp header_class(:stopped), do: "border-zinc-500/40 bg-zinc-500/10 text-zinc-200"
  defp header_class(:canceled), do: "border-zinc-600/40 bg-zinc-600/10 text-zinc-300"
  defp header_class(_), do: "border-zinc-700/40 bg-zinc-800/40 text-zinc-400"

  defp overall_banner(:passed), do: {"All green", "text-emerald-300"}
  defp overall_banner(:failed), do: {"Failing builds", "text-rose-300"}
  defp overall_banner(:running), do: {"Builds in flight", "text-sky-300"}
  defp overall_banner(_), do: {"No data", "text-zinc-400"}

  defp humanize_dot(%{state: "DONE", result: result}) when is_binary(result), do: result
  defp humanize_dot(%{state: state}) when is_binary(state), do: state
  defp humanize_dot(_), do: "unknown"

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
        <header class="flex flex-wrap items-end justify-between gap-6 pb-10">
          <div>
            <p class="text-xs uppercase tracking-[0.3em] text-zinc-500">BCCM Operations</p>
            <h1 class={["mt-2 text-4xl font-semibold tracking-tight sm:text-5xl", @banner_class]}>
              {@banner_text}
            </h1>
            <p class="mt-2 text-sm text-zinc-400">
              Semaphore CI · updated {format_updated_at(@updated_at)}
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

        <%= if @error do %>
          <div class="mb-6 rounded-lg border border-rose-500/30 bg-rose-500/10 px-4 py-3 text-sm text-rose-200">
            Couldn't reach Semaphore: {inspect(@error)}
          </div>
        <% end %>

        <%= cond do %>
          <% @projects == [] and is_nil(@updated_at) -> %>
            <div class="rounded-2xl border border-zinc-800 bg-zinc-900/60 px-6 py-12 text-center text-zinc-400">
              Warming up — fetching Semaphore status…
            </div>
          <% @projects == [] -> %>
            <div class="rounded-2xl border border-zinc-800 bg-zinc-900/60 px-6 py-12 text-center text-zinc-400">
              No projects returned.
            </div>
          <% true -> %>
            <div
              id="projects"
              class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4"
            >
              <article
                :for={project <- @projects}
                id={"project-#{project.id || project.name}"}
                class={[
                  "rounded-2xl border bg-zinc-900/60 p-5 shadow-sm shadow-black/30 transition hover:bg-zinc-900",
                  header_class(project_status(project))
                ]}
              >
                <header class="flex items-start justify-between gap-3">
                  <h2 class="truncate text-base font-semibold tracking-tight text-zinc-100">
                    {project.name}
                  </h2>
                  <span class={[
                    "shrink-0 rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider",
                    header_class(project_status(project))
                  ]}>
                    {project_status(project)}
                  </span>
                </header>
                <div class="mt-4 flex flex-wrap gap-2">
                  <%= if project.dots == [] do %>
                    <span class="text-xs text-zinc-500">no recent runs</span>
                  <% else %>
                    <span
                      :for={{dot, idx} <- Enum.with_index(project.dots)}
                      title={"##{idx + 1}: #{humanize_dot(dot)}"}
                      class={["block size-3 rounded-full ring-1 ring-black/40", dot_class(dot.color)]}
                    />
                  <% end %>
                </div>
              </article>
            </div>
        <% end %>

        <footer class="mt-10 text-center text-xs text-zinc-600">
          dots: newest on the left · auto-refreshes every minute
        </footer>
      </div>
    </div>
    """
  end
end
