@moduledoc """
souji (掃除) — cleaning a node: Rust target/ directories nobody is building in, and nix store paths nothing refers to, with a dry run first.

The two things that fill a developer node's disk (measured 2026-09-27: 29 GB
of target/ directories, and a nix store every one of whose paths was still
referenced). Both cleanings reclaim only what can be rebuilt or re-fetched.

  souji rust [--dry-run] [--min-age-hours N] [ROOTS...]  default ROOTS ~/code
  souji nix  [--dry-run] [--older-than-days N]           default 14
  souji all  [--dry-run]                                 both, rust first

The settings are one core model, `settings`, resolved by settei: the
defaults, then ~/.config/souji/souji.yaml, then SOUJI_ variables, then the
flags. `souji --help` prints the command line rendered from it, `souji
__complete` answers shell completion and `souji --explain KEY` says where a
setting came from.

A target/ directory counts only beside a Cargo.toml, and only when nothing
inside it changed in the last N hours (default 6): a build writing there,
or a binary running from it, is never pulled out from under. The nix
cleaning deletes this user's profile generations older than N days and then
every store path left unreferenced; run it as root to include the system's.

Every tool it runs is at a process boundary (find, du, nix-collect-garbage);
the logic is blue.

    nix_argv({older_than_days: 14, dry_run: false}) #=> ["nix-collect-garbage", "--delete-older-than", "14d"]
"""

use("hikisuu")
use("kazu", [:sum])
use("retsu", %i[concat_lists first flat_map is_empty size])
use("settei")

use("shisutemu", %i[last_nonempty_line status_of stderr_of stdout_of])

legacy_names("0.1.1", "sj")

legacy_names("0.1.2", [%w[sum kazu::sum]])

# ── arguments ────────────────────────────────────────────────────────

@doc """
settings: souji's core model: a dry run and the two age floors, each a knob with its default, floor, unit and doc. The flags, help, `--explain KEY`, the config file (~/.config/souji/souji.yaml), the SOUJI_ environment and the table in docs/config/souji.md are rendered from it.

    settei::defaults_of(settings) #=> {dry_run: false, min_age_hours: 6, older_than_days: 14}
"""
def settings()
  {
    dry_run: settei::knob(false, {doc: "say what would go; delete nothing"}),
    min_age_hours: settei::knob(
      6,
      {
        min: 0,
        unit: "hours",
        doc: "keep a target/ written to within this many hours"
      }
    ),
    older_than_days: settei::knob(
      14,
      {
        min: 0,
        unit: "days",
        doc: "delete profile generations older than this many days"
      }
    )
  }
end

@doc """
frame: souji's command line beside its settings: three commands and the roots to search.

    size(frame[:commands]) #=> 3
"""
def frame()
  {
    name: "souji",
    about: "clean a node: idle Rust target/ directories and unreferenced nix store paths",
    commands: [
      {
        name: :rust,
        about: "remove target/ directories nothing wrote to lately"
      },
      {
        name: :nix,
        about: "delete old generations, then unreferenced store paths"
      },
      {name: :all, about: "both, rust first"}
    ],
    positional: [
      {name: :roots, many: true, about: "where to look; ~/code when none"}
    ]
  }
end

@doc """
cli: souji's command line as hikisuu reads it, rendered from its settings and its frame.

    get(hikisuu::parse(["nix"], cli), :older_than_days) #=> 14
"""
def cli()
  settei::cli_spec(settings, frame)
end

@doc """
roots: where the rust cleaning looks: the roots given on the command line, else ~/code.

    roots({roots: ["/a", "/b"]}) #=> ["/a", "/b"]
"""
def roots(opts)
  if is_empty(opts[:roots])
    [path_join(getenv("HOME", "/"), "code")]
  else
    opts[:roots]
  end
end

# ── rust ─────────────────────────────────────────────────────────────

# waive B0083: integration debt recorded 2026-11-13: no test of this file declared kind: :integration reaches it yet
@doc """
targets: target/ directories under root, at most depth levels down, each beside a
Cargo.toml. find prunes at each target/ so it never walks inside one.

    procedure?(targets) #=> true
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

# waive B0083: integration debt recorded 2026-11-13: no test of this file declared kind: :integration reaches it yet
@doc """
size_kib: Kibibytes under dir, from du; 0 when du could not read it.

    procedure?(size_kib) #=> true
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

# waive B0083: integration debt recorded 2026-11-13: no test of this file declared kind: :integration reaches it yet
@doc """
active?: True when anything inside dir changed in the last `hours` hours: find stops
at the first such file. An age floor of 0 hours never counts a directory active.

    active?("/nowhere", 0) #=> false
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

    rust_survey([], 6) #=> []
"""
def rust_survey(roots, hours)
  map(
    (d) -> {path: d, kib: size_kib(d), active: active?(d, hours)},
    flat_map(roots, (r) -> targets(r, 4))
  )
end

@doc """
rust: the rust cleaning: survey every target/ under the roots and remove the idle ones, unless it is a dry run.

    procedure?(rust) #=> true
"""
def rust(opts)
  rows = rust_survey(roots(opts), opts[:min_age_hours])
  gone = filter((r) -> r[:active] == false, rows)
  if opts[:dry_run] == false
    map((r) -> rm_rf(r[:path]), gone)
  end
  {rows:, removed: gone, kib: sum(map((r) -> r[:kib], gone))}
end

# ── nix ──────────────────────────────────────────────────────────────

@doc """
nix_argv: the nix-collect-garbage command line for the age floor, with the dry run passed through.

    nix_argv({older_than_days: 7, dry_run: true}) #=> ["nix-collect-garbage", "--delete-older-than", "7d", "--dry-run"]
"""
def nix_argv(opts)
  concat_lists(
    [
      "nix-collect-garbage",
      "--delete-older-than",
      "#{to_s(opts[:older_than_days])}d"
    ],
    if opts[:dry_run]
      ["--dry-run"]
    else
      []
    end
  )
end

# waive B0083: integration debt recorded 2026-11-13: no test of this file declared kind: :integration reaches it yet
@doc """
nix: the nix cleaning: run nix-collect-garbage and keep whether it succeeded and its last line.

    procedure?(nix) #=> true
"""
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

@doc """
gib: a kibibyte count shown in GiB, to one decimal place.

    gib(2_097_152) #=> "2 GiB"
"""
def gib(kib)
  "#{to_s(round(kib / 104857.6) / 10)} GiB"
end

@doc """
rust_report: the rust cleaning's report: one line per target/, then the total.

    r = {rows: [{path: "/a/target", kib: 2_097_152, active: false}], removed: [{path: "/a/target"}], kib: 2_097_152}
    rust_report(r, true) #=> "  would remove  2 GiB  /a/target\nrust: would remove 1 of 1 target/ dirs, 2 GiB"
"""
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

@doc """
verdict: what the report says of one target/: kept when active, else the verb.

    verdict({active: true}, "removed") #=> "kept (active)"
"""
def verdict(row, verb)
  if row[:active]
    "kept (active)"
  else
    verb
  end
end

# waive B0084: integration debt recorded 2026-11-13: no test of this file declared kind: :integration reaches this seam yet
@doc """
main: the command's entry point: argv read by souji's cli through hikisuu, which answers help and completion and refuses a bad line with exit 64.

    get(hikisuu::outcome(["sweep"], cli), :status) #=> 64
"""
def main()
  settei::command("souji", settings, frame, perform)
end

@doc """
perform: one run of a parsed command line: the rust cleaning, the nix cleaning or both, each reported on stdout.

    procedure?(perform) #=> true
"""
def perform(opts)
  cmd = opts[:command]
  if cmd == :rust or cmd == :all
    write_stdout(concat(rust_report(rust(opts), opts[:dry_run]), line_break))
  end
  if cmd == :nix or cmd == :all
    n = nix(opts)
    write_stdout(unlines(["nix: #{n[:summary]}"]))
  end
  nil
end

# ── tests ────────────────────────────────────────────────────────────

test "settings: the environment sets a floor, a flag wins, a bad value warns alone, and explain names the layer"
  env = settei::env_of(
    {"SOUJI_MIN_AGE_HOURS" => "2", "SOUJI_OLDER_THAN_DAYS" => "-3"}
  )
  o = settei::line("souji", settings, frame, ["rust"], nil, env)
  assert o[:opts][:min_age_hours] == 2
  assert o[:opts][:older_than_days] == 14
  assert o[:warnings] ==
    ["older_than_days must be 0 or more, got -3 from SOUJI_OLDER_THAN_DAYS; kept 14"]
  f = settei::line(
    "souji",
    settings,
    frame,
    %w[rust --min-age-hours 9],
    nil,
    env
  )
  assert f[:opts][:min_age_hours] == 9
  x = settei::line(
    "souji",
    settings,
    frame,
    %w[--explain min_age_hours],
    nil,
    env
  )
  assert contains?(x[:text], "min_age_hours = 2")
  assert contains?(x[:text], "source   env SOUJI_MIN_AGE_HOURS")
  assert contains?(x[:text], "unit     hours")
end

test "arguments: commands, flags, roots, and refusals"
  o = hikisuu::parse(%w[rust --dry-run --min-age-hours 12 /a /b], cli)
  assert o[:command] == :rust
  assert o[:dry_run] == true
  assert o[:min_age_hours] == 12
  assert o[:roots] == %w[/a /b]
  d = hikisuu::parse(["nix"], cli)
  assert d[:older_than_days] == 14
  assert d[:dry_run] == false
  kind_of = fn(args)
    begin
      hikisuu::parse(args, cli)
      nil
    rescue e
      e.kind
    end
  end
  assert kind_of([]) == :usage
  assert kind_of(["sweep"]) == :usage
  assert kind_of(%w[rust --min-age-hours x]) == :usage
  assert kind_of(%w[rust --everything]) == :usage
  assert kind_of(%w[nix --older-than-days -1]) == :usage
end

test "the rust report: one line per target, kept when active, then the total"
  r = {
    rows: [
      {path: "/a/target", kib: 2_097_152, active: false},
      {path: "/b/target", kib: 0, active: true}
    ],
    removed: [{path: "/a/target"}],
    kib: 2_097_152
  }
  assert rust_report(r, true) ==
    join_lines(
      [
        "  would remove  2 GiB  /a/target",
        "  kept (active)  0 GiB  /b/target",
        "rust: would remove 1 of 2 target/ dirs, 2 GiB"
      ]
    )
  assert contains?(rust_report(r, false), "rust: removed 1 of 2") == true
end

test "the nix command line: generations older than N days, dry-run passed through"
  assert nix_argv({older_than_days: 7, dry_run: true}) ==
    %w[nix-collect-garbage --delete-older-than 7d --dry-run]
  assert nix_argv({older_than_days: 14, dry_run: false}) ==
    %w[nix-collect-garbage --delete-older-than 14d]
end

test "rust: only a target/ beside a Cargo.toml, only when idle, dry run deletes nothing"
  base = path_join(temp_dir("souji-test"), "souji-test")
  crate = path_join(base, "crate")
  mkdir_p(path_join(crate, "target/debug"))
  write_file(path_join(crate, "Cargo.toml"), unlines(["[package]"]))
  write_file(path_join(crate, "target/debug/x"), "bytes")
  # A target/ with no Cargo.toml beside it is not a Rust target.
  mkdir_p(path_join(base, "other/target"))
  # Just written, so active at 6 h: kept.
  r = rust({roots: [base], min_age_hours: 6, dry_run: false})
  assert size(r[:rows]) == 1
  assert size(r[:removed]) == 0
  assert path_exists(path_join(crate, "target")) == true
  # With no age guard it is eligible; a dry run still removes nothing.
  dry = rust({roots: [base], min_age_hours: 0, dry_run: true})
  assert size(dry[:removed]) == 1
  assert path_exists(path_join(crate, "target")) == true
  # For real.
  _wet = rust({roots: [base], min_age_hours: 0, dry_run: false})
  assert path_exists(path_join(crate, "target")) == false
  assert path_exists(path_join(base, "other/target")) == true
  rm_rf(base)
end
