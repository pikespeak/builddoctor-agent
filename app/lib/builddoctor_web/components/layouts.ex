defmodule BuilddoctorWeb.Layouts do
  @moduledoc "The page frame."
  use BuilddoctorWeb, :html

  embed_templates "layouts/*"

  @doc "The name and what it does, on every page."
  def brand(assigns) do
    ~H"""
    <header class="grid gap-4">
      <div class="flex flex-wrap items-center gap-x-8 gap-y-3">
        <a
          href={~p"/"}
          class="masthead"
          aria-label="Build! The Daily Flake, the newspaper of BuildDoctor"
        >
          <span>Build<i>!</i></span><small>The Daily Flake</small>
        </a>
        <nav aria-label="Pages" class="flex flex-wrap gap-x-6 font-bold">
          <a href={~p"/"} class="inline-flex min-h-11 items-center underline">Front page</a>
          <a href={~p"/archive"} class="inline-flex min-h-11 items-center underline">Archive</a>
          <a href={~p"/how-it-works"} class="inline-flex min-h-11 items-center underline">
            How it works
          </a>
        </nav>
      </div>
      <p class="border-y-2 border-bark py-2 text-base">
        <strong>Printed by BuildDoctor.</strong>
        It examines public GitHub Actions pipelines and suggests improvements. Changes are measured on its own test project only.
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
      <p><PC.button link_type="a" to={~p"/"} label="Back to the front page" /></p>
      <.legal />
    </main>
    """
  end
end
