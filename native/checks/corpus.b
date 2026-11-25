use("chuuzou", [:cz_host_image])
use("kuzushi", [:REFUSED_EXIT])
use("moji", %i[after_first before_first trim])
use("retsu", [:first])
use("shisutemu", %i[status_of stderr_of stdout_of])

@doc """
run_of: How a command ran, as the corpus compares runs: its exact exit status (-1 for a death by a signal, so it never equals a raise's 1) and what it printed.

    run_of(["true"]) #=> {status: 0, out: ""}
"""
def run_of(args)
  r = exec_capture(*args)
  {status: status_of(r), out: stdout_of(r)}
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
built: The program at `program` lowered by `blue ast` and compiled by hashiru, blue's own x86-64 compiler, through gen/native-row.b (`X64_ROW`) in :run mode, as bench.b's bluec path does: `{image: path}`; `{refused: why}` when the driver exits REFUSED_EXIT, why being its stderr after the `native: ` it opens with (the kind, then hashiru's message); or `{crashed: what}` for any other failure, the lowering's included, which is no refusal.

    built("absent.b", "/nonexistent")[:crashed].nil? #=> false
"""
def built(program, work)
  out = image_of(program, work)
  ast = exec_capture(self_exe, "ast", program)
  if status_of(ast) != 0
    {crashed: "blue ast: #{trim(stderr_of(ast))}"}
  else
    write_file("#{out}.lisp", stdout_of(ast))
    b = exec_capture(
      self_exe,
      "run",
      "--quiet",
      env_required("X64_ROW"),
      "--",
      "#{out}.lisp",
      out,
      "run"
    )
    if status_of(b) == 0
      {image: out}
    elsif status_of(b) == REFUSED_EXIT
      {refused: after_first(trim(stderr_of(b)), "native: ")}
    else
      {crashed: "exit #{to_s(status_of(b))}: #{trim(stderr_of(b))}"}
    end
  end
end

@doc """
hashiru: The program at `program` compiled by hashiru (built) and run: the run as run_of gives it, or `{refused: why}` or `{crashed: what}` as built answers.

    hashiru("absent.b", "/nonexistent")[:crashed].nil? #=> false
"""
def hashiru(program, work)
  b = built(program, work)
  if b[:image].nil?
    b
  else
    run_of(["chmod", "+x", b.image])
    run_of([b.image])
  end
end

@doc """
difference: How the run `got` of the program at `program` differs from the interpreter's, or nil when it prints the same and ends with the same exit status. A run hashiru refused or crashed on is judged by ledger_breaks, not here.

    difference("absent.b", {refused: "no code"}) #=> nil
"""
def difference(program, got)
  if got[:refused].nil? and got[:crashed].nil?
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
refusal_rows: The programs hashiru may refuse and why, from the ledger text: one `name.b: why` per line, blank lines skipped, why being what the driver says after `native: ` (built). The ledger only shrinks, and its reasons are held: a program refused with no row, a row naming a program hashiru compiles, and a program refused for another reason than its row's are each red.

    refusal_rows(unlines(["", "sums.b: unsupported: no reclaim"])) #=> [{name: "sums.b", why: "unsupported: no reclaim"}]
"""
def refusal_rows(text)
  map(
    (l) -> {name: trim(before_first(l, ":")), why: trim(after_first(l, ":"))},
    filter((l) -> trim(l) != "", moji::lines(text))
  )
end

@doc """
ledger_breaks: Each way the hashiru `runs` (each `{name:, run:}`) break the ledger `rows` (refusal_rows): a crash, which no row can hold; a refusal the ledger has no row for; a refusal for another reason than its row's; and a row whose program now compiles.

    ledger_breaks([{name: "a.b", run: {refused: "x"}}, {name: "b.b", run: {status: 0, out: ""}}], [{name: "b.b", why: "y"}]) #=> ["a.b: refused with no ledger row: x", "b.b: compiles, so its ledger row goes"]
"""
def ledger_breaks(runs, rows)
  filter(
    (d) -> d != nil,
    map(
      fn(r)
        row = first(filter((w) -> w.name == r.name, rows))
        if not r.run[:crashed].nil?
          "#{r.name}: hashiru crashed, which is no refusal: #{r.run[:crashed]}"
        elsif not r.run[:refused].nil? and row.nil?
          "#{r.name}: refused with no ledger row: #{r.run[:refused]}"
        elsif not r.run[:refused].nil? and row.why != r.run[:refused]
          "#{r.name}: refused for another reason than its ledger row: the row says `#{row.why}`, hashiru says `#{r.run[:refused]}`"
        elsif r.run[:refused].nil? and not row.nil?
          "#{r.name}: compiles, so its ledger row goes"
        end
      end,
      runs
    )
  )
end

@doc """
RECORD: how to write the ledger again after a reason moves on purpose: every corpus program compiled (built), each refusal written as its row; it runs on any host, since only the compile is read.
"""
RECORD = "CORPUS_DIR=native/corpus X64_ROW=gen/native-row.b X64_REFUSED=native/checks/x64.refused BLUE_PATH=bidamas blue run native/checks/corpus.b record"

@doc """
ledger_text: The ledger rows for the compiled corpus `builds` (each `{name:, built:}`), one `name.b: why` per refusal in the order given; a crash raises, since a crash is never written down as a refusal.

    ledger_text([{name: "a.b", built: {refused: "unsupported: x"}}, {name: "b.b", built: {image: "b"}}]) #=> unlines(["a.b: unsupported: x"])
"""
def ledger_text(builds)
  crashed = filter((b) -> not b.built[:crashed].nil?, builds)
  if crashed != []
    raise(
      :crashed,
      "#{first(crashed).name}: hashiru crashed: #{first(crashed).built.crashed}"
    )
  end
  unlines(
    map(
      (b) -> "#{b.name}: #{b.built.refused}",
      filter((b) -> not b.built[:refused].nil?, builds)
    )
  )
end

def main()
  if argv_get(0) == "record"
    work = temp_dir("hashiru-record")
    write_file(
      env_required("X64_REFUSED"),
      ledger_text(
        map((p) -> {name: path_basename(p), built: built(p, work)}, programs)
      )
    )
  else
    write_stderr(unlines(["usage: #{RECORD}"]))
    exit_with(64)
  end
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

test "hashiru: a run that ends otherwise, a crash and a moved reason each break the ledger"
  rows = [{name: "a.b", why: "unsupported: no `x`"}]
  assert ledger_breaks(
    [{name: "a.b", run: {refused: "unsupported: no `x`"}}],
    rows
  ) == []
  assert ledger_breaks(
    [{name: "a.b", run: {refused: "unsupported: no `y`"}}],
    rows
  ) ==
    ["a.b: refused for another reason than its ledger row: the row says `unsupported: no `x``, hashiru says `unsupported: no `y``"]
  assert ledger_breaks(
    [{name: "a.b", run: {crashed: "exit 5: native: unbound: no slot"}}],
    rows
  ) ==
    ["a.b: hashiru crashed, which is no refusal: exit 5: native: unbound: no slot"]
  assert ledger_breaks([], []) == []
  assert difference("absent.b", {crashed: "exit 5"}).nil?
  assert (ledger_text([{name: "a.b", built: {crashed: "exit 5"}}]) rescue
    :crashed) == :crashed
  assert ledger_text([]) == ""
end

test "chuuzou and hashiru: a run agrees only when it prints the same and ends with the same status"
  fault = path_join(env_required("CORPUS_DIR"), "fault.b")
  want = interpret(fault)
  assert want.status == 1
  assert difference(fault, want).nil?
  assert difference(fault, {status: -1, out: want.out}) != nil
  assert difference(fault, {status: 0, out: want.out}) != nil
  assert run_of(%w[env blue-corpus-no-such-command]).status == 127
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
  breaks = ledger_breaks(runs, rows)
  if breaks != []
    write_stderr(
      unlines(append(breaks, ["record a moved reason with: #{RECORD}"]))
    )
  end
  assert breaks == []
  assert differ == []
end
