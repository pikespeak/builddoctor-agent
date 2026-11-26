defmodule BuilddoctorWeb.FrontLive do
  @moduledoc "The front page: every project has its edition, every blank page is the start of an Examination."
  use BuilddoctorWeb, :live_view

  alias Builddoctor.Bench
  alias Builddoctor.Bench.Audit
  alias Builddoctor.Bench.Changes.Plant
  alias BuilddoctorWeb.{AuditView, Press, Requester}
  alias PetalComponents.Field

  @texts %{
    "error.repository.invalid" =>
      "Please enter a project as owner/name or as its GitHub address.",
    "error.repository.planted" => "This project already has its edition. Its result is there.",
    "error.again.tooSoon" =>
      "This project was examined in the last 24 hours. Please come back later.",
    "error.slot.taken" => "Somebody was faster. Please choose another page.",
    "error.limit.day" => "Today's free examinations are used up. New ones start at midnight UTC.",
    "error.limit.visitor" =>
      "You have used up your examinations for today. Please come back tomorrow.",
    "error.limit.busy" =>
      "Several projects are being read right now. Please try again in a minute.",
    "error.slot.invalid" => "Please choose a blank page.",
    "error.paper.busy" => "Every page is still being printed. Please try again in a minute."
  }

  @impl true
  def mount(params, session, socket) do
    if connected?(socket), do: BuilddoctorWeb.Endpoint.subscribe("audit:front")

    {:ok,
     socket
     |> assign(
       page_title: "Build! The front page",
       chosen: nil,
       project: project(params),
       error: nil
     )
     |> assign(
       pending: false,
       known: nil,
       own_error: nil,
       requester: Requester.signed_in?(session),
       session: Map.take(session, ["requester_since", "visitor"])
     )
     |> load()}
  end

  defp project(%{"project" => project}) when is_binary(project), do: String.slice(project, 0, 200)
  defp project(_), do: ""

  defp load(socket) do
    session = socket.assigns.session
    viewer = Requester.viewer(session)
    planted = Map.new(Bench.planted_audits!(actor: viewer), &{&1.slot, &1})
    free = Enum.reject(1..Audit.places(), &is_map_key(planted, &1))
    chosen = if socket.assigns.chosen in free, do: socket.assigns.chosen

    assign(socket,
      may_start: Requester.may_start?(session),
      planted: planted,
      free: free,
      chosen: chosen,
      lead: lead(Map.values(planted)),
      ads: planted |> jokes(:ad) |> Enum.take(6),
      stars: planted |> jokes(:star) |> Enum.uniq_by(& &1.sign) |> Enum.take(4),
      own: Enum.map(Bench.own_audits!(), &AuditView.load/1)
    )
  end

  # Among the ten newest editions with a finished picture, the fact-checker's highest rating leads;
  # without a rating, the newest. No failure or weakness of a project leads.
  defp lead(audits) do
    newest =
      audits
      |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
      |> Enum.filter(&leads?/1)
      |> Enum.take(10)

    newest
    |> Enum.filter(&(AuditView.stamp(hd(&1.findings)) == "Supported"))
    |> Enum.max_by(&hd(&1.findings).support_probability, fn -> List.first(newest) end)
  end

  # The newest lines of the agent's editor.
  defp jokes(planted, kind) do
    planted
    |> Map.values()
    |> Enum.flat_map(& &1.lines)
    |> Enum.filter(&(&1.kind == kind))
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
  end

  defp leads?(%{findings: [%{kind: kind} | _], pictures: pictures})
       when kind in [:waiting, :time, :cost, :flaky, :maintenance],
       do: story(pictures) != nil

  defp leads?(_), do: false

  defp story(pictures), do: Enum.find(pictures, &(&1.place == 1 and &1.state == :done))

  # Many small messages become one redraw.
  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{}, %{assigns: %{pending: true}} = socket),
    do: {:noreply, socket}

  def handle_info(%Phoenix.Socket.Broadcast{}, socket) do
    Process.send_after(self(), :refresh, 250)
    {:noreply, assign(socket, pending: true)}
  end

  def handle_info(:refresh, socket), do: {:noreply, socket |> assign(pending: false) |> load()}

  @impl true
  def handle_event("choose", %{"slot" => slot}, socket) do
    chosen = Enum.find(socket.assigns.free, &(to_string(&1) == slot))
    # The same page again gives it back.
    chosen = if chosen != socket.assigns.chosen, do: chosen
    {:noreply, assign(socket, chosen: chosen, error: nil, known: nil)}
  end

  def handle_event("release", _, socket), do: {:noreply, assign(socket, chosen: nil)}

  def handle_event("own", _, socket) do
    actor = Requester.actor(socket)

    case Bench.examine_own(actor: actor) do
      {:ok, audit} -> {:noreply, push_navigate(socket, to: ~p"/a/#{audit.id}")}
      {:error, error} -> {:noreply, assign(socket, own_error: own_text(error))}
    end
  end

  def handle_event("plant", %{"project" => project}, socket) when is_binary(project) do
    # On a full paper any page will do: the application gives the oldest finished one.
    slot = socket.assigns.chosen || List.first(socket.assigns.free) || 1

    actor = Requester.actor(socket)

    case Bench.plant_audit(project, slot, %{visitor: socket.assigns.session["visitor"]},
           actor: actor
         ) do
      {:ok, audit} ->
        {:noreply, push_navigate(socket, to: ~p"/a/#{audit.id}")}

      {:error, error} ->
        {:noreply,
         socket
         |> load()
         |> assign(project: project, error: text(error), known: known(project))}
    end
  end

  # The result that is already there, if the project has a place.
  defp known(project) do
    case project
         |> Plant.name()
         |> String.downcase()
         |> Bench.place_of(not_found_error?: false) do
      {:ok, %{id: id}} -> id
      _ -> nil
    end
  end

  defp own_text(error) do
    if Exception.message(error) =~ "error.again.running",
      do: "Our test project is being read already.",
      else: "This is not possible right now."
  end

  defp text(%Ash.Error.Forbidden{}), do: "Visitors cannot start an examination right now."

  defp text(error) do
    message = Exception.message(error)

    Enum.find_value(@texts, @texts["error.repository.invalid"], fn {key, text} ->
      if String.contains?(message, key), do: text
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="mx-auto grid max-w-6xl gap-6 px-4 py-6 sm:px-8">
      <Layouts.brand />
      <h1 class="font-display text-3xl sm:text-5xl">
        Is your GitHub pipeline slower than it has to be?
      </h1>
      <form
        :if={@may_start}
        id="plant"
        phx-submit="plant"
        data-track="print"
        class="flex flex-wrap items-end gap-3 border-3 border-dashed border-bark bg-sun p-4"
      >
        <Field.field
          id="project"
          name="project"
          label={if @chosen, do: "Project for page #{@chosen}", else: "Public project"}
          type="text"
          value={@project}
          placeholder="owner/name"
          autocomplete="off"
          autocapitalize="off"
          spellcheck="false"
          maxlength="200"
          required
          no_margin
          wrapper_class="grow"
          label_class="text-base font-bold text-bark"
          class="min-h-12 border-2 border-bark bg-white px-3 text-lg text-bark sm:text-lg focus-visible:border-leaf focus-visible:ring-3 focus-visible:ring-leaf"
          aria-invalid={to_string(@error != nil)}
          aria-describedby={@error && "project-error"}
        />
        <PC.button type="submit" phx-disable-with="Printing" label="Print it" class="min-h-12" />
      </form>
      <p :if={@error} id="project-error" role="alert" class="text-madder">
        {@error}
        <a :if={@known} id="known" href={~p"/a/#{@known}"} class="inline-block py-2 underline">
          Open its result
        </a>
      </p>
      <p :if={@chosen} phx-window-keydown="release" phx-key="Escape">
        <PC.button type="button" variant="outline" phx-click="release" label="Choose another page" />
      </p>
      <section :if={@requester} id="own-start" class="grid gap-2 border-2 border-bark bg-white p-4">
        <p class="max-w-prose">
          Examine our own test project, pikespeak/ci-patient. If the council passes a change, it starts a trial with 8 runs on GitHub, at most twice a day.
        </p>
        <p>
          <PC.button
            type="button"
            phx-click="own"
            phx-disable-with="Starting"
            label="Examine our test project"
          />
        </p>
        <p :if={@own_error} role="alert" class="text-madder">{@own_error}</p>
      </section>
      <p :if={!@may_start} id="reduced" class="max-w-prose text-lg">
        Right now, this page shows our own measured test project. Other projects are examined by the operator only.
        <a href={~p"/how-it-works"} class="inline-block py-2 underline">How it works</a>
      </p>
      <p :if={@may_start} aria-live="polite" id="count" class="text-lg">
        {if @free == [],
          do:
            "All #{Audit.places()} pages are taken. A new project takes the page of the oldest finished edition. The previous edition stays in the archive.",
          else: "#{map_size(@planted)} of #{Audit.places()} pages printed."}
        <span>Free and read-only: we change nothing in your project.</span>
      </p>
      <Layouts.entry />
      <.lead_story :if={@lead} audit={@lead} />
      <a
        :if={proven(@own)}
        id="extra"
        href={~p"/a/#{proven(@own).audit.id}"}
        class="grid gap-2 bg-madder p-5 text-white sm:p-8"
      >
        <span class="font-bold">Extra edition: proven on our own test project</span>
        <span class="font-display text-4xl uppercase sm:text-6xl">{own_words(proven(@own))}</span>
      </a>
      <section id="found" class="grid gap-3 border-t-8 border-bark pt-5">
        <h2 class="font-display text-3xl uppercase sm:text-4xl">All editions</h2>
        <p :if={@own == [] and @planted == %{}}>Nothing yet. Be the first.</p>
        <ul id="own" class="grid grid-cols-1 gap-x-8 md:grid-cols-2">
          <li :for={view <- @own}>
            <.card
              id={view.audit.id}
              name={view.audit.repository}
              words={own_words(view)}
              tag={own_tag(view)}
            />
          </li>
        </ul>
        <ul id="places" class="grid grid-cols-1 gap-x-8 md:grid-cols-2">
          <li
            :for={
              {slot, audit} <-
                Enum.sort_by(@planted, fn {_, a} -> a.inserted_at end, {:desc, DateTime})
            }
            id={"project-#{slot}"}
          >
            <.card
              id={audit.id}
              name={audit.repository}
              words={AuditView.summary(audit)}
              tag={tag(audit)}
              grade={audit.grade}
              picture={story(audit.pictures)}
              finding={List.first(audit.findings)}
            />
          </li>
        </ul>
      </section>
      <div
        :if={@ads != [] or @stars != []}
        class="grid gap-8 border-t-8 border-bark pt-5 md:grid-cols-[2fr_1fr]"
      >
        <section :if={@ads != []} id="ads" class="grid content-start gap-3">
          <h2 class="font-display text-3xl uppercase sm:text-4xl">Classified ads</h2>
          <ul class="grid gap-x-8 sm:grid-cols-2">
            <li :for={ad <- @ads} class="border-b border-bark py-2">{ad.text}</li>
          </ul>
        </section>
        <section :if={@stars != []} id="stars" class="grid content-start gap-3 bg-leaf p-5 text-white">
          <h2 class="font-display text-3xl uppercase sm:text-4xl">Horoscope</h2>
          <ul>
            <li :for={star <- @stars} class="border-b border-white py-2">
              <strong>{star.sign |> to_string() |> String.capitalize()}.</strong> {star.text}
            </li>
          </ul>
        </section>
        <p class="text-base md:col-span-2">
          Our agent writes the ads and the horoscope, and a council checks them. They are jokes and mean no particular project.
        </p>
      </div>
      <p id="own-ad" class="border-3 border-dashed border-bark bg-sun p-4 text-lg">
        <strong>Advertisement.</strong>
        Your private pipelines have stories, too.
        <a
          href={~p"/subscribe"}
          data-track="waiting list ad"
          class="inline-block py-2 font-bold underline"
        >Join the free waiting list for private editions</a>
      </p>
      <section :if={@may_start} id="pages" class="grid gap-3 border-t-8 border-bark pt-5">
        <h2 class="font-display text-3xl uppercase sm:text-4xl">Choose your page</h2>
        <p>A black page is printed and shows its project. A white one is free and can be yours.</p>
        <ol class="grid grid-cols-4 gap-1 sm:grid-cols-5 md:grid-cols-10">
          <li :for={slot <- 1..Audit.places()}>
            <.place slot={slot} audit={@planted[slot]} chosen={@chosen == slot} />
          </li>
        </ol>
      </section>
      <Layouts.footer requester={@requester} />
    </main>
    """
  end

  defp lead_story(assigns) do
    finding = hd(assigns.audit.findings)

    assigns =
      assign(assigns,
        finding: finding,
        headline: AuditView.headline(assigns.audit),
        seconds: AuditView.waited(finding, assigns.audit)
      )

    ~H"""
    <article id="lead" class="lead grid gap-5 border-t-8 border-bark pt-3">
      <h2 class="headline" data-long={to_string(String.length(@headline) > 34)}>{@headline}</h2>
      <div class="grid gap-6 md:grid-cols-[1.6fr_1fr]">
        <Press.photo
          audit={@audit}
          place={1}
          picture={story(@audit.pictures)}
          lines={@audit.lines}
          auto
        />
        <div class="grid content-start gap-4">
          <p :if={@headline != @finding.title} class="font-display text-2xl sm:text-3xl">
            {@finding.title}
          </p>
          <p><strong class="break-words">{@audit.repository}:</strong> {@finding.text}</p>
          <p class="font-bold">A suspicion, not proof.</p>
          <p :if={AuditView.stamp(@finding) == "Supported"} id="picked">
            <Press.stamp finding={@finding} />
            Jev by TypeSafe picked this story: the highest estimated support among the ten newest stories that can lead.
          </p>
          <p :if={@audit.grade}><Press.grade grade={@audit.grade} big /></p>
          <p>
            <a href={~p"/a/#{@audit.id}"} data-track="lead story" class="inline-block py-2 underline">
              Full story on page {@audit.slot}
            </a>
          </p>
          <Press.seconds :if={@seconds} wait={elem(@seconds, 0)} work={elem(@seconds, 1)} />
        </div>
      </div>
    </article>
    """
  end

  defp place(assigns) do
    ~H"""
    <button
      :if={@audit == nil}
      type="button"
      id={"place-#{@slot}"}
      class="page w-full"
      data-track="free page"
      data-chosen={to_string(@chosen)}
      aria-pressed={to_string(@chosen)}
      title={"Page #{@slot} is free. Print a project here."}
      aria-label={"Page #{@slot} is free. Print a project here."}
      phx-click={JS.push("choose", value: %{slot: to_string(@slot)}) |> JS.focus(to: "#project")}
    >
      <span>{@slot}</span><small aria-hidden="true">Free</small>
    </button>
    <a
      :if={@audit}
      id={"place-#{@slot}"}
      class="page"
      data-track="printed page"
      href={~p"/a/#{@audit.id}"}
      title={"#{@audit.repository}: #{tag(@audit)}"}
      aria-label={"Page #{@slot}, #{@audit.repository}: #{tag(@audit)}"}
    >
      <span>{@slot}</span><small>{short(@audit.repository)}</small>
    </a>
    """
  end

  # A long name breaks after a separator (zero-width space), not in the middle of a word.
  defp short(repository),
    do: repository |> String.split("/") |> List.last() |> String.replace(~r/[_.-]/, "\\0\u200B")

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :words, :string, required: true
  attr :tag, :string, required: true
  attr :picture, :map, default: nil
  attr :grade, :map, default: nil
  attr :finding, :map, default: nil

  defp card(assigns) do
    ~H"""
    <a
      href={~p"/a/#{@id}"}
      data-track="edition card"
      class="flex flex-wrap items-start gap-4 border-b-2 border-bark py-4"
    >
      <img
        :if={@picture}
        src={Press.photo_url(@picture, "jpg")}
        alt=""
        width="768"
        height="512"
        loading="lazy"
        class="w-20 shrink-0 border-2 border-bark sm:w-28"
      />
      <Press.grade :if={@grade} grade={@grade} />
      <span class="min-w-0 flex-1 basis-44">
        <strong class="block text-lg break-words">{@name}</strong>
        <span class="break-words">{@words}</span>
        <span :if={@finding && @finding.rated_by} class="mt-1 block">
          <Press.stamp finding={@finding} />
        </span>
      </span>
      <span class={["px-3 py-1 text-base font-bold whitespace-nowrap", tag_class(@tag)]}>
        {@tag}
      </span>
    </a>
    """
  end

  defp tag_class("Proven"), do: "bg-leaf text-white"
  defp tag_class("Suspicion"), do: "bg-way"
  defp tag_class(_), do: "bg-sand"

  defp tag(%{state: :examining}), do: "Being read"
  defp tag(%{findings: [_ | _]}), do: "Suspicion"
  defp tag(%{trials: [_ | _]}), do: "Suspicion"
  defp tag(_), do: "Nothing found"

  defp proven(own), do: Enum.find(own, &match?(%{trial: %{verdict: :accepted}}, &1))

  defp own_tag(%{trial: %{verdict: :accepted}}), do: "Proven"
  defp own_tag(%{audit: %{state: :done}}), do: "Not proven"
  defp own_tag(%{audit: %{state: :measuring}}), do: "Being measured"

  defp own_tag(%{audit: %{state: :awaiting_approval, council_done: true}, trial: nil}),
    do: "Not passed"

  defp own_tag(%{audit: %{state: :awaiting_approval}}), do: "Waiting"
  defp own_tag(_), do: "Being read"

  defp own_words(%{audit: %{state: :done}} = view) do
    case AuditView.before_after(view.trial.numbers) do
      [a, b] -> "#{view |> AuditView.result() |> elem(0)} #{a} → #{b}"
      nil -> view |> AuditView.result() |> elem(0)
    end
  end

  defp own_words(%{audit: %{state: :measuring}}),
    do: "Our own test project is being measured right now."

  defp own_words(%{audit: %{state: :awaiting_approval, council_done: true}, trial: nil}),
    do: "The council did not pass the proposal for our own test project."

  defp own_words(%{audit: %{state: :awaiting_approval}}),
    do: "Our own test project waits for the requester."

  defp own_words(_), do: "Our reporter is reading our own test project."
end
