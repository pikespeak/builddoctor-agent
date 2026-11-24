defmodule BuilddoctorWeb.Timeline do
  @moduledoc "The jobs of a run as readable rows: a dashed line for waiting, a bar for work."
  use Phoenix.Component

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :rows, :list, required: true

  def timeline(assigns) do
    ~H"""
    <ol id={@id} aria-label={@label} class="grid gap-2">
      <li
        :for={row <- @rows}
        class="grid grid-cols-[1fr_auto] items-center gap-x-3 sm:grid-cols-[minmax(6rem,16rem)_1fr_7.5rem]"
      >
        <span class="col-span-2 min-w-0 leading-tight font-bold break-words sm:col-span-1">
          {row.name}
        </span>
        <span class="relative block h-6 rounded bg-sand" aria-hidden="true">
          <span
            :if={row.from > 0}
            class="absolute left-0 top-1/2 border-t-2 border-dashed border-moss"
            style={"width:#{row.from}%"}
          />
          <span
            :if={row.width}
            class="absolute h-full rounded border-2 border-bark bg-leaf"
            style={"left:#{row.from}%;width:#{row.width}%"}
          />
        </span>
        <span class="text-right tabular-nums">{row.words}</span>
      </li>
    </ol>
    """
  end
end
