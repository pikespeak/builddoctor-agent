defmodule Builddoctor.DiffTest do
  use ExUnit.Case, async: true

  alias Builddoctor.Diff

  defp short(a, b), do: for(r <- Diff.lines(a, b), do: {r.kind, r.number, r.text})

  test "shows the change with its surroundings and line numbers" do
    before = Enum.map_join(1..9, "\n", &"l#{&1}")

    assert short(before, String.replace(before, "l5\n", "new\n")) == [
             {:gap, nil, "1 unchanged line"},
             {:same, 2, "l2"},
             {:same, 3, "l3"},
             {:same, 4, "l4"},
             {:removed, 5, "l5"},
             {:added, 5, "new"},
             {:same, 6, "l6"},
             {:same, 7, "l7"},
             {:same, 8, "l8"},
             {:gap, nil, "1 unchanged line"}
           ]
  end

  test "counts hidden lines and numbers both sides" do
    long = Enum.map_join(1..20, "\n", &"l#{&1}")
    assert [{:gap, nil, "17 unchanged lines"} | _] = short(long, long <> "\nend")
    assert [{:gap, nil, "20 unchanged lines"}] = short(long, long)
    assert [{:removed, 1, "a"}, {:same, 1, "b"}, {:added, 2, "c"}] = short("a\nb", "b\nc")
  end

  test "a lost final newline is visible" do
    assert {:removed, 2, ""} in short("a\n", "a")
  end

  @tag :tmp_dir
  test "the patch applies with git and gives exactly the changed file", %{tmp_dir: dir} do
    long = for i <- 1..40, do: "line #{i}\n"

    drop = fn lines, at ->
      lines |> Enum.with_index(1) |> Enum.reject(&(elem(&1, 1) in at)) |> Enum.map(&elem(&1, 0))
    end

    for {from, to} <- [
          {long, drop.(long, [5])},
          {long, drop.(long, [1])},
          {long, drop.(long, [40])},
          {long, drop.(long, [3, 20, 21, 38])},
          {long, ["new\n" | drop.(long, [10, 30])]},
          {drop.(long, [10]), long},
          {["a\n", "b\n"], ["a\n"]}
        ] do
      {from, to} = {Enum.join(from), Enum.join(to)}
      File.write!(Path.join(dir, "ci.yml"), from)
      File.write!(Path.join(dir, "change.patch"), Diff.patch(from, to, "ci.yml"))
      assert {_, 0} = System.cmd("git", ["init", "-q"], cd: dir)

      assert {out, 0} =
               System.cmd("git", ["apply", "change.patch"], cd: dir, stderr_to_stdout: true)

      assert out == "" and File.read!(Path.join(dir, "ci.yml")) == to
    end
  end
end
