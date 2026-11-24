defmodule Builddoctor.Forest.Tree do
  @moduledoc "Three kinds of trees; the kind depends on the seed only."
  import Builddoctor.Forest.Pen

  def draw(cx, cy, h, i, key, p) do
    s = h / 260
    w = 15 * s + 4
    lean = (rnd(key, :lean) - 0.5) * 26 * s
    leaf = &Enum.at(p.leaf, rem(i + &1, 3))

    trunk = [
      {cx - w * 1.9, cy + 3},
      {cx - w * 0.8, cy - h * 0.12},
      {cx - w * 0.55 + lean * 0.4, cy - h * 0.4},
      {cx - w * 0.3 + lean, cy - h * 0.72},
      {cx + w * 0.3 + lean, cy - h * 0.72},
      {cx + w * 0.6 + lean * 0.4, cy - h * 0.4},
      {cx + w * 0.85, cy - h * 0.12},
      {cx + w * 2, cy + 3}
    ]

    grain =
      for m <- 0..3,
          do:
            ink(
              "M#{n(cx - w * 0.4 + m * w * 0.3)} #{n(cy - h * 0.05)}q#{n(lean * 0.3)} #{n(-h * 0.2)} #{n(lean * 0.6)} #{n(-h * 0.45)}",
              1.1,
              p.lit,
              0.5
            )

    crown =
      case :erlang.phash2({key, :kind}, 3) do
        0 -> cloud(cx + lean, cy, h, leaf, key, p)
        1 -> flame(cx + lean, cy, h, leaf.(0), p)
        2 -> willow(cx + lean, cy, h, leaf, key, p)
      end

    [shape(trunk, p.bark, p, 2.4), grain, crown]
  end

  defp cloud(x, cy, h, leaf, key, p) do
    for {{dx, dy, rx, ry}, m} <-
          Enum.with_index([
            {-0.26, 0.62, 0.22, 0.16},
            {0.27, 0.6, 0.23, 0.16},
            {-0.02, 0.8, 0.27, 0.2},
            {-0.2, 0.86, 0.17, 0.13},
            {0.2, 0.88, 0.18, 0.14}
          ]) do
      {bx, by, a, b, k} = {x + dx * h, cy - dy * h, rx * h, ry * h, {key, m}}

      [
        shape(blob(bx, by, a, b, k, 12, 0.09), leaf.(m), p, 2.5),
        hatch(bx, by, a, b, k, {-0.2, 2.3}, 11, p.ink, 1.7),
        hatch(bx, by, a, b, {k, 2}, {3.5, 5}, 6, p.lit, 2),
        spiral(
          bx - a * 0.1,
          by - b * 0.05,
          a * 0.34,
          if(rem(m, 2) == 0, do: -1, else: 1),
          1.7,
          p.lit,
          2
        )
      ]
    end
  end

  defp flame(x, cy, h, tone, p) do
    top = cy - h
    width = fn u -> :math.sin(:math.pi() * :math.pow(u, 0.72)) * 0.2 * h end
    at = fn m -> {m / 14, width.(m / 14) * if(rem(m, 2) == 1, do: 1.1, else: 0.96)} end

    right =
      for m <- 0..14, {u, w} = at.(m), do: {x + :math.sin(u * 3) * 7 + w, top + u * h * 0.86}

    left =
      for m <- 13..1//-1, {u, w} = at.(m), do: {x + :math.sin(u * 3) * 7 - w, top + u * h * 0.86}

    veins =
      for m <- 1..7 do
        y = top + h * 0.86 * (m / 8.4)
        w = width.(m / 8.4) * 0.82

        for {side, c, t} <- [{1, p.ink, 1.7}, {-1, p.lit, 1.9}],
            do:
              ink(
                "M#{n(x)} #{n(y)}Q#{n(x + side * w * 0.5)} #{n(y - w * 0.1)} #{n(x + side * w)} #{n(y - w * 0.5)}",
                t,
                c,
                0.85
              )
      end

    [
      shape(right ++ left, tone, p, 2.6),
      veins,
      ink(
        "M#{n(x)} #{n(cy - h * 0.2)}Q#{n(x + 8)} #{n(cy - h * 0.6)} #{n(x)} #{n(top + h * 0.06)}",
        2,
        p.ink
      )
    ]
  end

  defp willow(x, cy, h, leaf, key, p) do
    {y, a} = {cy - h * 0.78, 0.34 * h}

    curtains =
      for {u, m} <- Enum.with_index([-1, 1, -0.55, 0.55, 0]) do
        bx = x + u * a * 0.72
        l = (0.52 - 0.16 * (1 - abs(u))) * h * if(m == 4, do: 0.62, else: 1)
        w = a * 0.36

        points = [
          {bx - w * 0.7, y - a * 0.1},
          {bx, y - a * 0.42 * (1 - abs(u) * 0.5)},
          {bx + w * 0.7, y - a * 0.1},
          {bx + w + u * 6, y + l * 0.5},
          {bx + w * 0.55 + u * 10, y + l * 0.86},
          {bx + u * 13, y + l},
          {bx - w * 0.55 + u * 10, y + l * 0.84},
          {bx - w + u * 6, y + l * 0.5}
        ]

        lines =
          for k <- -2..2 do
            sx = bx + k * w * 0.3
            odd = rem(abs(k), 2) == 1

            ink(
              "M#{n(sx)} #{n(y + a * 0.05)}Q#{n(sx + u * 8)} #{n(y + l * 0.5)} #{n(sx + u * 12)} #{n(y + l * (0.84 - abs(k) * 0.1))}",
              if(odd, do: 1.9, else: 1.3),
              if(odd, do: p.lit, else: p.ink),
              0.8
            )
          end

        [shape(points, leaf.(m), p, 2.4), lines]
      end

    [
      curtains,
      shape(blob(x, y - a * 0.2, a * 0.62, a * 0.36, key, 11, 0.08), leaf.(0), p, 2.4),
      spiral(x, y - a * 0.2, a * 0.26, 1, 1.7, p.lit, 2.1)
    ]
  end
end
