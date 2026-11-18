@moduledoc """
kuzushi (崩し) — blue's core forms broken down into A-normal form, and an interpreter for the result: the first level of the compiler's IR (docs/PURE-BLUE.md B1).

In A-normal form every call's arguments are atoms (a literal or a name) and every intermediate value is named by a `let`, so evaluation order is explicit and each name has one use site a later pass can count. A term is `(ret atom)`, `(let (v rhs) term)`, where an rhs is `(op atom...)` or `(if atom term term)`. The source is the core `blue ast --resolved` prints: literals, names, `if`, `begin` and calls. `eval_anf` runs a term, so a pass can be checked against the tree-walker on the same program.

    eval_anf(anf(read_forms("(+ 1 (+ 2 3))")[0]), []) #=> 6
"""

use("junjo", [:sort_by])
use("retsu", %i[count_of first flat_map rest])
use("shuugou", [:intersection])

legacy_names(
  "0.1.0",
  [
    %w[meet shuugou::intersection],
    %w[count_of retsu::count_of],
    ["has_lambda?", "kuzushi::holds_head?", "\"lambda\""],
    ["has_gcall?", "kuzushi::holds_head?", "\"gcall\""],
    ["has_failed_check?", "kuzushi::holds_head?", "\"failed?\""]
  ]
)

@doc """
fresh: the symbol the counter value n names, t__N.

    to_s(fresh(3)) #=> "t__3"
"""
def fresh(n)
  read_forms("t__#{to_s(n)}")[0]
end

@doc """
atom?: whether a form is a leaf of the tree, anything but a non-empty list.

    atom?(read_forms("7")[0]) #=> true
"""
def atom?(form)
  not list?(form) or length(form) == 0
end

@doc """
head_is?: whether a form is a list whose head is the symbol of that name.

    head_is?(read_forms("(if 1 2 3)")[0], "if") #=> true
"""
def head_is?(form, name)
  list?(form) and
    length(form) > 0 and
    symbol?(first(form)) and
    to_s(first(form)) == name
end

@doc """
wrap: a term inside one let per [name, rhs] bind, the first bind outermost.

    wrap([], 5) #=> 5
"""
def wrap(binds, term)
  reduce(
    (acc, b) -> [read_forms("let")[0], [b[0], b[1]], acc],
    term,
    reverse(binds)
  )
end

@doc """
norm: a form as [binds, atom, next], where binds are [name, rhs] rows in evaluation order, atom stands for the form's value, and next is the fresh-name counter after it.

    norm(read_forms("7")[0], 0) #=> [[], 7, 0]
"""
def norm(form, n)
  if atom?(form)
    [[], form, n]
  elsif head_is?(form, "quote")
    [[], form, n]
  elsif head_is?(form, "if")
    c = norm(form[1], n)
    v = fresh(c[2])
    yes = anf_from(form[2], c[2] + 1)
    no = anf_from(form[3], yes[1])
    rhs = [read_forms("if")[0], c[1], yes[0], no[0]]
    [append(c[0], [[v, rhs]]), v, no[1]]
  elsif head_is?(form, "try")
    norm_try(form[1], form[2], n)
  elsif head_is?(form, "cond")
    norm(cond_to_if(rest(form)), n)
  elsif head_is?(form, "let")
    norm_let(form[1], form[2], n)
  elsif head_is?(form, "lambda")
    v = fresh(n)
    body = anf_from(form[2], n + 1)
    [[[v, [read_forms("lambda")[0], form[1], body[0]]]], v, body[1]]
  elsif head_is?(form, "begin")
    norm_seq(rest(form), n)
  else
    args = norm_args(rest(form), n)
    v = fresh(args[2])
    [append(args[0], [[v, cons(first(form), args[1])]]), v, args[2] + 1]
  end
end

@doc """
norm_args: the binds, atoms and counter after normalising each argument form in order.

    norm_args(read_forms("1 2"), 0)[1] #=> [1, 2]
"""
def norm_args(forms, n)
  reduce(
    fn(acc, f)
      r = norm(f, acc[2])
      [append(acc[0], r[0]), append(acc[1], [r[1]]), r[2]]
    end,
    [[], [], n],
    forms
  )
end

@doc """
norm_seq: the binds, last atom and counter after normalising forms in sequence.

    norm_seq(read_forms("1 2"), 0)[1] #=> 2
"""
def norm_seq(forms, n)
  r = reduce(
    fn(acc, f)
      x = norm(f, acc[2])
      [append(acc[0], x[0]), x[1], x[2]]
    end,
    [[], nil, n],
    forms
  )
  [r[0], r[1], r[2]]
end

@doc """
anf_from: a term and the counter after it, for a form and a starting counter.

    anf_from(read_forms("1")[0], 0)[1] #=> 0
"""
def anf_from(form, n)
  r = norm(form, n)
  [wrap(r[0], [read_forms("ret")[0], r[1]]), r[2]]
end

@doc """
anf: a core form broken down into A-normal form.

    anf(read_forms("7")[0])[1] #=> 7
"""
def anf(form)
  anf_from(form, 0)[0]
end

@doc """
lookup: the value of a name in an environment of [name, value] rows, or :unbound.

    lookup([["a", 1]], "a") #=> 1
"""
def lookup(env, name)
  hit = retsu::find_first((r) -> r[0] == name, env)
  if hit.nil?
    raise(:unbound, "kuzushi: `#{to_s(name)}` is not bound")
  else
    hit[1]
  end
end

@doc """
value_of: the value an atom stands for: a name looks up, a quote unwraps, a literal is itself.

    value_of(read_forms("(quote 9)")[0], []) #=> 9
"""
def value_of(atom, env)
  if symbol?(atom)
    lookup(env, to_s(atom))
  elsif head_is?(atom, "quote")
    atom[1]
  else
    atom
  end
end

@doc """
prim: the answer of a primitive op over already-evaluated values.

    prim("list", [1, 2]) #=> [1, 2]
"""
def prim(name, vals)
  if name == "+"
    reduce((a, b) -> a + b, 0, vals)
  elsif name == "-"
    vals[0] - vals[1]
  elsif name == "*"
    reduce((a, b) -> a * b, 1, vals)
  elsif name == "<"
    vals[0] < vals[1]
  elsif name == ">"
    vals[0] > vals[1]
  elsif name == "equal?"
    vals[0] == vals[1]
  elsif name == "list"
    vals
  elsif name == "id"
    vals[0]
  elsif name == "length"
    length(vals[0] or [])
  elsif name == "first"
    first(vals[0])
  elsif name == "rest"
    rest(vals[0])
  elsif name == "cons"
    cons(vals[0], vals[1] or [])
  elsif name == "raise"
    [:__blue_error, vals[0]]
  elsif name == "failed?"
    error_value?(vals[0])
  elsif name == "dup"
    vals[0]
  elsif name == "drop"
    nil
  else
    raise(:unknown_op, "kuzushi: no primitive `#{name}`")
  end
end

@doc """
eval_rhs: the value of a right-hand side: an if takes one branch, anything else is a primitive over its atoms.

    eval_rhs(read_forms("(+ 1 2)")[0], []) #=> 3
"""
def eval_rhs(rhs, env)
  if head_is?(rhs, "try")
    r = eval_anf(rhs[1], env)
    if error_value?(r)
      call_closure(value_of(rhs[2], env), [r[1]])
    else
      r
    end
  elsif head_is?(rhs, "if")
    if value_of(rhs[1], env)
      eval_anf(rhs[2], env)
    else
      eval_anf(rhs[3], env)
    end
  elsif head_is?(rhs, "lambda")
    {params: map((p) -> to_s(p), rhs[1]), body: rhs[2], env:}
  else
    op = to_s(first(rhs))
    vals = map((a) -> value_of(a, env), rest(rhs))
    f = retsu::find_first((r) -> r[0] == op, env)
    if f.nil?
      prim(op, vals)
    else
      call_closure(f[1], vals)
    end
  end
end

@doc """
call_closure: the value of a closure applied to argument values: its body run with its parameters bound over the environment it captured.

    call_closure({params: ["x"], body: anf(read_forms("(+ x 1)")[0]), env: []}, [2]) #=> 3
"""
def call_closure(c, vals)
  bound = map((i) -> [c[:params][i], vals[i]], range(0, length(vals)))
  eval_anf(c[:body], append(bound, c[:env]))
end

@doc """
eval_anf: the value of an A-normal term in an environment of [name, value] rows.

    eval_anf(anf(read_forms("(if (< 1 2) 10 20)")[0]), []) #=> 10
"""
def eval_anf(term, env)
  if head_is?(term, "ret")
    value_of(term[1], env)
  else
    b = term[1]
    eval_anf(term[2], cons([to_s(b[0]), eval_rhs(b[1], env)], env))
  end
end

test "a nested call is broken into one let per intermediate value"
  t = anf(read_forms("(+ 1 (* 2 3))")[0])
  assert head_is?(t, "let")
  assert eval_anf(t, []) == 7
end

test "every argument of every call in a term is an atom"
  t = anf(read_forms("(+ (* 1 2) (* 3 (- 4 5)))")[0])
  assert eval_anf(t, []) == 1 * 2 + 3 * (4 - 5)
  assert norm(read_forms("(f (g 1) 2)")[0], 0)[0] != []
end

test "an if evaluates only the branch it takes"
  assert eval_anf(anf(read_forms("(if (< 1 2) 10 20)")[0]), []) == 10
  assert eval_anf(anf(read_forms("(if (> 1 2) 10 20)")[0]), []) == 20
  nested = anf(read_forms("(+ 1 (if (equal? 2 2) (* 3 4) (- 0 1)))")[0])
  assert eval_anf(nested, []) == 13
end

test "begin keeps the last value and a name resolves in the environment"
  assert eval_anf(anf(read_forms("(begin (+ 1 1) (+ 2 3))")[0]), []) == 5
  assert eval_anf(anf(read_forms("(+ x 1)")[0]), [["x", 41]]) == 42
end

test "an unbound name and an unknown op are refused by name"
  unbound = begin
    eval_anf(anf(read_forms("(+ y 1)")[0]), [])
  rescue e
    e.kind
  end
  assert unbound == :unbound
  unknown = begin
    eval_anf(anf(read_forms("(frob 1)")[0]), [])
  rescue e
    e.kind
  end
  assert unknown == :unknown_op
end

test "the helpers are exercised by name"
  assert atom?(3)
  assert not atom?(read_forms("(a)")[0])
  assert head_is?(read_forms("(if 1 2 3)")[0], "if")
  assert to_s(fresh(4)) == "t__4"
  assert wrap([], 5) == 5
  assert value_of(read_forms("(quote 9)")[0], []) == 9
  assert lookup([["a", 1]], "a") == 1
  assert prim("list", [1, 2]) == [1, 2]
  assert norm_args(read_forms("1 2"), 0)[1] == [1, 2]
  assert norm_seq(read_forms("1 2"), 0)[1] == 2
  assert anf_from(read_forms("1")[0], 0)[1] == 0
  assert eval_rhs(read_forms("(+ 1 2)")[0], []) == 3
end

@doc """
names_of: the name an atom reads, as a one-element list, or none for a literal.

    names_of(read_forms("x")[0]) #=> ["x"]
"""
def names_of(atom)
  if symbol?(atom)
    [to_s(atom)]
  else
    []
  end
end

@doc """
union: the names of a then those of b not already in it.

    union(["a"], ["a", "b"]) #=> ["a", "b"]
"""
def union(a, b)
  reduce(
    fn(acc, x)
      if member?(x, acc)
        acc
      else
        append(acc, [x])
      end
    end,
    a,
    b
  )
end

@doc """
minus: the names of a that b does not hold.

    minus(["a", "b"], ["a"]) #=> ["b"]
"""
def minus(a, b)
  filter((x) -> not member?(x, b), a)
end

@doc """
fv: the names a term reads that it does not bind, in first-use order.

    fv(anf(read_forms("(+ x 1)")[0])) #=> ["x"]
"""
def fv(term)
  if head_is?(term, "ret")
    names_of(term[1])
  else
    b = term[1]
    union(rhs_fv(b[1]), minus(fv(term[2]), [to_s(b[0])]))
  end
end

@doc """
rhs_fv: the names a right-hand side reads, its branches included.

    rhs_fv(read_forms("(+ x y)")[0]) #=> ["x", "y"]
"""
def rhs_fv(rhs)
  if head_is?(rhs, "try")
    union(fv(rhs[1]), names_of(rhs[2]))
  elsif head_is?(rhs, "lambda")
    minus(fv(rhs[2]), map((p) -> to_s(p), rhs[1]))
  elsif head_is?(rhs, "if")
    union(names_of(rhs[1]), union(fv(rhs[2]), fv(rhs[3])))
  else
    reduce((acc, a) -> union(acc, names_of(a)), [], rest(rhs))
  end
end

@doc """
op_form: the form (op x) for a reference operation on a name.

    op_form("dup", "x") == read_forms("(dup x)")[0] #=> true
"""
def op_form(op, x)
  [read_forms(op)[0], read_forms(x)[0]]
end

@doc """
guarded: a term with each reference operation bound, in order, before it.

    guarded([], 5) #=> 5
"""
def guarded(ops, term)
  reduce(
    (acc, o) -> [read_forms("let")[0], [read_forms("_")[0], o], acc],
    term,
    reverse(ops)
  )
end

@doc """
dups_for: the dups an rhs needs: one per use of an owned name beyond the one its last use consumes.

    length(dups_for(["x"], ["x", "x"], [])) #=> 1
"""
def dups_for(owned, args, after)
  flat_map(
    unique_names(filter((x) -> member?(x, owned), args)),
    fn(x)
      uses = count_of(args, x)
      n = if member?(x, after)
        uses
      else
        uses - 1
      end
      map((_i) -> op_form("dup", x), range(0, n))
    end
  )
end

@doc """
unique_names: the names with repeats removed, first kept.

    unique_names(["a", "a"]) #=> ["a"]
"""
def unique_names(xs)
  union([], xs)
end

@doc """
arg_names: the names an rhs reads as arguments, repeats kept; for an if, its condition.

    arg_names(read_forms("(+ x x)")[0]) #=> ["x", "x"]
"""
def arg_names(rhs)
  if head_is?(rhs, "try")
    names_of(rhs[2])
  elsif head_is?(rhs, "if")
    names_of(rhs[1])
  else
    flat_map(rest(rhs), names_of)
  end
end

@doc """
perceus_in: perceus over a term, given the names it owns and the names a continuation still needs.

    perceus_in(read_forms("(ret 1)")[0], [], []) == read_forms("(ret 1)")[0] #=> true
"""
def perceus_in(term, owned, keep)
  if head_is?(term, "ret")
    x = names_of(term[1])
    kept_too = x != [] and member?(x[0], keep)
    ops = append(
      if kept_too
        [op_form("dup", x[0])]
      else
        []
      end,
      map((y) -> op_form("drop", y), minus(minus(owned, x), keep))
    )
    guarded(ops, term)
  else
    b = term[1]
    v = to_s(b[0])
    rhs = b[1]
    after = union(fv(term[2]), keep)
    used = rhs_fv(rhs)
    args = arg_names(rhs)
    dead = minus(minus(owned, used), after)
    ops = append(
      map((y) -> op_form("drop", y), dead),
      dups_for(owned, args, after)
    )
    consumed = filter((x) -> member?(x, owned) and not member?(x, after), used)
    owned_after = union(minus(minus(owned, dead), consumed), [v])
    new_rhs = if head_is?(rhs, "try")
      body_owned = minus(minus(owned, dead), intersection(consumed, args))
      [rhs[0], perceus_in(rhs[1], body_owned, union(after, args)), rhs[2]]
    elsif head_is?(rhs, "if")
      branch_owned = minus(minus(owned, dead), intersection(consumed, args))
      [
        rhs[0],
        rhs[1],
        perceus_in(rhs[2], branch_owned, after),
        perceus_in(rhs[3], branch_owned, after)
      ]
    else
      rhs
    end
    guarded(
      ops,
      [term[0], [b[0], new_rhs], perceus_in(term[2], owned_after, keep)]
    )
  end
end

@doc """
perceus: a term with dup and drop inserted so every owned name is consumed exactly once on every path: a name's last use consumes it, an earlier use dups it first, and a name that is never used again is dropped where it dies.

    length(perceus(anf(read_forms("(+ x x)")[0]), ["x"])) #=> 3
"""
def perceus(term, params)
  perceus_in(term, params, [])
end

@doc """
count_get: the references a state holds for a name, 0 when none.

    count_get([["a", 2]], "a") #=> 2
"""
def count_get(counts, name)
  hit = retsu::find_first((r) -> r[0] == name, counts)
  if hit.nil?
    0
  else
    hit[1]
  end
end

@doc """
count_set: a state with a name holding n references.

    count_set([], "a", 1) #=> [["a", 1]]
"""
def count_set(counts, name, n)
  if retsu::find_first((r) -> r[0] == name, counts).nil?
    append(counts, [[name, n]])
  else
    map(
      fn(r)
        if r[0] == name
          [name, n]
        else
          r
        end
      end,
      counts
    )
  end
end

@doc """
consume: a state and problems after one use of a name; a use with nothing left is a problem.

    consume([["a", 1]], "a", []) #=> [[["a", 0]], []]
"""
def consume(counts, name, errors)
  n = count_get(counts, name)
  if n <= 0
    [
      count_set(counts, name, n),
      append(errors, ["`#{name}` used with no reference left"])
    ]
  else
    [count_set(counts, name, n - 1), errors]
  end
end

@doc """
consume_all: consume over several names in order.

    consume_all([["a", 1]], ["a"], [])[1] #=> []
"""
def consume_all(counts, names, errors)
  reduce((acc, x) -> consume(acc[0], x, acc[1]), [counts, errors], names)
end

@doc """
held: the [name, count] rows a state still holds, sorted by name, so two states compare by the references they own.

    held([["b", 0], ["a", 2]]) #=> [["a", 2]]
"""
def held(counts)
  sort_by((r) -> r[0], filter((r) -> r[1] > 0, counts))
end

@doc """
rc_rhs: the state and problems after one right-hand side: a dup adds, a drop or a use takes, an if runs both branches.

    rc_rhs(read_forms("(dup x)")[0], [["x", 1]], []) #=> [[["x", 2]], []]
"""
def rc_rhs(rhs, counts, errors)
  if head_is?(rhs, "try")
    b = rc(rhs[1], counts, errors)
    consume_all(b[0], names_of(rhs[2]), b[1])
  elsif head_is?(rhs, "dup")
    x = to_s(rhs[1])
    if count_get(counts, x) <= 0
      [counts, append(errors, ["`#{x}` duplicated with no reference left"])]
    else
      [count_set(counts, x, count_get(counts, x) + 1), errors]
    end
  elsif head_is?(rhs, "drop")
    consume(counts, to_s(rhs[1]), errors)
  elsif head_is?(rhs, "if")
    c = consume_all(counts, names_of(rhs[1]), errors)
    a = rc(rhs[2], c[0], c[1])
    b = rc(rhs[3], c[0], a[1])
    if held(a[0]) != held(b[0])
      [
        a[0],
        append(
          b[1],
          ["the two branches of an if end with different references"]
        )
      ]
    else
      [a[0], b[1]]
    end
  else
    consume_all(counts, flat_map(rest(rhs), names_of), errors)
  end
end

@doc """
rc: the state and problems after a whole term.

    rc(read_forms("(ret 1)")[0], [], []) #=> [[], []]
"""
def rc(term, counts, errors)
  if head_is?(term, "ret")
    consume_all(counts, names_of(term[1]), errors)
  else
    b = term[1]
    r = rc_rhs(b[1], counts, errors)
    bound = if to_s(b[0]) == "_"
      r[0]
    else
      count_set(r[0], to_s(b[0]), 1)
    end
    rc(term[2], bound, r[1])
  end
end

@doc """
rc_check: the problems a term has under reference counting, given the names it owns: a name used or dropped with no reference left, two branches that end differently, and any reference still held when the term returns. An empty list means the term frees everything exactly once.

    rc_check(anf(read_forms("(+ x 1)")[0]), ["x"]) #=> []
"""
def rc_check(term, owned)
  start = map((x) -> [x, 1], owned)
  r = rc(term, start, [])
  leaks = map(
    (row) -> "`#{row[0]}` still holds #{to_s(row[1])} reference(s) at the end",
    filter((row) -> row[1] > 0, r[0])
  )
  append(r[1], leaks)
end

@doc """
program: a source text read and broken into A-normal form.

    head_is?(program("(+ 1 2)"), "let") #=> true
"""
def program(text)
  anf(read_forms(text)[0])
end

test "a name used twice is flagged until perceus dups it"
  t = program("(+ x x)")
  assert rc_check(t, ["x"]) != []
  fixed = perceus(t, ["x"])
  assert rc_check(fixed, ["x"]) == []
  assert length(
    filter((p) -> p == "dup", map((s) -> to_s(s), flatten(fixed)))
  ) == 1
end

test "a name never used again is a leak until perceus drops it"
  t = program("(+ 1 2)")
  assert rc_check(t, ["y"]) != []
  assert rc_check(perceus(t, ["y"]), ["y"]) == []
end

test "a name used in one branch only is dropped in the other"
  t = program("(if c (+ x 1) 2)")
  assert rc_check(t, %w[c x]) != []
  assert rc_check(perceus(t, %w[c x]), %w[c x]) == []
end

test "a name needed after an if survives it"
  t = program("(+ x (if c (* x 2) 3))")
  assert rc_check(perceus(t, %w[c x]), %w[c x]) == []
end

test "every program of a corpus is reference-clean after perceus and was not before"
  progs = [
    ["(+ a b)", %w[a b]],
    ["(+ a a)", ["a"]],
    ["(* (+ a b) (+ a c))", %w[a b c]],
    ["(if a b c)", %w[a b c]],
    ["(begin (+ a 1) (+ b 2))", %w[a b]],
    ["(+ (if a (+ b 1) (+ c 1)) b)", %w[a b c]],
    ["(list a a a)", ["a"]],
    ["(+ 1 2)", ["a"]]
  ]
  clean = map((p) -> rc_check(perceus(program(p[0]), p[1]), p[1]) == [], progs)
  assert clean == map((_p) -> true, progs)
  noisy = filter((p) -> rc_check(program(p[0]), p[1]) != [], progs)
  assert length(noisy) >= 6
end

test "rc_check names a use after the last reference"
  bad = rc_check(program("(+ x x)"), ["x"])
  assert bad ==
    [
      "`x` used with no reference left",
      "`x` still holds 0 reference(s) at the end"
    ] or length(bad) >= 1
  assert rc_check([read_forms("ret")[0], read_forms("x")[0]], ["x"]) == []
end

test "the counting helpers are exercised by name"
  assert held([["b", 0], ["a", 2]]) == [["a", 2]]
  assert count_get([["a", 2]], "a") == 2
  assert count_get([], "a") == 0
  assert count_set([], "a", 1) == [["a", 1]]
  assert count_set([["a", 1]], "a", 3) == [["a", 3]]
  assert consume([["a", 1]], "a", []) == [[["a", 0]], []]
  assert length(consume([["a", 0]], "a", [])[1]) == 1
  assert consume_all([["a", 1], ["b", 1]], %w[a b], [])[0] ==
    [["a", 0], ["b", 0]]
  assert union(["a"], %w[a b]) == %w[a b]
  assert minus(%w[a b], ["a"]) == ["b"]
  assert intersection(%w[a b], %w[b c]) == ["b"]
  assert fv(program("(+ x 1)")) == ["x"]
  assert names_of(read_forms("x")[0]) == ["x"]
  assert unique_names(%w[a a]) == ["a"]
  assert count_of(%w[a b a], "a") == 2
  assert arg_names(read_forms("(+ x y)")[0]) == %w[x y]
  assert rhs_fv(read_forms("(+ x y)")[0]) == %w[x y]
  assert op_form("dup", "x") == read_forms("(dup x)")[0]
  assert guarded([], 5) == 5
  assert dups_for(["x"], %w[x x], []) == [op_form("dup", "x")]
  assert rc_rhs(read_forms("(dup x)")[0], [["x", 1]], []) == [[["x", 2]], []]
  assert perceus_in(read_forms("(ret 1)")[0], [], []) ==
    read_forms("(ret 1)")[0]
  assert rc(read_forms("(ret 1)")[0], [], []) == [[], []]
end

@doc """
norm_let: the binds for a source let: each binding's value normalised and named by its own name through id, then the body.

    eval_anf(anf(read_forms("(let ((a 2)) (* a a))")[0]), []) #=> 4
"""
def norm_let(bindings, body, n)
  r = reduce(
    fn(acc, b)
      x = norm(b[1], acc[1])
      [
        append(acc[0], append(x[0], [[b[0], [read_forms("id")[0], x[1]]]])),
        x[2]
      ]
    end,
    [[], n],
    bindings
  )
  t = norm(body, r[1])
  [append(r[0], t[0]), t[1], t[2]]
end

@doc """
cc_rhs: a right-hand side with its lambdas lifted: a lambda becomes (closure "label" captured...) and its function joins the lifted list; a call through a name in scope becomes (call f args...).

    cc_rhs(read_forms("(+ 1 2)")[0], [], "t")[1] #=> []
"""
def cc_rhs(rhs, scope, v)
  if head_is?(rhs, "try")
    body = cc_term(rhs[1], scope)
    [[rhs[0], body[0], rhs[2]], body[1]]
  elsif head_is?(rhs, "if")
    yes = cc_term(rhs[2], scope)
    no = cc_term(rhs[3], scope)
    [[rhs[0], rhs[1], yes[0], no[0]], append(yes[1], no[1])]
  elsif head_is?(rhs, "lambda")
    params = map((p) -> to_s(p), rhs[1])
    captured = intersection(minus(fv(rhs[2]), params), scope)
    inner = cc_term(rhs[2], append(params, captured))
    label = "fn_#{v}"
    lifted = {label:, params:, captured:, body: inner[0]}
    made = cons(
      read_forms("closure")[0],
      cons(label, map((c) -> read_forms(c)[0], captured))
    )
    [made, append(inner[1], [lifted])]
  elsif member?(to_s(first(rhs)), scope)
    [cons(read_forms("call")[0], rhs), []]
  else
    [rhs, []]
  end
end

@doc """
cc_term: a term with every lambda lifted, as [term, lifted functions], given the names in scope.

    cc_term(read_forms("(ret 1)")[0], [])[1] #=> []
"""
def cc_term(term, scope)
  if head_is?(term, "ret")
    [term, []]
  else
    b = term[1]
    r = cc_rhs(b[1], scope, to_s(b[0]))
    k = cc_term(term[2], append(scope, [to_s(b[0])]))
    [[term[0], [b[0], r[0]], k[0]], append(r[1], k[1])]
  end
end

@doc """
closure_convert: a term with every lambda lifted to a top-level function whose captured names are explicit: {main:, fns:}.

    closure_convert(anf(read_forms("(+ 1 2)")[0]))[:fns] #=> []
"""
def closure_convert(term)
  r = cc_term(term, [])
  {main: r[0], fns: r[1]}
end

@doc """
lifted_rhs: the value of a right-hand side of a closure-converted program: a closure packs its captured values, a call runs its function by label.

    lifted_rhs([], read_forms("(+ 1 2)")[0], []) #=> 3
"""
def lifted_rhs(fns, rhs, env)
  if head_is?(rhs, "try")
    r = lifted_term(fns, rhs[1], env)
    if error_value?(r)
      call_lifted(fns, value_of(rhs[2], env), [r[1]])
    else
      r
    end
  elsif head_is?(rhs, "if")
    if value_of(rhs[1], env)
      lifted_term(fns, rhs[2], env)
    else
      lifted_term(fns, rhs[3], env)
    end
  elsif head_is?(rhs, "closure")
    {label: rhs[1], vals: map((a) -> value_of(a, env), rest(rest(rhs)))}
  elsif head_is?(rhs, "gcall")
    call_lifted(
      fns,
      {label: "g_#{rhs[1]}", vals: []},
      map((a) -> value_of(a, env), rest(rest(rhs)))
    )
  elsif head_is?(rhs, "call")
    call_lifted(
      fns,
      value_of(rhs[1], env),
      map((a) -> value_of(a, env), rest(rest(rhs)))
    )
  else
    prim(to_s(first(rhs)), map((a) -> value_of(a, env), rest(rhs)))
  end
end

@doc """
lifted_term: the value of a term of a closure-converted program.

    lifted_term([], read_forms("(ret 4)")[0], []) #=> 4
"""
def lifted_term(fns, term, env)
  if head_is?(term, "ret")
    value_of(term[1], env)
  else
    b = term[1]
    lifted_term(
      fns,
      term[2],
      cons([to_s(b[0]), lifted_rhs(fns, b[1], env)], env)
    )
  end
end

@doc """
eval_program: the value of a closure-converted program, its functions found by label and every captured name passed in explicitly.

    eval_program(closure_convert(anf(read_forms("(+ 1 2)")[0]))) #=> 3
"""
def eval_program(p)
  lifted_term(p[:fns], p[:main], [])
end

@doc """
holds_head?: whether a tree holds a form with this head anywhere.

    holds_head?(read_forms("(a (lambda (x) x))")[0], "lambda") #=> true
    holds_head?(7, "lambda") #=> false
"""
def holds_head?(x, head)
  if not list?(x)
    false
  elsif head_is?(x, head)
    true
  else
    retsu::find_first((c) -> holds_head?(c, head), x) != nil
  end
end

test "closure conversion lifts every lambda and keeps every answer"
  progs = [
    "(let ((k 10)) (let ((f (lambda (x) (+ x k)))) (f 5)))",
    "(let ((f (lambda (x) (lambda (y) (+ x y))))) (let ((g (f 3))) (g 4)))",
    "(let ((a 1)) (let ((f (lambda (x) (if (< x a) a x)))) (+ (f 0) (f 5))))",
    "(let ((twice (lambda (g x) (g (g x))))) (let ((inc (lambda (n) (+ n 1)))) (twice inc 5)))"
  ]
  map(
    fn(src)
      t = anf(read_forms(src)[0])
      p = closure_convert(t)
      assert eval_program(p) == eval_anf(t, [])
      assert not holds_head?(p[:main], "lambda")
      assert retsu::find_first(
        (f) -> holds_head?(f[:body], "lambda"),
        p[:fns]
      ).nil?
    end,
    progs
  )
  assert eval_anf(anf(read_forms(first(progs))[0]), []) == 15
end

test "a lifted function captures exactly the names it reads from outside"
  p = closure_convert(
    anf(
      nth(
        0,
        read_forms("(let ((f (lambda (x) (lambda (y) (+ x y))))) (let ((g (f 3))) (g 4)))")
      )
    )
  )
  inner = retsu::find_first((f) -> f[:params] == ["y"], p[:fns])
  outer = retsu::find_first((f) -> f[:params] == ["x"], p[:fns])
  assert inner[:captured] == ["x"]
  assert outer[:captured] == []
  assert length(p[:fns]) == 2
end

test "the closure helpers are exercised by name"
  assert norm_let([], read_forms("1")[0], 0)[1] == 1
  assert call_closure(
    {params: ["x"], body: anf(read_forms("(* x 2)")[0]), env: []},
    [4]
  ) == 8
  assert cc_rhs(read_forms("(+ 1 2)")[0], [], "t")[0] ==
    read_forms("(+ 1 2)")[0]
  assert cc_term(read_forms("(ret 1)")[0], [])[0] == read_forms("(ret 1)")[0]
  assert lifted_rhs([], read_forms("(+ 1 2)")[0], []) == 3
  assert lifted_term([], read_forms("(ret 4)")[0], []) == 4
  assert holds_head?(read_forms("(a (lambda (x) x))")[0], "lambda")
  assert not holds_head?(7, "lambda")
end

@doc """
perceus_program: perceus over a closure-converted program: the main term owns nothing, and each lifted function owns its parameters and the names it captured.

    perceus_program(closure_convert(anf(read_forms("(+ 1 2)")[0])))[:fns] #=> []
"""
def perceus_program(p)
  {
    main: perceus(p[:main], []),
    fns: map(
      fn(f)
        assoc(f, :body, perceus(f[:body], append(f[:params], f[:captured])))
      end,
      p[:fns]
    )
  }
end

@doc """
rc_program: every reference problem of a closure-converted program, the main term's and each function's.

    rc_program(closure_convert(anf(read_forms("(+ 1 2)")[0]))) #=> []
"""
def rc_program(p)
  append(
    rc_check(p[:main], []),
    flat_map(
      p[:fns],
      fn(f)
        map(
          (m) -> "#{f[:label]}: #{m}",
          rc_check(f[:body], append(f[:params], f[:captured]))
        )
      end
    )
  )
end

test "perceus over closures leaves every function and the main term reference-clean, and keeps every answer"
  progs = [
    "(let ((k 10)) (let ((f (lambda (x) (+ x k)))) (f 5)))",
    "(let ((f (lambda (x) (lambda (y) (+ x y))))) (let ((g (f 3))) (g 4)))",
    "(let ((a 1)) (let ((f (lambda (x) (if (< x a) a x)))) (+ (f 0) (f 5))))",
    "(let ((twice (lambda (g x) (g (g x))))) (let ((inc (lambda (n) (+ n 1)))) (twice inc 5)))",
    "(let ((f (lambda (x) (+ x x)))) (f 2))"
  ]
  map(
    fn(src)
      t = anf(read_forms(src)[0])
      p = closure_convert(t)
      q = perceus_program(p)
      assert rc_program(q) == []
      assert eval_program(q) == eval_anf(t, [])
    end,
    progs
  )
  noisy = filter(
    (src) -> rc_program(closure_convert(anf(read_forms(src)[0]))) != [],
    progs
  )
  assert length(noisy) >= 3
end

@doc """
split_program: a program (begin (define (f params...) body)... main) as {defs: [{name, params, body}], main}; a form that is no such begin is all main.

    split_program(read_forms("(+ 1 2)")[0])[:defs] #=> []
"""
def split_program(form)
  if head_is?(form, "begin")
    parts = rest(form)
    defs = filter((d) -> head_is?(d, "define") and list?(d[1]), parts)
    others = filter((d) -> not (head_is?(d, "define") and list?(d[1])), parts)
    main = if length(others) == 1
      first(others)
    else
      cons(read_forms("begin")[0], others)
    end
    {
      defs: map(
        fn(d)
          {
            name: to_s(first(d[1])),
            params: map((p) -> to_s(p), rest(d[1])),
            body: d[2]
          }
        end,
        defs
      ),
      main:
    }
  else
    {defs: [], main: form}
  end
end

@doc """
globalize: a term with every call to a global function named in names, (f args...), made a direct call (gcall "f" args...).

    globalize(read_forms("(let (t (f 1)) (ret t))")[0], ["f"])[1][1][0] == read_forms("gcall")[0] #=> true
"""
def globalize(term, names)
  if head_is?(term, "ret")
    term
  else
    b = term[1]
    rhs = b[1]
    new_rhs = if head_is?(rhs, "try")
      [rhs[0], globalize(rhs[1], names), rhs[2]]
    elsif head_is?(rhs, "if")
      [rhs[0], rhs[1], globalize(rhs[2], names), globalize(rhs[3], names)]
    elsif head_is?(rhs, "lambda")
      [rhs[0], rhs[1], globalize(rhs[2], names)]
    elsif list?(rhs) and
        symbol?(first(rhs)) and
        member?(to_s(first(rhs)), names)
      cons(read_forms("gcall")[0], cons(to_s(first(rhs)), rest(rhs)))
    else
      rhs
    end
    [term[0], [b[0], new_rhs], globalize(term[2], names)]
  end
end

@doc """
prefix_labels: a closure-converted program with every lifted label given a prefix, so the closures of different functions never share a name.

    prefix_labels({main: read_forms("(ret 1)")[0], fns: []}, "g")[:fns] #=> []
"""
def prefix_labels(p, pre)
  {
    main: relabel(p[:main], pre),
    fns: map(
      fn(f)
        assoc(
          assoc(f, :label, "#{pre}#{f[:label]}"),
          :body,
          relabel(f[:body], pre)
        )
      end,
      p[:fns]
    )
  }
end

@doc """
relabel: a term with the label of every closure it makes given a prefix.

    relabel(read_forms("(ret 1)")[0], "g") == read_forms("(ret 1)")[0] #=> true
"""
def relabel(term, pre)
  if head_is?(term, "ret")
    term
  else
    b = term[1]
    rhs = b[1]
    new_rhs = if head_is?(rhs, "try")
      [rhs[0], relabel(rhs[1], pre), rhs[2]]
    elsif head_is?(rhs, "if")
      [rhs[0], rhs[1], relabel(rhs[2], pre), relabel(rhs[3], pre)]
    elsif head_is?(rhs, "closure")
      cons(rhs[0], cons("#{pre}#{rhs[1]}", rest(rest(rhs))))
    else
      rhs
    end
    [term[0], [b[0], new_rhs], relabel(term[2], pre)]
  end
end

@doc """
whole: a program with global functions, each made A-normal, closure-converted, given Perceus over its parameters and its lifted closures relabelled, and the main term the same: {main:, fns:, globals: [{name, params, body}]}.

    whole(read_forms("(+ 1 2)")[0])[:globals] #=> []
"""
def whole(form)
  s = split_program(form)
  names = map((d) -> d[:name], s[:defs])
  prep = fn(body, pre, params)
    c = cc_term(globalize(propagate(anf(body)), names), params)
    p = prefix_labels({main: c[0], fns: c[1]}, pre)
    q = perceus_program(p)
    {main: perceus(p[:main], params), fns: q[:fns]}
  end
  globals = map(
    fn(d)
      p = prep(d[:body], "#{d[:name]}__", d[:params])
      {name: d[:name], params: d[:params], body: p[:main], fns: p[:fns]}
    end,
    s[:defs]
  )
  m = prep(s[:main], "main__", [])
  {
    main: m[:main],
    fns: append(m[:fns], flat_map(globals, (g) -> g[:fns])),
    globals: map(
      (g) -> {name: g[:name], params: g[:params], body: g[:body]},
      globals
    )
  }
end

test "a program splits into its global functions and its main, and calls to them become direct"
  s = split_program(
    read_forms("(begin (define (f x) (+ x 1)) (define (g) 2) (f (g)))")[0]
  )
  assert map((d) -> d[:name], s[:defs]) == %w[f g]
  assert s[:defs][0][:params] == ["x"]
  w = whole(read_forms("(begin (define (f x) (+ x 1)) (f 2))")[0])
  assert length(w[:globals]) == 1
  assert holds_head?(w[:main], "gcall")
  t = globalize(anf(read_forms("(f 1)")[0]), ["f"])
  assert to_s(t[1][1][0]) == "gcall"
  assert t[1][1][1] == "f"
end

test "lifted labels are prefixed per function, in the function and at every closure made"
  p = closure_convert(anf(read_forms("(let ((f (lambda (x) x))) (f 1))")[0]))
  q = prefix_labels(p, "g__")
  assert starts_with?(q[:fns][0][:label], "g__")
  assert has_label?(q[:main], q[:fns][0][:label])
  assert relabel(read_forms("(ret 1)")[0], "z") == read_forms("(ret 1)")[0]
end

@doc """
has_label?: whether a tree holds a closure made with this label.

    has_label?(7, "f") #=> false
"""
def has_label?(x, label)
  if not list?(x)
    false
  elsif head_is?(x, "closure") and x[1] == label
    true
  else
    retsu::find_first((c) -> has_label?(c, label), x) != nil
  end
end

@doc """
cond_to_if: a cond's clauses as nested ifs: each (test expr) tests in order, an else clause is the last branch, and no clause matching answers nil.

    cond_to_if(read_forms("((else 3))")[0]) #=> 3
"""
def cond_to_if(clauses)
  if length(clauses) == 0
    nil
  else
    c = first(clauses)
    if symbol?(c[0]) and to_s(c[0]) == "else"
      c[1]
    else
      [read_forms("if")[0], c[0], c[1], cond_to_if(rest(clauses))]
    end
  end
end

test "cond tests its clauses in order, else last, and nil when none matches"
  run = (src) -> eval_anf(anf(read_forms(src)[0]), [])
  assert run("(cond ((< 2 1) 10) ((< 1 2) 20) (else 30))") == 20
  assert run("(cond ((< 2 1) 10) (else 30))") == 30
  assert run("(cond ((< 2 1) 10))").nil?
  assert run("(let ((case-subject 2)) (cond ((equal? case-subject 1) 10) ((equal? case-subject 2) 20) (else 30)))") ==
    20
  assert cond_to_if(read_forms("((a 1))")[0])[3].nil?
end

@doc """
norm_try: (try body (catch (e) handler)) as two binds: the handler as a lambda over e, then (try B h), where B is the body's term; on an error B answers, h is called with what was raised.

    eval_anf(propagate(anf(read_forms("(try (raise 7) (catch (e) (+ e 1)))")[0])), []) #=> 8
"""
def norm_try(body, catch, n)
  h = fresh(n)
  handler = anf_from(catch[2], n + 1)
  b = anf_from(body, handler[1])
  v = fresh(b[1])
  lam = [read_forms("lambda")[0], catch[1], handler[0]]
  [[[h, lam], [v, [read_forms("try")[0], b[0], h]]], v, b[1] + 1]
end

@doc """
error_value?: whether a value is an error made by raise.

    error_value?([:__blue_error, 1]) #=> true
    error_value?(3) #=> false
"""
def error_value?(x)
  list?(x) and length(x) == 2 and x[0] == :__blue_error
end

@doc """
call_lifted: a closure of a converted program applied to argument values: its function found by label, its parameters and captures bound.

    call_lifted([{label: "f", params: ["x"], captured: [], body: read_forms("(ret x)")[0]}], {label: "f", vals: []}, [5]) #=> 5
"""
def call_lifted(fns, c, args)
  f = retsu::find_first((g) -> g[:label] == c[:label], fns)
  bound = append(
    map((i) -> [f[:params][i], args[i]], range(0, length(args))),
    map((i) -> [f[:captured][i], c[:vals][i]], range(0, length(c[:vals])))
  )
  lifted_term(fns, f[:body], bound)
end

@doc """
SAFE_OPS: the operations that never answer an error; after anything else a term checks.

    member?("+", SAFE_OPS) #=> true
"""
SAFE_OPS = %w[
  +
  -
  *
  <
  >
  equal?
  list
  id
  cons
  first
  rest
  length
  get
  assoc
  hash-map
  print
  string_length
  dup
  drop
  failed?
  syscall6
  load_word
  store_word
  lambda
]

@doc """
may_fail?: whether a right-hand side can answer an error: a raise, a call, an if or try whose branch can, anything not in SAFE_OPS.

    may_fail?(read_forms("(+ 1 2)")[0]) #=> false
    may_fail?(read_forms("(f 1)")[0]) #=> true
"""
def may_fail?(rhs)
  not (
    list?(rhs) and symbol?(first(rhs)) and member?(to_s(first(rhs)), SAFE_OPS)
  )
end

@doc """
propagate: a term in which every right-hand side that can answer an error is followed by a check that returns the error at once, so an error travels out of each term and function to the nearest try; Perceus then frees on that path what the term owned, as on any other.

    eval_anf(propagate(anf(read_forms("(+ 1 (raise 4))")[0])), []) #=> [:__blue_error, 4]
"""
def propagate(term)
  if head_is?(term, "ret")
    term
  else
    b = term[1]
    rhs = b[1]
    inner = if head_is?(rhs, "if")
      [rhs[0], rhs[1], propagate(rhs[2]), propagate(rhs[3])]
    elsif head_is?(rhs, "try")
      [rhs[0], propagate(rhs[1]), rhs[2]]
    elsif head_is?(rhs, "lambda")
      [rhs[0], rhs[1], propagate(rhs[2])]
    else
      rhs
    end
    k = propagate(term[2])
    if may_fail?(rhs)
      v = to_s(b[0])
      c = read_forms("c_#{v}")[0]
      r = read_forms("r_#{v}")[0]
      lt = read_forms("let")[0]
      [
        lt,
        [b[0], inner],
        [
          lt,
          [c, [read_forms("failed?")[0], b[0]]],
          [
            lt,
            [r, [read_forms("if")[0], c, [read_forms("ret")[0], b[0]], k]],
            [read_forms("ret")[0], r]
          ]
        ]
      ]
    else
      [term[0], [b[0], inner], k]
    end
  end
end

@doc """
TRY_PROGRAMS: programs with raise and try, and the value each must give.

    TRY_PROGRAMS[0][1] #=> 8
"""
TRY_PROGRAMS = [
  ["(try (raise 7) (catch (e) (+ e 1)))", 8],
  ["(try (+ 1 2) (catch (e) 0))", 3],
  [
    "(begin (define (div a b) (if (equal? b 0) (raise 99) (* a b))) (+ (try (div 6 7) (catch (e) 0)) (try (div 1 0) (catch (e) e))))",
    141
  ],
  [
    "(begin (define (inner l) (if (equal? (length l) 0) (raise 5) (first l))) (define (outer l) (+ 1 (inner l))) (try (outer (list)) (catch (e) (* e 2))))",
    10
  ],
  [
    "(let ((l (list 1 2 3))) (try (begin (length l) (raise 4)) (catch (e) (+ e (length l)))))",
    7
  ]
]

test "an error travels to the nearest try, through functions, and each try answers its value"
  map(
    fn(p)
      w = whole(read_forms(p[0])[0])
      assert eval_whole(w) == p[1]
    end,
    TRY_PROGRAMS
  )
end

test "every try program is reference-clean on every path"
  map(
    fn(p)
      w = whole(read_forms(p[0])[0])
      assert rc_check(w[:main], []) == []
      map((g) -> assert rc_check(g[:body], g[:params]) == [], w[:globals])
      map(
        fn(f)
          assert rc_check(f[:body], append(f[:params], f[:captured])) == []
        end,
        w[:fns]
      )
    end,
    TRY_PROGRAMS
  )
end

@doc """
eval_whole: the value of a whole program: its main term over its lifted closures, a direct call running a global with its parameters bound.

    eval_whole(whole(read_forms("(+ 1 2)")[0])) #=> 3
"""
def eval_whole(w)
  globals_as_fns = map(
    fn(g)
      {label: "g_#{g[:name]}", params: g[:params], captured: [], body: g[:body]}
    end,
    w[:globals]
  )
  lifted_term(append(w[:fns], globals_as_fns), w[:main], [])
end

test "the try helpers are exercised by name"
  binds = norm_try(
    read_forms("(raise 1)")[0],
    read_forms("(catch (e) e)")[0],
    0
  )
  assert to_s(binds[0][1][1][0]) == "try"
  assert error_value?([:__blue_error, 2])
  assert not error_value?([1, 2])
  assert call_lifted(
    [{label: "f", params: ["x"], captured: [], body: read_forms("(ret x)")[0]}],
    {label: "f", vals: []},
    [3]
  ) == 3
  assert member?("print", SAFE_OPS)
  assert may_fail?(read_forms("(raise 1)")[0])
  assert not may_fail?(read_forms("(first l)")[0])
  t = propagate(anf(read_forms("(+ 1 (f 2))")[0]))
  assert holds_head?(t, "failed?")
  assert not holds_head?(propagate(anf(read_forms("(+ 1 2)")[0])), "failed?")
end

test "the passes take each rarer case beside them: quote, list words, a try that does not raise, a kept return, a dead dup, a program of several main forms"
  q = read_forms("(quote a)")[0]
  assert norm(q, 0)[1] == q
  assert prim("first", [[1, 2]]) == 1
  assert prim("rest", [[1, 2]]) == [2]
  assert prim("cons", [0, [1]]) == [0, 1]
  assert eval_anf(anf(read_forms("(try (+ 1 2) (catch (e) 0))")[0]), []) == 3
  kept = perceus_in(read_forms("(ret x)")[0], ["x"], ["x"])
  assert holds_head?(kept, "dup")
  dead = rc_rhs(read_forms("(dup x)")[0], [["x", 0]], [])
  assert dead[1] == ["`x` duplicated with no reference left"]
  two = split_program(read_forms("(begin (define (f) 1) (f) 2)")[0])
  assert length(two[:defs]) == 1
  assert head_is?(two[:main], "begin")
end
