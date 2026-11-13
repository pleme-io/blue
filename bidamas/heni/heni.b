@moduledoc """
heni (変異) — mutation testing for a blue package: each mutation changes one literal in a fresh copy of the package, runs its tests, and must make them fail.

A mutation the tests survive is a behaviour nothing checks. This is the red
run every gate is owed ("a gate that has never gone red proves nothing"),
made a command instead of a hand-written shell loop.

  heni <PACKAGE_DIR> <MUTATIONS.json> [--blue BIN] [--test FILE] [--finds]

`--finds` runs no test: it only checks that every mutation still finds its
text exactly once, and fails naming each one that would be refused. A rewrite
of the package that strands a mutation fails here in a second, not in a
post-merge run.

The tests run under the blue that runs heni (`self_exe`), unless --blue names
another: never a PATH lookup, which in a nix sandbox finds nothing.

MUTATIONS.json is a list of {"name", "file", "find", "replace"}: in `file`
(relative to the package), the text `find` becomes `replace`. `find` must
occur EXACTLY ONCE, so a mutation cannot silently hit the wrong place or no
place; one that does not is refused, and a refusal fails the run like a
survivor does.

Every mutation runs in its own fresh directory, first on BLUE_PATH, so an
earlier mutated copy can never shadow the package under test (measured
2026-09-27: a shared directory did exactly that). The unmutated copy runs
first as the control: if the tests fail with no mutation, no "caught" means
anything, and the run stops.

Exits non-zero (an uncaught error) when the control fails, or any mutation
survives, is refused, or is blind (its tests could not be started).

A run's caught ratio (`score`, caught over total) is a ratchet across
every package: `gen/heni-gate.b` holds each package at the ratio recorded in
`ratio.baseline` beside this file, and `blue gen/heni-gate.b record` is the
one writer of that file. A ratio that falls fails the gate and names the
package and its survivors.

    verdict({text: "t"}, 1) #=> :caught
"""

use("deeta", [:get_str])
use("hikisuu")
use("kansuu", [:maybe])
use("moji", %i[occurrences replace_first strip_prefix])

use("retsu", %i[count_where enumerate is_empty last])
use("settei")

use("shisutemu", %i[read_or status_of])

legacy_names("0.1.1", "hn")

# ── one mutation, pure ───────────────────────────────────────────────

# waive B0013: `apply` is a builtin heni also uses, so the prefix stays; heni::apply names it too
@doc """
hn_apply: {text} with `find` replaced, or {error} when it does not occur exactly once.
"""
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

@doc """
verdict: The verdict for one mutation from its test run's status. nil means the
tests could not be started at all: `blind`, never `caught`, because a run
that did not happen caught nothing.

    verdict({text: "t"}, 1) #=> :caught
"""
def verdict(applied, status)
  if applied[:error] != nil
    :refused
  elsif status.nil?
    :blind
  elsif status == 0
    :survived
  else
    :caught
  end
end

# ── the spec ─────────────────────────────────────────────────────────

@doc """
mutations: Mutations from parsed JSON: [{name, file, find, replace}].
"""
def mutations(parsed)
  if parsed.nil?
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

@doc """
stranded: the mutations that no longer apply to the package in `dir`, each as {name, detail}: its file is gone or its `find` does not occur exactly once. No test runs.

    stranded("/no/such/kazu", [{name: "a", file: "k.b", find: "x", replace: "y"}]) #=> [{name: "a", detail: "find occurs 0 times, not once"}]
"""
def stranded(dir, muts)
  map(
    (p) -> {name: p[0][:name], detail: p[1][:error]},
    filter(
      (p) -> p[1][:error] != nil,
      map(
        fn(m)
          text = read_or(path_join(dir, m[:file]), "")
          [m, hn_apply(text, m[:find], m[:replace])]
        end,
        muts
      )
    )
  )
end

@doc """
stranded_text: one line per stranded mutation, named by package and mutation.

    stranded_text("kazu", [{name: "a", detail: "find occurs 0 times, not once"}]) #=> "refused  kazu: a  (find occurs 0 times, not once)\n"
"""
def stranded_text(package, rows)
  join(
    map(
      (r) -> unlines(["refused  #{package}: #{r[:name]}  (#{r[:detail]})"]),
      rows
    ),
    ""
  )
end

@doc """
package_name: The package's name: the last segment of its directory.

    package_name("/a/b/kazu/") #=> "kazu"
"""
def package_name(dir)
  last(filter((s) -> not is_empty(s), split(dir, "/")))
end

# ── the fresh copy ───────────────────────────────────────────────────

@doc """
copy: Copy every file under `src` to `dest`, keeping relative paths.
"""
def copy(src, dest)
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

@doc """
tree_root: the bidama a package directory belongs to: the nearest directory at or above it holding a Bluefile, so a level is copied with its root.

    tree_root("/no/such/place") #=> "/no/such/place"
"""
def tree_root(dir)
  found = bluefile_at_or_above(dir)
  if found.nil?
    dir
  else
    found
  end
end

@doc """
bluefile_at_or_above: the nearest directory at or above `dir` that holds a Bluefile, or nil when none does.

    bluefile_at_or_above("/no/such/place") #=> nil
"""
def bluefile_at_or_above(dir)
  if is_file?(path_join(dir, "Bluefile"))
    dir
  else
    up = path_dirname(dir)
    if up == dir or up == "" or up == "." or up == "/"
      nil
    else
      bluefile_at_or_above(up)
    end
  end
end

@doc """
level_path: a package directory's path below the directory its bidama sits in: `kazu` for a bidama, `tree/kid` for a level.

    level_path("/no/such/kazu") #=> "kazu"
"""
def level_path(pkg_dir)
  root = tree_root(pkg_dir)
  concat(package_name(root), replace(pkg_dir, root, ""))
end

@doc """
fresh: A fresh root holding one copy of the bidama the package belongs to, its whole tree: <tmp>/heni-<now>-<tag>/<bidama>.
"""
def fresh(pkg_dir, tmp, tag)
  root = path_join(tmp, "heni-#{to_s(now_ms)}-#{tag}")
  bidama = tree_root(pkg_dir)
  copy(bidama, path_join(root, package_name(bidama)))
  root
end

# waive B0013: `test` is a reserved word, so the prefix stays; heni::test names it too
# waive B0083: integration debt recorded 2026-11-13: no test of this file declared kind: :integration reaches it yet
@doc """
hn_test: Run the copy's tests with the fresh root first on BLUE_PATH. The capture.
"""
def hn_test(blue, root, name, test_file)
  path = "#{root}:#{getenv("BLUE_PATH", "")}"
  exec_with_env(
    [["BLUE_PATH", path]],
    blue,
    "test",
    path_join(path_join(root, name), test_file)
  ) rescue
    nil
end

def status(cap)
  maybe(cap, nil, status_of)
end

# ── a whole run ──────────────────────────────────────────────────────

@doc """
run: spec: {package, mutations, blue, test, tmp}. Returns the report.
"""
def run(spec)
  pkg = spec[:package]
  name = package_name(pkg)
  test_file = if spec[:test].nil?
    "#{name}.b"
  else
    spec[:test]
  end
  blue = spec[:blue]
  if blue.nil?
    raise(
      :heni_no_blue,
      "heni runs each mutation's tests with the blue CLI, and none is running this program (self_exe() is nil); run heni through blue, or pass --blue"
    )
  end
  tmp = spec[:tmp]
  level = level_path(pkg)
  control_root = fresh(pkg, tmp, "control")
  control = status(hn_test(blue, control_root, level, test_file))
  rm_rf(control_root)
  if control != 0
    {control:, results: [], caught: 0, survived: 0, refused: 0, blind: 0}
  else
    results = map(
      (p) -> one(spec, level, test_file, p[0], p[1]),
      enumerate(spec[:mutations])
    )
    {
      control: 0,
      results:,
      caught: count_where((r) -> r[:verdict] == :caught, results),
      survived: count_where((r) -> r[:verdict] == :survived, results),
      refused: count_where((r) -> r[:verdict] == :refused, results),
      blind: count_where((r) -> r[:verdict] == :blind, results)
    }
  end
end

def one(spec, name, test_file, i, m)
  root = fresh(spec[:package], spec[:tmp], to_s(i))
  file = path_join(path_join(root, name), m[:file])
  applied = hn_apply(read_or(file, ""), m[:find], m[:replace])
  status = if applied[:error].nil?
    write_file(file, applied[:text])
    heni::status(hn_test(spec[:blue], root, name, test_file))
  end
  rm_rf(root)
  {name: m[:name], verdict: verdict(applied, status), detail: applied[:error]}
end

# ── the command ──────────────────────────────────────────────────────

def report_text(r)
  if r[:control] != 0
    unlines(
      [
        "control FAILED: the unmutated tests exit #{to_s(r[:control])}; no mutation was run"
      ]
    )
  else
    rows = join(
      map(
        (x) -> unlines(["#{to_s(x[:verdict])}  #{x[:name]}#{detail(x)}"]),
        r[:results]
      ),
      ""
    )
    concat(
      rows,
      unlines(
        [
          "#{to_s(r[:caught])} caught, #{to_s(r[:survived])} survived, #{to_s(r[:refused])} refused, #{to_s(r[:blind])} blind"
        ]
      )
    )
  end
end

def detail(x)
  if x[:detail].nil?
    ""
  else
    "  (#{x[:detail]})"
  end
end

@doc """
ok?: whether every mutation was caught.

    ok?({control: 0, survived: 0, refused: 0, blind: 0}) #=> true
"""
def ok?(r)
  r[:control] == 0 and r[:survived] == 0 and r[:refused] == 0 and r[:blind] == 0
end

@doc """
score: a run's caught ratio, the share of mutations its tests caught, as {caught, total}: every mutation run counts in total, only a caught one in caught.

    score({results: [{verdict: :caught}, {verdict: :survived}]}) #=> {caught: 1, total: 2}
"""
def score(r)
  {
    caught: count_where((x) -> x[:verdict] == :caught, r[:results]),
    total: length(r[:results])
  }
end

@doc """
fell?: whether a measured caught ratio is below a recorded one, compared without division; a package whose mutations all vanished fell too.

    fell?({caught: 3, total: 3}, {caught: 3, total: 4}) #=> true
"""
def fell?(recorded, measured)
  if measured[:total] == 0
    recorded[:total] > 0
  else
    measured[:caught] * recorded[:total] < recorded[:caught] * measured[:total]
  end
end

@doc """
survivors: the names of the mutations a run's tests survived.

    survivors({results: [{name: "a", verdict: :survived}, {name: "b", verdict: :caught}]}) #=> ["a"]
"""
def survivors(r)
  map((x) -> x[:name], filter((x) -> x[:verdict] == :survived, r[:results]))
end

@doc """
sound?: whether a run measured anything a ratio can stand on: the control passed and no mutation was refused or blind.

    sound?({control: 0, refused: 0, blind: 1}) #=> false
"""
def sound?(r)
  r[:control] == 0 and r[:refused] == 0 and r[:blind] == 0
end

@doc """
settings: heni's core model: which blue runs the tests and which test file to run, each unset by default.

    settei::defaults_of(settings) #=> {blue: nil, test: nil, finds: false}
"""
def settings()
  {
    blue: settei::knob(
      nil,
      {
        type: :text,
        value_name: "BIN",
        doc: "the blue that runs the tests; the one running heni when unset"
      }
    ),
    test: settei::knob(
      nil,
      {
        type: :text,
        value_name: "FILE",
        doc: "the test file to run, relative to the package"
      }
    ),
    finds: settei::knob(
      false,
      {
        set_by: [:flag],
        doc: "run no test; fail when a mutation no longer finds its text exactly once"
      }
    )
  }
end

@doc """
frame: heni's command line beside its settings: the package and its mutations file.

    frame[:name] #=> "heni"
"""
def frame()
  {
    name: "heni",
    about: "mutation testing for a blue package",
    positional: [
      {name: :package, about: "the package directory"},
      {name: :mutations_file, about: "the JSON list of mutations"}
    ]
  }
end

# waive B0084: integration debt recorded 2026-11-13: no test of this file declared kind: :integration reaches this seam yet
@doc """
cli: heni's command line as hikisuu reads it, rendered from its settings and its frame.

    get(hikisuu::parse(["p", "m.json"], cli), :mutations_file) #=> "m.json"
"""
def cli()
  settei::cli_spec(settings, frame)
end

@doc """
main: the command's entry point: argv, the config file and the HENI_ environment resolved through settei, which answers help, completion and --explain and refuses a bad line with exit 64.

    get(hikisuu::outcome(["/p"], cli), :status) #=> 64
"""
def main()
  settei::command("heni", settings, frame, mutate)
end

@doc """
mutate: one heni run from a parsed command line: every mutation run, the report on stdout, and an error when the run is not clean.

    procedure?(mutate) #=> true
"""
def mutate(a)
  if a[:finds]
    finds(a)
  else
    run_all(a)
  end
end

@doc """
finds: the `--finds` run: every stranded mutation on stdout, and an error when there is one.

    procedure?(finds) #=> true
"""
def finds(a)
  muts = mutations(json_parse(read_file(a[:mutations_file])))
  rows = stranded(a[:package], muts)
  write_stdout(stranded_text(package_name(a[:package]), rows))
  write_stdout(
    unlines(
      [
        "#{to_s(length(muts) - length(rows))} find their text, #{to_s(length(rows))} refused"
      ]
    )
  )
  if not is_empty(rows)
    raise(:heni_failed, "a mutation no longer finds its text exactly once")
  end
  rows
end

@doc """
run_all: the mutation run: every mutation tested, the report on stdout, and an error when the run is not clean.

    procedure?(run_all) #=> true
"""
def run_all(a)
  r = run(
    {
      package: a[:package],
      mutations: mutations(json_parse(read_file(a[:mutations_file]))),
      blue: a[:blue] or self_exe,
      test: a[:test],
      tmp: temp_dir("heni")
    }
  )
  write_stdout(report_text(r))
  if ok?(r) == false
    raise(
      :heni_failed,
      "a mutation survived or was refused, or the control failed"
    )
  end
  r
end

# ── tests ────────────────────────────────────────────────────────────

test "a mutation applies exactly once or is refused"
  assert hn_apply("a == 1", "== 1", "== 2")[:text] == "a == 2"
  assert hn_apply("x x", "x", "y")[:error] == "find occurs 2 times, not once"
  assert hn_apply("abc", "z", "y")[:error] == "find occurs 0 times, not once"
  assert hn_apply("abc", "", "y")[:error] == "an empty find matches everywhere"
end

test "the verdicts: refused, survived, caught"
  assert verdict({error: "no"}, nil) == :refused
  assert verdict({text: "t"}, 0) == :survived
  assert verdict({text: "t"}, 1) == :caught
  # The tests could not be started: blind, not caught.
  assert verdict({text: "t"}, nil) == :blind
  # Any blind mutation fails the run, as a survivor does.
  assert ok?({control: 0, survived: 0, refused: 0, blind: 1}) == false
  assert ok?({control: 0, survived: 0, refused: 0, blind: 0}) == true
end

test "arguments"
  a = hikisuu::parse(%w[/p/kazu m.json --blue /bin/blue], cli)
  assert a[:package] == "/p/kazu"
  assert a[:blue] == "/bin/blue"
  assert a[:test].nil?
  refused = fn(args)
    begin
      hikisuu::parse(args, cli)
      nil
    rescue e
      e.message
    end
  end
  assert refused(["/p"]) == "missing MUTATIONS_FILE"
  assert refused(%w[/p m --nope]) == "unknown flag --nope"
  assert package_name("/a/b/kazu/") == "kazu"
end

test "without a blue CLI, heni refuses rather than spawning its host"
  refused = run(
    {package: "/nonexistent", mutations: [], blue: nil, test: nil, tmp: "/tmp"}
  ) rescue
    :refused
  assert refused == :refused
end

# Under the blue CLI (`blue test`, the nix bidama gate) this runs for real.
# Embedded in another host (cargo's harness), self_exe() is nil and the test
# above covers the refusal instead: spawning the host would re-run it.
test "a run end to end: a caught mutation, a survivor, a refusal"
  if self_exe != nil
    end_to_end
  end
end

def end_to_end()
  tmp = path_join(temp_dir("heni-self"), "heni-self")
  pkg = path_join(tmp, "hnprobe")
  mkdir_p(pkg)
  write_file(
    path_join(pkg, "Bluefile"),
    unlines(["package(\"hnprobe\", \"0.1.0\")"])
  )
  write_program(
    path_join(pkg, "hnprobe.b"),
    unlines(
      [
        "@moduledoc \"\"\"",
        "hnprobe: the probe heni mutates, one checked word and one unchecked.",
        "",
        "    hp_double(3) #=> 6",
        "\"\"\"",
        "",
        "def hp_double(x)",
        "  x * 2",
        "end",
        "",
        "def hp_unused()",
        "  7",
        "end",
        "",
        "test \"double\"",
        "  assert hp_double(3) == 6",
        "end"
      ]
    )
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
      find: unlines(["  7"]),
      replace: unlines(["  8"])
    },
    {name: "not there", file: "hnprobe.b", find: "nowhere", replace: "x"}
  ]
  r = run({package: pkg, mutations: muts, blue: self_exe, test: nil, tmp:})
  assert r[:control] == 0
  assert map((x) -> x[:verdict], r[:results]) == %i[caught survived refused]
  assert ok?(r) == false
  assert contains?(
    report_text(r),
    "1 caught, 1 survived, 1 refused, 0 blind"
  ) == true
  # Control: a package whose own tests fail stops the run before any mutation.
  write_program(
    path_join(pkg, "hnprobe.b"),
    unlines(["test \"broken\"", "  assert 1 == 2", "end"])
  )
  bad = run({package: pkg, mutations: muts, blue: self_exe, test: nil, tmp:})
  assert bad[:control] != 0
  assert is_empty(bad[:results]) == true
  rm_rf(tmp)
  true
end

test "a caught ratio counts every mutation and falls only when it drops"
  r = {
    control: 0,
    refused: 0,
    blind: 0,
    results: [
      {name: "a", verdict: :caught},
      {name: "b", verdict: :survived},
      {name: "c", verdict: :caught}
    ]
  }
  assert score(r) == {caught: 2, total: 3}
  assert survivors(r) == ["b"]
  assert sound?(r) == true
  assert sound?(assoc(r, :refused, 1)) == false
  assert sound?(assoc(r, :control, 1)) == false
  assert fell?({caught: 3, total: 3}, {caught: 2, total: 3}) == true
  assert fell?({caught: 3, total: 3}, {caught: 3, total: 4}) == true
  assert fell?({caught: 3, total: 3}, {caught: 3, total: 3}) == false
  assert fell?({caught: 2, total: 3}, {caught: 3, total: 4}) == false
  assert fell?({caught: 3, total: 4}, {caught: 2, total: 3}) == true
  assert fell?({caught: 2, total: 2}, {caught: 0, total: 0}) == true
  assert fell?({caught: 0, total: 0}, {caught: 0, total: 0}) == false
end

test "a rewrite that strands a mutation is named with no test run"
  pkg = path_join(temp_dir("heni-finds"), "hnfinds")
  mkdir_p(pkg)
  write_file(
    path_join(pkg, "f.txt"),
    unlines(["  if not r[:ok]", "    :unread"])
  )
  muts = [
    {name: "held", file: "f.txt", find: "    :unread", replace: "    :up"},
    {name: "rewritten", file: "f.txt", find: "ok?(r)", replace: "true"},
    {name: "no file", file: "gone.b", find: "x", replace: "y"}
  ]
  assert map((r) -> r[:name], stranded(pkg, muts)) == ["rewritten", "no file"]
  write_file(
    path_join(pkg, "f.txt"),
    unlines(["  if not ok?(r)", "    :unread"])
  )
  assert map((r) -> r[:name], stranded(pkg, muts)) == ["no file"]
  spec = path_join(pkg, "m.json")
  write_file(
    spec,
    json_stringify(
      [{name: "held", file: "f.txt", find: "    :unread", replace: "    :up"}]
    )
  )
  assert mutate({package: pkg, mutations_file: spec, finds: true}) == []
  write_file(spec, json_stringify(muts))
  refused = begin
    mutate({package: pkg, mutations_file: spec, finds: true})
  rescue e
    e.message
  end
  assert refused == "a mutation no longer finds its text exactly once"
  ran = begin
    run_all(
      {
        package: path_join(pkg, "none"),
        mutations_file: spec,
        blue: nil,
        test: nil,
        finds: false
      }
    )
    :clean
  rescue e
    e.kind
  end
  assert member?(ran, %i[heni_no_blue heni_failed])
  assert hikisuu::parse(%w[/p m.json --finds], cli)[:finds] == true
  assert hikisuu::parse(%w[/p m.json], cli)[:finds] == false
  rm_rf(pkg)
end

test "status is nil without a capture and the capture's status with one"
  assert status(nil).nil?
  assert status([]) == 0
end
