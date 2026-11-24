defmodule Builddoctor.ForestTest do
  use ExUnit.Case, async: true

  alias Builddoctor.Forest
  alias Builddoctor.Forest.Palette

  @seq [
    %{name: "vet", start: 0, seconds: 10},
    %{name: "test", start: 13, seconds: 20},
    %{name: "build", start: 37, seconds: 22}
  ]
  @par Enum.map(@seq, &%{&1 | start: 0})

  test "every mood draws well-formed, script-free, repeatable SVG" do
    for mood <- Palette.moods(), jobs <- [@seq, @par], seed <- ~w(a/b c/d e/f) do
      plan =
        Forest.plan(seed, mood, jobs, span: 60, spread: 0.3, flowers: 12, caption: "One & two")

      svg = Forest.image(plan)
      assert svg == Forest.image(plan)
      assert {_, []} = :xmerl_scan.string(String.to_charlist(svg), quiet: true)
      refute svg =~ ~r/<script|onload|href/
      assert svg =~ "One &amp; two"
    end
  end

  test "texts are escaped" do
    svg = Forest.image(Forest.plan("x", :measuring, [%{name: "<script>", start: 0, seconds: 1}]))
    refute svg =~ "<script"
  end

  test "parallel jobs stand beside each other and place is time" do
    xs = fn jobs ->
      Forest.scene(Forest.plan("a", :measuring, jobs, span: 60)).trees
      |> Enum.sort_by(& &1.id)
      |> Enum.map(& &1.x)
    end

    assert xs.(@seq) == Enum.sort(xs.(@seq))
    assert length(Enum.uniq(xs.(@par))) == 3
    assert Enum.max(xs.(@par)) < Enum.max(xs.(@seq))
  end

  test "a job keeps the shape and size of its tree, however long and wherever it runs" do
    # The drawing without its place: all steps between the points of the trunk.
    trunk = fn jobs, name ->
      tree =
        Enum.find(
          Forest.scene(Forest.plan("a", :measuring, jobs, span: 100)).trees,
          &(&1.name == name)
        )

      [_, d] = Regex.run(~r/<path d="([^"]+)"/, IO.iodata_to_binary(tree.svg))
      points = for [x] <- Regex.scan(~r/-?[\d.]+/, d), do: String.to_float(x)
      [xs, ys] = for o <- 0..1, do: points |> Enum.drop(o) |> Enum.take_every(2)
      {Enum.max(xs) - Enum.min(xs), Enum.max(ys) - Enum.min(ys)}
    end

    slow = Enum.map(@seq, &%{&1 | seconds: &1.seconds * 3})

    for job <- @seq, jobs <- [slow, Enum.reverse(@par)] do
      {w, h} = trunk.(@seq, job.name)
      {w2, h2} = trunk.(jobs, job.name)
      assert_in_delta w, w2, 0.3
      assert_in_delta h, h2, 0.3
      assert h > 100
    end
  end

  test "draws exactly as many flowers as were saved" do
    count = fn saved ->
      svg = Forest.image(Forest.plan("a", :accepted, @seq, span: 100, flowers: saved))
      length(String.split(svg, "<ellipse")) - 1
    end

    assert count.(0) == 0 and count.(1) == 5 and count.(30) == 150
    assert Forest.describe(Forest.plan("a", :accepted, @seq, flowers: 1)) =~ "1 flower."
    assert Forest.describe(Forest.plan("a", :accepted, @seq, flowers: 30)) =~ "30 flowers."
  end

  test "an empty or long pipeline still draws" do
    for {jobs, span} <- [{[], 1}, {@seq, 300}, {@seq, 1000}, {@seq, 5000}] do
      assert Forest.image(Forest.plan("a", :accepted, jobs, span: span)) =~ "</svg>"
    end
  end

  test "describes the picture in words" do
    assert Forest.describe(Forest.plan("a", :accepted, @seq)) =~ "test 20 s from second 13"
    assert Forest.describe(Forest.plan("a", :stopped, [])) == "No jobs yet. State: stopped."
  end
end
