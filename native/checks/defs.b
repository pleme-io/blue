@moduledoc """
Tier T3, held to the interpreter: each definition of $DEFS_PROGRAM that
nix/native-defs.nix compiled into $DEFS_ROOT (the `native` tier's layout,
native/v1/<def_hash hex>/def) answers what `blue run` answers, and a run
with BLUE_NATIVE=on answers a call from the artifact its def_hash names.
"""

use("retsu", [:first])
use("tesuto", [:literal])

record pt(x: Int, y: Int)

record gauge(on: Bool, w: Float, n: Int)

record tag(label: Str, n: Int)

record bag(xs: List(Int), n: Int)

@doc """
cases: The calls each definition of native/defs/base.b is held to.
"""
def cases()
  [["square", [12]], ["sum_squares", [100, 0]], ["fib", [20]]]
end

def printed(r)
  if second(first(r)) == 0
    second(second(r))
  end
end

def hashes()
  r = exec_capture(
    self_exe,
    "ast",
    "--resolved",
    "--defs",
    env_required("DEFS_PROGRAM")
  )
  map((d) -> [d["key"], replace(d["hash"], "b3:", "")], json_read(printed(r)))
end

def hex_of(name)
  second(find(hashes, (h) -> first(h) == "%root/#{name}"))
end

def artifact(root, name)
  path_join(root, "native", "v1", hex_of(name), "def")
end

def driver(work, name, args)
  file = path_join(work, "#{name}.b")
  call = "#{name}(#{join(map(literal, args), ", ")})"
  write_program(
    file,
    unlines(
      [
        read_file(env_required("DEFS_PROGRAM")),
        "write_stdout(unlines([to_s(#{call})]))"
      ]
    )
  )
  file
end

def interpreted(work, name, args, env)
  printed(
    exec_with_env(env, self_exe, "run", "--quiet", driver(work, name, args))
  )
end

def native(name, args)
  printed(
    exec_capture(artifact(env_required("DEFS_ROOT"), name), *map(to_s, args))
  )
end

@doc """
off: The environment of a run the interpreter answers alone.
"""
def off()
  [%w[BLUE_NATIVE off]]
end

@doc """
disagreeing: The calls, each `[name, args]`, whose answer under BLUE_NATIVE=on, with the
artifacts of $DEFS_ROOT on the shelf, is not the interpreter's.
"""
def disagreeing(work, calls)
  on = [%w[BLUE_NATIVE on], ["BLUE_CACHE_SHARED", env_required("DEFS_ROOT")]]
  filter(
    fn(c)
      interpreted(work, first(c), second(c), off) !=
        interpreted(work, first(c), second(c), on)
    end,
    calls
  )
end

@doc """
swapped: The environment of a run whose shelf answers `name` from the artifact of `other`
(its executable and its library), so a call of `name` that answers what
`other` answers was answered by an artifact, not the interpreter.
"""
def swapped(work, name, other)
  shelf = path_join(work, "shelf", "native", "v1", hex_of(name))
  mkdir_p(shelf)
  from = path_join(env_required("DEFS_ROOT"), "native", "v1", hex_of(other))
  exec_capture("ln", "-s", path_join(from, "def"), path_join(shelf, "def"))
  exec_capture(
    "ln",
    "-s",
    path_join(from, "def.so"),
    path_join(shelf, "def.so")
  )
  [%w[BLUE_NATIVE on], ["BLUE_CACHE_SHARED", path_join(work, "shelf")]]
end

test "every compiled definition answers what the interpreter answers", {
  kind: :integration
}
  work = temp_dir("native-defs")
  differ = filter(
    fn(c)
      want = interpreted(work, first(c), second(c), off)
      want.nil? or "i#{want}" != native(first(c), second(c))
    end,
    cases
  )
  assert count(cases) == 3
  assert differ == []
end

test "the native tier answers a call from its def_hash's artifact", {
  kind: :integration
}
  work = temp_dir("native-tier")
  shelf = path_join(work, "shelf", "native", "v1", hex_of("fib"))
  mkdir_p(shelf)
  exec_capture(
    "ln",
    "-s",
    artifact(env_required("DEFS_ROOT"), "square"),
    path_join(shelf, "def")
  )
  on = [%w[BLUE_NATIVE on], ["BLUE_CACHE_SHARED", path_join(work, "shelf")]]
  held = [%w[BLUE_NATIVE off], ["BLUE_CACHE_SHARED", path_join(work, "shelf")]]
  assert interpreted(work, "fib", [5], held) == unlines(["5"])
  assert interpreted(work, "fib", [5], on) == unlines(["25"])
  assert interpreted(work, "square", [5], on) == unlines(["25"])
end

test "a Bool crosses the seam both ways", {kind: :integration}
  work = temp_dir("native-bool")
  calls = [
    ["small", [2]],
    ["small", [5]],
    ["pick", [true, 7]],
    ["pick", [false, 7]]
  ]
  assert disagreeing(work, calls) == []
  assert interpreted(work, "big", [5], off) == unlines(["true"])
  assert interpreted(work, "big", [5], swapped(work, "big", "small")) ==
    unlines(["false"])
end

test "a Float crosses the seam both ways", {kind: :integration}
  work = temp_dir("native-float")
  calls = [
    ["area", [1.5]],
    ["half", [-3.0]],
    ["wide", [2.5, 2]],
    ["wide", [1.5, 2]]
  ]
  assert disagreeing(work, calls) == []
  assert interpreted(work, "area", [4.0], off) == unlines(["56.0"])
  assert interpreted(work, "area", [4.0], swapped(work, "area", "half")) ==
    unlines(["2.0"])
end

test "a Str crosses the seam both ways", {kind: :integration}
  work = temp_dir("native-str")
  calls = [
    ["shout", ["hé", 3]],
    ["width", ["héllo"]],
    ["width", [""]],
    ["twice", ["ab"]]
  ]
  assert disagreeing(work, calls) == []
  assert interpreted(work, "twice", ["ab"], off) == unlines(["abab"])
  assert interpreted(work, "twice", ["ab"], swapped(work, "twice", "bang")) ==
    unlines(["ab!"])
end

test "a list of Ints crosses the seam both ways", {kind: :integration}
  work = temp_dir("native-list")
  calls = [
    ["grown", [[1, -2], 3]],
    ["grown", [[], 0]],
    ["tally", [[5, 6, 7]]],
    ["tally", [[]]]
  ]
  assert disagreeing(work, calls) == []
  assert interpreted(work, "grown", [[1], 2], off) == unlines(["[1, 2]"])
  assert interpreted(
    work,
    "grown",
    [[1], 2],
    swapped(work, "grown", "doubled")
  ) == unlines(["[1, 2, 2]"])
end

test "a record of Ints crosses the seam both ways", {kind: :integration}
  work = temp_dir("native-record")
  calls = [["shifted", [pt(1, -2), 5]], ["spread", [pt(7, 3)]]]
  assert disagreeing(work, calls) == []
  assert interpreted(work, "shifted", [pt(1, 2), 5], off) ==
    unlines(["pt({x: 6, y: 2})"])
  assert interpreted(
    work,
    "shifted",
    [pt(1, 2), 5],
    swapped(work, "shifted", "lifted")
  ) == unlines(["pt({x: 1, y: 7})"])
end

test "a list only tested is a set, and answers as the list does", {
  kind: :integration
}
  work = temp_dir("native-set")
  calls = [["hits", [[1, 3, 5], 50, 0]], ["hits", [[], 10, 0]]]
  assert disagreeing(work, calls) == []
  assert contains?(
    read_file(
      path_join(
        env_required("DEFS_ROOT"),
        "native",
        "v1",
        hex_of("hits"),
        "def.rs"
      )
    ),
    "set_of"
  )
end

test "a list only popped is a queue, and answers as the list does", {
  kind: :integration
}
  work = temp_dir("native-queue")
  calls = [["drain", [[4, -1, 9], 0]], ["drain", [[], 3]]]
  assert disagreeing(work, calls) == []
  assert contains?(
    read_file(
      path_join(
        env_required("DEFS_ROOT"),
        "native",
        "v1",
        hex_of("drain"),
        "def.rs"
      )
    ),
    "queue_of"
  )
end

test "a record of Bools and Floats crosses the seam both ways", {
  kind: :integration
}
  work = temp_dir("native-gauge")
  calls = [
    ["weighed", [gauge(true, 1.5, 3), 0.25]],
    ["switched", [gauge(false, -2.0, 7)]]
  ]
  assert disagreeing(work, calls) == []
  g = gauge(true, 1.5, 3)
  assert interpreted(work, "weighed", [g, 0.25], off) ==
    unlines(["gauge({n: 3, on: true, w: 1.75})"])
  assert interpreted(
    work,
    "weighed",
    [g, 0.25],
    swapped(work, "weighed", "lightened")
  ) == unlines(["gauge({n: 3, on: true, w: 1.25})"])
end

test "a record that holds a Str crosses the seam both ways", {
  kind: :integration
}
  work = temp_dir("native-tag")
  calls = [["bumped", [tag("é, a", 3), 4]], ["relabeled", [tag("", -1), "x"]]]
  assert disagreeing(work, calls) == []
  t = tag("é, a", 3)
  assert interpreted(work, "bumped", [t, 4], off) ==
    unlines(["tag({label: \"é, a\", n: 7})"])
  assert interpreted(
    work,
    "bumped",
    [t, 4],
    swapped(work, "bumped", "shrunk")
  ) == unlines(["tag({label: \"é, a\", n: -1})"])
end

test "a record that holds a list of Ints crosses the seam both ways", {
  kind: :integration
}
  work = temp_dir("native-bag")
  calls = [["pushed", [bag([1, -2], 0), 5]], ["tallied", [bag([], 9)]]]
  assert disagreeing(work, calls) == []
  b = bag([1], 0)
  assert interpreted(work, "pushed", [b, 5], off) ==
    unlines(["bag({n: 0, xs: [1, 5]})"])
  assert interpreted(
    work,
    "pushed",
    [b, 5],
    swapped(work, "pushed", "pushed_twice")
  ) == unlines(["bag({n: 0, xs: [1, 5, 5]})"])
end

test "a map of Strs to Ints crosses the seam both ways", {kind: :integration}
  work = temp_dir("native-map")
  m = assoc(assoc({}, "é, b", 2), "a", 1)
  calls = [
    ["put_word", [m, "c", 3]],
    ["put_word", [{}, "", -1]],
    ["looked_up", [m, "a"]],
    ["looked_up", [m, "absent"]]
  ]
  assert disagreeing(work, calls) == []
  assert interpreted(work, "put_word", [m, "c", 3], off) ==
    unlines(["{\"a\" => 1, \"c\" => 3, \"é, b\" => 2}"])
  assert interpreted(
    work,
    "put_word",
    [m, "c", 3],
    swapped(work, "put_word", "put_double")
  ) == unlines(["{\"a\" => 1, \"c\" => 6, \"é, b\" => 2}"])
end

test "a list of records crosses the seam both ways", {kind: :integration}
  work = temp_dir("native-items")
  ts = [tag("é, a", 3), tag("", -1)]
  calls = [
    ["placed", [[pt(1, 2)], 3]],
    ["placed", [[], 0]],
    ["swept", [[pt(1, 2), pt(-4, 5)], 0, pt(0, 1)]],
    ["swept", [[], 0, pt(7, 7)]],
    ["joined", [ts, [tag("b", 2)]]],
    ["joined", [[], []]],
    ["headed", [ts]]
  ]
  assert disagreeing(work, calls) == []
  assert interpreted(work, "placed", [[pt(1, 2)], 3], off) ==
    unlines(["[pt({x: 1, y: 2}), pt({x: 3, y: -3})]"])
  assert interpreted(
    work,
    "placed",
    [[pt(1, 2)], 3],
    swapped(work, "placed", "placed_twice")
  ) == unlines(["[pt({x: 1, y: 2}), pt({x: 3, y: -3}), pt({x: 3, y: -3})]"])
end

test "a lambda written in place for map, filter or reduce runs natively", {
  kind: :integration
}
  work = temp_dir("native-lambda")
  calls = [
    ["scaled", [[1, -2, 3], 4]],
    ["scaled", [[], 4]],
    ["kept", [[5, -1, 9, 2], 2]],
    ["kept", [[], 0]],
    ["crossed", [[1, 2], [3, 4, 5]]],
    ["crossed", [[], [1]]],
    ["nudged", [[pt(1, 2), pt(-3, 4)], 10]]
  ]
  assert disagreeing(work, calls) == []
  assert interpreted(work, "scaled", [[1, 2], 3], off) == unlines(["[3, 6]"])
  assert interpreted(
    work,
    "scaled",
    [[1, 2], 3],
    swapped(work, "scaled", "scaled_up")
  ) == unlines(["[4, 7]"])
end

test "a lambda in a local, called or mapped, runs natively", {
  kind: :integration
}
  work = temp_dir("native-held")
  calls = [
    ["held", [[1, -2, 3], 4]],
    ["held", [[], 4]],
    ["picked", [[5, -1, 9, 2], 2]],
    ["picked", [[], 0]],
    ["applied", [3, 10]],
    ["applied", [-4, 0]]
  ]
  assert disagreeing(work, calls) == []
  assert interpreted(work, "held", [[1, 2], 3], off) == unlines(["[3, 6]"])
  assert interpreted(
    work,
    "held",
    [[1, 2], 3],
    swapped(work, "held", "held_up")
  ) == unlines(["[4, 7]"])
end
