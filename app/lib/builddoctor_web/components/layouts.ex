defmodule BuilddoctorWeb.Layouts do
  @moduledoc "The page frame."
  use BuilddoctorWeb, :html

  embed_templates "layouts/*"

  @doc "The name and what it does, on every page."
  def brand(assigns) do
    ~H"""
    <header class="flex flex-wrap items-baseline gap-x-4 gap-y-1">
      <a href={~p"/"} class="inline-flex min-h-11 items-center font-display text-2xl font-bold">
        BuildDoctor
      </a>
      <a href={~p"/how-it-works"} class="inline-flex min-h-11 items-center text-base underline">
        How it works
      </a>
      <p class="w-full text-base">
        Examines public GitHub Actions pipelines and suggests improvements. Measures changes on its own test project and shows the results.
      </p>
    </header>
    <p
      id="offline"
      role="status"
      class="hidden border-2 border-madder bg-white p-3"
      phx-disconnected={JS.show()}
      phx-connected={JS.hide()}
    >
      Connection lost. Trying again. What you see may be out of date.
    </p>
    """
  end

  attr :requester, :boolean, default: false

  @doc "The way in and out for the Requester."
  def footer(assigns) do
    ~H"""
    <footer class="flex flex-wrap items-center gap-x-6 gap-y-2 border-t-2 border-bark pt-4">
      <.legal />
      <form :if={@requester} id="leave" method="post" action={~p"/requester/leave"}>
        <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
        <span>You are the requester.</span>
        <button type="submit" class="min-h-11 px-2 underline">Sign out</button>
      </form>
      <a :if={!@requester} href={~p"/requester"} class="inline-flex min-h-11 items-center underline">
        Requester sign-in
      </a>
    </footer>
    """
  end

  @doc "Always one click away."
  def legal(assigns) do
    ~H"""
    <nav aria-label="Legal" class="flex flex-wrap gap-x-6">
      <a href={~p"/imprint"} class="inline-flex min-h-11 items-center underline">Imprint</a>
      <a href={~p"/privacy"} class="inline-flex min-h-11 items-center underline">Privacy</a>
    </nav>
    """
  end

  attr :title, :string, required: true
  attr :text, :string, required: true

  @doc "A page without content still says what happened and what comes next."
  def nothing(assigns) do
    ~H"""
    <main class="mx-auto grid max-w-3xl gap-4 px-4 py-16">
      <.brand />
      <h1 class="font-display text-4xl font-bold">{@title}</h1>
      <p class="text-lg">{@text}</p>
      <p><PC.button link_type="a" to={~p"/"} label="Back to the forest" /></p>
      <.legal />
    </main>
    """
  end
end
