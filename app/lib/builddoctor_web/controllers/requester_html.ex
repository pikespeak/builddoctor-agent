defmodule BuilddoctorWeb.RequesterHTML do
  @moduledoc false
  use BuilddoctorWeb, :html

  alias PetalComponents.Field

  def new(assigns) do
    ~H"""
    <main class="mx-auto max-w-md px-4 py-16">
      <Layouts.brand />
      <h1 class="font-display text-3xl font-bold">Requester key</h1>
      <form method="post" action={~p"/requester"} class="mt-6 grid gap-4">
        <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
        <input :if={@audit} type="hidden" name="audit" value={@audit} />
        <Field.field
          id="key"
          name="key"
          label="Key"
          type="password"
          value=""
          autocomplete="off"
          required
          no_margin
          label_class="text-base font-bold text-bark"
          class="min-h-11 border-2 border-bark bg-white px-3 text-base text-bark sm:text-base focus-visible:border-madder focus-visible:ring-3 focus-visible:ring-madder"
          aria-invalid={to_string(@message != "")}
          aria-describedby={@message != "" && "key-error"}
        />
        <p :if={@message != ""} id="key-error" role="alert" class="text-madder">{@message}</p>
        <PC.button type="submit" label="Unlock" />
      </form>
      <p class="mt-4">
        <a href={if @audit, do: ~p"/a/#{@audit}", else: ~p"/"} class="inline-block py-2 underline">
          Back without the key
        </a>
      </p>
      <Layouts.legal />
    </main>
    """
  end
end
