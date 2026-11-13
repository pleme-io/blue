@moduledoc """
test-beside: the coverage gate every project with `packages` gets as `checks.test-beside` (docs/TESTING.md T2). It reads the coverage each `bidama-test-<pkg>` check already wrote, so no test runs twice, and judges it under the project's policy: the `coverage(file)` program's `policy()` when the Bluefile names one, else every package at enforce with no recorded debt.

    default_policy[:recorded] #=> ""
"""

use("retsu", %i[find_first first size])
use("shisutemu", %i[status_of stderr_of stdout_of])

use(
  "tesuto",
  %i[
    coverage_arms
    coverage_names
    coverage_red?
    coverage_report
    fresh_dir
    judge_coverage
    level
    levels
    waive
  ]
)

@doc """
default_policy: The policy of a project that names none: every package held at enforce, no waiver, no recorded debt, so every definition is reached by a test beside it.

    size(default_policy[:entries]) #=> 1
"""
def default_policy()
  {
    entries: [
      level(
        "*",
        :enforce,
        "a definition is reached by a test beside it (the default of every project with packages)"
      )
    ],
    recorded: ""
  }
end

@doc """
entry_of: A policy entry read back from JSON: its `level` a keyword again, and every key a keyword.

    entry_of({"entry" => "level", "scope" => "*", "level" => "audit", "why" => "w"}) #=> level("*", :audit, "w")
    entry_of({"entry" => "waive", "name" => "p::f", "why" => "w", "until" => "2027-01-01"}) #=> waive("p::f", "w", "2027-01-01")
"""
def entry_of(e)
  if e["entry"] == "level"
    level(
      e["scope"],
      find_first((l) -> to_s(l) == e["level"], levels),
      e["why"]
    )
  else
    waive(e["name"], e["why"], e["until"])
  end
end

@doc """
policy_of: The policy a `coverage(file)` program prints as JSON (`{entries: […], recorded: "…"}`), its entries read back with `entry_of`.

    policy_of("{\"entries\": [], \"recorded\": \"untested: p 1\"}")[:recorded] #=> "untested: p 1"
"""
def policy_of(text)
  doc = json_read(text)
  {
    entries: map(entry_of, doc["entries"] or []),
    recorded: doc["recorded"] or ""
  }
end

def read_policy(blue, file)
  if file == ""
    default_policy
  else
    cap = exec_capture(blue, "run", "--quiet", file, "--", "policy")
    if status_of(cap) != 0
      raise(:policy, "#{file} printed no policy: #{stderr_of(cap)}")
    end
    policy_of(stdout_of(cap))
  end
end

@doc """
measured_of: One package's measurement from the outputs of its `bidama-test-*` checks: every name none of them reached. A check that ran is green (nix keeps no red output), so it is never blind.

    measured_of("p", ["{\"covered\": 1, \"uncovered\": [\"p::f\"], \"untaken\": [\"p::g#0:1\"]}"]) #=> {package: "p", blind: false, names: ["p::f"], arms: ["p::g#0:1"]}
"""
def measured_of(package, texts)
  {
    package:,
    blind: false,
    names: reduce((acc, t) -> append(acc, coverage_names(t)), [], texts),
    arms: reduce((acc, t) -> append(acc, coverage_arms(t)), [], texts)
  }
end

@doc """
runs_of: Every package's measurement from a directory holding one directory per package, named for it, and in it the output of each of its `bidama-test-*` checks.

    runs_of(fresh_dir("runs")) #=> []
"""
def runs_of(dir)
  sort_keyed(
    (m) -> m[:package],
    map(
      fn(d)
        measured_of(
          path_basename(d),
          map(read_file, sort_keyed((f) -> f, ls(d)))
        )
      end,
      ls(dir)
    )
  )
end

def main()
  runs = first(argv)
  file = argv_get(1, "")
  policy = read_policy(self_exe, file)
  r = judge_coverage(
    policy[:entries],
    policy[:recorded],
    runs_of(runs),
    join(take(10, chars(now_rfc3339)), "")
  )
  home = if file == ""
    "the Bluefile's coverage(file)"
  else
    file
  end
  shown = coverage_report(r, policy[:recorded], home)
  if coverage_red?(r)
    write_stderr(unlines([shown]))
    exit_with(1)
  end
  write_stdout(
    unlines(
      [
        "test-beside: #{to_s(size(r[:verdicts]))} package(s) at or below their recorded debt",
        shown
      ]
    )
  )
end

test "a package the outputs show untested beyond its debt is red, and one at its debt is green"
  red = judge_coverage(
    default_policy[:entries],
    "",
    [measured_of("p", ["{\"covered\": 1, \"uncovered\": [\"p::f\"]}"])],
    "2026-11-13"
  )
  assert coverage_red?(red)
  held = judge_coverage(
    default_policy[:entries],
    "untested: p 1",
    [measured_of("p", ["{\"covered\": 1, \"uncovered\": [\"p::f\"]}"])],
    "2026-11-13"
  )
  assert not coverage_red?(held)
end

test "a project's policy is read back from its JSON, entries and debt"
  p = policy_of(
    json_stringify(
      {
        entries: [
          level("*", :audit, "trial"),
          waive("p::f", "why", "2027-01-01")
        ],
        recorded: "untested: p 2"
      }
    )
  )
  assert p[:entries] ==
    [level("*", :audit, "trial"), waive("p::f", "why", "2027-01-01")]
  assert p[:recorded] == "untested: p 2"
end
