@moduledoc """
memory: the ownership facts kuzushi reads from a program (M2 of docs/PURE-BLUE.md).
`blue explain --memory FILE` lowers FILE with `blue ast --resolved` and prints one
fact per line, in order: today the last read of each local (M1's facts).

    facts_of("(define (sq x) (* x x))") #=> ["sq: last_use x (* x x)"]
"""

use("kuzushi", [:memory_facts])
use("retsu", %i[first is_empty])

@doc """
facts_of: The facts kuzushi reads from resolved forms written as text.

    facts_of("(define (k x) 1)") #=> []
"""
def facts_of(text)
  memory_facts(read_forms(text))
end

def main(args)
  if is_empty(args)
    write_stderr(unlines(["usage: blue explain --memory FILE"]))
    false
  else
    file = first(args)
    lowered = exec_capture(self_exe, "ast", "--resolved", file)
    if lowered.status != 0
      write_stderr(
        join_lines(
          ["blue explain --memory: #{file} does not lower", lowered.stderr]
        )
      )
      false
    else
      facts = facts_of(lowered.stdout)
      if not is_empty(facts)
        write_stdout(unlines(facts))
      end
      true
    end
  end
end

test "a program's facts are its locals' last reads, one per local", {
  kind: :integration
}
  assert facts_of("(define (f x) (let ((y (+ x 1))) (* y x)))") ==
    ["f: last_use y (* y x)", "f: last_use x (* y x)"]
  assert facts_of("(define (k x) 1)") == []
end

main(argv)
