defmodule BuilddoctorWeb.SubscribeLive do
  @moduledoc """
  An advertisement of our own: private editions, for now a waiting list by email. Nothing is stored here.
  """
  use BuilddoctorWeb, :live_view

  alias BuilddoctorWeb.{Imprint, Requester}

  @impl true
  def mount(_params, session, socket) do
    contact = Imprint.load()

    {:ok,
     assign(socket,
       page_title: "Private editions",
       email: contact && contact.email,
       requester: Requester.signed_in?(session)
     )}
  end

  def mail(email) do
    query =
      URI.encode_query(
        [
          subject: "Waiting list for private editions",
          body:
            "Please put me on the waiting list for private editions of Build! and write to me when there is news."
        ],
        :rfc3986
      )

    "mailto:#{email}?#{query}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="mx-auto grid max-w-6xl gap-6 px-4 py-6 sm:px-8">
      <Layouts.brand />
      <p class="text-base">Advertisement in our own paper</p>
      <h1 class="font-display text-4xl uppercase sm:text-7xl">Coming up: your private edition</h1>
      <div class="grid items-start gap-8 md:grid-cols-[1.6fr_1fr]">
        <div class="grid max-w-prose gap-4 text-lg">
          <p>
            Your private pipelines have stories, too. We plan a private edition of Build!: your own repositories, your own headlines, shown only to you.
          </p>
          <p>
            We also plan a newsroom that writes fixes in any language and tests them in a throwaway Sprite before you see them.
          </p>
          <p class="font-bold">None of this exists yet, and we promise no date and no price.</p>
          <p>
            Today, BuildDoctor reads public projects only. Please do not send us code, keys or access to anything.
          </p>
          <h2 class="font-display text-3xl uppercase">What you can have today</h2>
          <ul class="grid list-disc gap-2 pl-6">
            <li>
              A printed edition of any public project with a suitable run. The daily limits apply.
            </li>
            <li>A patch, if the council passes one. You open the pull request yourself.</li>
            <li>A feed for every project with an edition, for your feed reader.</li>
          </ul>
        </div>
        <section id="waiting-list" class="grid gap-4 border-3 border-dashed border-bark bg-sun p-5">
          <h2 class="font-display text-3xl uppercase">Free waiting list</h2>
          <p class="text-lg font-bold">Wanted: readers with slow builds. Apply below.</p>
          <PC.button
            :if={@email}
            link_type="a"
            to={mail(@email)}
            label="Write to get on the list"
            class="min-h-12"
          />
          <p :if={@email}>
            Your mail program opens. If it does not, write to <a class="underline" href={mail(@email)}>{@email}</a>.
          </p>
          <p :if={!@email}>The list is not open yet.</p>
          <p class="text-base">
            We use your address only to write to you about private editions. Email us to be removed from the list.
            <a
              class="underline"
              href={~p"/privacy"}
            >Privacy</a>
          </p>
        </section>
      </div>
      <Layouts.footer requester={@requester} />
    </main>
    """
  end
end
