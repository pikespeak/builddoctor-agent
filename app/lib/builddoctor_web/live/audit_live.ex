defmodule BuilddoctorWeb.AuditLive do
  @moduledoc "One page per Audit: examine, approval, measure and verdict on one living stage."
  use BuilddoctorWeb, :live_view

  alias Builddoctor.Bench
  alias Builddoctor.Bench.{Actor, Audit}
  alias PetalComponents.Card
  alias BuilddoctorWeb.{AuditView, Press, Requester, Suggestion, Timeline}

  @impl true
  def mount(params, session, socket) do
    socket =
      assign(socket,
        session: Map.take(session, ["requester_since", "visitor"]),
        requester: Requester.signed_in?(session),
        pending: false,
        ticking: nil,
        proof: false,
        asking: false,
        message: nil,
        contact: contact()
      )

    case find(params, Requester.viewer(session)) do
      nil ->
        {:ok, assign(socket, view: nil, teaser: nil, page_title: "BuildDoctor")}

      audit ->
        if connected?(socket), do: BuilddoctorWeb.Endpoint.subscribe("audit:#{audit.id}")

        {:ok,
         socket
         |> assign(page_title: audit.repository, live: audit.state == :examining)
         |> show(audit)
         |> tease()}
    end
  end

  # Chosen once, so that it does not change while somebody reads.
  defp tease(socket) do
    viewer = Requester.viewer(socket.assigns.session)
    assign(socket, teaser: AuditView.teaser(socket.assigns.view, viewer))
  end

  defp feed(%{repository: repository}) do
    [owner, name] = String.split(repository, "/")
    ~p"/feed/#{owner}/#{name}"
  end

  defp contact do
    case BuilddoctorWeb.Imprint.load() do
      %{email: email} -> email
      nil -> nil
    end
  end

  defp find(%{"id" => id}, viewer) do
    case Bench.get_audit(id, actor: viewer) do
      {:ok, audit} -> audit
      _ -> nil
    end
  end

  defp show(socket, audit) do
    requester = Requester.signed_in?(socket.assigns.session)

    socket
    |> assign(
      view: AuditView.load(audit, Requester.viewer(socket.assigns.session)),
      requester: requester,
      may_start: Requester.may_start?(socket.assigns.session)
    )
    |> assign(notices: notices(requester, audit))
    |> draw()
    |> tick()
  end

  defp notices(true, audit), do: Bench.list_notices!(audit.id, actor: Actor.requester())
  defp notices(false, _), do: []

  # The seconds of a running job count on between two reports of the agent. One timer at most;
  # a sooner one replaces a later one.
  defp tick(%{assigns: %{view: view, ticking: ticking}} = socket) do
    wait =
      cond do
        AuditView.running?(view) -> 1000
        view.audit.state == :measuring -> 15_000
        true -> nil
      end

    left = if ticking, do: Process.read_timer(ticking) || 0

    if connected?(socket) and wait != nil and (left == nil or left > wait) do
      if ticking, do: Process.cancel_timer(ticking)
      assign(socket, ticking: Process.send_after(self(), :tick, wait))
    else
      socket
    end
  end

  defp draw(socket),
    do: assign(socket, timelines: AuditView.timelines(socket.assigns.view))

  # Many small messages become one redraw.
  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{}, %{assigns: %{pending: true}} = socket),
    do: {:noreply, socket}

  def handle_info(%Phoenix.Socket.Broadcast{}, socket) do
    Process.send_after(self(), :refresh, 250)
    {:noreply, assign(socket, pending: true)}
  end

  def handle_info(_, %{assigns: %{view: nil}} = socket), do: {:noreply, socket}

  def handle_info(:tick, socket),
    do: {:noreply, socket |> assign(ticking: nil) |> draw() |> tick()}

  def handle_info(:refresh, socket) do
    socket = assign(socket, pending: false)

    viewer = Requester.viewer(socket.assigns.session)

    case Bench.get_audit(socket.assigns.view.audit.id, actor: viewer) do
      {:ok, audit} -> {:noreply, show(socket, audit)}
      {:error, _} -> {:noreply, assign(socket, view: nil)}
    end
  end

  @impl true
  def handle_event("proof", _, socket), do: {:noreply, update(socket, :proof, &(not &1))}
  def handle_event("approve", _, socket), do: act(socket, &Bench.approve_audit(&1, actor: &2))

  def handle_event("ask", _, socket), do: {:noreply, assign(socket, asking: true)}
  def handle_event("keep", _, socket), do: {:noreply, assign(socket, asking: false)}

  def handle_event("again", _, socket) do
    actor = Requester.actor(socket)

    case Bench.examine_again(
           socket.assigns.view.audit.id,
           %{visitor: socket.assigns.session["visitor"]},
           actor: actor
         ) do
      {:ok, audit} -> {:noreply, push_navigate(socket, to: ~p"/a/#{audit.id}")}
      {:error, error} -> {:noreply, assign(socket, message: again(error))}
    end
  end

  def handle_event("stop", _, socket),
    do: act(socket, &Bench.stop_audit(&1, "Stopped by the requester.", actor: &2))

  # Only after the question; a stray click or message deletes nothing.
  def handle_event("remove", _, %{assigns: %{requester: true, asking: false}} = socket),
    do: {:noreply, socket}

  def handle_event("remove", _, socket) do
    actor = Requester.actor(socket)

    case Bench.remove_audit(socket.assigns.view.audit, actor: actor) do
      :ok -> {:noreply, push_navigate(socket, to: ~p"/")}
      {:error, _} -> {:noreply, assign(socket, message: "This is not possible right now.")}
    end
  end

  defp again(error) do
    message = Exception.message(error)

    cond do
      message =~ "error.again.tooSoon" ->
        "This project was examined in the last 24 hours. Please come back later."

      message =~ "error.limit.day" ->
        "Today's free examinations are used up. New ones start at midnight UTC."

      message =~ "error.limit.visitor" ->
        "You have used up your examinations for today. Please come back tomorrow."

      message =~ "error.limit.busy" ->
        "Several projects are being read right now. Please try again in a minute."

      message =~ "error.again.running" ->
        "This project is being examined again already."

      true ->
        "This is not possible right now."
    end
  end

  defp act(socket, fun) do
    actor = Requester.actor(socket)

    case fun.(socket.assigns.view.audit, actor) do
      {:ok, audit} -> {:noreply, socket |> assign(message: nil, asking: false) |> show(audit)}
      {:error, _} -> {:noreply, assign(socket, message: "This is not possible right now.")}
    end
  end

  @impl true
  def render(%{view: nil} = assigns) do
    ~H"""
    <Layouts.nothing
      title="No audit here"
      text="The address is wrong, or the project was removed."
    />
    """
  end

  def render(assigns) do
    ~H"""
    <main class="mx-auto grid max-w-6xl gap-6 px-4 py-6">
      <Layouts.brand />
      <h1 class="font-display text-2xl break-words sm:text-4xl">
        {@view.audit.repository}{if @view.audit.slot, do: ", page #{@view.audit.slot}"}
      </h1>
      <.edition :if={foreign?(@view.audit)} view={@view} live={@live} />
      <section aria-live="polite" class="grid gap-4 text-lg">
        <.moment
          view={@view}
          requester={@requester}
          proof={@proof}
          asking={@asking}
          may_start={@may_start}
        />
        <p :if={@message} role="alert" class="text-madder">{@message}</p>
      </section>
      <.other view={@view} />
      <.notices :if={@notices != []} notices={@notices} />
      <.findings view={@view} live={@live} />
      <div
        :if={@timelines != []}
        id="jobs"
        class="grid gap-5 border-2 border-bark bg-white p-4 sm:p-6"
      >
        <section :for={{{title, rows}, i} <- Enum.with_index(@timelines)} class="grid gap-3">
          <h2 class="font-display text-2xl font-bold">{title}</h2>
          <Timeline.timeline id={"timeline-#{i}"} label={title} rows={rows} />
        </section>
        <p class="text-base text-moss">
          The bar is work; the dashed line is waiting.
          <span :if={AuditView.more_jobs(@view.audit)}>{AuditView.more_jobs(@view.audit)}</span>
        </p>
      </div>
      <.suggestion_for view={@view} />
      <.facts view={@view} />
      <.grade_for view={@view} />
      <.next_story :if={@teaser} audit={@teaser} />
      <p :if={foreign?(@view.audit)} id="maintainer" class="max-w-prose border-l-4 border-bark pl-4">
        Is this your project? You can ask us to correct or remove this page.
        <a :if={@contact} class="inline-block py-2 underline" href={"mailto:#{@contact}"}>{@contact}</a>
        <a class="inline-block py-2 underline" href={~p"/privacy"}>What we store</a>
      </p>
      <p
        :if={foreign?(@view.audit) and @view.audit.state == :examined}
        id="follow"
        class="max-w-prose border-l-4 border-bark pl-4"
      >
        <a class="inline-block py-2 font-bold underline" href={feed(@view.audit)}>Follow this project in a feed reader</a>
        New editions appear there when somebody prints one again. Private repositories:
        <a class="inline-block py-2 underline" href={~p"/subscribe"}>join the waiting list</a>
      </p>
      <section :if={@view.events != []}>
        <h2 class="font-display text-2xl font-bold">How this edition was made</h2>
        <ol class="mt-3 grid gap-2">
          <li :for={e <- AuditView.events(@view)} class="flex flex-wrap gap-x-3">
            <time class="tabular-nums text-moss" datetime={e.inserted_at}>{Calendar.strftime(
              e.inserted_at,
              "%H:%M:%S"
            )} UTC</time>
            <span class="min-w-0 break-words">{e.message}</span>
            <a :if={e.reference} href={e.reference} class="underline" rel="noopener">See it on GitHub</a>
          </li>
        </ol>
      </section>
      <Layouts.footer requester={@requester} />
    </main>
    """
  end

  # The Examination before or after this one.
  defp other(assigns) do
    ~H"""
    <p :if={@view.newer} id="newer" class="border-2 border-bark bg-way p-3">
      {newer_words(@view.newer)}
      <a
        :if={@view.newer.state != :stopped}
        href={~p"/a/#{@view.newer.id}"}
        class="inline-block py-2 underline"
      >
        Open it
      </a>
    </p>
    <p :if={@view.audit.replaces_id && @view.audit.state in [:examining, :stopped]} id="older">
      The earlier result stays.
      <a href={~p"/a/#{@view.audit.replaces_id}"} class="inline-block py-2 underline">Open it</a>
    </p>
    """
  end

  defp newer_words(%{state: :examining}), do: "This project is being examined again."
  defp newer_words(%{state: :stopped} = a), do: "The latest attempt stopped: #{a.stop_reason}"
  defp newer_words(_), do: "There is a newer result."

  defp moment(%{view: %{audit: %{state: :examining}}} = assigns) do
    ~H"""
    <p>This page updates by itself.</p>
    <p :if={@view.waits} id="waits" class="border-2 border-bark bg-way p-3">
      GitHub lets us read again at <time datetime={@view.waits}>{Calendar.strftime(
        @view.waits,
        "%H:%M"
      )} UTC</time>. Reading goes on by itself, and nothing is lost.
    </p>
    <p :if={@view.audit.slot && @view.waits == nil} class="max-w-prose">
      Several projects are read at once. When GitHub's hourly limit is reached, reading goes on later.
    </p>
    <ol id="steps" class="grid gap-1">
      <li :for={{words, done} <- AuditView.steps(@view)} data-done={to_string(done)}>
        <span aria-hidden="true">{if done, do: "✓", else: "○"}</span>
        {words}<span class="sr-only">{if done, do: ", done", else: ", not done yet"}</span>
      </li>
    </ol>
    <p class="flex flex-wrap gap-3">
      <PC.button
        type="button"
        variant="outline"
        label="Copy the link"
        phx-click={JS.dispatch("builddoctor:copy", detail: %{text: url(~p"/a/#{@view.audit.id}")})}
      />
      <PC.button link_type="a" to={~p"/"} variant="outline" label="Back to the front page" />
    </p>
    <.stop :if={@requester} asking={@asking} measuring={false} />
    """
  end

  defp moment(%{view: %{audit: %{state: :awaiting_approval}, trial: nil}} = assigns) do
    ~H"""
    <p>The council is checking the proposal. Nothing starts before it has passed.</p>
    <.stop :if={@requester} asking={@asking} measuring={false} />
    """
  end

  defp moment(%{view: %{audit: %{state: :awaiting_approval}}} = assigns) do
    ~H"""
    <p class="max-w-prose">{@view.trial.hypothesis}</p>
    <p>
      Goal: <strong>{AuditView.goal(@view.trial.goal)}</strong>. {AuditView.total()} runs on GitHub, on two new branches. The main branch stays as it is.
    </p>
    <.change trial={@view.trial} path={@view.audit.workflow_path} />
    <div :if={@requester} class="flex flex-wrap gap-3">
      <PC.button phx-click="approve" phx-disable-with="Starting" label="Start the trial" />
      <.stop asking={@asking} measuring={false} />
    </div>
    <p :if={!@requester}>
      Waiting for the requester.
      <a href={~p"/requester?audit=#{@view.audit.id}"} class="inline-block py-2 underline">
        Are you the requester? Unlock the controls.
      </a>
    </p>
    """
  end

  defp moment(%{view: %{audit: %{state: :measuring}}} = assigns) do
    ~H"""
    <p class="font-bold tabular-nums">
      {AuditView.count(@view)} of {AuditView.total()} runs finished{side_text(@view.audit.live_side)}
    </p>
    <ol class="flex flex-wrap gap-2" aria-label="Finished runs">
      <li :for={r <- @view.runs} class="border border-bark px-2 py-1 text-base tabular-nums">
        {if r.trial_id, do: "Change", else: "Before"} {r.wall_seconds} s{if r.warmup, do: " (warm-up)"}
      </li>
    </ol>
    <p :if={@view.runs == [] and (@view.audit.live_jobs || []) == []} id="preparing">
      Preparing two branches. The first run starts when they are ready.
    </p>
    <p :if={AuditView.silent(@view.audit)} id="silent" class="border-2 border-bark bg-way p-3">
      No news for {AuditView.silent(@view.audit)} minutes. The run may be queued at GitHub.
      <a
        href={"https://github.com/#{@view.audit.repository}/actions"}
        class="inline-block py-2 underline"
        rel="noopener"
      >See it on GitHub</a>
    </p>
    <.stop :if={@requester} asking={@asking} measuring />
    """
  end

  defp moment(%{view: %{audit: %{state: :examined}}} = assigns) do
    ~H"""
    <p class="max-w-prose">
      We only read this project. The facts are computed from GitHub's data. The findings are a model's reading of them, so they are not proof. Statements that the council did not pass are not shown.
    </p>
    <p :if={@view.findings == [] and @view.trial == nil} id="calm" class="max-w-prose">
      That is a result too: no statement passed every check.
    </p>
    <div class="flex flex-wrap gap-3">
      <PC.button
        :if={@view.audit.slot && (@requester or (@may_start and AuditView.due?(@view.audit)))}
        type="button"
        phx-click="again"
        phx-disable-with="Starting"
        label="Examine again"
      />
      <PC.button link_type="a" to={~p"/"} variant="outline" label="Examine another project" />
      <PC.button
        :if={@requester && @view.audit.slot && !@asking}
        type="button"
        phx-click="ask"
        variant="ghost"
        label="Remove this project"
      />
    </div>
    <div
      :if={@requester && @view.audit.slot && @asking}
      id="sure-remove"
      role="group"
      aria-label="Remove for good?"
      class="grid gap-3 border-2 border-madder bg-white p-4"
    >
      <strong>
        Remove {@view.audit.repository} for good? All of its results are deleted. This cannot be undone.
      </strong>
      <div class="flex flex-wrap gap-3">
        <PC.button type="button" phx-click="keep" label="Keep it" />
        <PC.button
          type="button"
          phx-click="remove"
          phx-disable-with="Removing"
          variant="outline"
          label="Remove it for good"
        />
      </div>
    </div>
    """
  end

  defp moment(%{view: %{audit: %{state: :stopped}}} = assigns) do
    ~H"""
    <p>Stopped: {@view.audit.stop_reason}</p>
    <p :if={foreign?(@view.audit) and @view.audit.replaces_id == nil}>
      Its page is blank again. Visitors can enter this project again 24 hours after it was started.
    </p>
    <div class="flex flex-wrap gap-3">
      <PC.button
        :if={@requester and foreign?(@view.audit) and @view.audit.replaces_id == nil}
        link_type="a"
        to={~p"/?#{[project: @view.audit.repository]}"}
        label="Try again"
      />
      <PC.button link_type="a" to={~p"/"} variant="outline" label="Back to the front page" />
    </div>
    """
  end

  defp moment(assigns) do
    {headline, reason} = AuditView.result(assigns.view)
    assigns = assign(assigns, headline: headline, reason: reason, n: assigns.view.trial.numbers)
    assigns = assign(assigns, medians: AuditView.before_after(assigns.n))

    ~H"""
    <h2 class="font-display text-3xl font-bold">{@headline}</h2>
    <p :if={@medians} class="text-2xl font-bold tabular-nums">
      {Enum.at(@medians, 0)} <span aria-hidden="true">→</span>
      <span class="sr-only">before,</span> {Enum.at(@medians, 1)}
      <span class="text-base font-normal">
        <span class="sr-only">with the change,</span> median {AuditView.goal(@view.trial.goal)}
      </span>
    </p>
    <p>{@reason}</p>
    <div>
      <PC.button
        phx-click="proof"
        variant="ghost"
        aria-expanded={to_string(@proof)}
        label="Show the proof"
      />
    </div>
    <div class="overflow-x-auto">
      <table class="text-left tabular-nums">
        <thead>
          <tr>
            <th class="pr-6"></th><th class="pr-6">Before</th><th class="pr-6">With the change</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={m <- ["wait", "bill"]}>
            <th scope="row" class="pr-6">
              {String.capitalize(m)}{if m == @n["goal"], do: " (goal)"}
            </th>
            <td :for={s <- ["baseline", "candidate"]} class="pr-6">{range(@n[s], m)}</td>
          </tr>
        </tbody>
      </table>
    </div>
    <ul :if={@proof} class="grid gap-1">
      <li :for={r <- @view.runs}>
        <a
          class="underline"
          rel="noopener"
          href={"https://github.com/#{@view.audit.repository}/actions/runs/#{r.github_run_id}"}
        >
          {if r.trial_id, do: "With the change", else: "Before"}: {r.wall_seconds} s, {r.billed_minutes} billed min
        </a>
        {if r.warmup, do: " (warm-up, not counted)"}{if !r.succeeded, do: " (failed)"}
      </li>
      <li class="text-moss">
        Three measured runs per side on GitHub-hosted runners, in alternation. These times say nothing about how long a run that fails early would take.
      </li>
    </ul>
    """
  end

  # A trial belongs to our own project; a foreign one is only read.
  defp foreign?(audit), do: audit.repository not in Audit.measurable()

  defp stop(assigns) do
    ~H"""
    <div :if={!@asking}>
      <PC.button type="button" phx-click="ask" variant="outline" label="Stop" />
    </div>
    <div
      :if={@asking}
      id="sure"
      role="group"
      aria-label="Stop for sure?"
      class="flex flex-wrap items-center gap-3"
    >
      <strong>
        {if @measuring,
          do: "Stop this trial? Finished runs will not count for a verdict.",
          else: "Stop this audit?"}
      </strong>
      <PC.button type="button" phx-click="keep" label="Keep going" />
      <PC.button type="button" phx-click="stop" variant="outline" label="Stop it" />
    </div>
    """
  end

  # The newspaper of one project. Articles appear only after the council has passed them.
  defp edition(%{view: %{audit: %{state: state}}} = assigns)
       when state in [:examining, :examined] do
    working = state == :examining
    lead = List.first(assigns.view.findings)
    # The headline comes last; while it is written, its place stays open.
    ready = not working or AuditView.line(assigns.view.lines, :headline) != nil

    assigns =
      assign(assigns,
        working: working,
        lead: lead,
        ready: ready,
        headline: if(ready, do: AuditView.headline(told(assigns.view))),
        seconds: lead && AuditView.waited(lead, assigns.view.audit)
      )

    ~H"""
    <section id="edition" class="lead grid gap-5 border-t-8 border-bark pt-3">
      <p :if={@working} id="status" role="status" class="bg-sun p-3 font-bold">
        {AuditView.status(@view)}
      </p>
      <h2 :if={@ready} class="headline" data-long={to_string(String.length(@headline) > 34)}>
        <Press.typed id={"headline-#{:erlang.phash2(@headline)}"} text={@headline} live={@live} slow />
      </h2>
      <div :if={!@ready} class="lines huge" aria-hidden="true"><i style="width:78%"></i></div>
      <div class="grid items-start gap-6 md:grid-cols-[1.6fr_1fr]">
        <Press.photo
          audit={@view.audit}
          place={1}
          picture={@view.pictures[1]}
          lines={@view.lines}
          working={@working}
          live={@live}
          auto
        />
        <div class="grid content-start gap-4">
          <Press.lines :if={@lead == nil and @working} head={58} />
          <p :if={@lead} class="text-lg">
            <Press.typed id={"lead-#{key(@lead)}"} text={@lead.text} live={@live} />
          </p>
          <p :if={@lead != nil or not @working} class="font-bold">
            {if @lead, do: "A suspicion, not proof.", else: "That is a result too."}
          </p>
          <p :if={@view.audit.grade} class="flex items-center gap-4">
            <Press.grade grade={@view.audit.grade} big />
            <a href="#grade" class="inline-block py-2 underline">Why this grade</a>
          </p>
          <p :if={patch?(@view)} id="has-patch">
            <PC.button link_type="a" to="#suggestion" label="There is a patch" />
          </p>
          <Press.seconds :if={@seconds} wait={elem(@seconds, 0)} work={elem(@seconds, 1)} />
        </div>
      </div>
      <div class="grid items-start gap-6 sm:grid-cols-2">
        <Press.photo
          :for={place <- 2..3}
          :if={!in_article?(@view, place)}
          audit={@view.audit}
          place={place}
          picture={@view.pictures[place]}
          lines={@view.lines}
          working={@working}
          live={@live}
        />
      </div>
    </section>
    """
  end

  defp edition(assigns), do: ~H""

  defp told(%{audit: audit} = view),
    do: %{audit | findings: view.findings, trials: List.wrap(view.trial), lines: view.lines}

  # A grade shows every point it takes off.
  defp grade_for(%{view: %{audit: %{grade: nil}}} = assigns), do: ~H""

  defp grade_for(assigns) do
    ~H"""
    <section id="grade" class="grid gap-3 border-t-8 border-bark pt-4">
      <h2 class="font-display text-3xl uppercase">
        Grade {@view.audit.grade.letter}: {@view.audit.grade.points} of 100 points
      </h2>
      <ul class="grid max-w-prose">
        <li
          :for={{points, words} <- @view.audit.grade.off}
          class="flex justify-between gap-6 border-b border-bark py-2"
        >
          <span>{words}</span><strong class="whitespace-nowrap">−{points}</strong>
        </li>
      </ul>
      <p :if={@view.audit.grade.off == []}>Nothing was taken off.</p>
      <p class="max-w-prose">
        Computed by code from the GitHub data of this examination; not a judgment of the project. Duration and waiting for a runner do not count.
        <a href={~p"/how-it-works#grades"} class="inline-block py-2 underline">How we grade</a>
      </p>
    </section>
    """
  end

  defp next_story(assigns) do
    assigns =
      assign(assigns,
        headline: AuditView.headline(assigns.audit),
        picture: Enum.find(assigns.audit.pictures, &(&1.place == 1 and &1.state == :done))
      )

    ~H"""
    <aside id="teaser" aria-label="Another edition" class="bg-sun">
      <a href={~p"/a/#{@audit.id}"} class="flex flex-wrap items-center gap-5 p-5">
        <img
          :if={@picture}
          src={Press.photo_url(@picture, "jpg")}
          alt=""
          width="768"
          height="512"
          loading="lazy"
          class="w-full border-3 border-bark sm:w-56"
        />
        <Press.grade :if={@audit.grade} grade={@audit.grade} big />
        <span class="min-w-0 flex-1 basis-52">
          <span class="font-bold">Also in print: {@audit.repository}</span>
          <span class="font-display block text-3xl uppercase">{@headline}</span>
        </span>
      </a>
    </aside>
    """
  end

  # A picture stands in its article as soon as both are there.
  defp in_article?(view, place) do
    case view.pictures[place] do
      %{finding_id: id} when id != nil -> Enum.any?(view.findings, &(&1.id == id))
      _ -> false
    end
  end

  # The picture of the lead stands at the top of the page.
  defp picture_of(view, finding) do
    Enum.find(Map.values(view.pictures), &(&1.place > 1 and &1.finding_id == finding.id))
  end

  defp key(%{id: id}), do: id

  defp findings(%{view: %{audit: %{state: :examining}, findings: []}} = assigns) do
    ~H"""
    <section id="articles" class="grid gap-8 md:grid-cols-2" aria-hidden="true">
      <Press.lines head={64} /><Press.lines head={47} widths={[98, 100, 91, 97, 54]} />
    </section>
    """
  end

  defp findings(assigns) do
    ~H"""
    <section :if={@view.findings != []} id="findings" class="grid gap-3 border-t-8 border-bark pt-4">
      <h2 class="font-display text-3xl uppercase">Findings</h2>
      <ol class="grid gap-6 md:grid-cols-2">
        <li :for={f <- @view.findings} class="min-w-0">
          <article class={["h-full p-4 sm:p-5", if(sober?(f), do: "bg-white", else: "bg-paper")]}>
            <h3 class={
              if sober?(f),
                do: "text-xl font-bold",
                else: "font-display text-2xl uppercase sm:text-3xl"
            }>
              <Press.typed id={"title-#{f.id}"} text={f.title} live={@live} slow />
            </h3>
            <div :if={picture = picture_of(@view, f)} class="mt-3">
              <Press.photo
                audit={@view.audit}
                place={picture.place}
                picture={picture}
                lines={@view.lines}
                working={@view.audit.state == :examining}
                live={@live}
              />
            </div>
            <p class="mt-2 font-bold">
              <span class="bg-way px-2 py-1">{if AuditView.kind(f), do: AuditView.kind(f) <> " · "}Suspicion, checked by QA and Safety</span>
            </p>
            <p class="mt-3 max-w-prose">
              <Press.typed id={"text-#{f.id}"} text={f.text} live={@live} />
            </p>
            <p :if={f.advice} class="mt-2 max-w-prose">
              <strong>Try:</strong> <Press.typed id={"advice-#{f.id}"} text={f.advice} live={@live} />
            </p>
            <ul
              class="mt-3 grid gap-1 border-t border-bark pt-3 text-base"
              aria-label="Facts behind it"
            >
              <li :for={fact <- AuditView.evidence(f, @view.audit)} class="text-moss">
                <.fact fact={fact} audit={@view.audit} />
              </li>
            </ul>
          </article>
        </li>
      </ol>
    </section>
    """
  end

  # Failures and weaknesses are told without a show.
  defp sober?(%{kind: kind}), do: kind in [:failure, :file_error, :security]

  defp fact(assigns) do
    ~H"""
    {@fact.text}
    <a
      :if={@fact.commit}
      class="underline"
      rel="noopener"
      href={"https://github.com/#{@audit.repository}/commit/#{@fact.commit}"}
    >See the commit</a>
    """
  end

  defp notices(assigns) do
    ~H"""
    <section id="notices" class="grid gap-2 border-2 border-madder bg-white p-4 sm:p-6">
      <h2 class="font-display text-2xl font-bold">Only you see this</h2>
      <p>Tell the maintainer first. Visitors and models do not get these lines.</p>
      <ul class="grid list-disc gap-1 pl-6">
        <li :for={n <- @notices}>Line {n.line}: {AuditView.notice(n)}</li>
      </ul>
    </section>
    """
  end

  defp facts(assigns) do
    ~H"""
    <section :if={(@view.audit.facts || []) != []} id="facts" class="grid gap-3">
      <h2 class="font-display text-2xl font-bold">Facts</h2>
      <p>Computed from GitHub's data, without a model.</p>
      <ul class="grid list-disc gap-1 pl-6">
        <li :for={fact <- @view.audit.facts}><.fact fact={fact} audit={@view.audit} /></li>
      </ul>
    </section>
    """
  end

  defp suggestion_for(%{view: %{trial: %{original: o}, audit: %{state: s}}} = assigns)
       when is_binary(o) and s in [:examined, :done] do
    ~H"""
    <p :if={@view.audit.state == :examined} class="max-w-prose text-lg">{@view.trial.hypothesis}</p>
    <.change trial={@view.trial} path={@view.audit.workflow_path} />
    <Suggestion.suggestion
      :if={@view.audit.state == :examined or @view.trial.verdict == :accepted}
      audit={@view.audit}
      trial={@view.trial}
    />
    """
  end

  defp suggestion_for(assigns), do: ~H""

  defp patch?(%{trial: %{original: o}, audit: %{state: :examined}}) when is_binary(o), do: true
  defp patch?(_), do: false

  defp change(assigns) do
    ~H"""
    <Card.card class="border-bark bg-white p-4 sm:p-6">
      <h2 class="font-display text-2xl font-bold">The change</h2>
      <p class="font-mono text-base break-words">{@path}</p>
      <div
        id="change"
        class="mt-3 overflow-x-auto border border-bark focus-visible:outline-3 focus-visible:outline-madder"
        role="region"
        aria-label="The change to the workflow"
        tabindex="0"
      >
        <ol class="w-max min-w-full py-1 font-mono text-sm leading-6">
          <li
            :for={row <- AuditView.change(@trial)}
            class={["flex gap-3 px-3", row_class(row.kind)]}
            data-kind={row.kind}
          >
            <span class="w-8 shrink-0 text-right select-none" aria-hidden="true">{row.number}</span>
            <span class="w-3 shrink-0 font-bold" aria-hidden="true">{sign(row.kind)}</span>
            <span :if={row.kind in [:removed, :added]} class="sr-only">{row.kind}:</span>
            <code class="whitespace-pre">{row.text}</code>
          </li>
        </ol>
      </div>
    </Card.card>
    """
  end

  defp row_class(:removed), do: "bg-removed"
  defp row_class(:added), do: "bg-added"
  defp row_class(:gap), do: "text-moss italic"
  defp row_class(:same), do: nil

  defp sign(:removed), do: "-"
  defp sign(:added), do: "+"
  defp sign(_), do: ""

  defp side_text(nil), do: ""
  defp side_text(:baseline), do: ", now without the change"
  defp side_text(:trial), do: ", now with the change"

  defp range(nil, _), do: "no runs"

  defp range(summary, m) do
    %{"median" => median, "min" => low, "max" => high} = summary[m]
    "#{median} #{AuditView.unit(m)} (#{low} to #{high})"
  end
end
