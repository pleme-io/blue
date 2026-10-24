use("retsu", [:all_but_last, :first, :last, :reject])
use("shisutemu", [:status_of, :stderr_of, :stdout_of])

def off?()
  v = getenv("BLUE_PREPUSH_OFF")
  if v.nil?
    false
  elsif v == "1"
    true
  else
    write_stderr(
      "prepush: BLUE_PREPUSH_OFF is \"#{v}\"; the one value it takes is 1\n"
    )
    exit_with(2)
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

def gate(name, f)
  t = now_ms
  r = f()
  [name, first(r), now_ms - t, last(r)]
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

def gen_pin()
  pin = exec_capture(
    "nix",
    "eval",
    "--raw",
    "github:pleme-io/substrate#genPin.version"
  )
  if not exec_ok?("which", "gen")
    [:blind, "gen is not on PATH\n"]
  elsif status_of(pin) != 0
    [:blind, "could not read substrate's gen pin:\n#{stderr_of(pin)}"]
  else
    installed = blue::trim(stdout_of(exec_capture("gen", "--version")))
    if installed == "gen #{stdout_of(pin)}"
      [:green, ""]
    else
      [
        :red,
        "#{installed} is installed; substrate pins gen #{stdout_of(pin)}. Run:\n  nix flake update substrate --flake ~/code/github/pleme-io/nix\n  nix run ~/code/github/pleme-io/nix#rebuild\n"
      ]
    end
  end
end

def gen_tie()
  if not exec_ok?("which", "gen")
    [:blind, "gen is not on PATH\n"]
  elsif status_of(exec_capture("gen", "confirm")) == 0
    [:green, ""]
  else
    was = lines_of(git(["status", "--porcelain", "--untracked-files=all"]))
    built = exec_capture("gen", "build", ".")
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

def report(r)
  mark = get({green: "✅", red: "❌", blind: "➖"}, nth(1, r))
  write_stderr("#{mark} #{nth(0, r)} (#{to_s(nth(2, r) / 1000)}s)\n")
  if nth(1, r) != :green
    write_stderr(nth(3, r))
  end
end

if off?
  write_stderr("prepush: off (BLUE_PREPUSH_OFF=1); nothing checked\n")
  exit_with(0)
end

root = blue::trim(git(["rev-parse", "--show-toplevel"]))
dirty = lines_of(git(["status", "--porcelain", "--untracked-files=no"]))

if dirty != []
  write_stderr(
    "⚠️ prepush reads the working tree, and #{to_s(count(dirty))} tracked files differ from HEAD\n"
  )
end

bin = dir_of(self_exe)
dirs = map(dir_of, lines_of(git(["ls-files", "*Bluefile.lock"])))

results = append(
  [
    gate(
      "cargo fmt",
      () -> verdict(exec_capture("cargo", "fmt", "--all", "--", "--check"))
    ),
    gate(
      "Bluefile.lock fresh",
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
    )
  ],
  map(
    (d) -> gate("regen #{d}", () -> regen(bin, root, d)),
    filter(regenerates?, dirs)
  ),
  [
    gate("gen is substrate's pin", () -> gen_pin),
    gate("Cargo.gen.lock tied", () -> gen_tie),
    gate("every member's test targets compile alone", () -> test_targets),
    gate(
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
    )
  ]
)

map(report, results)
red = filter((r) -> nth(1, r) == :red, results)

if red == []
  write_stderr("🟢 prepush: no gate red\n")
else
  write_stderr(
    "🔴 prepush: #{to_s(count(red))} red; fix it, or push with BLUE_PREPUSH_OFF=1\n"
  )
  exit_with(1)
end
