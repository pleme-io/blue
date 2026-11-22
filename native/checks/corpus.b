use("chuuzou", [:cz_host_image])
use("moji", %i[before_first trim])
use("retsu", [:first])
use("shisutemu", %i[status_of stderr_of stdout_of])

def run_of(args)
  r = exec_capture(*args)
  {ok: second(first(r)) == 0, out: second(second(r))}
end

def interpret(program)
  run_of([self_exe, "run", "--quiet", program])
end

def image_of(program, work)
  path_join(work, replace(path_basename(program), ".b", ""))
end

def native(program, work)
  run_of(
    [
      cz_host_image(
        program,
        env_required("CORPUS_SEAM"),
        image_of(program, work)
      )
    ]
  )
end

@doc """
hashiru: The program at `program` compiled by hashiru, blue's own x86-64 compiler, and run: `blue ast` lowers it and gen/native-row.b (`X64_ROW`) compiles the tree in :run mode, as bench.b's bluec path does. Answers the run as `run_of` does, or `{refused: why}` naming what hashiru has no code for.

    hashiru("absent.b", "/nonexistent")[:refused].nil? #=> false
"""
def hashiru(program, work)
  out = image_of(program, work)
  ast = exec_capture(self_exe, "ast", program)
  if status_of(ast) != 0
    {refused: "blue ast: #{trim(stderr_of(ast))}"}
  else
    write_file("#{out}.lisp", stdout_of(ast))
    built = exec_capture(
      self_exe,
      "run",
      "--quiet",
      env_required("X64_ROW"),
      "--",
      "#{out}.lisp",
      out,
      "run"
    )
    if status_of(built) != 0
      {refused: trim(stderr_of(built))}
    else
      run_of(["chmod", "+x", out])
      run_of([out])
    end
  end
end

@doc """
difference: How the run `got` of the program at `program` differs from the interpreter's, or nil when it prints the same and ends the same. A run hashiru refused is judged by the ledger, not here.

    difference("absent.b", {refused: "no code"}) #=> nil
"""
def difference(program, got)
  if got[:refused].nil?
    want = interpret(program)
    if want != got
      "#{path_basename(program)}: interpreter #{to_s(want)}, native #{to_s(got)}"
    end
  end
end

def programs()
  filter((p) -> ends_with?(p, ".b"), ls(env_required("CORPUS_DIR")))
end

@doc """
refusal_rows: The programs hashiru may refuse, by name, from the ledger text: one `name.b: why` per line, blank lines skipped. The ledger only shrinks: a program refused with no row, or a row naming a program hashiru compiles, is red.

    refusal_rows(unlines(["", "sums.b: no reclaim"])) #=> ["sums.b"]
"""
def refusal_rows(text)
  map(
    (l) -> trim(before_first(l, ":")),
    filter((l) -> trim(l) != "", moji::lines(text))
  )
end

@doc """
ledger_breaks: Each way the hashiru `runs` (each `{name:, run:}`) break the ledger `rows`: a refusal the ledger has no row for, and a row whose program now compiles.

    ledger_breaks([{name: "a.b", run: {refused: "x"}}, {name: "b.b", run: {ok: true, out: ""}}], ["b.b"]) #=> ["a.b: refused with no ledger row: x", "b.b: compiles, so its ledger row goes"]
"""
def ledger_breaks(runs, rows)
  filter(
    (d) -> d != nil,
    map(
      fn(r)
        if not r.run[:refused].nil? and not member?(r.name, rows)
          "#{r.name}: refused with no ledger row: #{r.run[:refused]}"
        elsif r.run[:refused].nil? and member?(r.name, rows)
          "#{r.name}: compiles, so its ledger row goes"
        end
      end,
      runs
    )
  )
end

test "chuuzou and hashiru: the corpus is not empty and holds a failing run"
  assert count(programs) >= 6
  assert member?("fault.b", map(path_basename, programs))
end

test "chuuzou: every corpus program runs the same interpreted and native"
  work = path_join(temp_dir("chuuzou-corpus"), "chuuzou-corpus")
  assert filter(
    (d) -> d != nil,
    map((p) -> difference(p, native(p, work)), programs)
  ) == []
end

test "hashiru: each corpus program it compiles runs as interpreted"
  work = temp_dir("hashiru-corpus")
  runs = map(
    (p) -> {program: p, name: path_basename(p), run: hashiru(p, work)},
    programs
  )
  rows = refusal_rows(read_file(env_required("X64_REFUSED")))
  differ = filter(
    (d) -> d != nil,
    map((r) -> difference(r.program, r.run), runs)
  )
  refused = filter((r) -> not r.run[:refused].nil?, runs)
  write_stdout(
    unlines(
      [
        "hashiru corpus: #{count(runs)} programs, #{count(runs) - count(refused) - count(differ)} compiled and agreeing, #{count(refused)} refused (#{join(map((r) -> r.name, refused), ", ")})"
      ]
    )
  )
  assert ledger_breaks(runs, rows) == []
  assert differ == []
end
