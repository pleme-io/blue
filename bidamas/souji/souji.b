@moduledoc """
souji (掃除) — cleaning a node: Rust target/ directories nobody is building in, and nix store paths nothing refers to, with a dry run first.

The two things that fill a developer node's disk (measured 2026-09-27: 29 GB
of target/ directories, and a nix store every one of whose paths was still
referenced). Both cleanings reclaim only what can be rebuilt or re-fetched.

  souji rust [--dry-run] [--min-age-hours N] [ROOT...]   default ROOT ~/code
  souji nix  [--dry-run] [--older-than-days N]           default 14
  souji all  [--dry-run]                                 both, rust first

A target/ directory counts only beside a Cargo.toml, and only when nothing
inside it changed in the last N hours (default 6): a build writing there,
or a binary running from it, is never pulled out from under. The nix
cleaning deletes this user's profile generations older than N days and then
every store path left unreferenced; run it as root to include the system's.

Every tool it runs is at a process boundary (find, du, nix-collect-garbage);
the logic is blue.

    nix_argv({days: 14, dry_run: false}) #=> ["nix-collect-garbage", "--delete-older-than", "14d"]
"""

use(
  "retsu",
  [
    :concat_lists,
    :contains,
    :drop_n,
    :first,
    :flat_map,
    :is_empty,
    :push,
    :rest,
    :size
  ]
)

use("shisutemu", [:last_nonempty_line, :status_of, :stderr_of, :stdout_of])

legacy_names("0.1.1", "sj")

# ── arguments ────────────────────────────────────────────────────────

@doc """
parse: {command, dry_run, hours, days, roots} from argv, or {error: why}.
"""
def parse(args)
  if is_empty(args)
    {error: "a command: rust, nix or all"}
  else
    cmd = first(args)
    if contains(["rust", "nix", "all"], cmd) == false
      {error: "unknown command #{cmd}: rust, nix or all"}
    else
      parse_flags(
        rest(args),
        {
          command: cmd,
          dry_run: false,
          hours: 6,
          days: 14,
          roots: [],
          error: nil
        }
      )
    end
  end
end

def parse_flags(args, acc)
  if is_empty(args) or acc[:error] != nil
    acc
  else
    a = first(args)
    if a == "--dry-run"
      parse_flags(rest(args), assoc(acc, :dry_run, true))
    elsif a == "--min-age-hours" or a == "--older-than-days"
      v = if size(args) > 1
        to_int(args[1])
      end
      if v.nil? or v < 0
        assoc(acc, :error, "#{a} needs a whole number of 0 or more")
      else
        key = if a == "--min-age-hours"
          :hours
        else
          :days
        end
        parse_flags(drop_n(args, 2), assoc(acc, key, v))
      end
    elsif starts_with?(a, "--")
      assoc(acc, :error, "unknown flag #{a}")
    else
      parse_flags(rest(args), assoc(acc, :roots, push(acc[:roots], a)))
    end
  end
end

def roots(opts)
  if is_empty(opts[:roots])
    [path_join(getenv("HOME", "/"), "code")]
  else
    opts[:roots]
  end
end

# ── rust ─────────────────────────────────────────────────────────────

@doc """
targets: target/ directories under root, at most depth levels down, each beside a
Cargo.toml. find prunes at each target/ so it never walks inside one.
"""
def targets(root, depth)
  cap = exec_capture(
    "find",
    root,
    "-maxdepth",
    to_s(depth),
    "-type",
    "d",
    "-name",
    "target",
    "-prune"
  )
  filter(
    (d) -> path_exists(path_join(path_dirname(d), "Cargo.toml")),
    filter(
      (l) -> is_empty(blue::trim(l)) == false,
      split(stdout_of(cap), line_break)
    )
  )
end

@doc """
size_kib: Kibibytes under dir, from du; 0 when du could not read it.
"""
def size_kib(dir)
  cap = exec_capture("du", "-sk", dir)
  n = to_int(first(split(blue::trim(stdout_of(cap)), "\t")))
  if n.nil?
    0
  else
    n
  end
end

@doc """
active?: True when anything inside dir changed in the last `hours` hours: find stops
at the first such file.
"""
def active?(dir, hours)
  if hours == 0
    false
  else
    cap = exec_capture(
      "find",
      dir,
      "-mmin",
      "-#{to_s(hours * 60)}",
      "-print",
      "-quit"
    )
    is_empty(blue::trim(stdout_of(cap))) == false
  end
end

@doc """
rust_survey: One row per target/: {path, kib, active}.
"""
def rust_survey(roots, hours)
  map(
    (d) -> {path: d, kib: size_kib(d), active: active?(d, hours)},
    flat_map(roots, (r) -> targets(r, 4))
  )
end

def rust(opts)
  rows = rust_survey(roots(opts), opts[:hours])
  gone = filter((r) -> r[:active] == false, rows)
  if opts[:dry_run] == false
    map((r) -> rm_rf(r[:path]), gone)
  end
  {rows:, removed: gone, kib: sum(map((r) -> r[:kib], gone))}
end

def sum(xs)
  reduce((a, x) -> a + x, 0, xs)
end

# ── nix ──────────────────────────────────────────────────────────────

def nix_argv(opts)
  concat_lists(
    ["nix-collect-garbage", "--delete-older-than", "#{to_s(opts[:days])}d"],
    if opts[:dry_run]
      ["--dry-run"]
    else
      []
    end
  )
end

def nix(opts)
  cap = exec_capture(*nix_argv(opts)) rescue nil
  if cap.nil?
    {ok: false, summary: "nix-collect-garbage could not be started"}
  else
    out = concat(stdout_of(cap), stderr_of(cap))
    {ok: status_of(cap) == 0, summary: last_nonempty_line(out)}
  end
end

# ── report ───────────────────────────────────────────────────────────

def gib(kib)
  "#{to_s(round(kib / 104857.6) / 10)} GiB"
end

def rust_report(r, dry)
  verb = if dry
    "would remove"
  else
    "removed"
  end
  lines = map(
    (row) -> "  #{verdict(row, verb)}  #{gib(row[:kib])}  #{row[:path]}",
    r[:rows]
  )
  join(
    concat_lists(
      lines,
      [
        "rust: #{verb} #{to_s(size(r[:removed]))} of #{to_s(size(r[:rows]))} target/ dirs, #{gib(r[:kib])}"
      ]
    ),
    line_break
  )
end

def verdict(row, verb)
  if row[:active]
    "kept (active)"
  else
    verb
  end
end

@doc """
main: The command's entry point. blue has no exit(), so a usage error is printed
to stderr and then thrown, which exits the process non-zero; a run that
completes returns nil.
"""
def main()
  opts = parse(argv)
  if opts[:error] != nil
    write_stderr(
      unlines(
        [
          "souji: #{opts[:error]}",
          "usage: souji rust|nix|all [--dry-run] [--min-age-hours N] [--older-than-days N] [ROOT...]"
        ]
      )
    )
    raise(:souji_usage, opts[:error])
  else
    cmd = opts[:command]
    if cmd == "rust" or cmd == "all"
      write_stdout(concat(rust_report(rust(opts), opts[:dry_run]), line_break))
    end
    if cmd == "nix" or cmd == "all"
      n = nix(opts)
      write_stdout(unlines(["nix: #{n[:summary]}"]))
    end
    nil
  end
end

# ── tests ────────────────────────────────────────────────────────────

test "arguments: commands, flags, roots, and refusals"
  o = parse(["rust", "--dry-run", "--min-age-hours", "12", "/a", "/b"])
  assert o[:command] == "rust"
  assert o[:dry_run] == true
  assert o[:hours] == 12
  assert o[:roots] == ["/a", "/b"]
  # Defaults.
  d = parse(["nix"])
  assert d[:days] == 14
  assert d[:dry_run] == false
  # The controls: no command, an unknown one, a bad number, an unknown flag.
  assert parse([])[:error] != nil
  assert parse(["sweep"])[:error] != nil
  assert parse(["rust", "--min-age-hours", "x"])[:error] != nil
  assert parse(["rust", "--everything"])[:error] != nil
end

test "the nix command line: generations older than N days, dry-run passed through"
  assert nix_argv({days: 7, dry_run: true}) ==
    ["nix-collect-garbage", "--delete-older-than", "7d", "--dry-run"]
  assert nix_argv({days: 14, dry_run: false}) ==
    ["nix-collect-garbage", "--delete-older-than", "14d"]
end

test "rust: only a target/ beside a Cargo.toml, only when idle, dry run deletes nothing"
  base = path_join(getenv("TMPDIR", "/tmp"), "souji-test-#{to_s(now_ms)}")
  crate = path_join(base, "crate")
  mkdir_p(path_join(crate, "target/debug"))
  write_file(path_join(crate, "Cargo.toml"), unlines(["[package]"]))
  write_file(path_join(crate, "target/debug/x"), "bytes")
  # A target/ with no Cargo.toml beside it is not a Rust target.
  mkdir_p(path_join(base, "other/target"))
  # Just written, so active at 6 h: kept.
  r = rust({roots: [base], hours: 6, dry_run: false})
  assert size(r[:rows]) == 1
  assert size(r[:removed]) == 0
  assert path_exists(path_join(crate, "target")) == true
  # With no age guard it is eligible; a dry run still removes nothing.
  dry = rust({roots: [base], hours: 0, dry_run: true})
  assert size(dry[:removed]) == 1
  assert path_exists(path_join(crate, "target")) == true
  # For real.
  _wet = rust({roots: [base], hours: 0, dry_run: false})
  assert path_exists(path_join(crate, "target")) == false
  assert path_exists(path_join(base, "other/target")) == true
  rm_rf(base)
end
