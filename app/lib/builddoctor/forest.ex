defmodule Builddoctor.Forest do
  @moduledoc """
  Draws a pipeline as a hand-drawn forest. Pure: the same plan gives the same picture.
  A tree is a job and keeps its shape and size, because the work stays the same. Time is only
  the way: a root marks the seconds of a job, a pennant the end of the run. Only what is proven
  to be saved grows: the flowers.
  The plan must come from validated Ash data; every text is escaped here as well.
  """
  import Builddoctor.Forest.Pen
  alias Builddoctor.Forest.{Palette, Tree}

  @w 1200
  @h 630
  @x0 120
  @x1 1080
  @tree 210

  defmodule Plan do
    @moduledoc "What the picture shows."
    @enforce_keys [:seed, :mood, :span, :jobs]
    defstruct [
      :seed,
      :mood,
      :span,
      :jobs,
      spread: 0.0,
      caption: "",
      walked: 1.0,
      seeds: false,
      flowers: 0
    ]
  end

  @doc """
  Builds a plan from jobs with name, start and seconds. While a run is watched, a job also has
  `live`: {:queued, nil}, {:running, seconds} or {:done, seconds}. Start and seconds then only
  place the tree; they are never shown as if they were measured now.
  """
  def plan(seed, mood, jobs, opts \\ []) do
    stop = jobs |> Enum.map(&(&1.start + &1.seconds)) |> Enum.max(fn -> 1 end)

    %Plan{
      seed: seed,
      mood: mood,
      span: max(opts[:span] || 1, max(stop, 1)),
      jobs: jobs,
      spread: opts[:spread] || 0.0,
      caption: opts[:caption] || "",
      walked: opts[:walked] || 1.0,
      seeds: opts[:seeds] || false,
      flowers: opts[:flowers] || 0
    }
  end

  @doc "The parts of the scene, so that a page can update the trees alone."
  def scene(%Plan{} = plan) do
    p = Palette.get(plan.mood)

    %{
      ink: p.ink,
      back: [
        sky(plan, p),
        hills(plan, p),
        ground(plan, p),
        roots(plan, p),
        meadow(plan, p),
        seeds(plan, p)
      ],
      trees: trees(plan, p),
      front: [air(plan, p), near(plan, p), caption(plan, p)],
      doctor: doctor(plan, p),
      doctor_at: doctor_at(plan)
    }
  end

  @doc "A complete image file without script, fully grown."
  def image(%Plan{} = plan) do
    s = scene(plan)

    IO.iodata_to_binary([
      ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 #{@w} #{@h}" width="#{@w}" height="#{@h}" role="img" aria-label="#{esc(describe(plan))}">),
      "<title>",
      esc(plan.seed),
      "</title>",
      s.back,
      Enum.map(s.trees, & &1.svg),
      Enum.map(s.trees, & &1.label),
      place(s.doctor_at, s.doctor),
      s.front,
      "</svg>"
    ])
  end

  defp place({dx, dy}, drawing),
    do: [~s[<g transform="translate(#{dx} #{dy})">], drawing, "</g>"]

  def describe(%Plan{jobs: []} = plan), do: "No jobs yet. State: #{plan.mood}."

  def describe(%Plan{} = plan) do
    jobs = Enum.map_join(plan.jobs, ", ", &words/1)
    "#{jobs}. State: #{plan.mood}.#{bloom(plan.flowers)}"
  end

  # Running seconds are left out, so that the description does not change every second.
  defp bloom(0), do: ""
  defp bloom(1), do: " 1 flower."
  defp bloom(count), do: " #{count} flowers."

  defp words(%{live: {:queued, _}} = job), do: "#{job.name} not started"
  defp words(%{live: {:running, _}} = job), do: "#{job.name} running"
  defp words(%{live: {:done, seconds}} = job), do: "#{job.name} done in #{seconds} s"
  defp words(job), do: "#{job.name} #{job.seconds} s from second #{job.start}"

  # The list below the picture has the whole name.
  defp short(name),
    do: if(String.length(name) > 18, do: String.slice(name, 0, 17) <> "…", else: name)

  defp tag(%{live: {:queued, _}} = job), do: job.name
  defp tag(%{live: {:running, seconds}} = job), do: "#{job.name} #{seconds}s…"
  defp tag(%{live: {:done, seconds}} = job), do: "#{job.name} #{seconds}s"
  defp tag(job), do: "#{job.name} #{job.seconds}s"

  def x(plan, t), do: @x0 + (@x1 - @x0) * t / plan.span

  def way(plan, x),
    do: 478 + :math.sin(x / 150 + rnd(plan.seed, :way) * 7) * 13 + :math.sin(x / 61) * 4

  defp across(step \\ 40), do: Enum.to_list(-40..(@w + 40)//step)

  defp sky(plan, p) do
    k = {plan.seed, :sky}
    cx = 360 + rnd(k, 0) * 460
    [top, mid, low] = p.sky

    rings =
      for i <- 0..8 do
        dash =
          Enum.map_join(
            1..4,
            " ",
            &n(8 + rnd(k, {i, &1}) * if(rem(&1, 2) == 1, do: 80, else: 16))
          )

        ~s(<circle cx="#{n(cx)}" cy="#{p.sun_y}" r="#{n(108 + i * i * 2.1 + i * 17)}" fill="none" stroke="#{p.sun}" stroke-width="#{n(4.2 - i * 0.36)}" stroke-dasharray="#{dash}" opacity="#{n(0.85 - i * 0.085)}"/>)
      end

    wind =
      for i <- 0..4 do
        wx = 80 + i * 240 + rnd(k, {:wx, i}) * 90
        wy = 60 + rnd(k, {:wy, i}) * 120
        s = 18 + rnd(k, {:ws, i}) * 30
        len = 0.6 + rnd(k, {:wl, i})

        [
          spiral(wx, wy, s, 1, 1.6, p.cream, 2.2),
          ink(
            curve([
              {wx + s, wy},
              {wx + s + 60 * len, wy + s * 0.8},
              {wx + s + 150 * len, wy + s * 0.5},
              {wx + s + 210 * len, wy + s * 0.9}
            ]),
            2.2,
            p.cream,
            0.7
          )
        ]
      end

    [
      ~s(<defs><linearGradient id="sky-#{plan.mood}" x1="0" y1="0" x2="0" y2=".75"><stop stop-color="#{top}"/><stop offset=".62" stop-color="#{mid}"/><stop offset="1" stop-color="#{low}"/></linearGradient></defs>),
      ~s(<rect width="#{@w}" height="#{@h}" fill="url(#sky-#{plan.mood}\)"/>),
      ~s(<circle cx="#{n(cx)}" cy="#{p.sun_y}" r="92" fill="#{p.sun}"/>),
      rings,
      wind
    ]
  end

  defp hills(plan, p) do
    for {{base, amp}, i} <- Enum.with_index([{300, 44}, {350, 36}, {398, 26}, {440, 16}]) do
      k = {plan.seed, :hill, i}
      {a, b} = {rnd(k, :a) * 9, rnd(k, :b) * 9}

      ridge =
        for x <- across(),
            do:
              {x,
               base + :math.sin(x / (170 - i * 18) + a) * amp + :math.sin(x / 63 + b) * amp * 0.3}

      cuts =
        for m <- 1..5 do
          tone = Enum.at(p.hills, if(rem(m, 2) == 1, do: min(3, i + 1), else: max(0, i - 1)))

          dash =
            Enum.map_join(1..4, " ", &n(12 + rnd(k, {m, &1}) * if(&1 == 1, do: 150, else: 40)))

          line =
            for {x, y} <- ridge, do: {x, y + m * (11 + i * 1.5) + :math.sin(x / 37 + m) * 2.5}

          ~s(<path d="#{curve(line)}" fill="none" stroke="#{tone}" stroke-width="#{n(5 - m * 0.6)}" stroke-dasharray="#{dash}" opacity=".7"/>)
        end

      [
        ~s(<path d="#{curve(ridge)}L#{@w + 40} #{@h}L-40 #{@h}z" fill="#{Enum.at(p.hills, i)}"/>),
        cuts,
        ~s(<path d="#{curve(ridge)}" fill="none" stroke="#{p.ink}" stroke-width="#{n(1 + i * 0.45)}" opacity=".75"/>),
        if(i < 3, do: far_trees(k, ridge, i, p), else: [])
      ]
    end
  end

  defp far_trees(k, ridge, i, p) do
    d =
      for m <- 0..15 do
        x = 20 + m * 76 + rnd(k, {:fx, m}) * 46
        {_, y} = Enum.at(ridge, round((x + 40) / 40))
        h = 14 + rnd(k, {:fh, m}) * 20 + i * 7

        "M#{n(x)} #{n(y + 5)}q#{n(-h * 0.28)} #{n(-h * 0.45)} 0 #{n(-h)}q#{n(h * 0.28)} #{n(h * 0.55)} 0 #{n(h)}z"
      end

    ~s(<path d="#{d}" fill="#{Enum.at(p.hills, i + 1)}" stroke="#{p.ink}" stroke-width=".9" stroke-opacity=".6"/>)
  end

  defp ground(plan, p) do
    edge = for x <- across(), do: {x, way(plan, x) - 16}
    top = for x <- across(), do: {x, way(plan, x) + 10}
    bottom = for x <- across(), do: {x, way(plan, x) + 30 + :math.sin(x / 90) * 4}
    "M" <> back = curve(Enum.reverse(bottom))

    step =
      cond do
        plan.span > 1800 -> 600
        plan.span > 600 -> 120
        plan.span > 180 -> 30
        true -> 10
      end

    stones =
      for t <- Enum.take_every(0..trunc(plan.span), step) do
        {sx, sy} = {x(plan, t), way(plan, x(plan, t)) + 46}

        [
          shape(blob(sx, sy, 11, 7, {plan.seed, :stone, t}, 8, 0.14), p.way, p, 1.6, 1.5),
          ~s(<text class="axis" x="#{n(sx)}" y="#{n(sy + 26)}" text-anchor="middle" font-size="15" fill="#{p.cream}" font-family="Georgia,serif">#{t}s</text>)
        ]
      end

    [
      ~s(<path d="#{curve(edge)}L#{@w + 40} #{@h}L-40 #{@h}z" fill="#{p.ground}"/>),
      ink(curve(edge), 3, p.ink),
      ~s(<path d="#{curve(top)}L#{back}z" fill="#{p.way}"/>),
      ink(curve(top), 2.2, p.ink),
      ink(curve(bottom), 2.6, p.ink),
      stones
    ]
  end

  defp meadow(plan, p) do
    k = {plan.seed, :meadow}

    grass =
      for i <- 0..149 do
        gx = rnd(k, {:x, i}) * @w
        h = 8 + rnd(k, {:h, i}) * 15
        lean = (rnd(k, {:l, i}) - 0.5) * 9
        tone = if rem(i, 3) == 0, do: p.lit, else: Enum.at(p.leaf, 2)

        ink(
          "M#{n(gx)} #{n(way(plan, gx) - 10)}q#{n(lean / 2)} #{n(-h * 0.6)} #{n(lean)} #{n(-h)}",
          1.5,
          tone,
          0.9
        )
      end

    [grass, if(plan.flowers > 0, do: flowers(plan, p, k), else: [])]
  end

  defp flowers(plan, p, k) do
    from = min(x(plan, stop(plan.jobs)) + 30, @x1 - 80)
    step = (@x1 - from) / plan.flowers

    for i <- 0..(plan.flowers - 1) do
      fx = from + (i + 0.2 + rnd(k, {:fx, i}) * 0.6) * step
      y = way(plan, fx) - 10
      h = 20 + rnd(k, {:fh, i}) * 44
      s = 5 + rnd(k, {:fs, i}) * 6
      tone = Enum.at(["#d9574a", "#f2b84b", "#fff6dc", "#8a5fa8"], rem(i, 4))

      petals =
        for m <- 0..4,
            do:
              ~s(<ellipse cx="#{n(fx)}" cy="#{n(y - h - s * 0.9)}" rx="#{n(s * 0.55)}" ry="#{n(s)}" transform="rotate(#{m * 72 + i * 13} #{n(fx)} #{n(y - h)}\)"/>)

      [
        ink("M#{n(fx)} #{n(y)}q4 #{n(-h / 2)} 0 #{n(-h)}", 1.8, p.ink),
        ~s(<g fill="#{tone}" stroke="#{p.ink}" stroke-width="1.1">),
        petals,
        ~s(</g><circle cx="#{n(fx)}" cy="#{n(y - h)}" r="#{n(s * 0.45)}" fill="#{p.sun}" stroke="#{p.ink}"/>)
      ]
    end
  end

  defp trees(plan, p) do
    plan.jobs
    |> lanes()
    |> Enum.sort_by(fn {_, lane, _} -> -lane end)
    |> Enum.map(fn {job, lane, i} ->
      mid = (x(plan, job.start) + x(plan, job.start + job.seconds)) / 2
      cx = min(mid + lane * 118, @x1 + 40)
      cy = way(plan, cx) - 6 - lane * 13
      h = @tree

      %{
        id: i,
        name: job.name,
        x: n(cx),
        y: n(cy),
        svg: Tree.draw(cx, cy, h, 0, {plan.seed, job.name}, p),
        badge: badge(cx, cy - h - 30, i + 1, p),
        label: label(cx, cy - h - 26 - lane * 22, tag(%{job | name: short(job.name)}), p)
      }
    end)
  end

  # While a run is watched, its times are not known yet.
  defp roots(%{jobs: [%{live: _} | _]}, _), do: []
  defp roots(%{jobs: []}, _), do: []

  defp roots(plan, p) do
    lines =
      for {job, lane, _} <- lanes(plan.jobs) do
        from = x(plan, job.start)
        to = max(x(plan, job.start + job.seconds), from + 4)
        y = fn at -> way(plan, at) + 13 + min(lane, 2) * 7 end
        points = for m <- 0..8, at = from + (to - from) * m / 8, do: {at, y.(at)}

        [ink(curve(points), 7, p.ink), ink(curve(points), 4, Enum.at(p.leaf, rem(lane, 3)))]
      end

    at = x(plan, stop(plan.jobs))
    foot = way(plan, at) + 28

    [
      lines,
      ink("M#{n(at)} #{n(foot)}V#{n(foot - 96)}", 4, p.ink),
      ~s(<path d="M#{n(at)} #{n(foot - 96)}q22 -8 44 8q-22 4 -44 18z" fill="#{p.sun}" stroke="#{p.ink}" stroke-width="2.4"/>)
    ]
  end

  defp stop(jobs), do: jobs |> Enum.map(&(&1.start + &1.seconds)) |> Enum.max(fn -> 0 end)

  # Jobs that run at the same time stand beside each other.
  defp lanes(jobs) do
    {out, _} =
      jobs
      |> Enum.with_index()
      |> Enum.map_reduce(%{}, fn {job, i}, busy ->
        lane = Enum.find(0..length(jobs), &(Map.get(busy, &1, 0) <= job.start))
        {{job, lane, i}, Map.put(busy, lane, job.start + max(job.seconds, 1))}
      end)

    out
  end

  defp label(cx, y, text, p) do
    w = String.length(text) * 9.4 + 20

    ~s(<g transform="translate(#{n(cx)} #{n(y)}\)"><rect x="#{n(-w / 2)}" y="-17" width="#{n(w)}" height="27" rx="3" fill="#{p.cream}" stroke="#{p.ink}" stroke-width="2"/><text text-anchor="middle" y="2" font-size="17" font-weight="700" font-family="Georgia,serif" fill="#{p.ink}">#{esc(text)}</text></g>)
  end

  # On a phone the label would be unreadable; the number points to the list below the picture.
  defp badge(cx, y, number, p),
    do:
      ~s[<g transform="translate(#{n(cx)} #{n(y)})"><circle r="32" fill="#{p.cream}" stroke="#{p.ink}" stroke-width="4"/><text text-anchor="middle" y="15" font-size="44" font-weight="700" font-family="Georgia,serif" fill="#{p.ink}">#{number}</text></g>]

  # Nothing is known yet, so seeds lie in the ground.
  defp seeds(%{seeds: false}, _), do: []

  defp seeds(plan, p) do
    for i <- 0..5 do
      sx = @x0 + 60 + i * 150 + rnd(plan.seed, {:seed, i}) * 60
      sy = way(plan, sx) - 8

      [
        ~s(<path d="M#{n(sx - 26)} #{n(sy + 6)}q26 -24 52 0z" fill="#{p.bark}" stroke="#{p.ink}" stroke-width="2"/>),
        ink("M#{n(sx)} #{n(sy - 6)}q-3 -12 2 -24", 3, p.ink),
        ~s(<path d="M#{n(sx + 2)} #{n(sy - 30)}q16 -16 24 -4q-10 12 -24 4z" fill="#{p.lit}" stroke="#{p.ink}" stroke-width="1.6"/>)
      ]
    end
  end

  defp doctor_at(%{mood: :accepted}), do: {@x1 - 120, 178}

  defp doctor_at(plan) do
    dx = @x0 - 40 + (@x1 - @x0) * plan.walked
    {n(dx), n(way(plan, dx) + 20)}
  end

  defp doctor(plan, p) do
    flying = plan.mood == :accepted

    ~s[<g transform="scale(#{if flying, do: 1.5, else: 1.25}) rotate(#{if flying, do: -9, else: 0})">#{Builddoctor.Forest.Figure.draw(flying, p)}</g>]
  end

  defp air(plan, p) do
    k = {plan.seed, :air}

    leaves =
      if plan.mood == :rejected do
        for i <- 0..45 do
          s = 5 + rnd(k, {:s, i}) * 6

          ~s[<path d="M0 0q#{n(s)} #{n(-s)} #{n(s * 2)} 0q#{n(-s)} #{n(s)} #{n(-s * 2)} 0z" transform="translate(#{n(rnd(k, {:x, i}) * @w)} #{n(120 + rnd(k, {:y, i}) * 450)}) rotate(#{n(rnd(k, {:r, i}) * 360)})" fill="#{Enum.at(p.leaf, rem(i, 3))}" stroke="#{p.ink}" stroke-width=".9"/>]
        end
      else
        []
      end

    thick = if plan.mood == :inconclusive, do: max(0.45, plan.spread), else: plan.spread * 0.6
    [leaves, if(thick > 0.02, do: fog(p, thick), else: [])]
  end

  defp fog(p, thick) do
    for m <- 0..5 do
      top = for x <- -60..(@w + 60)//80, do: {x, 250 + m * 44 + :math.sin(x / 130 + m * 2) * 13}

      "M" <> back =
        curve(Enum.reverse(for {x, y} <- top, do: {x, y + 34 + :math.sin(x / 90 + m) * 9}))

      ~s(<path d="#{curve(top)}L#{back}z" fill="#{p.cream}" opacity="#{n(min(thick, 1.0) * 0.72)}"/>)
    end
  end

  defp near(plan, p) do
    k = {plan.seed, :near}

    for i <- 0..21 do
      left = i < 11
      nx = if left, do: -30 + rnd(k, {:x, i}) * 120, else: @w - 90 + rnd(k, {:x, i}) * 120
      h = 40 + rnd(k, {:h, i}) * 62
      ln = if(left, do: 1, else: -1) * (10 + rnd(k, {:l, i}) * 40)

      blades =
        for m <- 2..7 do
          u = m / 8
          {px, py, s} = {nx + ln * u * u, @h - h * u, (1 - u) * 20 + 6}

          for side <- [1, -1],
              do:
                "M#{n(px)} #{n(py)}q#{n(side * s * 0.7)} #{n(-s * 0.9)} #{n(side * s * 1.5)} #{n(-s * 0.3)}q#{n(-side * s * 0.6)} #{n(s * 0.6)} #{n(-side * s * 1.5)} #{n(s * 0.3)}z"
        end

      [
        ink(
          "M#{n(nx)} #{@h + 6}Q#{n(nx + ln * 0.1)} #{n(@h - h * 0.6)} #{n(nx + ln)} #{n(@h - h)}",
          3,
          p.ink
        ),
        ~s(<path d="#{blades}" fill="#{if rem(i, 3) == 0, do: p.ground, else: p.ink}" stroke="#{p.ink}"/>)
      ]
    end
  end

  defp caption(%{caption: ""}, _), do: []

  defp caption(plan, p) do
    ~s(<text class="caption" x="#{div(@w, 2)}" y="602" text-anchor="middle" font-size="22" font-style="italic" font-family="Georgia,serif" fill="#{p.cream}" stroke="#{p.ink}" stroke-width="5" paint-order="stroke" stroke-linejoin="round">#{esc(plan.caption)}</text>)
  end
end
