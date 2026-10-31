use("gamen", %i[duration_text show_step])
use("moji", %i[glob_match? take_chars])

use("retsu", %i[all_but_last enumerate first flat_map last reject rest])

use("shisutemu", %i[status_of stderr_of stdout_of])

@doc """
gate_table: Every gate the pre-push hook knows, as data. A gate has an id, a
label, a weight and the paths it reads, as globs. A light gate runs on every
push whose paths it reads; a heavy gate runs with BLUE_PREPUSH_FULL=1, and
otherwise CI runs it when the push lands. The none weight names paths that no
gate reads.

    map((g) -> get(g, :id), filter((g) -> get(g, :weight) == :light, gate_table)) #=> ["cargo-fmt", "blue-fmt", "locks", "retired", "gen-confirm", "swept-codes"]
"""
def gate_table()
  [
    {
      id: "cargo-fmt",
      label: "cargo fmt",
      weight: :light,
      inputs: %w[**/*.rs **/rustfmt.toml **/Cargo.toml]
    },
    {id: "blue-fmt", label: "blue fmt", weight: :light, inputs: ["**/*.b"]},
    {
      id: "locks",
      label: "Bluefile.lock fresh",
      weight: :light,
      inputs: %w[**/Bluefile **/Bluefile.lock **/*.b]
    },
    {
      id: "retired",
      label: "a retired word ships its fixer",
      weight: :light,
      inputs: %w[bidamas/**/*.b gen/retired.b]
    },
    {
      id: "gen-confirm",
      label: "Cargo.gen.lock fresh (gen confirm)",
      weight: :light,
      inputs: %w[Cargo.lock Cargo.gen.lock **/Cargo.toml]
    },
    {
      id: "swept-codes",
      label: "every rule code is swept across the consumers",
      weight: :light,
      inputs: %w[crates/** gen/consumers.b gen/consumers.json]
    },
    {
      id: "regen",
      label: "regen",
      weight: :heavy,
      inputs: %w[
        **/*.b
        **/Bluefile
        **/Bluefile.lock
        crates/**
        docs/**
        examples/**
        spec/**
      ]
    },
    {
      id: "gen-pin",
      label: "gen is substrate's pin",
      weight: :heavy,
      inputs: ["flake.lock"]
    },
    {
      id: "consumers",
      label: "every consumer in gen/consumers.json stays green at this blue",
      weight: :heavy,
      inputs: %w[
        crates/**
        bidamas/**
        spec/**
        gen/consumers.b
        gen/consumers.json
      ]
    },
    {
      id: "gen-tie",
      label: "Cargo.gen.lock tied",
      weight: :heavy,
      inputs: %w[Cargo.lock Cargo.gen.lock **/Cargo.toml]
    },
    {
      id: "test-beside",
      label: "tests beside every bidama definition",
      weight: :heavy,
      inputs: %w[bidamas/** gen/test-beside.b]
    },
    {
      id: "test-targets",
      label: "every member's test targets compile alone",
      weight: :heavy,
      inputs: %w[crates/** **/Cargo.toml]
    },
    {
      id: "tests",
      label: "registry_graph, check_corpus, distribution, verb_graph",
      weight: :heavy,
      inputs: %w[
        crates/**
        bidamas/**
        spec/**
        gen/**
        docs/verbs/**
        examples/**
        **/Cargo.toml
      ]
    },
    {
      id: "conformance",
      label: "conformance, strict as CI runs it",
      weight: :heavy,
      inputs: %w[spec/** crates/** bidamas/**]
    },
    {
      id: "prose",
      label: "prose",
      weight: :none,
      inputs: %w[**/*.md LICENSE **/.gitignore]
    }
  ]
end

@doc """
every_gate_paths: The paths that select every gate when a push changes one:
the locks every build reads, the toolchain, and the gate itself.

    member?("Cargo.lock", every_gate_paths) #=> true
"""
def every_gate_paths()
  %w[
    Cargo.lock
    flake.lock
    flake.nix
    rust-toolchain*
    nix/**
    .githooks/**
    gen/prepush.b
  ]
end

@doc """
reads?: Whether a gate's globs match a path.

    reads?({inputs: ["**/*.b"]}, "gen/regen.b") #=> true
    reads?({inputs: ["**/*.b"]}, "Cargo.toml") #=> false
"""
def reads?(gate, path)
  any?((p) -> glob_match?(p, path), gate[:inputs])
end

@doc """
selection: Which gates a set of changed paths selects, and why. A path that
selects every gate, or a path no gate names, selects every gate: an unknown
path fails closed. The answer holds the gate ids in table order, and a reason
that is empty when the paths chose the gates one by one.

    get(selection(["bidamas/retsu/retsu.b"], gate_table), :ids) #=> ["blue-fmt", "locks", "retired", "regen", "consumers", "test-beside", "tests", "conformance"]
    get(selection(["README.md"], gate_table), :ids) #=> []
"""
def selection(changed, table)
  ids = map((g) -> g[:id], filter((g) -> g[:weight] != :none, table))
  every = filter(
    (p) -> any?((g) -> glob_match?(g, p), every_gate_paths),
    changed
  )
  unknown = reject((p) -> any?((g) -> reads?(g, p), table), changed)
  if every != []
    {ids:, reason: "#{first(every)} selects every gate"}
  elsif unknown != []
    {ids:, reason: "no gate names #{first(unknown)}, so every gate runs"}
  else
    {
      ids: filter(
        fn(id)
          g = first(filter((t) -> t[:id] == id, table))
          any?((p) -> reads?(g, p), changed)
        end,
        ids
      ),
      reason: ""
    }
  end
end

@doc """
weight_of: A gate id's weight in the table.

    weight_of("cargo-fmt", gate_table) #=> :light
"""
def weight_of(id, table)
  first(filter((g) -> g[:id] == id, table))[:weight]
end

@doc """
planned: The gate ids this run judges: every gate with BLUE_PREPUSH_FULL=1,
else the light gates the selection holds.

    planned(["blue-fmt", "regen"], false, gate_table) #=> ["blue-fmt"]
    count(planned([], true, gate_table)) #=> 14
"""
def planned(ids, full, table)
  if full
    map((g) -> g[:id], filter((g) -> g[:weight] != :none, table))
  else
    filter((id) -> weight_of(id, table) == :light, ids)
  end
end

@doc """
skipped: The gate ids BLUE_PREPUSH_SKIP turns off, as a comma-separated list
of gate ids; each gate's own off switch. Unset or empty skips none. An id the
table does not hold is refused with the ids it does, so a misspelt id never
silently runs the gate it meant to skip.

    skipped(nil, gate_table) #=> []
    skipped("gen-confirm, swept-codes", gate_table) #=> ["gen-confirm", "swept-codes"]
    skipped("gen-confrim", gate_table) #=> {refused: "gen-confrim"}
"""
def skipped(v, table)
  ids = map((g) -> g[:id], filter((g) -> g[:weight] != :none, table))
  named = reject((w) -> w == "", map(trim, split(v or "", ",")))
  unknown = reject((w) -> member?(w, ids), named)
  if unknown != []
    {refused: join(unknown, ", ")}
  else
    distinct(named)
  end
end

@doc """
zero_sha?: Whether a ref update names no commit, as git writes a new or a
deleted ref.

    zero_sha?("0000000000000000000000000000000000000000") #=> true
    zero_sha?("8bd5119") #=> false
"""
def zero_sha?(sha)
  sha != "" and replace(sha, "0", "") == ""
end

@doc """
updates_of: The ref updates git writes to a pre-push hook's stdin, one per
line as local ref, local sha, remote ref and remote sha; a deleted ref is no
update to check.

    updates_of("refs/heads/a 1111 refs/heads/a 0000") #=> [{local: "1111", remote: "0000"}]
    updates_of("(delete) 0000 refs/heads/a 1111") #=> []
"""
def updates_of(text)
  rows = filter((w) -> count(w) == 4, map((l) -> split(l, " "), lines_of(text)))
  map((w) -> {local: w[1], remote: w[3]}, reject((w) -> zero_sha?(w[1]), rows))
end

@doc """
green_key: The base a green record names: a star when the run judged the
whole tree, else the base trees the changed paths were read against.

    green_key(true, ["b", "a"]) #=> "*"
    green_key(false, ["b", "a", "b"]) #=> "a,b"
"""
def green_key(whole, bases)
  if whole
    "*"
  else
    join(sort_keyed((b) -> b, distinct(bases)), ",")
  end
end

@doc """
green_hit: The record that lets this push skip, or nil. A record is a line
`mode key time seconds`; a full record covers every push of its tree, and a
light record covers a light push with the same key. A dirty tree never
skips, because the gates read the working tree and not the pushed commit.

    green_hit(["light a,b 2026-10-24T12:00:00Z 4.1"], false, "a,b", false) #=> ["light", "a,b", "2026-10-24T12:00:00Z", "4.1"]
    green_hit(["light a,b 2026-10-24T12:00:00Z 4.1"], false, "a,b", true) #=> nil
    green_hit(["light a,b 2026-10-24T12:00:00Z 4.1"], true, "*", false) #=> nil
"""
def green_hit(records, full, key, dirty)
  if dirty
    nil
  else
    hits = filter(
      fn(r)
        if count(r) != 4
          false
        elsif first(r) == "full"
          true
        else
          not full and (r[1] == key or r[1] == "*")
        end
      end,
      map((l) -> split(l, " "), records)
    )
    if hits == []
      nil
    else
      last(hits)
    end
  end
end

@doc """
lock_dir_of: The directory of the nearest Bluefile.lock above a path.

    lock_dir_of(["." , "bidamas/retsu"], "bidamas/retsu/retsu.b") #=> "bidamas/retsu"
    lock_dir_of([".", "bidamas/retsu"], "gen/regen.b") #=> "."
"""
def lock_dir_of(dirs, path)
  owners = filter((d) -> d != "." and starts_with?(path, "#{d}/"), dirs)
  reduce(
    fn(best, d)
      if count(split(d, "/")) > count(split(best, "/"))
        d
      else
        best
      end
    end,
    ".",
    owners
  )
end

@doc """
expected: The seconds the last runs took for these labels, from timing lines
`ms label`; nil when a label has no timing yet.

    expected(["1000 cargo fmt", "500 blue fmt", "1200 cargo fmt"], ["cargo fmt", "blue fmt"]) #=> 1.7
    expected([], ["cargo fmt"]) #=> nil
"""
def expected(lines, labels)
  rows = map(
    fn(l)
      w = split(l, " ")
      [join(rest(w), " "), first(w)]
    end,
    lines
  )
  ms = map(
    fn(label)
      seen = filter((r) -> first(r) == label, rows)
      if seen == []
        nil
      else
        to_int(last(last(seen)))
      end
    end,
    labels
  )
  if member?(nil, ms)
    nil
  else
    round(reduce((a, b) -> a + b, 0, ms) / 100) / 10
  end
end

def off?()
  v = getenv("BLUE_PREPUSH_OFF")
  if v.nil?
    false
  elsif v == "1"
    true
  else
    write_stderr(
      unlines(
        ["prepush: BLUE_PREPUSH_OFF is \"#{v}\"; the one value it takes is 1"]
      )
    )
    exit_with(2)
  end
end

@doc """
full?: Whether BLUE_PREPUSH_FULL asks for every gate; it takes 1 or nothing.

    full?(nil) #=> false
    full?("1") #=> true
"""
def full?(v)
  if v.nil? or v == ""
    false
  elsif v == "1"
    true
  else
    write_stderr(
      unlines(
        ["prepush: BLUE_PREPUSH_FULL is \"#{v}\"; the one value it takes is 1"]
      )
    )
    exit_with(2)
  end
end

def lines_of(text)
  reject((l) -> l == "", split(text, line_break))
end

def git(args)
  stdout_of(exec_capture("git", *args))
end

def dir_of(path)
  parts = split(path, "/")
  if count(parts) == 1
    "."
  else
    join(all_but_last(parts), "/")
  end
end

def verdict(cap)
  if status_of(cap) == 0
    [:green, ""]
  else
    [:red, "#{stdout_of(cap)}#{stderr_of(cap)}"]
  end
end

def manifest(dir)
  json_read(read_file("#{dir}/Bluefile.lock"))["manifest"]
end

def regenerates?(dir)
  m = manifest(dir)
  any?(
    (k) -> get(m, k) != nil,
    %w[catalog generated workloads registries services]
  )
end

def absent_tools(dir)
  reject((t) -> exec_ok?("which", t), manifest(dir)["tools"] or [])
end

def members()
  meta = exec_capture("cargo", "metadata", "--no-deps", "--format-version", "1")
  map((p) -> p["name"], json_read(stdout_of(meta))["packages"])
end

def test_targets()
  red = reject(
    (r) -> status_of(last(r)) == 0,
    map(
      (m) -> [m, exec_capture("cargo", "test", "-q", "-p", m, "--no-run")],
      members
    )
  )
  if red == []
    [:green, ""]
  else
    [
      :red,
      join(
        map((r) -> join_lines(["#{first(r)}:", stderr_of(last(r))]), red),
        line_break
      )
    ]
  end
end

def changed()
  "#{git(%w[status --porcelain --untracked-files=all])}#{git(["diff"])}"
end

def regen(bin, root, dir)
  was = lines_of(git(%w[status --porcelain --untracked-files=all]))
  before = changed
  run = exec_with_env(
    [["PATH", "#{bin}:#{getenv("PATH")}"]],
    "env",
    "-C",
    dir,
    "blue",
    "run",
    "#{root}/gen/regen.b"
  )
  now = lines_of(git(%w[status --porcelain --untracked-files=all]))
  if status_of(run) != 0
    missing = absent_tools(dir)
    if missing == []
      [:red, stderr_of(run)]
    else
      [:blind, unlines(["needs #{join(missing, ", ")}, which is not on PATH"])]
    end
  elsif before == changed
    [:green, ""]
  else
    [
      :red,
      unlines(
        [
          "regen rewrote stale generated files; commit them:",
          join(reject((l) -> member?(l, was), now), line_break)
        ]
      )
    ]
  end
end

def gen_pin()
  pin = exec_capture(
    "nix",
    "eval",
    "--raw",
    "github:pleme-io/substrate#genPin.version"
  )
  if not exec_ok?("which", "gen")
    [:blind, unlines(["gen is not on PATH"])]
  elsif status_of(pin) != 0
    [
      :blind,
      join_lines(["could not read substrate's gen pin:", stderr_of(pin)])
    ]
  else
    installed = trim(stdout_of(exec_capture("gen", "--version")))
    if installed == "gen #{stdout_of(pin)}"
      [:green, ""]
    else
      [
        :red,
        unlines(
          [
            "#{installed} is installed; substrate pins gen #{stdout_of(pin)}. Run:",
            "  nix flake update substrate --flake ~/code/github/pleme-io/nix",
            "  nix run ~/code/github/pleme-io/nix#rebuild"
          ]
        )
      ]
    end
  end
end

def gen_confirm()
  if not exec_ok?("which", "gen")
    [:blind, unlines(["gen is not on PATH"])]
  else
    confirmed = exec_capture("gen", "confirm")
    if status_of(confirmed) == 0
      [:green, ""]
    else
      [
        :red,
        unlines(
          [
            trim("#{stdout_of(confirmed)}#{stderr_of(confirmed)}"),
            "Cargo.gen.lock is not tied to Cargo.lock and the manifests. Run gen build . and commit Cargo.gen.lock"
          ]
        )
      ]
    end
  end
end

def gen_tie()
  confirmed = gen_confirm
  if first(confirmed) != :red
    confirmed
  else
    was = lines_of(git(%w[status --porcelain --untracked-files=all]))
    built = exec_capture("gen", "build", ".")
    now = lines_of(git(%w[status --porcelain --untracked-files=all]))
    if status_of(built) != 0
      [:red, stderr_of(built)]
    else
      [
        :red,
        unlines(
          [
            "Cargo.gen.lock was not tied to Cargo.lock and the manifests; gen build rewrote it. Commit:",
            join(reject((l) -> member?(l, was), now), line_break)
          ]
        )
      ]
    end
  end
end

def main()
  hook = getenv("BLUE_PREPUSH_GLOBAL_HOOK", "")
  fed = if getenv("BLUE_PREPUSH_HOOK") == "1"
    read_file("/dev/stdin")
  else
    ""
  end
  if hook != "" and path_exists(hook)
    g = exec_with_stdin(fed, hook, *argv)
    write_stderr("#{stdout_of(g)}#{stderr_of(g)}")
    if status_of(g) != 0
      exit_with(status_of(g))
    end
  end
  if off?
    write_stderr(
      unlines(["prepush: off (BLUE_PREPUSH_OFF=1); nothing checked"])
    )
    exit_with(0)
  end
  full = full?(getenv("BLUE_PREPUSH_FULL"))
  skip = skipped(getenv("BLUE_PREPUSH_SKIP"), gate_table)
  if map?(skip)
    write_stderr(
      unlines(
        [
          "prepush: BLUE_PREPUSH_SKIP names #{skip[:refused]}, which is no gate; it takes gate ids from: #{join(map((g) -> g[:id], reject((g) -> g[:weight] == :none, gate_table)), ", ")}"
        ]
      )
    )
    exit_with(2)
  end
  started = now_ms
  common = trim(git(%w[rev-parse --path-format=absolute --git-common-dir]))
  store = "#{common}/prepush"
  remote = if count(argv) > 0
    first(argv)
  else
    "origin"
  end
  trunk = "refs/remotes/#{remote}/main"
  base_of = fn(sha, other)
    known = not zero_sha?(other) and
      exec_ok?("git", "cat-file", "-e", "#{other}^{commit}")
    against = if known
      other
    else
      trunk
    end
    m = exec_capture("git", "merge-base", sha, against)
    if status_of(m) == 0
      trim(stdout_of(m))
    end
  end
  updates = if fed == ""
    [{local: trim(git(%w[rev-parse HEAD])), remote: ""}]
  else
    updates_of(fed)
  end
  if updates == []
    write_stderr(
      unlines(["prepush: the push only deletes refs; nothing to check"])
    )
    exit_with(0)
  end
  pairs = map((u) -> [u[:local], base_of(u[:local], u[:remote])], updates)
  blind = any?((p) -> last(p).nil?, pairs)
  paths = distinct(
    flat_map(
      reject((p) -> last(p).nil?, pairs),
      (p) -> lines_of(git(["diff", "--name-only", last(p), first(p)]))
    )
  )
  table = gate_table
  chosen = if blind
    {
      ids: map((g) -> g[:id], filter((g) -> g[:weight] != :none, table)),
      reason: "no base on #{trunk} for a pushed commit, so every gate runs"
    }
  else
    selection(paths, table)
  end
  whole = full or chosen[:reason] != ""
  dirty = lines_of(git(%w[status --porcelain --untracked-files=no]))
  head_tree = trim(git(%w[rev-parse HEAD^{tree}]))
  trees = distinct(
    map((p) -> trim(git(["rev-parse", "#{first(p)}^{tree}"])), pairs)
  )
  one_tree = trees == [head_tree]
  key = green_key(
    whole,
    map((p) -> trim(git(["rev-parse", "#{last(p)}^{tree}"])), pairs)
  )
  mode = if full
    "full"
  else
    "light"
  end
  record = "#{store}/green/#{head_tree}"
  kept = if path_exists(record)
    lines_of(read_file(record))
  else
    []
  end
  hit = green_hit(kept, full, key, dirty != [] or not one_tree)
  if not hit.nil?
    write_stderr(
      unlines(
        [
          "🟢 prepush: tree #{take_chars(head_tree, 10)} passed the #{first(hit)} gate at #{hit[2]} (#{last(hit)}s); nothing to run"
        ]
      )
    )
    exit_with(0)
  end
  if dirty != []
    write_stderr(
      unlines(
        [
          "⚠️ prepush reads the working tree, and #{to_s(count(dirty))} tracked files differ from HEAD; a green run is not recorded"
        ]
      )
    )
  elsif not one_tree
    write_stderr(
      unlines(
        ["⚠️ prepush reads the working tree, and the push names a commit other than HEAD; a green run is not recorded"]
      )
    )
  end
  root = trim(git(%w[rev-parse --show-toplevel]))
  bin = dir_of(self_exe)
  dirs = map(dir_of, lines_of(git(%w[ls-files *Bluefile.lock])))
  scoped_b = filter((p) -> ends_with?(p, ".b") and path_exists(p), paths)
  scoped_dirs = distinct(
    map(
      (p) -> lock_dir_of(dirs, p),
      filter(
        (p) -> reads?(first(filter((g) -> g[:id] == "locks", table)), p),
        paths
      )
    )
  )
  bfiles = if whole
    lines_of(git(%w[ls-files *.b]))
  else
    scoped_b
  end
  ldirs = if whole
    dirs
  else
    scoped_dirs
  end
  runners = {
    "cargo-fmt" => [
      [
        "cargo fmt",
        () -> verdict(exec_capture("cargo", "fmt", "--all", "--", "--check"))
      ]
    ],
    "blue-fmt" => [
      [
        "blue fmt",
        fn()
          if bfiles == []
            [:green, ""]
          else
            verdict(exec_capture("#{bin}/blue", "fmt", "--check", *bfiles))
          end
        end
      ]
    ],
    "locks" => [
      [
        "Bluefile.lock fresh",
        fn()
          if ldirs == []
            [:green, ""]
          else
            verdict(
              exec_capture(
                "#{bin}/blue",
                "bluefile",
                "--confirm",
                *map((d) -> "#{d}/Bluefile", ldirs)
              )
            )
          end
        end
      ]
    ],
    "retired" => [
      [
        "a retired word ships its fixer",
        fn()
          tested = exec_capture("#{bin}/blue", "test", "#{root}/gen/retired.b")
          if status_of(tested) != 0
            verdict(tested)
          else
            verdict(
              exec_capture(
                "#{bin}/blue",
                "#{root}/gen/retired.b",
                trim(git(["merge-base", trunk, "HEAD"])),
                "HEAD"
              )
            )
          end
        end
      ]
    ],
    "regen" => map(
      (d) -> ["regen #{d}", () -> regen(bin, root, d)],
      filter(regenerates?, dirs)
    ),
    "gen-confirm" => [
      ["Cargo.gen.lock fresh (gen confirm)", () -> gen_confirm]
    ],
    "swept-codes" => [
      [
        "every rule code is swept across the consumers",
        fn()
          verdict(
            exec_capture("#{bin}/blue", "#{root}/gen/consumers.b", "swept")
          )
        end
      ]
    ],
    "gen-pin" => [["gen is substrate's pin", () -> gen_pin]],
    "consumers" => [
      [
        "every consumer in gen/consumers.json stays green at this blue",
        fn()
          verdict(
            exec_capture("#{bin}/blue", "#{root}/gen/consumers.b", "sweep")
          )
        end
      ]
    ],
    "gen-tie" => [["Cargo.gen.lock tied", () -> gen_tie]],
    "test-beside" => [
      [
        "tests beside every bidama definition",
        fn()
          verdict(
            exec_capture("#{bin}/blue", "test", "#{root}/gen/test-beside.b")
          )
        end
      ]
    ],
    "test-targets" => [
      ["every member's test targets compile alone", () -> test_targets]
    ],
    "tests" => [
      [
        "registry_graph, check_corpus, distribution, verb_graph",
        fn()
          verdict(
            exec_capture(
              "cargo",
              "test",
              "-q",
              "--no-fail-fast",
              "-p",
              "blue-lang-cli",
              "-p",
              "blue-lang-pkg",
              "--test",
              "registry_graph",
              "--test",
              "check_corpus",
              "--test",
              "distribution",
              "--test",
              "verb_graph"
            )
          )
        end
      ]
    ],
    "conformance" => [
      [
        "conformance, strict as CI runs it",
        fn()
          verdict(
            exec_with_env(
              [["BLUE_BIN", "#{bin}/blue"], %w[BLUE_CONFORMANCE_STRICT 1]],
              "cargo",
              "test",
              "-q",
              "-p",
              "blue-lang-test",
              "--test",
              "conformance"
            )
          )
        end
      ]
    ]
  }
  ids = reject((id) -> member?(id, skip), planned(chosen[:ids], full, table))
  gates = flat_map(ids, (id) -> get(runners, id))
  ci = reject((id) -> member?(id, ids) or member?(id, skip), chosen[:ids])
  timings_file = "#{store}/timings"
  timings = if path_exists(timings_file)
    lines_of(read_file(timings_file))
  else
    []
  end
  guess = expected(timings, map(first, gates))
  why = if full
    "BLUE_PREPUSH_FULL=1 runs every gate"
  elsif chosen[:reason] != ""
    chosen[:reason]
  elsif paths == []
    "the push changes no path"
  else
    "#{to_s(count(paths))} changed paths since #{take_chars(last(first(pairs)), 10)}"
  end
  scope = if whole
    ""
  else
    " (#{to_s(count(bfiles))} .b, #{to_s(count(ldirs))} lock dirs)"
  end
  ran = if gates == []
    "no gate"
  else
    "#{join(map(first, gates), ", ")}#{scope}"
  end
  later = if ci == []
    ""
  else
    "; CI runs #{join(ci, ", ")} when it lands (git land)"
  end
  off = if skip == []
    ""
  else
    "; ➖ BLUE_PREPUSH_SKIP turns off #{join(skip, ", ")}"
  end
  took = if guess.nil?
    "no timing yet"
  else
    "about #{to_s(guess)}s by the last runs"
  end
  write_stderr(
    unlines(
      [
        "prepush (#{mode}): #{why}: #{ran}#{later}#{off}; #{took}. BLUE_PREPUSH_FULL=1 runs every gate, BLUE_PREPUSH_OFF=1 none, BLUE_PREPUSH_SKIP=ID,… the gates named"
      ]
    )
  )
  mkdir_p(store)
  total = count(gates)
  results = map(
    fn(p)
      i = first(p)
      g = last(p)
      show_step({state: :running, at: i + 1, of: total, name: first(g)}, {})
      t = now_ms
      f = last(g)
      r = f()
      spent = now_ms - t
      append_file(timings_file, unlines(["#{to_s(spent)} #{first(g)}"]))
      show_step(
        {
          state: get({green: :done, red: :failed, blind: :skipped}, first(r)),
          at: i + 1,
          of: total,
          name: first(g),
          ms: spent
        },
        {}
      )
      if first(r) != :green
        write_stderr(last(r))
      end
      [first(g), first(r)]
    end,
    enumerate(gates)
  )
  red = map(first, filter((r) -> last(r) == :red, results))
  if red == []
    if dirty == [] and one_tree and skip == []
      mkdir_p("#{store}/green")
      append_file(
        record,
        unlines(
          [
            "#{mode} #{key} #{now_rfc3339} #{to_s(round((now_ms - started) / 100) / 10)}"
          ]
        )
      )
    end
    write_stderr(
      unlines(["🟢 prepush: no gate red (#{duration_text(now_ms - started)})"])
    )
  else
    write_stderr(
      unlines(
        [
          "🔴 prepush: #{to_s(count(red))} red: #{join(red, "; ")}. Fix it, or skip once with BLUE_PREPUSH_SKIP=ID git push (one gate) or BLUE_PREPUSH_OFF=1 git push (every gate)"
        ]
      )
    )
    exit_with(1)
  end
end

test "a .b-only change selects the .b gates and no Rust gate"
  s = selection(%w[bidamas/shuugou/shuugou.b gen/regen.b], gate_table)
  assert s[:reason] == ""
  assert planned(s[:ids], false, gate_table) == %w[blue-fmt locks retired]
  assert not member?("test-targets", s[:ids])
end

test "a Cargo.lock change selects every gate"
  s = selection(["Cargo.lock"], gate_table)
  assert s[:reason] == "Cargo.lock selects every gate"
  assert planned(s[:ids], false, gate_table) ==
    %w[cargo-fmt blue-fmt locks retired gen-confirm swept-codes]
  assert count(s[:ids]) == 14
end

test "an unknown path selects every gate"
  s = selection(%w[bidamas/retsu/retsu.b tools/new.toml], gate_table)
  assert s[:reason] == "no gate names tools/new.toml, so every gate runs"
  assert count(s[:ids]) == 14
end

test "a Rust change selects cargo fmt, the swept codes and the heavy gates"
  s = selection(["crates/blue-lang-fmt/src/lib.rs"], gate_table)
  assert planned(s[:ids], false, gate_table) == %w[cargo-fmt swept-codes]
  assert member?("tests", s[:ids])
end

test "a manifest change runs gen confirm before the push, not only in CI"
  s = selection(["crates/blue-lang-lsp/Cargo.toml"], gate_table)
  assert s[:reason] == ""
  assert planned(s[:ids], false, gate_table) ==
    %w[cargo-fmt gen-confirm swept-codes]
  assert member?("gen-tie", s[:ids])
end

test "a new rule code is judged before the push, by the swept record alone"
  s = selection(["crates/blue-lang-check/src/lib.rs"], gate_table)
  assert member?("swept-codes", planned(s[:ids], false, gate_table))
  c = selection(["gen/consumers.json"], gate_table)
  assert planned(c[:ids], false, gate_table) == ["swept-codes"]
end

test "BLUE_PREPUSH_SKIP turns off the gates it names and refuses an id that is no gate"
  assert skipped(nil, gate_table) == []
  assert skipped("", gate_table) == []
  assert skipped("gen-confirm", gate_table) == ["gen-confirm"]
  assert skipped(" swept-codes ,gen-confirm,swept-codes", gate_table) ==
    %w[swept-codes gen-confirm]
  assert skipped("gen-confirm,nope", gate_table) == {refused: "nope"}
  assert skipped("prose", gate_table) == {refused: "prose"}
end

test "a recorded green tree skips a push with the same base"
  rs = ["light t1 2026-10-24T12:00:00Z 3.2"]
  assert green_hit(rs, false, "t1", false) ==
    %w[light t1 2026-10-24T12:00:00Z 3.2]
  assert green_hit(rs, false, "t2", false).nil?
  assert green_hit(["full * 2026-10-24T12:00:00Z 400.0"], false, "t2", false) !=
    nil
end

test "a dirty tree never skips"
  assert green_hit(["full * 2026-10-24T12:00:00Z 400.0"], true, "*", true).nil?
  assert green_hit(
    ["light t1 2026-10-24T12:00:00Z 3.2"],
    false,
    "t1",
    true
  ).nil?
end
