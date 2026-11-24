defmodule Builddoctor.Forest.Pen do
  @moduledoc "Drawing tools: seeded chance, curves, uneven ink, offset paint and hatching."

  @doc "Chance between 0 and 1 that depends only on the key."
  def rnd(key, i), do: :erlang.phash2({key, i}, 1_000_003) / 1_000_003

  @doc "A short number."
  def n(x) when is_integer(x), do: x
  def n(x), do: Float.round(x, 1)

  def esc(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  @doc "A smooth path through points."
  def curve(points, closed \\ false) do
    t = List.to_tuple(points)
    size = tuple_size(t)

    at =
      if closed,
        do: &elem(t, Integer.mod(&1, size)),
        else: &elem(t, &1 |> max(0) |> min(size - 1))

    {x0, y0} = at.(0)

    body =
      for i <- 0..(if(closed, do: size, else: size - 1) - 1) do
        {{ax, ay}, {bx, by}, {cx, cy}, {dx, dy}} = {at.(i - 1), at.(i), at.(i + 1), at.(i + 2)}

        "C#{n(bx + (cx - ax) / 6)} #{n(by + (cy - ay) / 6)} #{n(cx - (dx - bx) / 6)} #{n(cy - (dy - by) / 6)} #{n(cx)} #{n(cy)}"
      end

    "M#{n(x0)} #{n(y0)}#{body}#{if closed, do: "z"}"
  end

  def ink(d, w, color, opacity \\ 1) do
    ~s(<path d="#{d}" fill="none" stroke="#{color}" stroke-width="#{n(w)}" stroke-linecap="round" stroke-linejoin="round" opacity="#{opacity}"/>)
  end

  @doc "Paint slightly off, a searching pencil line, then uneven ink."
  def shape(points, fill, p, w \\ 2.2, off \\ 3) do
    d = curve(points, true)

    [
      ~s[<path d="#{d}" fill="#{fill}" transform="translate(#{off} #{n(off * 0.7)})"/>],
      ~s[<g transform="translate(-1.6 1.2)">],
      ink(d, 0.8, p.bark, 0.6),
      "</g>",
      ink(d, w, p.ink),
      ~s[<g transform="translate(.9 .8)">],
      ink(d, w * 0.55, p.ink),
      "</g>"
    ]
  end

  def blob(cx, cy, rx, ry, key, count \\ 11, jitter \\ 0.1) do
    for i <- 0..(count - 1) do
      a = i / count * 2 * :math.pi()
      q = 1 + (rnd(key, {:blob, i}) - 0.5) * 2 * jitter
      {cx + :math.cos(a) * rx * q, cy + :math.sin(a) * ry * q}
    end
  end

  def hatch(cx, cy, rx, ry, key, {from, to}, count, color, w) do
    d =
      for i <- 0..(count - 1) do
        a = from + (to - from) * (i + rnd(key, {:ha, i}) * 0.5) / count
        l = 0.52 + rnd(key, {:hl, i}) * 0.2
        m = (0.9 + l) / 2

        "M#{n(cx + :math.cos(a) * rx * 0.9)} #{n(cy + :math.sin(a) * ry * 0.9)}Q#{n(cx + :math.cos(a + 0.12) * rx * m)} #{n(cy + :math.sin(a + 0.12) * ry * m)} #{n(cx + :math.cos(a + 0.06) * rx * l)} #{n(cy + :math.sin(a + 0.06) * ry * l)}"
      end

    ink(d, w, color, 0.75)
  end

  def spiral(cx, cy, size, dir, turns, color, w) do
    steps = round(turns * 10)

    points =
      for i <- 0..steps do
        a = i / 10 * 2 * :math.pi() * dir
        l = size * (1 - i / (steps + 2))
        {cx + :math.cos(a) * l, cy + :math.sin(a) * l * 0.82}
      end

    ink(curve(points), w, color, 0.8)
  end
end
