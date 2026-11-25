defmodule Builddoctor.Bench.GradeTest do
  use ExUnit.Case, async: true

  alias Builddoctor.Bench.Grade

  defp fact(id, text \\ "x"), do: %{id: id, text: text}

  defp runs(total, failed),
    do: fact("failed", "Of the last #{total} finished runs of this workflow, #{failed} failed.")

  defp grade(facts, state \\ :examined, at \\ ~U[2026-11-24 13:50:00Z]),
    do: Grade.of(%{state: state, facts: facts, inserted_at: at})

  defp off(facts), do: 100 - grade([runs(10, 0) | facts]).points

  test "nothing to take off is an A++" do
    assert grade([runs(3, 0)]) == %{letter: "A++", points: 100, off: []}
  end

  test "every rule has its points" do
    assert off([fact("red1"), fact("red2"), fact("redstep1")]) == 15
    assert off([fact("flaky")]) == 10
    assert off([fact("file1")]) == 10
    assert off([fact("file1"), fact("file2"), fact("file3")]) == 20
    assert off([fact("rights", "The workflow file gives every job all write permissions.")]) == 15
    assert off([fact("rights", "The workflow file does not set permissions for every job.")]) == 5
    assert off([fact("pinned", "Steps without a fixed commit: 2.")]) == 10
    assert off([fact("pinned", "Steps without a fixed commit: 0.")]) == 0
    assert off([fact("timeout")]) == 5
    assert off([fact("concurrency")]) == 5

    for {percent, points} <- [{14, 0}, {15, 5}, {29, 5}, {30, 10}] do
      assert off([fact("setup", "Setup steps: 9 s, #{percent}% of all step time.")]) == points
    end

    for id <- ~w(run last queue history needs step1 cause failstep plan ask1),
        do: assert(off([fact(id)]) == 0)
  end

  test "failed runs count by their share" do
    for {total, failed, points} <- [{100, 1, 95}, {10, 2, 85}, {100, 39, 85}, {10, 4, 75}] do
      assert grade([runs(total, failed)]).points == points
    end
  end

  test "the borders of the letters" do
    for {points, letter} <- [
          {100, "A++"},
          {99, "A+"},
          {95, "A+"},
          {94, "A"},
          {85, "A"},
          {84, "B"},
          {70, "B"},
          {69, "C"},
          {55, "C"},
          {54, "D"},
          {40, "D"},
          {39, "F"},
          {0, "F"}
        ],
        do: assert(Grade.letter(points) == letter)
  end

  test "the worst pipeline is an F and never below zero" do
    all = [
      runs(4, 4),
      fact("red1"),
      fact("flaky"),
      fact("file1"),
      fact("file2"),
      fact("rights", "all write permissions"),
      fact("pinned", "fixed commit: 9."),
      fact("timeout"),
      fact("concurrency"),
      fact("setup", "90% of all step time")
    ]

    assert %{letter: "F", points: 0, off: off} = grade(all)
    assert length(off) == 9
  end

  test "no grade without enough facts or before the end" do
    refute grade([])
    refute grade([runs(2, 0)])
    refute grade([fact("failed", "something else")])
    refute grade([runs(3, 4)])
    refute grade([runs(10, 0)], :examining)
    refute grade([runs(10, 0)], :examined, ~U[2026-11-24 13:49:59Z])
    refute Grade.of(%{state: :examined, facts: nil, inserted_at: ~U[2026-11-25 00:00:00Z]})
  end

  test "the published rules name every grade and rule" do
    assert length(Grade.grades()) == 7 and length(Grade.rules()) == 9
  end
end
