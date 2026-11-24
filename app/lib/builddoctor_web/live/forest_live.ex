defmodule BuilddoctorWeb.ForestLive do
  @moduledoc "The public forest: 100 places, every free one is the start of an Examination."
  use BuilddoctorWeb, :live_view

  alias Builddoctor.Bench
  alias Builddoctor.Bench.Audit
  alias Builddoctor.Bench.Changes.Plant
  alias BuilddoctorWeb.{AuditView, Requester}
  alias PetalComponents.Field

  @texts %{
    "error.repository.invalid" =>
      "Please enter a project as owner/name or as its GitHub address.",
    "error.repository.planted" =>
      "This project already has a place in the forest. Its result is there.",
    "error.slot.taken" => "Somebody was faster. Please choose another place.",
    "error.limit.day" => "Today's free examinations are used up. New ones start at midnight UTC.",
    "error.limit.busy" =>
      "Several projects are being read right now. Please try again in a minute.",
    "error.slot.invalid" => "Please choose a free place."
  }

  @impl true
  def mount(params, session, socket) do
    if connected?(socket), do: BuilddoctorWeb.Endpoint.subscribe("audit:forest")

    {:ok,
     socket
     |> assign(page_title: "The public forest", chosen: nil, project: project(params), error: nil)
     |> assign(
       pending: false,
       known: nil,
       own_error: nil,
       requester: Requester.signed_in?(session),
       session: Map.take(session, ["requester_since"])
     )
     |> load()}
  end

  defp project(%{"project" => project}) when is_binary(project), do: String.slice(project, 0, 200)
  defp project(_), do: ""

  defp load(socket) do
    planted = Map.new(Bench.planted_audits!(), &{&1.slot, &1})
    free = Enum.reject(1..Audit.places(), &is_map_key(planted, &1))
    chosen = if socket.assigns.chosen in free, do: socket.assigns.chosen

    assign(socket,
      planted: planted,
      free: free,
      chosen: chosen,
      own: Enum.map(Bench.own_audits!(), &AuditView.load/1)
    )
  end

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
    # The same seed again gives the place back.
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
    slot = socket.assigns.chosen || List.first(socket.assigns.free)

    actor = Requester.actor(socket)

    case Bench.plant_audit(project, slot, actor: actor) do
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
    case project |> Plant.name() |> String.downcase() |> Bench.place_of() do
      {:ok, %{id: id}} -> id
      _ -> nil
    end
  end

  defp own_text(error) do
    if Exception.message(error) =~ "error.again.running",
      do: "Our test project is being read already.",
      else: "This is not possible right now."
  end

  defp text(error) do
    message = Exception.message(error)

    Enum.find_value(@texts, @texts["error.repository.invalid"], fn {key, text} ->
      if String.contains?(message, key), do: text
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="mx-auto grid max-w-6xl gap-6 px-4 py-6">
      <Layouts.brand />
      <h1 class="font-display text-3xl font-bold sm:text-5xl">
        Is your GitHub pipeline slower than it has to be?
      </h1>
      <form
        :if={@free != []}
        id="plant"
        phx-submit="plant"
        class="flex max-w-3xl flex-wrap items-end gap-3"
      >
        <Field.field
          id="project"
          name="project"
          label={if @chosen, do: "Project for place #{@chosen}", else: "Public project"}
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
          class="min-h-12 border-2 border-bark bg-white px-3 text-lg text-bark sm:text-lg focus-visible:border-madder focus-visible:ring-3 focus-visible:ring-madder"
          aria-invalid={to_string(@error != nil)}
          aria-describedby={@error && "project-error"}
        />
        <PC.button type="submit" phx-disable-with="Planting" label="Examine it" class="min-h-12" />
      </form>
      <p :if={@error} id="project-error" role="alert" class="text-madder">
        {@error}
        <a :if={@known} id="known" href={~p"/a/#{@known}"} class="inline-block py-2 underline">
          Open its result
        </a>
      </p>
      <p :if={@chosen} phx-window-keydown="release" phx-key="Escape">
        <PC.button type="button" variant="outline" phx-click="release" label="Choose another place" />
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
      <p aria-live="polite" id="count" class="text-lg">
        {if @free == [],
          do: "The forest is full. All #{Audit.places()} places are planted.",
          else: "#{map_size(@planted)} of #{Audit.places()} places planted."}
        <a :if={@free == []} href="#found" class="inline-block py-2 underline">See what was found</a>
        <span :if={@free != []}>Free and read-only. Choose a seed or just enter a project.</span>
      </p>
      <svg
        id="forest"
        viewBox="0 0 1200 420"
        class="block h-auto w-full border-2 border-bark"
        stroke-linejoin="round"
        stroke-linecap="round"
      >
        <title>The public forest</title>
        <defs>
          <linearGradient id="dawn" x2="0" y2="1">
            <stop stop-color="#7fb4b5" /><stop offset="1" stop-color="#fbe9bd" />
          </linearGradient>
        </defs>
        <rect width="1200" height="420" fill="url(#dawn)" />
        <circle cx="880" cy="96" r="58" fill="#fff4cf" />
        <path d="M0 150q200-80 420-20t430-30t350 10V420H0z" fill="#9db58f" />
        <path d="M0 186q260-70 520-10t680-30V420H0z" fill="#5f8a5c" />
        <path d="M0 200q300-34 620 0t580-12V420H0z" fill="#37603f" />
        <a :if={proven(@own)} href={~p"/a/#{proven(@own).audit.id}"}>
          <title>{proven(@own).audit.repository}: {own_words(proven(@own))}</title>
          <g transform="translate(1040 205) scale(2.1)"><.drawing kind={:tree} turn={0} /></g>
        </a>
        <.place
          :for={slot <- 1..Audit.places()}
          slot={slot}
          audit={@planted[slot]}
          chosen={@chosen == slot}
        />
      </svg>
      <section id="found" class="grid gap-3">
        <h2 class="font-display text-2xl font-bold">Examined so far</h2>
        <p :if={@own == [] and @planted == %{}}>Nothing yet. Be the first.</p>
        <ul id="own" class="grid gap-2">
          <li :for={view <- @own}>
            <.card
              id={view.audit.id}
              kind={own_kind(view)}
              name={view.audit.repository}
              words={own_words(view)}
              tag={own_tag(view)}
            />
          </li>
        </ul>
        <ul id="places" class="grid gap-2">
          <li
            :for={
              {slot, audit} <-
                Enum.sort_by(@planted, fn {_, a} -> a.inserted_at end, {:desc, DateTime})
            }
            id={"project-#{slot}"}
          >
            <.card
              id={audit.id}
              kind={kind(audit)}
              name={audit.repository}
              words={AuditView.summary(audit)}
              tag={tag(audit)}
            />
          </li>
        </ul>
      </section>
      <Layouts.footer requester={@requester} />
    </main>
    """
  end

  # Places stand in five rows of twenty; the whole cell can be clicked, so a finger hits one too.
  defp place(assigns) do
    row = div(assigns.slot - 1, 20)
    x = 30 + rem(assigns.slot - 1, 20) * 60 + :erlang.phash2({:x, assigns.slot}, 20) - 10

    assigns =
      assign(assigns,
        cell: "translate(#{rem(assigns.slot - 1, 20) * 60} #{210 + row * 42})",
        at: "translate(#{x} #{246 + row * 42})",
        turn: :erlang.phash2(assigns.slot, 17) - 8
      )

    ~H"""
    <g
      :if={@audit == nil}
      id={"place-#{@slot}"}
      class="seed cursor-pointer"
      data-chosen={to_string(@chosen)}
      phx-click={JS.push("choose", value: %{slot: to_string(@slot)}) |> JS.focus(to: "#project")}
    >
      <title>Place {@slot} is free. Plant a project here.</title>
      <g transform={@cell}><rect width="60" height="42" fill="transparent" /></g>
      <g transform={@at}><.drawing kind={:seed} turn={@turn} /></g>
    </g>
    <a :if={@audit} id={"place-#{@slot}"} href={~p"/a/#{@audit.id}"}>
      <title>{@audit.repository}: {tag(@audit)}</title>
      <g transform={@cell}><rect width="60" height="42" fill="transparent" /></g>
      <g transform={@at}><.drawing kind={kind(@audit)} turn={@turn} /></g>
    </a>
    """
  end

  defp card(assigns) do
    ~H"""
    <a
      href={~p"/a/#{@id}"}
      class="grid grid-cols-[3.5rem_1fr] items-center gap-x-4 gap-y-2 rounded-lg border-2 border-bark bg-white p-3 sm:grid-cols-[3.5rem_1fr_auto]"
    >
      <svg
        viewBox="-34 -64 68 70"
        class="size-14"
        aria-hidden="true"
        stroke-linejoin="round"
        stroke-linecap="round"
      >
        <.drawing kind={@kind} turn={0} />
      </svg>
      <span class="min-w-0">
        <strong class="block text-lg break-words">{@name}</strong>
        <span class="break-words">{@words}</span>
      </span>
      <span class={[
        "col-start-2 justify-self-start rounded-full px-3 py-1 text-base font-bold whitespace-nowrap sm:col-start-3",
        tag_class(@tag)
      ]}>
        {@tag}
      </span>
    </a>
    """
  end

  defp tag_class("Proven"), do: "bg-added"
  defp tag_class("Suspicion"), do: "bg-way"
  defp tag_class(_), do: "bg-sand"

  defp kind(%{state: :examining}), do: :sprout
  defp kind(_), do: :seedling

  defp tag(%{state: :examining}), do: "Being read"
  defp tag(%{findings: [_ | _]}), do: "Suspicion"
  defp tag(%{trials: [_ | _]}), do: "Suspicion"
  defp tag(_), do: "Nothing found"

  defp proven(own), do: Enum.find(own, &(own_kind(&1) == :tree))

  defp own_kind(%{trial: %{verdict: :accepted}}), do: :tree
  defp own_kind(_), do: :seedling

  defp own_tag(%{trial: %{verdict: :accepted}}), do: "Proven"
  defp own_tag(%{audit: %{state: :done}}), do: "Not proven"
  defp own_tag(%{audit: %{state: :measuring}}), do: "Being measured"
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

  defp own_words(%{audit: %{state: :awaiting_approval}}),
    do: "Our own test project waits for the requester."

  defp own_words(_), do: "The doctor is reading our own test project."

  attr :kind, :atom, required: true
  attr :turn, :integer, required: true

  # Small drawings of one hand: soil, ink outline, flat colors. The foot is at 0, 0.
  defp drawing(assigns) do
    ~H"""
    <g stroke="#14171f" stroke-width="2">
      <g :if={@kind == :seed}>
        <path d="M-12 2q12 -10 24 0z" fill="#7a5138" />
        <path d="M0 -3q-5 -5 0 -11q5 6 0 11z" fill="#f2b84b" />
      </g>
      <g :if={@kind == :sprout}>
        <path d="M-16 2q16 -12 32 0z" fill="#7a5138" />
        <g transform={"rotate(#{@turn})"}>
          <path d="M0 -4v-14" fill="none" /><path d="M0 -18q10 -11 16 -2q-7 9 -16 2z" fill="#cfdd7c" />
        </g>
      </g>
      <g :if={@kind == :seedling}>
        <path d="M-20 2q20 -14 40 0z" fill="#7a5138" />
        <g transform={"rotate(#{@turn})"}>
          <path d="M0 -5v-34" fill="none" />
          <path d="M0 -20q-18 -12 -24 2q10 10 24 -2z" fill="#7aa647" />
          <path d="M0 -34q16 -18 26 -2q-10 12 -26 2z" fill="#cfdd7c" />
        </g>
      </g>
      <g :if={@kind == :tree}>
        <path d="M-5 2q3 -16 2 -32h6q-1 16 2 32z" fill="#4d3526" />
        <circle cx="-14" cy="-34" r="14" fill="#4f8f57" /><circle
          cx="14"
          cy="-34"
          r="14"
          fill="#2f7a6b"
        />
        <circle cx="0" cy="-47" r="15" fill="#7aa647" />
      </g>
    </g>
    """
  end
end
