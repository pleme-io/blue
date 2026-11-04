@moduledoc """
vm-run: Run a `vm_check` inside the machine it booted, and judge it. The control must fail, so a harness that runs nothing cannot pass; the kernel must be the one declared, so a pass cannot come from the wrong kernel; the program must exit zero and print what the declaration expects.

    blue run vm-run.b -- PLAN.json
"""

use("deeta", [:get_or])

use("retsu", %i[first flat_map rest])

use("shisutemu", %i[status_of stderr_of stdout_of])

@doc """
missing: The expected lines a run's output does not hold.

    missing(["a", "b"], "a c") #=> ["b"]
    missing([], "") #=> []
"""
def missing(expect, text)
  retsu::reject((e) -> contains?(text, e), expect)
end

@doc """
faults: Why a run does not count, as text; empty when it counts.

    faults({"release" => "6.6.", "expect" => ["ok"], "control" => {"expect" => ["1 failed"]}}, {release: "6.6.1", status: 0, output: "ok", control_status: 1, control_output: "1 failed"}) #=> []
"""
def faults(plan, run)
  release = if starts_with?(run[:release], plan["release"])
    []
  else
    ["booted #{run[:release]}, and the declaration names #{plan["release"]}"]
  end
  control = if run[:control_status] == 0
    ["the control passed, so this harness cannot go red"]
  else
    map(
      (e) -> "the control's output lacks #{e}: it did not fail as it must",
      missing(plan["control"]["expect"], run[:control_output])
    )
  end
  status = if run[:status] == 0
    []
  else
    ["the program exited #{to_s(run[:status])}"]
  end
  output = map(
    (e) -> "the program's output lacks #{e}",
    missing(plan["expect"], run[:output])
  )
  flat_map([release, control, status, output], (x) -> x)
end

@doc """
env_words: A plan's environment as `env` arguments.

    env_words({"A" => "1"}) #=> ["A=1"]
    env_words({}) #=> []
"""
def env_words(env)
  map((e) -> "#{first(e)}=#{second(e)}", map_entries(env))
end

def captured(argv)
  r = exec_capture(first(argv), *rest(argv))
  {status: status_of(r), output: "#{stdout_of(r)}#{stderr_of(r)}"}
end

def main()
  plan = json_read(read_file(argv[0]))
  env = append(["env"], env_words(get_or(plan, "env", {})))
  release = trim(read_file("/proc/sys/kernel/osrelease"))
  control = captured(
    append(env, %w[blue test --allow host], [plan["control"]["program"]])
  )
  run = captured(append(env, ["blue", plan["program"]]))
  write_stdout(
    unlines(
      [
        "release #{release}",
        "--- control, which must fail",
        control[:output],
        "--- #{plan["program"]}",
        run[:output]
      ]
    )
  )
  found = faults(
    plan,
    {
      release:,
      status: run[:status],
      output: run[:output],
      control_status: control[:status],
      control_output: control[:output]
    }
  )
  if found != []
    write_stdout(unlines(map((f) -> "🔴 vm: #{f}", found)))
    exit_with(1)
  end
  write_stdout(unlines(["🟢 vm: #{release}: control red, program green"]))
end

def plan()
  {
    "release" => "6.6.",
    "expect" => ["suite: 2 passed", "green"],
    "control" => {"expect" => ["1 passed, 1 failed"]}
  }
end

def good()
  {
    release: "6.6.119",
    status: 0,
    output: "suite: 2 passed, 0 failed green",
    control_status: 1,
    control_output: "2 test(s): 1 passed, 1 failed"
  }
end

test "a run that holds everything the plan names counts"
  assert faults(plan, good) == []
end

test "a green run on the wrong kernel does not count"
  got = faults(plan, assoc(good, :release, "6.12.93"))
  assert count(got) == 1
  assert contains?(first(got), "booted 6.12.93")
end

test "a control that passes, or fails for another reason, does not count"
  assert contains?(
    first(faults(plan, assoc(good, :control_status, 0))),
    "cannot go red"
  )
  other = assoc(good, :control_output, "no such file")
  assert contains?(first(faults(plan, other)), "did not fail as it must")
end

test "a program that exits red, or says nothing of what it ran, does not count"
  assert contains?(first(faults(plan, assoc(good, :status, 3))), "exited 3")
  silent = faults(plan, assoc(good, :output, ""))
  assert count(silent) == 2
  assert contains?(first(silent), "lacks suite: 2 passed")
end
