defmodule BuilddoctorWeb.ArchiveLive do
  @moduledoc "Every edition that is still stored, the newest first."
  use BuilddoctorWeb, :live_view

  alias Builddoctor.Bench
  alias BuilddoctorWeb.{AuditView, Press, Requester}

  @per_page 24

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     assign(socket,
       page_title: "The archive",
       session: Map.take(session, ["requester_since"]),
       requester: Requester.signed_in?(session)
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    page = page(params)
    viewer = Requester.viewer(socket.assigns.session)

    result =
      Bench.archived_audits!(
        actor: viewer,
        page: [limit: @per_page, offset: (page - 1) * @per_page]
      )

    {:noreply, assign(socket, audits: result.results, more: result.more?, number: page)}
  end

  defp page(%{"page" => text}) when is_binary(text) do
    case Integer.parse(text) do
      {n, ""} when n in 1..1000 -> n
      _ -> 1
    end
  end

  defp page(_), do: 1

  @impl true
  def render(assigns) do
    ~H"""
    <main class="mx-auto grid max-w-6xl gap-6 px-4 py-6 sm:px-8">
      <Layouts.brand />
      <h1 class="font-display text-4xl uppercase sm:text-6xl">The archive</h1>
      <p class="max-w-prose">
        Every stored edition, the newest first. Editions about other projects are deleted after 90 days.
      </p>
      <p :if={@audits == []}>Nothing here.</p>
      <ul id="archive" class="grid grid-cols-1 gap-x-8 md:grid-cols-2">
        <li :for={audit <- @audits} class="border-b-2 border-bark">
          <a href={~p"/a/#{audit.id}"} class="flex items-center gap-4 py-4">
            <Press.grade grade={audit.grade} />
            <span class="min-w-0">
              <time class="text-moss" datetime={audit.inserted_at}>
                {Calendar.strftime(audit.inserted_at, "%B %-d, %Y, %H:%M")} UTC
              </time>
              <strong class="block text-lg break-words">{audit.repository}</strong>
              <span class="break-words">{AuditView.summary(audit)}</span>
              <span
                :for={finding <- Enum.take(audit.findings, 1)}
                :if={finding.rated_by}
                class="mt-1 block"
              >
                <Press.stamp finding={finding} />
              </span>
            </span>
          </a>
        </li>
      </ul>
      <nav aria-label="Pages of the archive" class="flex flex-wrap gap-6">
        <.link
          :if={@number > 1}
          patch={~p"/archive?page=#{@number - 1}"}
          class="inline-flex min-h-11 items-center underline"
        >
          Newer editions
        </.link>
        <.link
          :if={@more}
          patch={~p"/archive?page=#{@number + 1}"}
          class="inline-flex min-h-11 items-center underline"
        >
          Older editions
        </.link>
      </nav>
      <Layouts.footer requester={@requester} />
    </main>
    """
  end
end
