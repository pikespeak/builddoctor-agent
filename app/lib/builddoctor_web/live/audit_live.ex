defmodule BuilddoctorWeb.AuditLive do
  @moduledoc "One page per Audit: examine, approval, measure and verdict on one living stage."
  use BuilddoctorWeb, :live_view

  alias Builddoctor.{Bench, Forest}
  alias Builddoctor.Bench.{Actor, Audit}
  alias PetalComponents.Card
  alias BuilddoctorWeb.{AuditView, Requester, Suggestion, Timeline}

  @impl true
  def mount(params, session, socket) do
    socket =
      assign(socket,
        session: Map.take(session, ["requester_since"]),
        requester: Requester.signed_in?(session),
        side: :after,
        pending: false,
        ticking: nil,
        proof: false,
        asking: false,
        message: nil,
        contact: contact()
      )

    case find(params) do
      nil ->
        {:ok, assign(socket, view: nil, page_title: "BuildDoctor")}

      audit ->
        if connected?(socket), do: BuilddoctorWeb.Endpoint.subscribe("audit:#{audit.id}")
        {:ok, socket |> assign(page_title: audit.repository) |> show(audit)}
    end
  end

  defp contact do
    case BuilddoctorWeb.Imprint.load() do
      %{email: email} -> email
      nil -> nil
    end
  end

  defp find(%{"id" => id}) do
    case Bench.get_audit(id) do
      {:ok, audit} -> audit
      _ -> nil
    end
  end

  defp show(socket, audit) do
    requester = Requester.signed_in?(socket.assigns.session)

    socket
    |> assign(view: AuditView.load(audit), requester: requester)
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

  defp draw(socket) do
    plan = AuditView.plan(socket.assigns.view, socket.assigns.side)

    assign(socket,
      plan: plan,
      scene: Forest.scene(plan),
      timelines: AuditView.timelines(socket.assigns.view)
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

  def handle_info(_, %{assigns: %{view: nil}} = socket), do: {:noreply, socket}

  def handle_info(:tick, socket),
    do: {:noreply, socket |> assign(ticking: nil) |> draw() |> tick()}

  def handle_info(:refresh, socket) do
    socket = assign(socket, pending: false)

    case Bench.get_audit(socket.assigns.view.audit.id) do
      {:ok, audit} -> {:noreply, show(socket, audit)}
      {:error, _} -> {:noreply, assign(socket, view: nil)}
    end
  end

  @impl true
  def handle_event("side", %{"side" => side}, socket) when side in ["before", "after"] do
    {:noreply, socket |> assign(side: String.to_existing_atom(side)) |> draw()}
  end

  def handle_event("proof", _, socket), do: {:noreply, update(socket, :proof, &(not &1))}
  def handle_event("approve", _, socket), do: act(socket, &Bench.approve_audit(&1, actor: &2))

  def handle_event("ask", _, socket), do: {:noreply, assign(socket, asking: true)}
  def handle_event("keep", _, socket), do: {:noreply, assign(socket, asking: false)}

  def handle_event("again", _, socket) do
    actor = Requester.actor(socket)

    case Bench.examine_again(socket.assigns.view.audit.id, actor: actor) do
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
      <h1 class="font-display text-3xl font-bold break-words sm:text-5xl">
        {@view.audit.repository}
      </h1>
      <section aria-live="polite" class="grid gap-4 text-lg">
        <.moment view={@view} requester={@requester} side={@side} proof={@proof} asking={@asking} />
        <p :if={@message} role="alert" class="text-madder">{@message}</p>
      </section>
      <.other view={@view} />
      <.notices :if={@notices != []} notices={@notices} />
      <.findings view={@view} />
      <div
        :if={@timelines != []}
        id="jobs"
        class="grid gap-5 border-2 border-bark bg-white p-4 sm:p-6"
      >
        <section :for={{{title, rows}, i} <- Enum.with_index(@timelines)} class="grid gap-3">
          <h2 class="font-display text-2xl font-bold">{title}</h2>
          <Timeline.timeline id={"timeline-#{i}"} label={title} rows={rows} />
        </section>
        <.meadow view={@view} />
        <p class="text-base text-moss">
          The bar is work; the dashed line is waiting.
          <span :if={AuditView.more_jobs(@view.audit)}>{AuditView.more_jobs(@view.audit)}</span>
        </p>
      </div>
      <.suggestion_for view={@view} />
      <.facts view={@view} />
      <figure :if={AuditView.picture?(@plan)}>
        <svg
          viewBox="0 0 1200 630"
          class="block h-auto w-full border-2 border-bark"
          role="img"
          aria-label={Forest.describe(@plan)}
        >
          <g id={"back-#{@plan.mood}"}>{raw(@scene.back)}</g>
          <g
            :for={t <- @scene.trees}
            id={"tree-#{t.id}"}
            class="tree"
            data-stage={AuditView.stage(@view, t.name)}
          >
            {raw(t.svg)}
          </g>
          <g
            :for={t <- @scene.trees}
            id={"label-#{t.id}"}
            class="tree-label"
            data-stage={AuditView.stage(@view, t.name)}
          >
            <g class="tag">{raw(t.label)}</g>
            <g class="badge">{raw(t.badge)}</g>
          </g>
          <g id="doctor" class="doctor" style={doctor_style(@scene.doctor_at)}>
            {raw(@scene.doctor)}
          </g>
          <g id="front">{raw(@scene.front)}</g>
        </svg>
        <figcaption class="mt-2 font-display text-lg italic sm:hidden">{@plan.caption}</figcaption>
      </figure>
      <p :if={@plan.jobs != [] and AuditView.picture?(@plan)} id="legend" class="text-base text-moss">
        {AuditView.legend(@view, @side)}
      </p>
      <p :if={foreign?(@view.audit)} id="maintainer" class="max-w-prose border-l-4 border-bark pl-4">
        Is this your project? You can ask us to correct or remove this page.
        <a :if={@contact} class="inline-block py-2 underline" href={"mailto:#{@contact}"}>{@contact}</a>
        <a class="inline-block py-2 underline" href={~p"/privacy"}>What we store</a>
      </p>
      <section :if={@view.events != []}>
        <h2 class="font-display text-2xl font-bold">What the doctor did</h2>
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
    <p>The doctor is reading the workflow and its last run. This page updates automatically.</p>
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
      <PC.button link_type="a" to={~p"/"} variant="outline" label="Back to the forest" />
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
    <h2 class="font-display text-3xl font-bold">
      {examined_headline(@view)}
    </h2>
    <p class="max-w-prose">
      The doctor only read this project. The facts are computed from GitHub's data. The findings are a model's reading of them, so they are not proof. Statements that the council did not pass are not shown.
    </p>
    <p :if={@view.findings == [] and @view.trial == nil} id="calm" class="max-w-prose">
      That is a result too: no statement passed every check.
    </p>
    <div class="flex flex-wrap gap-3">
      <PC.button
        :if={@view.audit.slot && (@requester or AuditView.due?(@view.audit))}
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
      Its place in the forest is free again.
    </p>
    <div class="flex flex-wrap gap-3">
      <PC.button
        :if={foreign?(@view.audit) and @view.audit.replaces_id == nil}
        link_type="a"
        to={~p"/?#{[project: @view.audit.repository]}"}
        label="Try again"
      />
      <PC.button link_type="a" to={~p"/"} variant="outline" label="Back to the forest" />
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
    <div class="flex flex-wrap gap-3" role="group" aria-label="Show the pipeline">
      <PC.button
        phx-click="side"
        phx-value-side="before"
        variant={if @side == :before, do: "solid", else: "outline"}
        aria-pressed={to_string(@side == :before)}
        label="Before"
      />
      <PC.button
        phx-click="side"
        phx-value-side="after"
        variant={if @side == :after, do: "solid", else: "outline"}
        aria-pressed={to_string(@side == :after)}
        label="After"
      />
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

  defp examined_headline(%{findings: [first | _]}), do: first.title
  defp examined_headline(%{trial: %{}}), do: "The doctor has a suspicion."
  defp examined_headline(_), do: "Nothing found."

  defp findings(assigns) do
    ~H"""
    <section :if={@view.findings != []} id="findings" class="grid gap-3">
      <h2 class="font-display text-2xl font-bold">Findings</h2>
      <ol class="grid gap-3">
        <li :for={f <- @view.findings}>
          <Card.card class="border-bark bg-white p-4 sm:p-6">
            <p class="flex flex-wrap items-baseline justify-between gap-3">
              <strong class="font-display text-xl">{f.title}</strong>
              <span class="rounded-full bg-way px-3 py-1 text-base font-bold">
                {if AuditView.kind(f), do: AuditView.kind(f) <> " · "}Suspicion, checked by QA and Safety
              </span>
            </p>
            <p class="mt-2 max-w-prose">{f.text}</p>
            <p :if={f.advice} class="mt-2 max-w-prose"><strong>Try:</strong> {f.advice}</p>
            <ul
              class="mt-3 grid gap-1 border-t border-bark pt-3 text-base"
              aria-label="Facts behind it"
            >
              <li :for={fact <- AuditView.evidence(f, @view.audit)} class="text-moss">
                <.fact fact={fact} audit={@view.audit} />
              </li>
            </ul>
          </Card.card>
        </li>
      </ol>
    </section>
    """
  end

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

  # The saved time as a meadow, on the scale of the run before.
  defp meadow(assigns) do
    assigns = assign(assigns, meadow: AuditView.meadow(assigns.view))

    ~H"""
    <div :if={@meadow} id="meadow" class="grid gap-2">
      <div class="relative h-11 rounded border-2 border-bark bg-grass" aria-hidden="true">
        <span
          class="absolute inset-y-0 left-0 grid place-items-center border-r-2 border-bark bg-way font-bold tabular-nums"
          style={"width:#{@meadow.kept}%"}
        >
          {@meadow.words}
        </span>
        <span
          :for={f <- @meadow.flowers}
          class={["absolute size-3 rounded-full border-2 border-bark", f.color]}
          style={"left:#{f.left}%;top:#{f.top}px"}
        />
      </div>
      <p>{@meadow.legend}</p>
    </div>
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

  defp doctor_style({dx, dy}), do: "transform: translate(#{dx}px, #{dy}px)"

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
