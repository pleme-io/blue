use("retsu")
use("moji")
use("shisutemu")
use("deeta")

# heni (変異) — mutation testing for a blue package: each mutation changes one literal in a fresh copy of the package, runs its tests, and must make them fail.
#
# A mutation the tests survive is a behaviour nothing checks. This is the red
# run every gate is owed ("a gate that has never gone red proves nothing"),
# made a command instead of a hand-written shell loop.
#
#   heni <PACKAGE_DIR> <MUTATIONS.json> [--blue BIN] [--test FILE]
#
# The tests run under the blue that runs heni (`self_exe`), unless --blue names
# another: never a PATH lookup, which in a nix sandbox finds nothing.
#
# MUTATIONS.json is a list of {"name", "file", "find", "replace"}: in `file`
# (relative to the package), the text `find` becomes `replace`. `find` must
# occur EXACTLY ONCE, so a mutation cannot silently hit the wrong place or no
# place; one that does not is refused, and a refusal fails the run like a
# survivor does.
#
# Every mutation runs in its own fresh directory, first on BLUE_PATH, so an
# earlier mutated copy can never shadow the package under test (measured
# 2026-09-27: a shared directory did exactly that). The unmutated copy runs
# first as the control: if the tests fail with no mutation, no "caught" means
# anything, and the run stops.
#
# Exits non-zero (an uncaught error) when the control fails, or any mutation
# survives, is refused, or is blind (its tests could not be started).

# ── one mutation, pure ───────────────────────────────────────────────

# {text} with `find` replaced, or {error} when it does not occur exactly once.
def hn_apply(text, find, replace)
  n = occurrences(text, find)
  if length(find) == 0
    {error: "an empty find matches everywhere"}
  elsif n == 1
    {text: replace_first(text, find, replace)}
  else
    {error: "find occurs #{to_s(n)} times, not once"}
  end
end

# The verdict for one mutation from its test run's status. nil means the
# tests could not be started at all: `blind`, never `caught`, because a run
# that did not happen caught nothing.
def hn_verdict(applied, status)
  if get(applied, :error) != nil
    :refused
  elsif status == nil
    :blind
  elsif status == 0
    :survived
  else
    :caught
  end
end

# ── the spec ─────────────────────────────────────────────────────────

# Mutations from parsed JSON: [{name, file, find, replace}].
def hn_mutations(parsed)
  if parsed == nil
    []
  else
    map(
      fn(m)
        {
          name: get_str(m, "name", "?"),
          file: get_str(m, "file", ""),
          find: get_str(m, "find", ""),
          replace: get_str(m, "replace", "")
        }
      end,
      parsed
    )
  end
end

# The package's name: the last segment of its directory.
def hn_package_name(dir)
  last(filter(fn(s) !is_empty(s) end, split(dir, "/")))
end

# ── the fresh copy ───────────────────────────────────────────────────

# Copy every file under `src` to `dest`, keeping relative paths.
def hn_copy(src, dest)
  base = if ends_with?(src, "/")
    src
  else
    concat(src, "/")
  end
  map(
    fn(f)
      target = path_join(dest, strip_prefix(f, base))
      mkdir_p(path_dirname(target))
      write_file(target, read_file(f))
    end,
    walk_dir(src)
  )
  dest
end

# A fresh root holding one copy of the package: <tmp>/heni-<now>-<tag>/<name>.
def hn_fresh(pkg_dir, tmp, tag)
  root = path_join(tmp, "heni-#{to_s(now_ms())}-#{tag}")
  hn_copy(pkg_dir, path_join(root, hn_package_name(pkg_dir)))
  root
end

# Run the copy's tests with the fresh root first on BLUE_PATH. The capture.
def hn_test(blue, root, name, test_file)
  path = "#{root}:#{getenv("BLUE_PATH", "")}"
  try(
    exec_with_env(
      [["BLUE_PATH", path]],
      blue,
      "test",
      path_join(path_join(root, name), test_file)
    ),
    catch(_e(), nil)
  )
end

def hn_status(cap)
  if cap == nil
    nil
  else
    status_of(cap)
  end
end

# ── a whole run ──────────────────────────────────────────────────────

# spec: {package, mutations, blue, test, tmp}. Returns the report.
def hn_run(spec)
  pkg = get(spec, :package)
  name = hn_package_name(pkg)
  test_file = if get(spec, :test) == nil
    "#{name}.b"
  else
    get(spec, :test)
  end
  blue = get(spec, :blue)
  if blue == nil
    throw(
      error(
        :heni_no_blue,
        "heni runs each mutation's tests with the blue CLI, and none is running this program (self_exe() is nil); run heni through blue, or pass --blue"
      )
    )
  end
  tmp = get(spec, :tmp)
  control_root = hn_fresh(pkg, tmp, "control")
  control = hn_status(hn_test(blue, control_root, name, test_file))
  rm_rf(control_root)
  if control != 0
    {
      control: control,
      results: [],
      caught: 0,
      survived: 0,
      refused: 0,
      blind: 0
    }
  else
    results = map(
      fn(p) hn_one(spec, name, test_file, nth(0, p), nth(1, p)) end,
      enumerate(get(spec, :mutations))
    )
    {
      control: 0,
      results: results,
      caught: count_where(fn(r) get(r, :verdict) == :caught end, results),
      survived: count_where(fn(r) get(r, :verdict) == :survived end, results),
      refused: count_where(fn(r) get(r, :verdict) == :refused end, results),
      blind: count_where(fn(r) get(r, :verdict) == :blind end, results)
    }
  end
end

def hn_one(spec, name, test_file, i, m)
  root = hn_fresh(get(spec, :package), get(spec, :tmp), to_s(i))
  file = path_join(path_join(root, name), get(m, :file))
  applied = hn_apply(read_or(file, ""), get(m, :find), get(m, :replace))
  status = if get(applied, :error) == nil
    write_file(file, get(applied, :text))
    hn_status(hn_test(get(spec, :blue), root, name, test_file))
  else
    nil
  end
  rm_rf(root)
  {
    name: get(m, :name),
    verdict: hn_verdict(applied, status),
    detail: get(applied, :error)
  }
end

# ── the command ──────────────────────────────────────────────────────

def hn_report_text(r)
  if get(r, :control) != 0
    "control FAILED: the unmutated tests exit #{to_s(get(r, :control))}; no mutation was run\n"
  else
    rows = join(
      map(
        fn(x)
          "#{to_s(get(x, :verdict))}  #{get(x, :name)}#{hn_detail(x)}\n"
        end,
        get(r, :results)
      ),
      ""
    )
    concat(
      rows,
      "#{to_s(get(r, :caught))} caught, #{to_s(get(r, :survived))} survived, #{to_s(get(r, :refused))} refused, #{to_s(get(r, :blind))} blind\n"
    )
  end
end

def hn_detail(x)
  if get(x, :detail) == nil
    ""
  else
    "  (#{get(x, :detail)})"
  end
end

def hn_ok?(r)
  get(r, :control) == 0 &&
    get(r, :survived) == 0 &&
    get(r, :refused) == 0 &&
    get(r, :blind) == 0
end

# {package, mutations_file, blue, test} from argv, or {error}.
def hn_parse(args)
  if size(args) < 2
    {error: "usage: heni PACKAGE_DIR MUTATIONS.json [--blue BIN] [--test FILE]"}
  else
    hn_parse_flags(
      drop(2, args),
      {
        package: nth(0, args),
        mutations_file: nth(1, args),
        blue: self_exe(),
        test: nil,
        error: nil
      }
    )
  end
end

def hn_parse_flags(args, acc)
  if is_empty(args) || get(acc, :error) != nil
    acc
  else
    flag = first(args)
    if contains(["--blue", "--test"], flag) && size(args) >= 2
      key = if flag == "--blue"
        :blue
      else
        :test
      end
      hn_parse_flags(drop(2, args), assoc(acc, key, nth(1, args)))
    else
      assoc(acc, :error, "unknown argument #{flag}")
    end
  end
end

def hn_main()
  a = hn_parse(argv())
  if get(a, :error) != nil
    write_stderr("#{get(a, :error)}\n")
    throw(error(:heni_usage, get(a, :error)))
  end
  r = hn_run(
    {
      package: get(a, :package),
      mutations: hn_mutations(json_parse(read_file(get(a, :mutations_file)))),
      blue: get(a, :blue),
      test: get(a, :test),
      tmp: getenv("TMPDIR", "/tmp")
    }
  )
  write_stdout(hn_report_text(r))
  if hn_ok?(r) == false
    throw(
      error(
        :heni_failed,
        "a mutation survived or was refused, or the control failed"
      )
    )
  end
  r
end

# ── tests ────────────────────────────────────────────────────────────

test "a mutation applies exactly once or is refused"
  assert get(hn_apply("a == 1", "== 1", "== 2"), :text) == "a == 2"
  assert get(hn_apply("x x", "x", "y"), :error) ==
    "find occurs 2 times, not once"
  assert get(hn_apply("abc", "z", "y"), :error) ==
    "find occurs 0 times, not once"
  assert get(hn_apply("abc", "", "y"), :error) ==
    "an empty find matches everywhere"
end

test "the verdicts: refused, survived, caught"
  assert hn_verdict({error: "no"}, nil) == :refused
  assert hn_verdict({text: "t"}, 0) == :survived
  assert hn_verdict({text: "t"}, 1) == :caught
  # The tests could not be started: blind, not caught.
  assert hn_verdict({text: "t"}, nil) == :blind
  # Any blind mutation fails the run, as a survivor does.
  assert hn_ok?({control: 0, survived: 0, refused: 0, blind: 1}) == false
  assert hn_ok?({control: 0, survived: 0, refused: 0, blind: 0}) == true
end

test "arguments"
  a = hn_parse(["/p/kazu", "m.json", "--blue", "/bin/blue"])
  assert get(a, :package) == "/p/kazu"
  assert get(a, :blue) == "/bin/blue"
  assert get(a, :test) == nil
  assert get(hn_parse(["/p"]), :error) != nil
  assert get(hn_parse(["/p", "m", "--nope"]), :error) ==
    "unknown argument --nope"
  assert hn_package_name("/a/b/kazu/") == "kazu"
end

test "without a blue CLI, heni refuses rather than spawning its host"
  refused = try(
    hn_run(
      {
        package: "/nonexistent",
        mutations: [],
        blue: nil,
        test: nil,
        tmp: "/tmp"
      }
    ),
    catch(_e(), :refused)
  )
  assert refused == :refused
end

# Under the blue CLI (`blue test`, the nix bidama gate) this runs for real.
# Embedded in another host (cargo's harness), self_exe() is nil and the test
# above covers the refusal instead: spawning the host would re-run it.
test "a run end to end: a caught mutation, a survivor, a refusal"
  if self_exe() != nil
    hn_end_to_end()
  end
end

def hn_end_to_end()
  tmp = path_join(getenv("TMPDIR", "/tmp"), "heni-self-#{to_s(now_ms())}")
  pkg = path_join(tmp, "hnprobe")
  mkdir_p(pkg)
  write_file(path_join(pkg, "Bluefile"), "package(\"hnprobe\", \"0.1.0\")\n")
  write_file(
    path_join(pkg, "hnprobe.b"),
    "def hp_double(x)\n  x * 2\nend\n\ndef hp_unused()\n  7\nend\n\ntest \"double\"\n  assert hp_double(3) == 6\nend\n"
  )
  muts = [
    {
      name: "double becomes triple",
      file: "hnprobe.b",
      find: "x * 2",
      replace: "x * 3"
    },
    {
      name: "an unchecked constant",
      file: "hnprobe.b",
      find: "  7\n",
      replace: "  8\n"
    },
    {name: "not there", file: "hnprobe.b", find: "nowhere", replace: "x"}
  ]
  r = hn_run(
    {package: pkg, mutations: muts, blue: self_exe(), test: nil, tmp: tmp}
  )
  assert get(r, :control) == 0
  assert map(fn(x) get(x, :verdict) end, get(r, :results)) ==
    [:caught, :survived, :refused]
  assert hn_ok?(r) == false
  assert contains?(
    hn_report_text(r),
    "1 caught, 1 survived, 1 refused, 0 blind"
  ) ==
    true
  # Control: a package whose own tests fail stops the run before any mutation.
  write_file(
    path_join(pkg, "hnprobe.b"),
    "test \"broken\"\n  assert 1 == 2\nend\n"
  )
  bad = hn_run(
    {package: pkg, mutations: muts, blue: self_exe(), test: nil, tmp: tmp}
  )
  assert get(bad, :control) != 0
  assert is_empty(get(bad, :results)) == true
  rm_rf(tmp)
  true
end
