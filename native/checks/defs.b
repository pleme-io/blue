@moduledoc """
Tier T3, held to the interpreter: each definition of $DEFS_PROGRAM that
nix/native-defs.nix compiled into $DEFS_ROOT (the `native` tier's layout,
native/v1/<def_hash hex>/def) answers what `blue run` answers, and a run
with BLUE_NATIVE=on answers a call from the artifact its def_hash names.
"""

use("retsu", [:first])
use("tesuto", [:literal])

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

test "every compiled definition answers what the interpreter answers", {
  kind: :integration
}
  work = temp_dir("native-defs")
  differ = filter(
    fn(c)
      want = interpreted(work, first(c), second(c), [%w[BLUE_NATIVE off]])
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
  off = [%w[BLUE_NATIVE off], ["BLUE_CACHE_SHARED", path_join(work, "shelf")]]
  assert interpreted(work, "fib", [5], off) == unlines(["5"])
  assert interpreted(work, "fib", [5], on) == unlines(["25"])
  assert interpreted(work, "square", [5], on) == unlines(["25"])
end

test "a Bool crosses the seam both ways", {kind: :integration}
  work = temp_dir("native-bool")
  root = env_required("DEFS_ROOT")
  on = [%w[BLUE_NATIVE on], ["BLUE_CACHE_SHARED", root]]
  off = [%w[BLUE_NATIVE off]]
  calls = [
    ["small", [2]],
    ["small", [5]],
    ["pick", [true, 7]],
    ["pick", [false, 7]]
  ]
  differ = filter(
    fn(c)
      interpreted(work, first(c), second(c), off) !=
        interpreted(work, first(c), second(c), on)
    end,
    calls
  )
  assert differ == []
  shelf = path_join(work, "shelf", "native", "v1", hex_of("big"))
  mkdir_p(shelf)
  small = path_join(root, "native", "v1", hex_of("small"))
  exec_capture("ln", "-s", path_join(small, "def"), path_join(shelf, "def"))
  exec_capture(
    "ln",
    "-s",
    path_join(small, "def.so"),
    path_join(shelf, "def.so")
  )
  swapped = [
    %w[BLUE_NATIVE on],
    ["BLUE_CACHE_SHARED", path_join(work, "shelf")]
  ]
  assert interpreted(work, "big", [5], off) == unlines(["true"])
  assert interpreted(work, "big", [5], swapped) == unlines(["false"])
end

test "a Float crosses the seam both ways", {kind: :integration}
  work = temp_dir("native-float")
  root = env_required("DEFS_ROOT")
  on = [%w[BLUE_NATIVE on], ["BLUE_CACHE_SHARED", root]]
  off = [%w[BLUE_NATIVE off]]
  calls = [
    ["area", [1.5]],
    ["half", [-3.0]],
    ["wide", [2.5, 2]],
    ["wide", [1.5, 2]]
  ]
  differ = filter(
    fn(c)
      interpreted(work, first(c), second(c), off) !=
        interpreted(work, first(c), second(c), on)
    end,
    calls
  )
  assert differ == []
  shelf = path_join(work, "shelf", "native", "v1", hex_of("area"))
  mkdir_p(shelf)
  half = path_join(root, "native", "v1", hex_of("half"))
  exec_capture("ln", "-s", path_join(half, "def"), path_join(shelf, "def"))
  exec_capture(
    "ln",
    "-s",
    path_join(half, "def.so"),
    path_join(shelf, "def.so")
  )
  swapped = [
    %w[BLUE_NATIVE on],
    ["BLUE_CACHE_SHARED", path_join(work, "shelf")]
  ]
  assert interpreted(work, "area", [4.0], off) == unlines(["56.0"])
  assert interpreted(work, "area", [4.0], swapped) == unlines(["2.0"])
end

test "a Str crosses the seam both ways", {kind: :integration}
  work = temp_dir("native-str")
  root = env_required("DEFS_ROOT")
  on = [%w[BLUE_NATIVE on], ["BLUE_CACHE_SHARED", root]]
  off = [%w[BLUE_NATIVE off]]
  calls = [
    ["shout", ["hé", 3]],
    ["width", ["héllo"]],
    ["width", [""]],
    ["twice", ["ab"]]
  ]
  differ = filter(
    fn(c)
      interpreted(work, first(c), second(c), off) !=
        interpreted(work, first(c), second(c), on)
    end,
    calls
  )
  assert differ == []
  shelf = path_join(work, "shelf", "native", "v1", hex_of("twice"))
  mkdir_p(shelf)
  bang = path_join(root, "native", "v1", hex_of("bang"))
  exec_capture("ln", "-s", path_join(bang, "def"), path_join(shelf, "def"))
  exec_capture(
    "ln",
    "-s",
    path_join(bang, "def.so"),
    path_join(shelf, "def.so")
  )
  swapped = [
    %w[BLUE_NATIVE on],
    ["BLUE_CACHE_SHARED", path_join(work, "shelf")]
  ]
  assert interpreted(work, "twice", ["ab"], off) == unlines(["abab"])
  assert interpreted(work, "twice", ["ab"], swapped) == unlines(["ab!"])
end
