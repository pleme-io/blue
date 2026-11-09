use("chuuzou", [:cz_host_image])

def run_of(args)
  r = exec_capture(*args)
  {ok: second(first(r)) == 0, out: second(second(r))}
end

def interpret(program)
  run_of([self_exe, "run", "--quiet", program])
end

def native(program, work)
  out = path_join(work, replace(path_basename(program), ".b", ""))
  run_of([cz_host_image(program, env_required("CORPUS_SEAM"), out)])
end

def difference(program, work)
  want = interpret(program)
  got = native(program, work)
  if want != got
    "#{path_basename(program)}: interpreter #{to_s(want)}, native #{to_s(got)}"
  end
end

def programs()
  filter((p) -> ends_with?(p, ".b"), ls(env_required("CORPUS_DIR")))
end

test "the corpus is not empty and holds a failing run"
  assert count(programs) >= 6
  assert member?("fault.b", map(path_basename, programs))
end

test "every corpus program prints the same and ends the same, interpreted and native"
  work = path_join(getenv("TMPDIR", "/tmp"), "chuuzou-corpus-#{to_s(now_ns)}")
  assert filter((d) -> d != nil, map((p) -> difference(p, work), programs)) ==
    []
end
