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

# souji (掃除) — cleaning a node: Rust target/ directories nobody is building in, and nix store paths nothing refers to, with a dry run first.
#
# The two things that fill a developer node's disk (measured 2026-09-27: 29 GB
# of target/ directories, and a nix store every one of whose paths was still
# referenced). Both cleanings reclaim only what can be rebuilt or re-fetched.
#
#   souji rust [--dry-run] [--min-age-hours N] [ROOT...]   default ROOT ~/code
#   souji nix  [--dry-run] [--older-than-days N]           default 14
#   souji all  [--dry-run]                                 both, rust first
#
# A target/ directory counts only beside a Cargo.toml, and only when nothing
# inside it changed in the last N hours (default 6): a build writing there,
# or a binary running from it, is never pulled out from under. The nix
# cleaning deletes this user's profile generations older than N days and then
# every store path left unreferenced; run it as root to include the system's.
#
# Every tool it runs is at a process boundary (find, du, nix-collect-garbage);
# the logic is blue.

# ── arguments ────────────────────────────────────────────────────────

# {command, dry_run, hours, days, roots} from argv, or {error: why}.
def sj_parse(args)
  if is_empty(args)
    {error: "a command: rust, nix or all"}
  else
    cmd = first(args)
    if contains(["rust", "nix", "all"], cmd) == false
      {error: "unknown command #{cmd}: rust, nix or all"}
    else
      sj_parse_flags(
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

def sj_parse_flags(args, acc)
  if is_empty(args) || get(acc, :error) != nil
    acc
  else
    a = first(args)
    if a == "--dry-run"
      sj_parse_flags(rest(args), assoc(acc, :dry_run, true))
    elsif a == "--min-age-hours" || a == "--older-than-days"
      v = if size(args) > 1
        to_int(nth(1, args))
      else
        nil
      end
      if v == nil || v < 0
        assoc(acc, :error, "#{a} needs a whole number of 0 or more")
      else
        key = if a == "--min-age-hours"
          :hours
        else
          :days
        end
        sj_parse_flags(drop_n(args, 2), assoc(acc, key, v))
      end
    elsif starts_with?(a, "--")
      assoc(acc, :error, "unknown flag #{a}")
    else
      sj_parse_flags(rest(args), assoc(acc, :roots, push(get(acc, :roots), a)))
    end
  end
end

def sj_roots(opts)
  if is_empty(get(opts, :roots))
    [path_join(getenv("HOME", "/"), "code")]
  else
    get(opts, :roots)
  end
end

# ── rust ─────────────────────────────────────────────────────────────

# target/ directories under root, at most depth levels down, each beside a
# Cargo.toml. find prunes at each target/ so it never walks inside one.
def sj_targets(root, depth)
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
    fn(d) path_exists(path_join(path_dirname(d), "Cargo.toml")) end,
    filter(fn(l) is_empty(trim(l)) == false end, split(stdout_of(cap), "\n"))
  )
end

# Kibibytes under dir, from du; 0 when du could not read it.
def sj_size_kib(dir)
  cap = exec_capture("du", "-sk", dir)
  n = to_int(first(split(trim(stdout_of(cap)), "\t")))
  if n == nil
    0
  else
    n
  end
end

# True when anything inside dir changed in the last `hours` hours: find stops
# at the first such file.
def sj_active?(dir, hours)
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
    is_empty(trim(stdout_of(cap))) == false
  end
end

# One row per target/: {path, kib, active}.
def sj_rust_survey(roots, hours)
  map(
    fn(d) {path: d, kib: sj_size_kib(d), active: sj_active?(d, hours)} end,
    flat_map(fn(r) sj_targets(r, 4) end, roots)
  )
end

def sj_rust(opts)
  rows = sj_rust_survey(sj_roots(opts), get(opts, :hours))
  gone = filter(fn(r) get(r, :active) == false end, rows)
  if get(opts, :dry_run) == false
    map(fn(r) rm_rf(get(r, :path)) end, gone)
  end
  {rows: rows, removed: gone, kib: sj_sum(map(fn(r) get(r, :kib) end, gone))}
end

def sj_sum(xs)
  reduce(fn(a, x) a + x end, 0, xs)
end

# ── nix ──────────────────────────────────────────────────────────────

def sj_nix_argv(opts)
  concat_lists(
    [
      "nix-collect-garbage",
      "--delete-older-than",
      "#{to_s(get(opts, :days))}d"
    ],
    if get(opts, :dry_run)
      ["--dry-run"]
    else
      []
    end
  )
end

def sj_nix(opts)
  cap = try(apply(exec_capture, sj_nix_argv(opts)), catch(_e(), nil))
  if cap == nil
    {ok: false, summary: "nix-collect-garbage could not be started"}
  else
    out = concat(stdout_of(cap), stderr_of(cap))
    {ok: status_of(cap) == 0, summary: last_nonempty_line(out)}
  end
end

# ── report ───────────────────────────────────────────────────────────

def sj_gib(kib)
  "#{to_s(round(kib / 104857.6) / 10)} GiB"
end

def sj_rust_report(r, dry)
  verb = if dry
    "would remove"
  else
    "removed"
  end
  lines = map(
    fn(row)
      "  #{sj_verdict(row, verb)}  #{sj_gib(get(row, :kib))}  #{get(row, :path)}"
    end,
    get(r, :rows)
  )
  join(
    concat_lists(
      lines,
      [
        "rust: #{verb} #{to_s(size(get(r, :removed)))} of #{to_s(size(get(r, :rows)))} target/ dirs, #{sj_gib(get(r, :kib))}"
      ]
    ),
    "\n"
  )
end

def sj_verdict(row, verb)
  if get(row, :active)
    "kept (active)"
  else
    verb
  end
end

# The command's entry point. blue has no exit(), so a usage error is printed
# to stderr and then thrown, which exits the process non-zero; a run that
# completes returns nil.
def sj_main()
  opts = sj_parse(argv())
  if get(opts, :error) != nil
    write_stderr(
      "souji: #{get(opts, :error)}\nusage: souji rust|nix|all [--dry-run] [--min-age-hours N] [--older-than-days N] [ROOT...]\n"
    )
    throw(error(:souji_usage, get(opts, :error)))
  else
    cmd = get(opts, :command)
    if cmd == "rust" || cmd == "all"
      write_stdout(
        concat(sj_rust_report(sj_rust(opts), get(opts, :dry_run)), "\n")
      )
    end
    if cmd == "nix" || cmd == "all"
      n = sj_nix(opts)
      write_stdout("nix: #{get(n, :summary)}\n")
    end
    nil
  end
end

# ── tests ────────────────────────────────────────────────────────────

test "arguments: commands, flags, roots, and refusals"
  o = sj_parse(["rust", "--dry-run", "--min-age-hours", "12", "/a", "/b"])
  assert get(o, :command) == "rust"
  assert get(o, :dry_run) == true
  assert get(o, :hours) == 12
  assert get(o, :roots) == ["/a", "/b"]
  # Defaults.
  d = sj_parse(["nix"])
  assert get(d, :days) == 14
  assert get(d, :dry_run) == false
  # The controls: no command, an unknown one, a bad number, an unknown flag.
  assert get(sj_parse([]), :error) != nil
  assert get(sj_parse(["sweep"]), :error) != nil
  assert get(sj_parse(["rust", "--min-age-hours", "x"]), :error) != nil
  assert get(sj_parse(["rust", "--everything"]), :error) != nil
end

test "the nix command line: generations older than N days, dry-run passed through"
  assert sj_nix_argv({days: 7, dry_run: true}) ==
    ["nix-collect-garbage", "--delete-older-than", "7d", "--dry-run"]
  assert sj_nix_argv({days: 14, dry_run: false}) ==
    ["nix-collect-garbage", "--delete-older-than", "14d"]
end

test "rust: only a target/ beside a Cargo.toml, only when idle, dry run deletes nothing"
  base = path_join(getenv("TMPDIR", "/tmp"), "souji-test-#{to_s(now_ms())}")
  crate = path_join(base, "crate")
  mkdir_p(path_join(crate, "target/debug"))
  write_file(path_join(crate, "Cargo.toml"), "[package]\n")
  write_file(path_join(crate, "target/debug/x"), "bytes")
  # A target/ with no Cargo.toml beside it is not a Rust target.
  mkdir_p(path_join(base, "other/target"))
  # Just written, so active at 6 h: kept.
  r = sj_rust({roots: [base], hours: 6, dry_run: false})
  assert size(get(r, :rows)) == 1
  assert size(get(r, :removed)) == 0
  assert path_exists(path_join(crate, "target")) == true
  # With no age guard it is eligible; a dry run still removes nothing.
  dry = sj_rust({roots: [base], hours: 0, dry_run: true})
  assert size(get(dry, :removed)) == 1
  assert path_exists(path_join(crate, "target")) == true
  # For real.
  _wet = sj_rust({roots: [base], hours: 0, dry_run: false})
  assert path_exists(path_join(crate, "target")) == false
  assert path_exists(path_join(base, "other/target")) == true
  rm_rf(base)
end
