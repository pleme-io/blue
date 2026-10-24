use("retsu", [:all_but_last, :enumerate, :first, :last, :reject])
use("shisutemu", [:status_of, :stderr_of, :stdout_of])

def gate_ids()
  ["fmt", "locks", "regen", "gen-pin", "gen-tie", "test-targets", "tests"]
end

def refuse(text)
  write_stderr("prepush: #{text}\n")
  exit_with(2)
end

def off?()
  v = getenv("BLUE_PREPUSH_OFF")
  if v.nil?
    false
  elsif v == "1"
    true
  else
    refuse("BLUE_PREPUSH_OFF is \"#{v}\"; the one value it takes is 1")
  end
end

def skipped()
  v = getenv("BLUE_PREPUSH_SKIP", "")
  ids = reject((s) -> s == "", map((s) -> blue::trim(s), split(v, ",")))
  bad = reject((s) -> member?(s, gate_ids), ids)
  if bad != []
    refuse(
      "BLUE_PREPUSH_SKIP names #{join(bad, ", ")}; the gates are #{join(gate_ids, ", ")}"
    )
  end
  ids
end

def cache_on?()
  v = getenv("BLUE_PREPUSH_CACHE", "on")
  if member?(v, ["on", "off"])
    v == "on"
  else
    refuse("BLUE_PREPUSH_CACHE is \"#{v}\"; it takes on or off")
  end
end

def lines_of(text)
  reject((l) -> l == "", split(text, "\n"))
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

def seconds(ms)
  "#{to_s(round(ms / 100) / 10)}s"
end

def store()
  "#{blue::trim(git(["rev-parse", "--path-format=absolute", "--git-common-dir"]))}/blue-prepush"
end

def wire()
  have = lines_of(git(["config", "--local", "--get-all", "include.path"]))
  if not member?("../.githooks/config", have)
    git(["config", "--local", "--add", "include.path", "../.githooks/config"])
  end
end

def source()
  [".", ":(exclude,glob)*.md", ":(exclude,glob)docs/**/*.md"]
end

def key_of(id, groups, tools)
  dirty = join(
    map(
      fn(g)
        git(append(["status", "--porcelain", "--untracked-files=all", "--"], g))
      end,
      groups
    ),
    ""
  )
  if dirty != ""
    nil
  else
    listing = join(
      map((g) -> git(append(["ls-files", "-s", "--"], g)), groups),
      ""
    )
    digest_hex(:sha256, "#{id}\n#{tools}\n#{listing}")
  end
end

def ledger(id)
  "#{store}/#{id}"
end

def local_green?(id, key)
  path_exists(ledger(id)) and member?(key, lines_of(read_file(ledger(id))))
end

def sui_url()
  getenv("BLUE_PREPUSH_SUI", "http://rio:5000")
end

def marker(id, key)
  dir = "#{store}/markers/#{key}"
  mkdir_p(dir)
  write_file("#{dir}/blue-gate-#{id}", "#{key}\n")
  r = exec_capture("nix", "store", "add-file", "#{dir}/blue-gate-#{id}")
  if status_of(r) == 0
    blue::trim(stdout_of(r))
  end
end

def curl()
  if path_exists("/usr/bin/curl")
    "/usr/bin/curl"
  else
    "curl"
  end
end

def fleet_green?(id, key)
  if sui_url == "off"
    false
  else
    path = marker(id, key)
    if path.nil?
      false
    else
      hash = first(split(path_basename(path), "-"))
      r = exec_capture(
        curl,
        "-s",
        "-o",
        "/dev/null",
        "-m",
        "3",
        "-w",
        "%{http_code}",
        "#{sui_url}/#{hash}.narinfo"
      )
      stdout_of(r) == "200"
    end
  end
end

def remember(id, key)
  mkdir_p(store)
  append_file(ledger(id), "#{key}\n")
  signing = getenv("BLUE_PREPUSH_SUI_KEY")
  if sui_url != "off" and not signing.nil?
    path = marker(id, key)
    if not path.nil?
      pushed = exec_capture(
        "sui",
        "cache",
        "push",
        "--cache-url",
        sui_url,
        "--signing-key",
        signing,
        path
      )
      if status_of(pushed) != 0
        write_stderr(
          "prepush: sui did not take the green mark for #{id}; it stays local\n"
        )
      end
    end
  end
end

def run_gate(g, i, total, skip, cache)
  id = first(g)
  step = "[#{to_s(i + 1)}/#{to_s(total)}] #{nth(1, g)}"
  if member?(id, skip)
    write_stderr("➖ #{step} (off: BLUE_PREPUSH_SKIP names #{id})\n")
    [nth(1, g), :off, :off]
  else
    t = now_ms
    key = if cache
      f = nth(2, g)
      f()
    end
    where = if key.nil?
      nil
    elsif local_green?(id, key)
      "this clone"
    elsif fleet_green?(id, key)
      "the fleet's cache"
    end
    if not where.nil?
      if where != "this clone"
        remember(id, key)
      end
      write_stderr(
        "✅ #{step} (#{seconds(now_ms - t)}; green in #{where} for these inputs)\n"
      )
      [nth(1, g), :green, :cached]
    else
      write_stderr("⏳ #{step} …\n")
      f = last(g)
      r = f()
      mark = get({green: "✅", red: "❌", blind: "➖"}, first(r))
      write_stderr("#{mark} #{step} (#{seconds(now_ms - t)})\n")
      if first(r) != :green
        write_stderr(last(r))
      elsif not key.nil?
        remember(id, key)
      end
      [nth(1, g), first(r), :ran]
    end
  end
end

def manifest(dir)
  get(json_read(read_file("#{dir}/Bluefile.lock")), "manifest")
end

def regenerates?(dir)
  m = manifest(dir)
  any?(
    (k) -> get(m, k) != nil,
    ["catalog", "generated", "workloads", "services"]
  )
end

def outputs(dir)
  m = manifest(dir)
  generated = map(
    (e) -> path_join(dir, get(last(e), "output")),
    map_entries(get(m, "generated") or {})
  )
  if get(m, "catalog").nil?
    generated
  else
    append([path_join(dir, get(m, "catalog"))], generated)
  end
end

def absent_tools(dir)
  reject((t) -> exec_ok?("which", t), get(manifest(dir), "tools") or [])
end

def members()
  meta = exec_capture("cargo", "metadata", "--no-deps", "--format-version", "1")
  map((p) -> get(p, "name"), get(json_read(stdout_of(meta)), "packages"))
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
    [:red, join(map((r) -> "#{first(r)}:\n#{stderr_of(last(r))}", red), "\n")]
  end
end

def changed()
  "#{git(["status", "--porcelain", "--untracked-files=all"])}#{git(["diff"])}"
end

def regen(bin, root, dir)
  was = lines_of(git(["status", "--porcelain", "--untracked-files=all"]))
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
  now = lines_of(git(["status", "--porcelain", "--untracked-files=all"]))
  if status_of(run) != 0
    missing = absent_tools(dir)
    if missing == []
      [:red, stderr_of(run)]
    else
      [:blind, "needs #{join(missing, ", ")}, which is not on PATH\n"]
    end
  elsif before == changed
    [:green, ""]
  else
    [
      :red,
      "regen rewrote stale generated files; commit them:\n#{join(reject((l) -> member?(l, was), now), "\n")}\n"
    ]
  end
end

def pinned(root, installable)
  r = exec_capture(
    "nix",
    "build",
    "--no-link",
    "--print-out-paths",
    "--inputs-from",
    root,
    installable
  )
  if status_of(r) == 0
    [:green, last(lines_of(stdout_of(r)))]
  else
    [:blind, "could not build #{installable} from flake.lock:\n#{stderr_of(r)}"]
  end
end

def tool_path(root, installable)
  dir = "#{store}/tools"
  mkdir_p(dir)
  lock = blue::trim(git(["rev-parse", "HEAD:flake.lock"]))
  memo = "#{dir}/#{digest_hex(:sha256, "#{installable}\n#{lock}")}"
  held = if path_exists(memo)
    blue::trim(read_file(memo))
  end
  if not held.nil? and path_exists(held)
    [:green, held]
  else
    r = pinned(root, installable)
    if first(r) == :green
      write_file(memo, "#{last(r)}\n")
    end
    r
  end
end

def gen_pin(root)
  r = tool_path(root, "substrate#gen")
  if first(r) == :green
    v = blue::trim(stdout_of(exec_capture("#{last(r)}/bin/gen", "--version")))
    write_stderr("   #{v} from the substrate flake.lock pins, not PATH\n")
    [:green, ""]
  else
    r
  end
end

def gen_bin(root)
  "#{last(tool_path(root, "substrate#gen"))}/bin/gen"
end

def gen_tie(root)
  gen = gen_bin(root)
  if status_of(exec_capture(gen, "confirm")) == 0
    [:green, ""]
  else
    was = lines_of(git(["status", "--porcelain", "--untracked-files=all"]))
    built = exec_capture(gen, "build", ".")
    now = lines_of(git(["status", "--porcelain", "--untracked-files=all"]))
    if status_of(built) != 0
      [:red, stderr_of(built)]
    else
      [
        :red,
        "Cargo.gen.lock was not tied to Cargo.lock and the manifests; gen build rewrote it. Commit:\n#{join(reject((l) -> member?(l, was), now), "\n")}\n"
      ]
    end
  end
end

def fmt(root)
  r = tool_path(root, "substrate#rustToolchain")
  if first(r) != :green
    r
  else
    verdict(
      exec_with_env(
        [["PATH", "#{last(r)}/bin:#{getenv("PATH")}"]],
        "#{last(r)}/bin/cargo",
        "fmt",
        "--all",
        "--",
        "--check"
      )
    )
  end
end

def toolchain()
  "#{stdout_of(exec_capture("cargo", "--version"))}#{stdout_of(exec_capture("uname", "-sm"))}"
end

if off?
  write_stderr("prepush: off (BLUE_PREPUSH_OFF=1); nothing checked\n")
  exit_with(0)
end

skip = skipped
cache = cache_on?
wire

root = blue::trim(git(["rev-parse", "--show-toplevel"]))
dirty = lines_of(git(["status", "--porcelain", "--untracked-files=no"]))

if dirty != []
  write_stderr(
    "⚠️ prepush reads the working tree, and #{to_s(count(dirty))} tracked files differ from HEAD\n"
  )
end

bin = dir_of(self_exe)
dirs = map(dir_of, lines_of(git(["ls-files", "*Bluefile.lock"])))

gates = append(
  [
    [
      "fmt",
      "cargo fmt",
      fn()
        key_of(
          "fmt",
          [["*.rs", "*rustfmt.toml", "*Cargo.toml"]],
          last(tool_path(root, "substrate#rustToolchain"))
        )
      end,
      () -> fmt(root)
    ],
    [
      "locks",
      "Bluefile.lock fresh",
      fn()
        key_of(
          "locks",
          [["*Bluefile", "*Bluefile.lock", "crates", "Cargo.lock"]],
          ""
        )
      end,
      fn()
        verdict(
          exec_capture(
            "#{bin}/blue",
            "bluefile",
            "--confirm",
            *map((d) -> "#{d}/Bluefile", dirs)
          )
        )
      end
    ]
  ],
  map(
    fn(d)
      groups = if d == "."
        [source, outputs(d)]
      else
        [[d, "bidamas", "crates", "Cargo.lock", "gen/regen.b"]]
      end
      [
        "regen",
        "regen #{d}",
        () -> key_of("regen #{d}", groups, ""),
        () -> regen(bin, root, d)
      ]
    end,
    filter(regenerates?, dirs)
  ),
  [
    ["gen-pin", "gen is substrate's pin", () -> nil, () -> gen_pin(root)],
    [
      "gen-tie",
      "Cargo.gen.lock tied",
      fn()
        key_of(
          "gen-tie",
          [["Cargo.lock", "Cargo.gen.lock", "*Cargo.toml"]],
          gen_bin(root)
        )
      end,
      () -> gen_tie(root)
    ],
    [
      "test-targets",
      "every member's test targets compile alone",
      () -> key_of("test-targets", [source], toolchain),
      () -> test_targets
    ],
    [
      "tests",
      "registry_graph, check_corpus, distribution, verb_graph",
      () -> key_of("tests", [source], toolchain),
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
  ]
)

total = count(gates)

write_stderr(
  "prepush: #{to_s(total)} gates; a gate green before for the same inputs is skipped. BLUE_PREPUSH_OFF=1 skips all, BLUE_PREPUSH_SKIP=<ids> skips some, BLUE_PREPUSH_CACHE=off runs every one\n"
)

started = now_ms

results = map(
  (p) -> run_gate(last(p), first(p), total, skip, cache),
  enumerate(gates)
)

red = map(first, filter((r) -> nth(1, r) == :red, results))
cached = count(filter((r) -> last(r) == :cached, results))

if red == []
  write_stderr(
    "🟢 prepush: no gate red (#{seconds(now_ms - started)}; #{to_s(cached)} of #{to_s(total)} skipped as already green)\n"
  )
else
  write_stderr(
    "🔴 prepush: #{to_s(count(red))} red: #{join(red, "; ")}. Fix it, or skip once with BLUE_PREPUSH_OFF=1 git push\n"
  )
  exit_with(1)
end
