defmodule BccmDashboardWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  configured with the design system tokens defined in `assets/css/app.css`
  (colors like `surface-default`, `text-default`, `primary-default`, and
  typography scales like `text-title-3`, `text-body-2`). Here are useful
  references:

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: BccmDashboardWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="fixed top-4 right-4 z-50"
      {@rest}
    >
      <div class={[
        "flex items-start gap-3 p-4 rounded-md shadow-floating w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap text-body-3",
        @kind == :info && "bg-semantic-info text-text-light-default",
        @kind == :error && "bg-semantic-error text-text-light-default"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
        <div class="flex-1">
          <p :if={@title} class="text-title-3 font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <button type="button" class="group self-start cursor-pointer" aria-label={gettext("close")}>
          <.icon name="hero-x-mark" class="size-5 opacity-60 group-hover:opacity-100" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button.

  ## Examples

      <.button>Send!</.button>
      <.button variant="secondary" size="small">Cancel</.button>
      <.button variant="tertiary" icon="hero-plus" label="Add" />
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :variant, :string, values: ~w(primary secondary tertiary), default: "primary"
  attr :size, :string, values: ~w(small medium large), default: "medium"
  attr :label, :string, default: nil
  attr :icon, :string, default: nil, doc: "a heroicon name (e.g. \"hero-plus\")"
  attr :loading, :boolean, default: false
  attr :class, :any, default: nil

  attr :rest, :global,
    include: ~w(href navigate patch method download name value disabled type target)

  slot :inner_block

  def button(%{rest: rest} = assigns) do
    assigns = assign(assigns, :class, [button_classes(assigns), assigns.class])

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        <.icon :if={@icon} name={@icon} class="size-4" />
        <span :if={render_slot(@inner_block) || @label}>
          {render_slot(@inner_block) || @label}
        </span>
      </.link>
      """
    else
      ~H"""
      <button
        type={@rest[:type] || "button"}
        disabled={@rest[:disabled] || @loading}
        class={@class}
        {Map.drop(@rest, [:type, :disabled])}
      >
        <.icon :if={@icon} name={@icon} class="size-4" />
        <span :if={render_slot(@inner_block) || @label}>
          {render_slot(@inner_block) || @label}
        </span>
      </button>
      """
    end
  end

  defp button_classes(%{variant: variant, size: size}) do
    [
      "inline-flex items-center justify-center select-none cursor-pointer",
      "transition-transform duration-200 ease-out-expo active:scale-95",
      "disabled:opacity-50 disabled:pointer-events-none disabled:cursor-not-allowed",
      button_variant(variant),
      button_size(size)
    ]
  end

  defp button_variant("primary"), do: "bg-primary-default text-on-primary gradient-border-dark"
  defp button_variant("secondary"), do: "bg-surface-indent text-text-default"
  defp button_variant("tertiary"), do: "bg-transparent text-text-default hover:bg-surface-indent"

  defp button_size("small"), do: "rounded-2xl px-3 py-1.5 text-title-3 gap-1"
  defp button_size("medium"), do: "rounded-3xl px-4 py-2.5 text-title-2 gap-2"
  defp button_size("large"), do: "rounded-4xl px-5 py-3.5 text-title-2 gap-2"

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as hidden and radio,
  are best written directly in your templates.

  ## Examples

      <.input field={@form[:email]} type="email" />
      <.input name="my-input" errors={["oh no!"]} />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select switch tel text textarea time url week)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :string, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :string, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div>
      <label class={[
        "group inline-flex cursor-pointer items-center gap-2 text-body-3 text-text-default select-none",
        "has-[:disabled]:cursor-not-allowed has-[:disabled]:opacity-50"
      ]}>
        <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class="sr-only peer"
          {@rest}
        />
        <span class={[
          "inline-flex size-[18px] shrink-0 items-center justify-center rounded-md border border-border-1 bg-surface-default",
          "transition-colors duration-150 ease-out-expo",
          "group-hover:border-text-muted",
          "group-has-checked:border-primary-default group-has-checked:bg-primary-default",
          "peer-focus-visible:outline peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2 peer-focus-visible:outline-focus-ring"
        ]}>
          <.icon
            name="hero-check-mini"
            class="size-3.5 text-on-primary opacity-0 group-has-checked:opacity-100 transition-opacity duration-150 ease-out-expo"
          />
        </span>
        <span :if={@label}>{@label}</span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "switch"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div>
      <label class={[
        "group inline-flex cursor-pointer items-center gap-2.5",
        "has-[:disabled]:cursor-not-allowed has-[:disabled]:opacity-50"
      ]}>
        <input type="hidden" name={@name} value="false" disabled={@rest[:disabled]} />
        <input
          type="checkbox"
          id={@id}
          name={@name}
          value="true"
          checked={@checked}
          class="sr-only"
          {@rest}
        />
        <span class="inline-flex h-6 w-10 shrink-0 items-center rounded-full bg-text-default/15 p-0.5 transition-colors duration-200 ease-out-expo group-has-checked:bg-primary-default">
          <span class="size-5 rounded-full bg-white shadow-resting transition-transform duration-200 ease-out-expo group-has-checked:translate-x-4" />
        </span>
        <span :if={@label} class="text-body-3 text-text-default select-none">{@label}</span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div>
      <label class="block">
        <span :if={@label} class="block mb-1 text-title-3 text-text-default">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[
            @class ||
              "w-full rounded-md border border-border-1 bg-surface-default text-text-default text-body-2 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-focus-ring",
            @errors != [] && (@error_class || "border-semantic-error")
          ]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div>
      <label class="block">
        <span :if={@label} class="block mb-1 text-title-3 text-text-default">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class ||
              "w-full rounded-md border border-border-1 bg-surface-default text-text-default text-body-2 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-focus-ring",
            @errors != [] && (@error_class || "border-semantic-error")
          ]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div>
      <label class="block">
        <span :if={@label} class="block mb-1 text-title-3 text-text-default">{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            @class ||
              "w-full rounded-md border border-border-1 bg-surface-default text-text-default text-body-2 px-3 py-2 focus:outline-none focus:ring-2 focus:ring-focus-ring",
            @errors != [] && (@error_class || "border-semantic-error")
          ]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-body-3 text-semantic-error">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4"]}>
      <div>
        <h1 class="text-heading-3 text-text-default">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-body-3 text-text-muted">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="overflow-hidden rounded-xl border border-border-1">
      <table class="w-full text-left">
        <thead>
          <tr class="bg-surface-indent">
            <th
              :for={col <- @col}
              class="px-4 py-2.5 text-caption-1 font-medium text-text-muted"
            >
              {col[:label]}
            </th>
            <th :if={@action != []} class="px-4 py-2.5">
              <span class="sr-only">{gettext("Actions")}</span>
            </th>
          </tr>
        </thead>
        <tbody
          id={@id}
          phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}
          class="divide-y divide-border-1"
        >
          <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
            <td
              :for={col <- @col}
              phx-click={@row_click && @row_click.(row)}
              class={[
                "px-4 py-2.5 text-body-3 text-text-default",
                @row_click && "hover:cursor-pointer"
              ]}
            >
              {render_slot(col, @row_item.(row))}
            </td>
            <td :if={@action != []} class="w-0 px-4 py-2.5 font-medium">
              <div class="flex gap-2 justify-end">
                <%= for action <- @action do %>
                  {render_slot(action, @row_item.(row))}
                <% end %>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="divide-y divide-border-1 rounded-2xl border border-border-1 bg-surface-default">
      <li :for={item <- @item} class="flex flex-col gap-1 px-4 py-3.5">
        <div class="text-title-3 font-semibold text-text-default">{item.title}</div>
        <div class="text-body-3 text-text-muted">{render_slot(item)}</div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  @doc """
  Renders an empty/error/info state with an icon, title, description, and
  optional action slot.

  ## Examples

      <.view_state icon="hero-inbox" title="Nothing here yet" />

      <.view_state
        icon="hero-inbox"
        title="No results"
        description="Try a different search."
      >
        <:action>
          <.button variant="secondary" size="small">Reset</.button>
        </:action>
      </.view_state>
  """
  attr :icon, :string, default: nil
  attr :title, :string, default: nil
  attr :description, :string, default: nil
  attr :icon_class, :string, default: nil
  slot :action

  def view_state(assigns) do
    ~H"""
    <div class="flex size-full flex-col items-center justify-center p-6 text-center">
      <div :if={@icon} class="mb-6">
        <.icon name={@icon} class={["size-8 text-text-hint", @icon_class]} />
      </div>
      <p :if={@title} class="text-heading-3 text-text-default">{@title}</p>
      <p :if={@description} class="text-body-2 text-text-hint mt-1">{@description}</p>
      <div
        :if={@action != []}
        class="mt-6 flex flex-wrap items-center justify-center gap-2"
      >
        {render_slot(@action)}
      </div>
    </div>
    """
  end

  @doc """
  Renders an empty state. Defaults to an inbox icon and a "nothing here yet"
  title; both are overridable.
  """
  attr :icon, :string, default: "hero-inbox"
  attr :title, :string, default: nil
  attr :description, :string, default: nil
  slot :action

  def empty_state(assigns) do
    ~H"""
    <.view_state
      icon={@icon}
      title={@title || gettext("Nothing here yet")}
      description={@description}
    >
      <:action :if={@action != []}>{render_slot(@action)}</:action>
    </.view_state>
    """
  end

  @doc """
  Renders an error state. Defaults to an alert icon (in semantic-error) and a
  "something went wrong" title; both are overridable.
  """
  attr :icon, :string, default: "hero-exclamation-circle"
  attr :title, :string, default: nil
  attr :description, :string, default: nil
  slot :action

  def error_state(assigns) do
    ~H"""
    <.view_state
      icon={@icon}
      title={@title || gettext("Something went wrong")}
      description={@description}
      icon_class="text-semantic-error"
    >
      <:action :if={@action != []}>{render_slot(@action)}</:action>
    </.view_state>
    """
  end

  @doc """
  Renders an indeterminate loading spinner.

  Animations are
  defined as `spinner-rotate` and `spinner-segment` utilities in `app.css`.

  ## Examples

      <.loading_state />
      <.loading_state size={64} />
  """
  attr :size, :integer, default: 40

  def loading_state(assigns) do
    ~H"""
    <div class="flex size-full items-center justify-center px-4">
      <svg
        class="text-primary-contrast spinner-rotate"
        width={@size}
        height={@size}
        viewBox="0 0 24 24"
        fill="none"
      >
        <circle class="opacity-0" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="2.5" />
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
    </div>
    """
  end

  @doc """
  Renders a CSS-only tooltip wrapper. The trigger is the inner block; the
  tooltip content comes from the `:content` slot (or the `content` attr).

  Uses
  Tailwind classes for one of four placements (`top`/`bottom`/`left`/`right`)
  and shows on hover or focus-within.

  ## Examples

      <.tooltip text="Save changes">
        <.button icon="hero-check" />
      </.tooltip>

      <.tooltip placement="bottom">
        <:content>
          <strong>Tip:</strong> press <kbd>⌘K</kbd> to search.
        </:content>
        <.button variant="tertiary" icon="hero-question-mark-circle" />
      </.tooltip>
  """
  attr :text, :string, default: nil, doc: "plain-text tooltip content"
  attr :placement, :string, values: ~w(top bottom left right), default: "top"
  attr :gap, :integer, default: 8, doc: "pixel offset between trigger and tooltip"
  attr :class, :any, default: nil
  slot :inner_block, required: true
  slot :content, doc: "rich tooltip content; takes precedence over :text"

  def tooltip(assigns) do
    ~H"""
    <span class="relative inline-flex group">
      {render_slot(@inner_block)}
      <span
        role="tooltip"
        style={"--tooltip-gap: #{@gap}px"}
        class={[
          "pointer-events-none absolute z-50 max-w-xs whitespace-normal rounded-lg gradient-border bg-surface-raise px-2.5 py-1.5",
          "text-caption-1 text-text-default shadow-floating",
          "opacity-0 scale-95 transition-[opacity,transform] duration-200 ease-out-expo",
          "group-hover:opacity-100 group-hover:scale-100",
          "group-focus-within:opacity-100 group-focus-within:scale-100",
          tooltip_placement(@placement),
          @class
        ]}
      >
        {render_slot(@content) || @text}
      </span>
    </span>
    """
  end

  defp tooltip_placement("top"),
    do: "bottom-full left-1/2 -translate-x-1/2 mb-[var(--tooltip-gap)] origin-bottom"

  defp tooltip_placement("bottom"),
    do: "top-full left-1/2 -translate-x-1/2 mt-[var(--tooltip-gap)] origin-top"

  defp tooltip_placement("left"),
    do: "right-full top-1/2 -translate-y-1/2 mr-[var(--tooltip-gap)] origin-right"

  defp tooltip_placement("right"),
    do: "left-full top-1/2 -translate-y-1/2 ml-[var(--tooltip-gap)] origin-left"

  @doc """
  Renders a small colored pill used to label statuses or counts.

  ## Examples

      <.badge label="New" />
      <.badge variant="success" label="Active" />
      <.badge variant="error">3 failures</.badge>
  """
  attr :variant, :string,
    values: ~w(success warning info error neutral),
    default: "neutral"

  attr :label, :string, default: nil
  attr :class, :any, default: nil
  slot :inner_block

  def badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center rounded-lg px-2 py-0.5 text-caption-1",
      badge_variant(@variant),
      @class
    ]}>
      {render_slot(@inner_block) || @label}
    </span>
    """
  end

  defp badge_variant("success"), do: "bg-semantic-success/15 text-semantic-success"
  defp badge_variant("warning"), do: "bg-semantic-warning/15 text-semantic-warning"
  defp badge_variant("info"), do: "bg-semantic-info/15 text-semantic-info"
  defp badge_variant("error"), do: "bg-semantic-error/15 text-semantic-error"
  defp badge_variant("neutral"), do: "bg-surface-indent text-text-muted"

  @doc """
  Renders a full-width tinted notice with an optional icon.

  ## Examples

      <.banner icon="hero-information-circle" variant="info">
        Your changes have been saved.
      </.banner>

      <.banner variant="error" icon="hero-exclamation-triangle">
        Something went wrong while saving.
      </.banner>
  """
  attr :variant, :string,
    values: ~w(success warning info error neutral),
    default: "neutral"

  attr :icon, :string, default: nil, doc: "a heroicon name (e.g. \"hero-check-circle\")"
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def banner(assigns) do
    ~H"""
    <div class={[
      "flex items-center gap-3 rounded-xl px-4 py-3 text-body-3",
      banner_variant(@variant),
      @class
    ]}>
      <.icon :if={@icon} name={@icon} class="size-5 shrink-0" />
      <div class="flex-1">{render_slot(@inner_block)}</div>
    </div>
    """
  end

  defp banner_variant("success"), do: "bg-semantic-success/15 text-semantic-success"
  defp banner_variant("warning"), do: "bg-semantic-warning/15 text-semantic-warning"
  defp banner_variant("info"), do: "bg-semantic-info/15 text-semantic-info"
  defp banner_variant("error"), do: "bg-semantic-error/15 text-semantic-error"
  defp banner_variant("neutral"), do: "bg-surface-indent text-text-muted"

  @doc """
  Renders a circular avatar showing an image when `src` is given, otherwise
  the initials of `name`.

  Shows
  the image when `src` is set and otherwise the initials — there is no
  on-error fallback.

  ## Examples

      <.avatar name="Sigve Hansen" />
      <.avatar src="/img/me.jpg" name="Sigve Hansen" size="large" />
  """
  attr :src, :string, default: nil
  attr :name, :string, default: nil
  attr :size, :string, values: ~w(small medium large), default: "medium"
  attr :class, :any, default: nil

  def avatar(assigns) do
    assigns = assign(assigns, :initials, avatar_initials(assigns[:name]))

    ~H"""
    <span class={[
      "relative inline-flex shrink-0 items-center justify-center overflow-hidden rounded-full",
      avatar_size(@size),
      @class
    ]}>
      <img
        :if={@src}
        src={@src}
        alt={@name || ""}
        class="size-full object-cover"
      />
      <span
        :if={!@src}
        class="bg-primary-default text-on-primary flex size-full items-center justify-center font-semibold"
      >
        {@initials}
      </span>
    </span>
    """
  end

  defp avatar_size("small"), do: "size-6 text-caption-2"
  defp avatar_size("medium"), do: "size-8 text-caption-1"
  defp avatar_size("large"), do: "size-10 text-title-3"

  defp avatar_initials(nil), do: "?"
  defp avatar_initials(""), do: "?"

  defp avatar_initials(name) when is_binary(name) do
    name
    |> String.split(" ", trim: true)
    |> Enum.take(2)
    |> Enum.map(&String.first/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join()
    |> String.upcase()
    |> case do
      "" -> "?"
      letters -> letters
    end
  end

  @doc """
  Renders a toggle switch.

  Implemented as a styled
  checkbox — the visual track and thumb react to `:checked` via the
  `group-has-checked:` Tailwind modifier.

  ## Examples

      <.switch name="notifications" label="Enable notifications" />
      <.switch name="dark_mode" checked />
  """
  attr :id, :string, default: nil
  attr :name, :string, default: nil
  attr :value, :any, default: nil
  attr :checked, :boolean, default: false
  attr :label, :string, default: nil
  attr :disabled, :boolean, default: false
  attr :class, :any, default: nil

  attr :rest, :global, include: ~w(form required readonly phx-change phx-blur phx-click)

  def switch(assigns) do
    ~H"""
    <label class={[
      "group inline-flex cursor-pointer items-center gap-2.5",
      "has-[:disabled]:cursor-not-allowed has-[:disabled]:opacity-50",
      @class
    ]}>
      <input
        type="checkbox"
        id={@id}
        name={@name}
        value={if @value == nil, do: "true", else: @value}
        checked={@checked}
        disabled={@disabled}
        class="sr-only"
        {@rest}
      />
      <span class="inline-flex h-6 w-10 shrink-0 items-center rounded-full bg-text-default/15 p-0.5 transition-colors duration-200 ease-out-expo group-has-checked:bg-primary-default">
        <span class="size-5 rounded-full bg-white shadow-resting transition-transform duration-200 ease-out-expo group-has-checked:translate-x-4" />
      </span>
      <span :if={@label} class="text-body-3 text-text-default select-none">{@label}</span>
    </label>
    """
  end

  @doc """
  Renders a card-bordered table with column headers and an optional empty-state
  message. Use this for static-shape tables where you control the row markup.

  For Phoenix-style streamed
  tables with per-row click handling and action columns, use `table/1`.

  ## Examples

      <.simple_table columns={["Name", "Status", "Created"]}>
        <tr :for={user <- @users} class="border-t border-border-1">
          <td class="px-4 py-2.5 text-body-3 text-text-default">{user.name}</td>
          <td class="px-4 py-2.5"><.badge variant="success" label="Active" /></td>
          <td class="px-4 py-2.5 text-body-3 text-text-muted">{user.inserted_at}</td>
        </tr>
      </.simple_table>

      <.simple_table columns={["Name"]} empty="No users yet" />
  """
  attr :columns, :list, required: true
  attr :empty, :string, default: nil
  attr :class, :any, default: nil
  slot :inner_block

  def simple_table(assigns) do
    ~H"""
    <div class={["overflow-hidden rounded-xl border border-border-1", @class]}>
      <table class="w-full">
        <thead>
          <tr class="bg-surface-indent text-left">
            <th
              :for={col <- @columns}
              class="px-4 py-2.5 text-caption-1 font-medium text-text-muted"
            >
              {col}
            </th>
          </tr>
        </thead>
        <tbody>
          {render_slot(@inner_block)}
        </tbody>
      </table>
      <div :if={@empty} class="px-4 py-12 text-center text-body-2 text-text-hint">
        {@empty}
      </div>
    </div>
    """
  end

  @doc """
  A simple card.
  """
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <div class="rounded-2xl gradient-border shadow-resting bg-surface-raise p-4">
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  A labeled stat card. Renders a small caption above a large value slot.
  """
  attr :label, :string, required: true
  slot :inner_block, required: true

  def stat_card(assigns) do
    ~H"""
    <.card>
      <p class="text-caption-1 text-text-muted">{@label}</p>
      <p class="mt-1 text-heading-2 font-semibold text-text-default">
        {render_slot(@inner_block)}
      </p>
    </.card>
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(BccmDashboardWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(BccmDashboardWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
