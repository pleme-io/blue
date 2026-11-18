use("hadome", %i[failures measurement parse])
use("junjo", [:sort_by])
use("moji", [:includes])
use("retsu", %i[is_empty size])
use("shisutemu", %i[read_or status_of stdout_of])
use("shuugou", [:unique])

BASELINE = "gen/mutation-census.baseline"

RECORD = "blue gen/mutation-census.b record"

KINDS = %w[mutation-set mutation-while mutation-redefine]

def head?(node, name)
  list?(node) and
    length(node) > 0 and
    symbol?(retsu::first(node)) and
    to_s(retsu::first(node)) == name
end

def zero()
  [0, 0, 0]
end

def plus(a, b)
  [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
end

def defined_names(forms)
  map(
    (f) -> to_s(f[1]),
    filter((f) -> head?(f, "define") and length(f) > 1 and symbol?(f[1]), forms)
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
  if head?(node, "set!")
    [1, 0, 0]
  elsif head?(node, "while")
    [0, 1, 0]
  elsif head?(node, "begin")
    [0, 0, redefined(defined_names(retsu::rest(node)))]
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
  ms = measured(blue_files)
  bad = retsu::flat_map(
    KINDS,
    fn(k)
      map(
        (f) -> f[:message],
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

test "tally counts set!, while and a repeated define in one block"
  forms = read_forms("(define (f) (begin (define a 0) (define a 1) (while (< a 3) (set! a (+ a 1))) a))")
  assert tally(forms[0]) == [1, 1, 1]
  assert tally(read_forms("(define (g) (begin (define a 0) a))")[0]) ==
    [0, 0, 0]
  assert tally(nil) == [0, 0, 0]
end
