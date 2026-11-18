use("hadome", %i[failures measurement parse])
use("junjo", [:sort_by])
use("kuzushi", [:head_is?])
use("moji", [:includes])
use("retsu", %i[is_empty size])
use("shisutemu", %i[read_or status_of stdout_of])
use("shuugou", [:unique])

BASELINE = "gen/mutation-census.baseline"

RECORD = "blue gen/mutation-census.b record"

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

def counts_of(path)
  r = exec_capture(self_exe, "ast", path)
  if status_of(r) != 0
    zero
  else
    reduce((acc, f) -> plus(acc, tally(f)), zero, read_forms(stdout_of(r)))
  end
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
      map((p) -> replace(p, "./", ""), walk_dir("."))
    )
  )
end

def measured(paths)
  retsu::flat_map(
    paths,
    fn(p)
      c = counts_of(p)
      filter(
        (m) -> m != nil,
        [
          if c[0] > 0
            {kind: KINDS[0], m: measurement(p, c[0])}
          end,
          if c[1] > 0
            {kind: KINDS[1], m: measurement(p, c[1])}
          end,
          if c[2] > 0
            {kind: KINDS[2], m: measurement(p, c[2])}
          end
        ]
      )
    end
  )
end

def rows_text(ms)
  join(
    map(
      (x) -> unlines(["#{x[:kind]}: #{x[:m][:key]} #{to_s(x[:m][:size])}"]),
      ms
    ),
    ""
  )
end

def record()
  ms = measured(blue_files)
  write_file(BASELINE, rows_text(ms))
  write_stdout(unlines(["recorded #{to_s(size(ms))} row(s) in #{BASELINE}"]))
end

def main()
  if argv_get(0) == "record"
    record
  else
    write_stderr(unlines(["usage: #{RECORD}"]))
    exit_with(64)
  end
end

test "no file gains a rebind past its recorded count, and a new file with one must be recorded"
  rows = parse(read_or(BASELINE, ""))
  assert size(blue_files) >= 500
  ms = measured(blue_files)
  bad = retsu::flat_map(
    KINDS,
    fn(k)
      map(
        (f) -> f[1],
        failures(rows, k, map((x) -> x[:m], filter((x) -> x[:kind] == k, ms)))
      )
    end
  )
  if not is_empty(bad)
    write_stderr(unlines(bad))
    write_stderr(unlines(["record a fall with: #{RECORD}"]))
  end
  assert is_empty(bad)
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
