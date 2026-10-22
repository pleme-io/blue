use("retsu", [:all_but_last, :first, :last, :reject])
use("shisutemu", [:status_of, :stderr_of, :stdout_of])

def off?()
  v = getenv("BLUE_PREPUSH_OFF")
  if v == nil
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

root = trim(git(["rev-parse", "--show-toplevel"]))
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
    gate(
      "registry_graph, check_corpus, distribution",
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
            "distribution"
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
