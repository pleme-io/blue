use("gamen", [:duration_text, :show_step])
use("retsu", [:all_but_last, :enumerate, :first, :last, :reject])
use("shisutemu", [:status_of, :stderr_of, :stdout_of])

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

def run_gate(g, i, total)
  show_step({state: :running, at: i + 1, of: total, name: first(g)}, {})
  t = now_ms
  f = last(g)
  r = f()
  show_step(
    {
      state: get({green: :done, red: :failed, blind: :skipped}, first(r)),
      at: i + 1,
      of: total,
      name: first(g),
      ms: now_ms - t
    },
    {}
  )
  if first(r) != :green
    write_stderr(last(r))
  end
  [first(g), first(r)]
end

def manifest(dir)
  get(json_read(read_file("#{dir}/Bluefile.lock")), "manifest")
end

def regenerates?(dir)
  m = manifest(dir)
  any?(
    (k) -> get(m, k) != nil,
    ["catalog", "generated", "workloads", "registries", "services"]
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
    installed = blue::trim(stdout_of(exec_capture("gen", "--version")))
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

def gen_tie()
  if not exec_ok?("which", "gen")
    [:blind, unlines(["gen is not on PATH"])]
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

if off?
  write_stderr(unlines(["prepush: off (BLUE_PREPUSH_OFF=1); nothing checked"]))
  exit_with(0)
end

root = blue::trim(git(["rev-parse", "--show-toplevel"]))
dirty = lines_of(git(["status", "--porcelain", "--untracked-files=no"]))

if dirty != []
  write_stderr(
    unlines(
      [
        "⚠️ prepush reads the working tree, and #{to_s(count(dirty))} tracked files differ from HEAD"
      ]
    )
  )
end

bin = dir_of(self_exe)
dirs = map(dir_of, lines_of(git(["ls-files", "*Bluefile.lock"])))

gates = append(
  [
    [
      "cargo fmt",
      () -> verdict(exec_capture("cargo", "fmt", "--all", "--", "--check"))
    ],
    [
      "blue fmt, every .b as checks.blue-fmt reads it",
      fn()
        verdict(
          exec_capture(
            "#{bin}/blue",
            "fmt",
            "--check",
            *lines_of(git(["ls-files", "*.b"]))
          )
        )
      end
    ],
    [
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
    ]
  ],
  map(
    (d) -> ["regen #{d}", () -> regen(bin, root, d)],
    filter(regenerates?, dirs)
  ),
  [
    ["gen is substrate's pin", () -> gen_pin],
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
              "origin/main",
              "HEAD"
            )
          )
        end
      end
    ],
    ["Cargo.gen.lock tied", () -> gen_tie],
    ["every member's test targets compile alone", () -> test_targets],
    [
      "tests beside every bidama definition",
      fn()
        verdict(
          exec_capture("#{bin}/blue", "test", "#{root}/gen/test-beside.b")
        )
      end
    ],
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
  ]
)

total = count(gates)

write_stderr(
  unlines(
    [
      "prepush: #{to_s(total)} gates, a few minutes; ctrl-c stops it, BLUE_PREPUSH_OFF=1 git push skips it"
    ]
  )
)

started = now_ms
results = map((p) -> run_gate(last(p), first(p), total), enumerate(gates))
red = map(first, filter((r) -> last(r) == :red, results))

if red == []
  write_stderr(
    unlines(["🟢 prepush: no gate red (#{duration_text(now_ms - started)})"])
  )
else
  write_stderr(
    unlines(
      [
        "🔴 prepush: #{to_s(count(red))} red: #{join(red, "; ")}. Fix it, or skip once with BLUE_PREPUSH_OFF=1 git push"
      ]
    )
  )
  exit_with(1)
end
