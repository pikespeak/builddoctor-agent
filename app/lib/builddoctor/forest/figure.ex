defmodule Builddoctor.Forest.Figure do
  @moduledoc "The small doctor in the picture, a placeholder until the illustration exists."

  @open "M-6 -38C-30 -70 -62 -68 -78 -50C-66 -46 -62 -38 -58 -30C-44 -30 -28 -22 -8 -24z"
  @folded "M-6 -38C-20 -44 -32 -34 -34 -10C-28 -14 -24 -10 -20 -4C-16 -12 -12 -18 -6 -22z"

  def draw(flying, p) do
    wing =
      ~s(<path d="#{if flying, do: @open, else: @folded}" fill="#{p.cream}" stroke="#{p.ink}" stroke-width="2"/>)

    [
      wing,
      ~s[<g transform="scale(-1 1)">#{wing}</g>],
      part("M-9 -42C-18 -24 -20 -8 -18 2L18 2C20 -8 18 -24 9 -42z", "#f5ead0", p),
      ~s(<path d="M-4 -40L-8 2L0 2L0 -30L4 -40L8 2L0 2z" fill="#9c3427"/>),
      part(
        "M-13 -52C-26 -56 -20 -72 -10 -70C-8 -82 8 -82 10 -70C22 -74 26 -56 13 -52z",
        "#77746d",
        p
      ),
      part("M-10 -60Q0 -68 10 -60Q11 -44 0 -40Q-11 -44 -10 -60z", "#c9905f", p),
      ~s(<path d="M0 -51C-6 -55 -14 -46 -19 -52C-18 -42 -6 -43 0 -47C6 -43 18 -42 19 -52C14 -46 6 -55 0 -51z" fill="#3b312d"/>),
      eye(-4, p),
      eye(5, p),
      if(flying, do: [], else: lantern(p))
    ]
  end

  defp part(d, fill, p),
    do: ~s(<path d="#{d}" fill="#{fill}" stroke="#{p.ink}" stroke-width="2"/>)

  defp eye(x, p),
    do:
      ~s(<circle cx="#{x}" cy="-57" r="3.4" fill="#fff" stroke="#{p.ink}" stroke-width="1.2"/><circle cx="#{x + 0.4}" cy="-57" r="1.2" fill="#{p.ink}"/>)

  defp lantern(p),
    do:
      ~s(<path d="M16 -24L27 -34V-22" fill="none" stroke="#{p.ink}" stroke-width="2"/><circle cx="27" cy="-15" r="6" fill="#f2c45a" stroke="#{p.ink}" stroke-width="1.6"/><circle cx="27" cy="-15" r="18" fill="#f2c45a" opacity=".22"/>)
end
