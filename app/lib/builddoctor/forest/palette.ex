defmodule Builddoctor.Forest.Palette do
  @moduledoc "The light of each mood."

  @moods %{
    measuring: %{
      sky: ~w(#31506b #d98e5f #f3c987),
      sun: "#f9dfa2",
      sun_y: 300,
      hills: ~w(#8a6a6a #6c5560 #4c4a52 #38453f),
      ground: "#2f3a30",
      leaf: ~w(#c9782f #a94f2c #d9a441),
      lit: "#f0bd62",
      bark: "#3a2a25",
      way: "#d9b47c",
      ink: "#211a1c",
      cream: "#fbeccb"
    },
    accepted: %{
      sky: ~w(#7fb4b5 #f2d9a0 #fbe9bd),
      sun: "#fff4cf",
      sun_y: 200,
      hills: ~w(#9db58f #7fa070 #5f8a5c #48734c),
      ground: "#37603f",
      leaf: ~w(#4f8f57 #7aa647 #2f7a6b),
      lit: "#cfdd7c",
      bark: "#4d3526",
      way: "#f3dfad",
      ink: "#1f2a22",
      cream: "#fff6dc"
    },
    rejected: %{
      sky: ~w(#4b5568 #9c7f78 #d7b08c),
      sun: "#e9cfa4",
      sun_y: 330,
      hills: ~w(#7c6f72 #66595f #514a50 #423f3f),
      ground: "#383432",
      leaf: ~w(#8d4a2f #75402f #a8703c),
      lit: "#c58b51",
      bark: "#33282a",
      way: "#bb9a78",
      ink: "#1e191b",
      cream: "#f6e3c8"
    },
    stopped: %{
      sky: ~w(#1d2740 #35405c #5d6480),
      sun: "#d5dae6",
      sun_y: 170,
      hills: ~w(#4a5068 #3d435a #32384c #292f40),
      ground: "#232936",
      leaf: ~w(#4f6272 #43566a #6b7a86),
      lit: "#8996a6",
      bark: "#2b2a33",
      way: "#8d8fa0",
      ink: "#14171f",
      cream: "#e6e8ef"
    },
    inconclusive: %{
      sky: ~w(#8fa3ab #c3c9c0 #dcd8c6),
      sun: "#f3edda",
      sun_y: 210,
      hills: ~w(#a3b0ae #8a9b9a #6f8585 #566d6c),
      ground: "#445a58",
      leaf: ~w(#5f7f76 #7c9484 #8a8f6f),
      lit: "#b9c4a5",
      bark: "#3b4240",
      way: "#cfd0bf",
      ink: "#26302f",
      cream: "#f7f4e4"
    }
  }

  def moods, do: Map.keys(@moods)
  def get(mood) when is_map_key(@moods, mood), do: @moods[mood]
end
