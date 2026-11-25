use("kuzushi", %i[CRASHED_EXIT REFUSED_EXIT ir_eval program_of row_outcome])
use("kyohi")

@doc """
main: run the resolved core in argv 0 (`blue ast --resolved` output) through B1's IR (kuzushi: A-normal form, closure conversion, Perceus with borrowed parameters, its evaluator) and write the value as a one-element list's literal. An error ends the run with the status kuzushi's row_outcome gives, the one contract both backend row drivers keep, its kind and message on stderr: REFUSED_EXIT for a row kuzushi refuses, which the conformance `ir` column reads as blind, and CRASHED_EXIT for any other error, which it reads as a crash; a reference the IR leaves live exits 4, naming it.
"""
def main()
  o = row_outcome(
    "ir",
    () -> ir_eval(program_of(read_forms(read_file(argv_get(0)))))
  )
  if o[:exit] != nil
    write_stderr(unlines([o.why]))
    exit_with(o.exit)
  end
  r = o.value
  if r[:live] != []
    write_stderr(unlines(r[:live]))
    exit_with(4)
  end
  write_stdout(unlines([to_s([r[:value]])]))
end

test "a program kuzushi accepts gives its value with nothing live"
  r = ir_eval(program_of(read_forms("(define (f x) (+ x x)) (f 4)")))
  assert r[:value] == 8
  assert r[:live] == []
end

test "a refusal and a recursion past the depth budget exit 3, anything else 5"
  assert row_outcome("ir", () -> raise(:ir_refused, "no `frob`"))[:exit] ==
    REFUSED_EXIT
  assert get(
    row_outcome("ir", () -> raise(read_forms(":depth-exceeded")[0], "deep")),
    :exit
  ) == REFUSED_EXIT
  assert row_outcome("ir", () -> raise(:type_mismatch, "list"))[:exit] ==
    CRASHED_EXIT
end

test "a program kuzushi has no code for is refused before it runs"
  assert kyohi::raised(() -> ir_eval(program_of(read_forms("(frob 1)")))) ==
    :ir_refused
end
