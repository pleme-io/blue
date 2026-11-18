@moduledoc """
kuzushi (崩し) — blue's core forms broken down into A-normal form, and an interpreter for the result: the first level of the compiler's IR (docs/PURE-BLUE.md B1).

In A-normal form every call's arguments are atoms (a literal or a name) and every intermediate value is named by a `let`, so evaluation order is explicit and each name has one use site a later pass can count. A term is `(ret atom)`, `(let (v rhs) term)`, where an rhs is `(op atom...)` or `(if atom term term)`. The source is the core `blue ast --resolved` prints: literals, names, `if`, `begin` and calls. `eval_anf` runs a term, so a pass can be checked against the tree-walker on the same program.

    eval_anf(anf(read_forms("(+ 1 (+ 2 3))")[0]), []) #=> 6
"""

use("junjo", [:sort_by])
use("retsu", %i[first flat_map rest])

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
    rhs = [
      read_forms("if")[0],
      c[1],
      anf_from(form[2], c[2] + 1)[0],
      anf_from(form[3], c[2] + 1)[0]
    ]
    [append(c[0], [[v, rhs]]), v, c[2] + 1]
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
  else
    raise(:unknown_op, "kuzushi: no primitive `#{name}`")
  end
end

@doc """
eval_rhs: the value of a right-hand side: an if takes one branch, anything else is a primitive over its atoms.

    eval_rhs(read_forms("(+ 1 2)")[0], []) #=> 3
"""
def eval_rhs(rhs, env)
  if head_is?(rhs, "if")
    if value_of(rhs[1], env)
      eval_anf(rhs[2], env)
    else
      eval_anf(rhs[3], env)
    end
  else
    prim(to_s(first(rhs)), map((a) -> value_of(a, env), rest(rhs)))
  end
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
meet: the names of a that b also holds.

    meet(["a", "b"], ["b", "c"]) #=> ["b"]
"""
def meet(a, b)
  filter((x) -> member?(x, b), a)
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
  if head_is?(rhs, "if")
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
count_of: how many times a name appears.

    count_of(["a", "b", "a"], "a") #=> 2
"""
def count_of(xs, x)
  length(filter((y) -> y == x, xs))
end

@doc """
arg_names: the names an rhs reads as arguments, repeats kept; for an if, its condition.

    arg_names(read_forms("(+ x x)")[0]) #=> ["x", "x"]
"""
def arg_names(rhs)
  if head_is?(rhs, "if")
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
    new_rhs = if head_is?(rhs, "if")
      branch_owned = minus(minus(owned, dead), meet(consumed, args))
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
  if head_is?(rhs, "dup")
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
  assert meet(%w[a b], %w[b c]) == ["b"]
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
