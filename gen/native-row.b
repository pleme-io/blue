use("hashiru", [:compile_program])

@doc """
program_of: the one form a lowered file compiles as: its only form, or every form in one begin.

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
mode_of: the mode a row compiles in: :show when argv names it third, else :exit.

    mode_of(%w[a b show]) #=> :show
    mode_of(%w[a b]) #=> :exit
"""
def mode_of(args)
  if length(args) > 2 and args[2] == "show"
    :show
  else
    :exit
  end
end

@doc """
main: compile the lowered tree in argv 0 (`blue ast` output) to a static x86-64 executable at argv 1 whose exit status is the program's value, or, with `show` as argv 2, that writes its value as blue writes it and exits 0 (hashiru's :show mode, for a value no exit status can carry). A program hashiru has no code for yet exits 3 and names the gap on stderr, which the conformance native column reads as blind, not as a failure.
"""
def main()
  forms = read_forms(read_file(argv_get(0)))
  code = begin
    compile_program(program_of(forms), mode_of(argv))
  rescue e
    write_stderr(unlines(["native: #{to_s(e.kind)}: #{e.message}"]))
    exit_with(3)
  end
  write_bytes(argv_get(1), code)
end

test "a lowered file of one form compiles that form, and of several, one begin"
  assert program_of(read_forms("(+ 1 2)")) == read_forms("(+ 1 2)")[0]
  b = program_of(read_forms("(define (f) 1) (f)"))
  assert length(b) == 3
end

test "a program hashiru compiles is executable bytes"
  assert length(compile_program(program_of(read_forms("(+ 1 2)")), :exit)) > 0
end

test "a third argument of show compiles the row to write its value"
  assert mode_of(%w[in out show]) == :show
  assert mode_of(%w[in out]) == :exit
  assert length(compile_program(program_of(read_forms("\"x\"")), :show)) > 0
end
