use("kuzushi", [:ir_eval])
use("kyohi")

@doc """
program_of: the one form a lowered file runs as: its only form, or every form in one begin.

    program_of(read_forms("7")) #=> 7
    program_of(read_forms("(define (f) 1) (f)"))[0] == read_forms("begin")[0] #=> true
"""
def program_of(forms)
  if length(forms) == 1
    forms[0]
  else
    cons(read_forms("begin")[0], forms)
  end
end

@doc """
exit_for: the exit status for an error that ends the IR run: 3 (the row is refused, not counted) for kuzushi's refusal and for a recursion past blue's call-depth budget, which kuzushi's evaluator reaches before the walker does since it runs each IR call through several blue frames and loops no tail call; 5 (a crash) for anything else.

    exit_for(:ir_refused) #=> 3
    exit_for(:type_mismatch) #=> 5
"""
def exit_for(kind)
  if kind == :ir_refused or to_s(kind) == "depth-exceeded"
    3
  else
    5
  end
end

@doc """
main: run the resolved core in argv 0 (`blue ast --resolved` output) through B1's IR (kuzushi: A-normal form, closure conversion, Perceus with borrowed parameters, its evaluator) and write the value as a one-element list's literal. A row kuzushi refuses exits 3 (exit_for), naming why on stderr, which the conformance `ir` column reads as blind; a reference the IR leaves live exits 4, naming it; any other error in the IR exits 5, which the column reads as a crash.
"""
def main()
  r = begin
    ir_eval(program_of(read_forms(read_file(argv_get(0)))))
  rescue e
    write_stderr(unlines(["ir: #{to_s(e.kind)}: #{e.message}"]))
    exit_with(exit_for(e.kind))
  end
  if r[:live] != []
    write_stderr(unlines(r[:live]))
    exit_with(4)
  end
  write_stdout(unlines([to_s([r[:value]])]))
end

test "a lowered file of one form runs that form, and of several, one begin"
  assert program_of(read_forms("(+ 1 2)")) == read_forms("(+ 1 2)")[0]
  assert length(program_of(read_forms("(define (f) 1) (f)"))) == 3
end

test "a program kuzushi accepts gives its value with nothing live"
  r = ir_eval(program_of(read_forms("(define (f x) (+ x x)) (f 4)")))
  assert r[:value] == 8
  assert r[:live] == []
end

test "a refusal and a recursion past the depth budget exit 3, anything else 5"
  assert exit_for(:ir_refused) == 3
  assert exit_for(read_forms(":depth-exceeded")[0]) == 3
  assert exit_for(:type_mismatch) == 5
end

test "a program kuzushi has no code for is refused before it runs"
  assert kyohi::raised(() -> ir_eval(program_of(read_forms("(frob 1)")))) ==
    :ir_refused
end
