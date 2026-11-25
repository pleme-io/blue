use("hadome", %i[blind failures parse row])
use("hikisuu", [:flag])
use("junjo", [:sort_by])
use("kuzushi", [:head_is?])
use("kyohi", %i[kinds ok ok? refusal refusal_of refused value why])
use("moji", %i[includes lines])
use("retsu", %i[first is_empty size])
use("shisutemu", %i[read_or status_of stderr_of stdout_of])
use("shuugou", [:unique])

BASELINE = "gen/mutation-census.baseline"

@doc """
root: the tree the census reads: $GEN_ROOT, where a nix check places its inputs, or the working directory.

    string?(root) #=> true
"""
def root()
  getenv("GEN_ROOT", ".")
end

RECORD = "blue gen/mutation-census.b record [--receipt \"<kind>: <why>\"]"

KINDS = %w[mutation-set mutation-while mutation-redefine]

def zero()
  [0, 0, 0]
end

def plus(a, b)
  [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
end

@doc """
defined_names: the names a block defines that an author wrote. A lowering temporary such as bind-subject holds a hyphen, which blue's syntax cannot spell, so no author's closure can hold it, and rebinding it is never seen: it is left out.

    defined_names(read_forms("(define a 1) (define bind-subject 2)")) #=> ["a"]
"""
def defined_names(forms)
  filter(
    (n) -> not includes(n, "-"),
    map(
      (f) -> to_s(f[1]),
      filter(
        (f) -> head_is?(f, "define") and length(f) > 1 and symbol?(f[1]),
        forms
      )
    )
  )
end

@doc """
redefined: how many names a `begin` block defines more than once, which is a rebind of a name a closure may already hold.

    redefined(["define", "a"]) #=> 0
"""
def redefined(names)
  length(names) - length(unique(names))
end

def own(node)
  if head_is?(node, "set!")
    [1, 0, 0]
  elsif head_is?(node, "while")
    [0, 1, 0]
  elsif head_is?(node, "begin")
    [0, 0, captured_rebinds(retsu::rest(node))]
  else
    zero
  end
end

@doc """
tally: the rebinds in one lowered form, as [set!, while, redefine] counts.

    tally(nil) #=> [0, 0, 0]
"""
def tally(node)
  if node.nil? or not list?(node)
    zero
  else
    reduce((acc, child) -> plus(acc, tally(child)), own(node), node)
  end
end

@doc """
read_of: the census of one `blue ast` run, as a kyohi result: ok of the [set!, while, redefine] counts of the tree it printed, or refused as blind when it could not read the file, which is never zero rebinds.

    value(read_of([[:status, 0], [:stdout, "(define (f) (set! a 1))"], [:stderr, ""]])) #=> [1, 0, 0]
    kinds([refusal_of(read_of([[:status, 1], [:stdout, ""], [:stderr, "parse error"]]))]) #=> [:blind]
"""
def read_of(r)
  if status_of(r) != 0
    said = first(lines(stderr_of(r))) or ""
    refused(refusal(:blind, "blue ast exited #{to_s(status_of(r))}: #{said}"))
  else
    ok(reduce((acc, f) -> plus(acc, tally(f)), zero, read_forms(stdout_of(r))))
  end
end

def counts_of(path)
  read_of(exec_capture(self_exe, "ast", path_join(root, path)))
end

def blue_files()
  sort_by(
    (p) -> p,
    filter(
      fn(p)
        ends_with?(p, ".b") and
          not includes(p, "/target/") and
          not includes(p, "/.git/") and
          not includes(p, "/result")
      end,
      map((p) -> replace(p, "#{root}/", ""), walk_dir(root))
    )
  )
end

@doc """
rows_of: the census rows of one file's read: a row for each kind it holds at least one of, or, when the file could not be read, a blind row for every kind.

    rows_of("a.b", ok([2, 0, 1])) #=> [row("mutation-set", "a.b", 2), row("mutation-redefine", "a.b", 1)]
"""
def rows_of(path, read)
  if ok?(read)
    c = value(read)
    retsu::flat_map(
      range(0, size(KINDS)),
      fn(i)
        if c[i] > 0
          [row(KINDS[i], path, c[i])]
        else
          []
        end
      end
    )
  else
    map((k) -> blind(k, path, why(refusal_of(read))), KINDS)
  end
end

def measured(paths)
  retsu::flat_map(paths, (p) -> rows_of(p, counts_of(p)))
end

@doc """
failed: every row of a census that grew, is new, or is blind, as its message.

    failed([], []) #=> []
"""
def failed(rows, ms)
  retsu::flat_map(
    KINDS,
    (k) -> map((f) -> f[1], failures(rows, k, filter((m) -> m[:kind] == k, ms)))
  )
end

def record(receipt)
  got = hadome::record(
    path_join(root, BASELINE),
    measured(blue_files),
    {receipt:}
  )
  if ok?(got)
    write_stdout(
      unlines(["recorded #{to_s(value(got))} row(s) in #{BASELINE}"])
    )
  else
    write_stderr(unlines([why(refusal_of(got)), "usage: #{RECORD}"]))
    exit_with(1)
  end
end

def main()
  if argv_get(0) == "record"
    record(flag(argv, "--receipt"))
  else
    write_stderr(unlines(["usage: #{RECORD}"]))
    exit_with(64)
  end
end

test "no file gains a rebind past its recorded count, a new file with one must be recorded, and no file is blind"
  rows = parse(read_or(path_join(root, BASELINE), ""))
  assert size(blue_files) >= 500
  bad = failed(rows, measured(blue_files))
  if not is_empty(bad)
    write_stderr(unlines(bad))
    write_stderr(
      unlines(
        ["a file that gained a rebind is recorded with its reason: #{RECORD}"]
      )
    )
  end
  assert is_empty(bad)
end

test "a file blue ast cannot read is blind in every kind, never zero rebinds, and a blind census is red"
  read = read_of([[:status, 1], [:stdout, ""], [:stderr, "1:5: parse error"]])
  got = rows_of("b/three.b", read)
  assert map((r) -> r[:kind], got) == KINDS
  assert failed([], got) ==
    map(
      (k) -> "#{k}: b/three.b is blind: blue ast exited 1: 1:5: parse error",
      KINDS
    )
  assert failed([], rows_of("b/two.b", ok([0, 0, 0]))) == []
end

test "a record banks a fall, and refuses a gained rebind with no receipt and a blind file with one"
  path = path_join(temp_dir("census"), "census.baseline")
  write_file(path, unlines(["mutation-set: a.b 3"]))
  assert value(hadome::record(path, rows_of("a.b", ok([1, 0, 0])), {})) == 1
  assert read_file(path) == unlines(["mutation-set: a.b 1"])
  up = hadome::record(path, rows_of("a.b", ok([2, 0, 0])), {})
  assert kinds([refusal_of(up)]) == [:unreceipted]
  blinded = hadome::record(
    path,
    rows_of("a.b", refused(refusal(:blind, "unread"))),
    {receipt: "measurement: a.b"}
  )
  assert kinds([refusal_of(blinded)]) == [:blind]
  assert read_file(path) == unlines(["mutation-set: a.b 1"])
end

test "tally counts set!, while and a captured repeated define in one block"
  forms = read_forms("(define (f) (begin (define a 0) (define g (lambda () a)) (define a 1) (while (< a 3) (set! a (+ a 1))) a))")
  assert tally(forms[0]) == [1, 1, 1]
  assert tally(read_forms("(define (g) (begin (define a 0) a))")[0]) ==
    [0, 0, 0]
  assert tally(nil) == [0, 0, 0]
end

test "a lowering temporary defined twice is no rebind, an author's name is"
  b = nth(
    0,
    read_forms("(begin (define bind-subject 1) (define bind-subject 2) (define x 1) (define g (lambda () (+ x bind-subject))) (define x 2))")
  )
  assert tally(b) == [0, 0, 1]
end

@doc """
reads?: whether a tree reads a name anywhere.

    reads?(read_forms("(+ a 1)")[0], "a") #=> true
"""
def reads?(node, name)
  if symbol?(node)
    to_s(node) == name
  elsif list?(node)
    retsu::find_first((c) -> reads?(c, name), node) != nil
  else
    false
  end
end

@doc """
lambdas_in: every lambda anywhere in a tree.

    length(lambdas_in(read_forms("(f (lambda (x) x))")[0])) #=> 1
"""
def lambdas_in(node)
  if not list?(node)
    []
  elsif head_is?(node, "lambda")
    [node]
  else
    retsu::flat_map(node, lambdas_in)
  end
end

@doc """
captured_rebinds: how many names a block defines more than once that a closure in the block reads: the rebinds a closure can see change. A name defined again with no closure holding it is a fresh value under an old name, which no one can observe.

    captured_rebinds(read_forms("(define a 1) (define a 2)")) #=> 0
    captured_rebinds(read_forms("(define a 1) (define f (lambda () a)) (define a 2)")) #=> 1
"""
def captured_rebinds(forms)
  names = defined_names(forms)
  twice = filter((n) -> length(filter((m) -> m == n, names)) > 1, unique(names))
  closures = retsu::flat_map(forms, lambdas_in)
  length(
    filter(
      (n) -> retsu::find_first((l) -> reads?(l, n), closures) != nil,
      twice
    )
  )
end

test "a name defined again counts only when a closure in the block reads it"
  plain = read_forms("(begin (define s 1) (define s (+ s 1)) s)")[0]
  assert tally(plain) == [0, 0, 0]
  held = nth(
    0,
    read_forms("(begin (define s 1) (define f (lambda () s)) (define s 2) (f))")
  )
  assert tally(held) == [0, 0, 1]
end
