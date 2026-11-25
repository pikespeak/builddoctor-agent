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
    <nav aria-label="About this site" class="flex flex-wrap gap-x-6">
      <a href={~p"/imprint"} class="inline-flex min-h-11 items-center underline">Imprint</a>
      <a href={~p"/privacy"} class="inline-flex min-h-11 items-center underline">Privacy</a>
      <a
        href="https://fly.io/hacksgiving/"
        rel="noopener"
        class="inline-flex min-h-11 items-center underline"
      >
        Built for Fly.io Hacksgiving 2026
      </a>
      <button
        :if={BuilddoctorWeb.Analytics.settings()}
        type="button"
        data-analytics-do="open"
        class="analytics-choice min-h-11 cursor-pointer items-center underline"
      >
        Analytics choice
      </button>
    </nav>
    """
  end

  attr :settings, :map, required: true

  @doc "Asks before PostHog is loaded. Hidden until consent.js has a reason to show it."
  def analytics_consent(assigns) do
    ~H"""
    <section
      id="analytics-consent"
      hidden
      tabindex="-1"
      aria-labelledby="analytics-title"
      class="group/analytics fixed inset-x-0 bottom-0 z-50 max-h-[80vh] overflow-y-auto border-t-4 border-bark bg-white p-3 sm:p-4"
      data-site={@settings.site}
      data-key={@settings.key}
      data-host={@settings.host}
      data-src={~p"/assets/js/analytics.js"}
    >
      <div class="mx-auto grid max-w-3xl gap-2 sm:gap-3 group-data-[signal=true]/analytics:hidden">
        <h2 id="analytics-title" class="font-display text-xl sm:text-2xl">
          May we count your visit?
        </h2>
        <p>
          If you accept, PostHog stores an ID here and reports the pages and buttons you use. Undo it in the footer. <a
            href={~p"/privacy#analytics"}
            class="underline"
          >Privacy</a>.
        </p>
        <div class="grid grid-cols-2 gap-3">
          <button type="button" data-analytics-do="decline" class="consent-button">Decline</button>
          <button type="button" data-analytics-do="accept" class="consent-button">Accept</button>
        </div>
      </div>
      <div class="mx-auto hidden max-w-3xl gap-3 group-data-[signal=true]/analytics:grid">
        <p>Your browser asks websites not to track you. We respect that, so analytics stays off.</p>
        <button type="button" data-analytics-do="close" class="consent-button">Close</button>
      </div>
    </section>
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
