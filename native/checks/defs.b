@moduledoc """
Tier T3, held to the interpreter: each definition of $DEFS_PROGRAM that
nix/native-defs.nix compiled into $DEFS_ROOT (the `native` tier's layout,
native/v1/<def_hash hex>/def) answers what `blue run` answers, and a run
with BLUE_NATIVE=on answers a call from the artifact its def_hash names.
"""

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
  call = "#{name}(#{join(map(to_s, args), ", ")})"
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
      want.nil? or want != native(first(c), second(c))
    end,
    cases
  )
  assert count(cases) == 3
  assert differ == []
end

test "a run with the native tier on answers a call from the artifact its def_hash names", {
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
