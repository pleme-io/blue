@moduledoc """
blue crash immunize: write a crash's regression lock beside the code it
crashed.

The CLI (`crates/blue-lang-cli/src/crash.rs`) resolves the crash, bisects it
to the fewest messages that still crash the target, renders each recorded
value as a blue literal and hands this program the plan as JSON: `argv` is
`["immunize", PLAN]`. This program appends two definitions to the plan's file
with `write_program`, so the file stays canonical:

- a helper that spawns the target with its recorded arguments, sends it those
  messages, and answers `:survived` when the target took them all (it
  finished, or it waits for more), else the reason it exited;
- a test declaring `satisfies: [:nist_ir_4]` and the target, asserting that
  the helper answers `:survived`.

On the crash's code the test is red, and the reason it prints is the crash.
It goes green when the target takes the input. A breach reproduces only under
the hold the crash ran under, and a test cannot declare a hold, so the program
prints the `blue test --allow` line that holds the test to it.
"""

@doc """
The name of the helper that replays the crash `plan` records.
"""
def helper_name(plan)
  "immunize_#{plan.short}"
end

@doc """
The helper and the test that lock the crash `plan` records, as lines of
blue.
"""
def lock_lines(plan)
  name = helper_name(plan)
  args = join(plan.args, ", ")
  sends = map((m) -> "  send(pid, #{m})", plan.messages)
  head = [
    "",
    "def #{name}()",
    "  pid = spawn(#{plan.target}, [#{args}])",
    "  ref = monitor(pid)"
  ]
  tail = [
    "  down = receive([:down, ref, :_, :_]) rescue [:down, ref, pid, :normal]",
    "  if down[3] == :normal",
    "    :survived",
    "  else",
    "    down[3]",
    "  end",
    "end",
    "",
    "test \"#{plan.target} takes the input that crashed it (b3:#{plan.short})\", {satisfies: [:#{plan.control}], target: #{plan.target}}",
    "  assert #{name} == :survived",
    "end"
  ]
  append(head, sends, tail)
end

@doc """
The command that runs the lock under the hold the crash ran under.
"""
def run_line(plan)
  allow = map((a) -> " --allow #{a}", plan.allow)
  "blue test#{join(allow, "")} #{plan.file}"
end

def immunize(plan)
  write_program(
    plan.file,
    unlines(append([read_file(plan.file)], lock_lines(plan)))
  )
  report = [
    "wrote #{helper_name(plan)} and its test to #{plan.file}",
    "input: #{length(plan.messages)} of #{plan.taken} messages taken (bisected)",
    "run: #{run_line(plan)}"
  ]
  write_stdout(unlines(report))
  true
end

def main()
  if argv[0] == "immunize"
    immunize(json_parse(argv[1]))
  else
    raise(:usage, "usage: blue crash immunize CRASH [--into FILE]")
  end
end

test "the lock spawns the target, sends each message and asserts it survived"
  plan = json_parse("{\"short\": \"abc\", \"target\": \"worker\", \"args\": [\"0\"], \"messages\": [\"\\\"poison\\\"\"], \"control\": \"nist_ir_4\", \"allow\": [\"none\"], \"file\": \"w.b\"}")
  lines = lock_lines(plan)
  assert lines[1] == "def immunize_abc()"
  assert lines[2] == "  pid = spawn(worker, [0])"
  assert lines[4] == "  send(pid, \"poison\")"
  assert lines[length(lines) - 2] == "  assert immunize_abc == :survived"
  assert run_line(plan) == "blue test --allow none w.b"
end

test "a crash with no hold runs its lock with no allow"
  plan = json_parse("{\"allow\": [], \"file\": \"w.b\", \"args\": [], \"messages\": []}")
  assert run_line(plan) == "blue test w.b"
end
