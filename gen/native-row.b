use("hashiru", [:compile_program])
use("kuzushi", %i[CRASHED_EXIT REFUSED_EXIT program_of row_outcome])

@doc """
mode_of: the mode a row compiles in, named by argv 2: :show (the default) writes the program's value as blue writes it and exits 0, :run runs it as a script (C3's benchmark), its value dropped and its exit status 0, and :exit ends with the value as the exit status, which only hashiru's own programs read, since a status cannot tell a value from a fault or one value from another.

    mode_of(%w[a b show]) #=> :show
    mode_of(%w[a b run]) #=> :run
    mode_of(%w[a b exit]) #=> :exit
    mode_of(%w[a b]) #=> :show
"""
def mode_of(args)
  if length(args) > 2 and args[2] == "run"
    :run
  elsif length(args) > 2 and args[2] == "exit"
    :exit
  else
    :show
  end
end

@doc """
compiled: the lowered forms compiled by hashiru in a mode, as kuzushi's row_outcome gives it: {value: the executable's bytes}, or {exit:, why:} when the compile raises, REFUSED_EXIT for a program hashiru has no code for yet and CRASHED_EXIT for a compile that breaks.

    compiled(read_forms("(frob 1)"), :show)[:exit] #=> REFUSED_EXIT
"""
def compiled(forms, mode)
  row_outcome("native", () -> compile_program(program_of(forms), mode))
end

@doc """
main: compile the lowered tree in argv 0 (`blue ast` output) to a static x86-64 executable at argv 1, in the mode argv 2 names (mode_of). A compile that raises ends with the status compiled gives, its kind and message on stderr: the conformance native column reads REFUSED_EXIT as blind and anything else as a crash, and the corpus check holds a refusal's reason to its ledger.
"""
def main()
  o = compiled(read_forms(read_file(argv_get(0))), mode_of(argv))
  if o[:exit] != nil
    write_stderr(unlines([o.why]))
    exit_with(o.exit)
  end
  write_bytes(argv_get(1), o.value)
end

test "a program hashiru compiles is executable bytes"
  assert length(compiled(read_forms("(+ 1 2)"), :show).value) > 0
end

test "a row compiles to write its value unless argv names run or exit"
  assert mode_of(%w[in out]) == :show
  assert mode_of(%w[in out show]) == :show
  assert mode_of(%w[in out run]) == :run
  assert mode_of(%w[in out exit]) == :exit
  assert length(compiled(read_forms("\"x\""), :show).value) > 0
end

test "a program hashiru has no code for is refused, and a compile that breaks is a crash"
  assert compiled(read_forms("(frob 1)"), :show) ==
    {
      exit: REFUSED_EXIT,
      why: "native: unsupported: hashiru: no reference-counted code for `frob` yet"
    }
  assert compiled(read_forms("(let (x 1) x)"), :show)[:exit] == CRASHED_EXIT
  assert length(compiled(read_forms("(list () (list))"), :show).value) > 0
end
