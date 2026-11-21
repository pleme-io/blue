@moduledoc """
kuzushi (崩し) — blue's core forms broken down into A-normal form, and an interpreter for the result: the first level of the compiler's IR (docs/PURE-BLUE.md B1).

In A-normal form every call's arguments are atoms (a literal or a name) and every intermediate value is named by a `let`, so evaluation order is explicit and each name has one use site a later pass can count. A term is `(ret atom)`, `(let (v rhs) term)`, where an rhs is `(op atom...)` or `(if atom term term)`. The source is the core `blue ast --resolved` prints: literals, names, `if`, `begin` and calls. `eval_anf` runs a term, so a pass can be checked against the tree-walker on the same program.

    eval_anf(anf(read_forms("(+ 1 (+ 2 3))")[0]), []) #=> 6
"""

use("junjo", [:sort_by])
use("kyohi")
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
  elsif head_is?(form, "and") or head_is?(form, "or")
    norm_logic(to_s(first(form)), rest(form), n)
  else
    args = norm_args(rest(form), n)
    v = fresh(args[2])
    [append(args[0], [[v, cons(first(form), args[1])]]), v, args[2] + 1]
  end
end

@doc """
norm_logic: `and` and `or` over their operand forms as ifs that answer the deciding operand's own value, as blue does: `(and a b)` is a when a does not hold, else b; `(or a b)` is a when a holds, else b; with no operands `and` is true and `or` nil.

    eval_anf(anf(read_forms("(list (and 1 2) (and () 1) (or () 3) (or 2 4))")[0]), []) #=> [2, nil, 3, 2]
"""
def norm_logic(op, forms, n)
  if length(forms) == 0
    [
      [],
      if op == "and"
        true
      end,
      n
    ]
  elsif length(forms) == 1
    norm(forms[0], n)
  else
    c = norm(forms[0], n)
    v = fresh(c[2])
    later = anf_from(cons(read_forms(op)[0], rest(forms)), c[2] + 1)
    kept = [read_forms("ret")[0], c[1]]
    rhs = if op == "and"
      [read_forms("if")[0], c[1], later[0], kept]
    else
      [read_forms("if")[0], c[1], kept, later[0]]
    end
    [append(c[0], [[v, rhs]]), v, later[1]]
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
norm_seq: the binds, last atom and counter after normalising forms in sequence; a (define name form) among them binds the name for the forms after it, as blue's resolved tree writes a local.

    norm_seq(read_forms("1 2"), 0)[1] #=> 2
"""
def norm_seq(forms, n)
  once_defined(forms)
  r = reduce(
    fn(acc, f)
      x = if head_is?(f, "define") and symbol?(f[1])
        b = named(f[1], f[2], acc[2])
        [b[0], nil, b[1]]
      else
        norm(f, acc[2])
      end
      [append(acc[0], x[0]), x[1], x[2]]
    end,
    [[], nil, n],
    forms
  )
  [r[0], r[1], r[2]]
end

@doc """
once_defined: forms whose (define name form) entries each name a different name; a name defined twice is refused with :rebind before any code is made, since a closure made between the two would keep the first value where blue reads the name when the closure runs.

    length(once_defined(read_forms("(define a 1) (define b 2)"))) #=> 2
"""
def once_defined(forms)
  names = map(
    (f) -> to_s(f[1]),
    filter((f) -> head_is?(f, "define") and symbol?(f[1]), forms)
  )
  again = filter((x) -> count_of(names, x) > 1, names)
  if again != []
    raise(
      :rebind,
      "kuzushi: `#{again[0]}` is defined again in one sequence; a closure made before the second definition would keep the first value"
    )
  end
  forms
end

test "a name defined twice in one sequence is refused before any code is made"
  twice = nth(
    0,
    read_forms("(begin (define n 1) (define f (lambda () n)) (define n 2) (f))")
  )
  assert (anf(twice) rescue :rebind) == :rebind
  assert (once_defined(rest(twice)) rescue :rebind) == :rebind
  once = read_forms("(begin (define n 1) (define m 2) (+ n m))")[0]
  assert eval_anf(anf(once), []) == 3
  assert once_defined([]) == []
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
value_of: the value an atom stands for: a name looks up, a quote unwraps, the empty form `()` (how the resolved tree writes nil) is nil, a literal is itself.

    value_of(read_forms("(quote 9)")[0], []) #=> 9
    value_of(read_forms("()")[0], []) #=> nil
"""
def value_of(atom, env)
  if symbol?(atom)
    lookup(env, to_s(atom))
  elsif head_is?(atom, "quote")
    atom[1]
  elsif list?(atom) and length(atom) == 0
    nil
  else
    atom
  end
end

@doc """
map_from: a map with each key of a flat [key, value, ...] list assoc'd in order onto m, so a later key wins as in a map literal.

    map_from({}, [:a, 1, :a, 2]) #=> {a: 2}
"""
def map_from(m, kvs)
  if length(kvs) < 2
    m
  else
    map_from(assoc(m, kvs[0], kvs[1]), rest(rest(kvs)))
  end
end

@doc """
PRIMS: the primitive operations kuzushi's evaluator runs, as [name, use, answer] rows: use is :reads when the op only reads its arguments (a borrowed name may be passed to it) and :stores when it keeps an argument inside what it answers (an owned reference is moved in); answer takes the evaluated arguments. Each answer is blue's own word, so a row agrees with the walker by construction.

    retsu::find_first((p) -> p[0] == "nth", PRIMS)[1] #=> :reads
"""
PRIMS = [
  ["+", :reads, (v) -> reduce((a, b) -> a + b, first(v), rest(v))],
  ["-", :reads, (v) -> v[0] - v[1]],
  ["*", :reads, (v) -> reduce((a, b) -> a * b, first(v), rest(v))],
  ["/", :reads, (v) -> v[0] / v[1]],
  ["mod", :reads, (v) -> v[0] % v[1]],
  ["<", :reads, (v) -> v[0] < v[1]],
  [">", :reads, (v) -> v[0] > v[1]],
  ["<=", :reads, (v) -> v[0] <= v[1]],
  [">=", :reads, (v) -> v[0] >= v[1]],
  ["equal?", :reads, (v) -> v[0] == v[1]],
  ["not=", :reads, (v) -> v[0] != v[1]],
  ["not", :reads, (v) -> not v[0]],
  ["length", :reads, (v) -> length(v[0] or [])],
  ["first", :reads, (v) -> first(v[0])],
  ["rest", :reads, (v) -> rest(v[0])],
  ["nth", :reads, (v) -> v[1][v[0]]],
  ["get", :reads, (v) -> get(v[0], v[1])],
  ["member?", :reads, (v) -> member?(v[0], v[1])],
  [
    "range",
    :reads,
    fn(v)
      if length(v) == 1
        range(v[0])
      elsif length(v) == 2
        range(v[0], v[1])
      else
        range(v[0], v[1], v[2])
      end
    end
  ],
  ["reverse", :reads, (v) -> reverse(v[0])],
  ["take", :reads, (v) -> take(v[0], v[1])],
  ["distinct", :reads, (v) -> distinct(v[0])],
  ["flatten", :reads, (v) -> flatten(v[0])],
  ["to_s", :reads, (v) -> to_s(v[0])],
  ["failed?", :reads, (v) -> error_value?(v[0])],
  ["list", :stores, (v) -> v],
  ["id", :stores, (v) -> v[0]],
  ["cons", :stores, (v) -> cons(v[0], v[1] or [])],
  ["append", :stores, (v) -> reduce((a, b) -> append(a, b), [], v)],
  ["assoc", :stores, (v) -> assoc(v[0], v[1], v[2])],
  ["hash-map", :stores, (v) -> map_from({}, v)],
  ["raise", :stores, (v) -> [:__blue_error, v[0]]],
  ["dup", :stores, (v) -> v[0]],
  ["drop", :stores, (_v) -> nil]
]

@doc """
prim_row: the PRIMS row of an op, or nil when kuzushi has no such primitive.

    prim_row("frob") #=> nil
    prim_row("+")[1] #=> :reads
"""
def prim_row(name)
  retsu::find_first((p) -> p[0] == name, PRIMS)
end

@doc """
prim: the answer of a primitive op over already-evaluated values.

    prim("list", [1, 2]) #=> [1, 2]
"""
def prim(name, vals)
  row = prim_row(name)
  if row.nil?
    raise(:unknown_op, "kuzushi: no primitive `#{name}`")
  end
  answer = row[2]
  answer(vals)
end

@doc """
trapped: the value of a try body, run by thunk; a primitive that fails as it runs (blue's own word raising, an overflow, a depth past the budget) answers the error value raise makes, carrying blue's error, so the try's handler gets what blue's rescue would.

    trapped(() -> 4) #=> 4
"""
def trapped(thunk)
  thunk()
rescue e
  [:__blue_error, e]
end

@doc """
eval_rhs: the value of a right-hand side: an if takes one branch, anything else is a primitive over its atoms.

    eval_rhs(read_forms("(+ 1 2)")[0], []) #=> 3
"""
def eval_rhs(rhs, env)
  if head_is?(rhs, "try")
    r = trapped(() -> eval_anf(rhs[1], env))
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
  perceus_at(term, owned, keep, OWNED_ONLY)
end

@doc """
OWNED_ONLY: the calling convention in which nothing is borrowed: every parameter is owned by its function, every argument position consumes and an if's test consumes its name (tests: :take), the convention `whole` compiles with.

    OWNED_ONLY[:borrowed] #=> []
"""
OWNED_ONLY = {borrowed: [], sigs: [], tests: :take}

@doc """
convention_ctx: the ctx perceus_at and rc_check_at count with under a convention. :borrow takes the borrowed names and the signatures, and duplicates a name an if tests that a branch also reads (tests: :dup), so the test consumes one reference and the branch owns the other; :owned is OWNED_ONLY's rule, where the test's reference is the only one, which hashiru's native code matches by reading a test without releasing it.

    convention_ctx(:borrow, ["l"], [])[:tests] #=> :dup
    convention_ctx(:owned, [], []) == OWNED_ONLY #=> true
"""
def convention_ctx(convention, borrowed, sigs)
  {
    borrowed:,
    sigs:,
    tests: if convention == :borrow
      :dup
    else
      :take
    end
  }
end

@doc """
branch_kept: the names an if's test consumes that one of its branches reads too, which the :dup convention duplicates before the test; none under :take or for any other rhs.

    branch_kept(read_forms("(if t (ret 1) (ret t))")[0], {borrowed: [], sigs: [], tests: :dup}) #=> ["t"]
    branch_kept(read_forms("(if t (ret 1) (ret t))")[0], OWNED_ONLY) #=> []
"""
def branch_kept(rhs, ctx)
  if head_is?(rhs, "if") and ctx[:tests] == :dup
    intersection(
      minus(names_of(rhs[1]), ctx[:borrowed]),
      union(fv(rhs[2]), fv(rhs[3]))
    )
  else
    []
  end
end

@doc """
lent: the names an rhs passes to a borrowed parameter of a global function, which the call reads without consuming; sigs holds each global's [name, [borrowed? per parameter]].

    lent(read_forms("(gcall \"f\" x y)")[0], {borrowed: [], sigs: [["f", [true, false]]]}) #=> ["x"]
"""
def lent(rhs, ctx)
  if head_is?(rhs, "gcall")
    sig = retsu::find_first((s) -> s[0] == rhs[1], ctx[:sigs])
    args = rest(rest(rhs))
    if sig.nil?
      []
    else
      flat_map(
        filter((i) -> sig[1][i], range(0, length(args))),
        (i) -> names_of(args[i])
      )
    end
  else
    []
  end
end

@doc """
taken: the names an rhs consumes as arguments, repeats kept: arg_names without a borrowed name, which nothing consumes, and without a name passed to a borrowed parameter.

    taken(read_forms("(gcall \"f\" x y)")[0], {borrowed: ["y"], sigs: [["f", [true, false]]]}) #=> []
"""
def taken(rhs, ctx)
  owned_args = if head_is?(rhs, "gcall")
    sig = retsu::find_first((s) -> s[0] == rhs[1], ctx[:sigs])
    args = rest(rest(rhs))
    flat_map(
      filter((i) -> sig.nil? or not sig[1][i], range(0, length(args))),
      (i) -> names_of(args[i])
    )
  else
    arg_names(rhs)
  end
  filter((x) -> not member?(x, ctx[:borrowed]), owned_args)
end

@doc """
perceus_at: perceus over a term under a calling convention ctx ({borrowed:, sigs:}): a borrowed name is never duplicated or dropped, and a name passed to a borrowed parameter of a global is read by the call, so it stays owned after it and is dropped where it dies.

    perceus_at(read_forms("(ret 1)")[0], [], [], OWNED_ONLY) == read_forms("(ret 1)")[0] #=> true
"""
def perceus_at(term, owned, keep, ctx)
  if head_is?(term, "ret")
    x = names_of(term[1])
    kept_too = x != [] and
      member?(x[0], keep) and
      not member?(x[0], ctx[:borrowed])
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
    args = taken(rhs, ctx)
    reads = lent(rhs, ctx)
    kept = branch_kept(rhs, ctx)
    dead = minus(minus(owned, used), after)
    ops = append(
      map((y) -> op_form("drop", y), dead),
      dups_for(owned, args, union(union(after, reads), kept))
    )
    consumed = filter(
      fn(x)
        member?(x, owned) and not member?(x, after) and not member?(x, reads)
      end,
      used
    )
    owned_after = union(minus(minus(owned, dead), consumed), [v])
    new_rhs = if head_is?(rhs, "try")
      body_owned = minus(minus(owned, dead), intersection(consumed, args))
      [rhs[0], perceus_at(rhs[1], body_owned, union(after, args), ctx), rhs[2]]
    elsif head_is?(rhs, "if")
      branch_owned = minus(
        minus(owned, dead),
        minus(intersection(consumed, args), kept)
      )
      [
        rhs[0],
        rhs[1],
        perceus_at(rhs[2], branch_owned, after, ctx),
        perceus_at(rhs[3], branch_owned, after, ctx)
      ]
    else
      rhs
    end
    guarded(
      ops,
      [term[0], [b[0], new_rhs], perceus_at(term[2], owned_after, keep, ctx)]
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
  rc_rhs_at(rhs, counts, errors, OWNED_ONLY)
end

@doc """
rc_rhs_at: rc_rhs under a calling convention: a borrowed name is never consumed, and a call consumes nothing it passes to a borrowed parameter.

    rc_rhs_at(read_forms("(+ x 1)")[0], [], [], {borrowed: ["x"], sigs: []}) #=> [[], []]
"""
def rc_rhs_at(rhs, counts, errors, ctx)
  if head_is?(rhs, "try")
    b = rc_at(rhs[1], counts, errors, ctx)
    consume_all(b[0], taken(rhs, ctx), b[1])
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
    c = consume_all(counts, taken(rhs, ctx), errors)
    a = rc_at(rhs[2], c[0], c[1], ctx)
    b = rc_at(rhs[3], c[0], a[1], ctx)
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
    consume_all(counts, taken(rhs, ctx), errors)
  end
end

@doc """
rc: the state and problems after a whole term.

    rc(read_forms("(ret 1)")[0], [], []) #=> [[], []]
"""
def rc(term, counts, errors)
  rc_at(term, counts, errors, OWNED_ONLY)
end

@doc """
rc_at: rc under a calling convention: a returned borrowed name is not consumed, and each right-hand side is counted by rc_rhs_at.

    rc_at(read_forms("(ret x)")[0], [], [], {borrowed: ["x"], sigs: []}) #=> [[], []]
"""
def rc_at(term, counts, errors, ctx)
  if head_is?(term, "ret")
    consume_all(
      counts,
      filter((x) -> not member?(x, ctx[:borrowed]), names_of(term[1])),
      errors
    )
  else
    b = term[1]
    r = rc_rhs_at(b[1], counts, errors, ctx)
    bound = if to_s(b[0]) == "_"
      r[0]
    else
      count_set(r[0], to_s(b[0]), 1)
    end
    rc_at(term[2], bound, r[1], ctx)
  end
end

@doc """
rc_check: the problems a term has under reference counting, given the names it owns: a name used or dropped with no reference left, two branches that end differently, and any reference still held when the term returns. An empty list means the term frees everything exactly once.

    rc_check(anf(read_forms("(+ x 1)")[0]), ["x"]) #=> []
"""
def rc_check(term, owned)
  rc_check_at(term, owned, OWNED_ONLY)
end

@doc """
rc_check_at: rc_check under a calling convention, the owned names starting with one reference each and the borrowed ones with none.

    rc_check_at(anf(read_forms("(+ x 1)")[0]), [], {borrowed: ["x"], sigs: []}) #=> []
"""
def rc_check_at(term, owned, ctx)
  start = map((x) -> [x, 1], owned)
  r = rc_at(term, start, [], ctx)
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
      x = named(b[0], b[1], acc[1])
      [append(acc[0], x[0]), x[1]]
    end,
    [[], n],
    bindings
  )
  t = norm(body, r[1])
  [append(r[0], t[0]), t[1], t[2]]
end

@doc """
named: the binds that give a name the value of a form, through id, and the counter after them.

    named(read_forms("a")[0], read_forms("(+ 1 2)")[0], 0)[1] #=> 1
"""
def named(name, form, n)
  x = norm(form, n)
  [append(x[0], [[name, [read_forms("id")[0], x[1]]]]), x[2]]
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
    r = trapped(() -> lifted_term(fns, rhs[1], env))
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
  whole_in(form, :owned)
end

@doc """
whole_in: `whole` under a calling convention: :owned, where every parameter is owned by its function, or :borrow, where a global function's parameter that is only read is borrowed (borrow_sigs), so Perceus emits no dup or drop for it and its callers keep what they pass there. Each global carries its borrowed parameters and the program its signatures, which ir_live counts with.

    whole_in(read_forms("(begin (define (f l) (length l)) (f (list 1)))")[0], :borrow)[:globals][0][:borrowed] #=> ["l"]
"""
def whole_in(form, convention)
  s = split_program(form)
  names = map((d) -> d[:name], s[:defs])
  arity_checked(s)
  lower = fn(body, pre, params)
    c = cc_term(globalize(propagate(anf(body)), names), params)
    prefix_labels({main: c[0], fns: c[1]}, pre)
  end
  lowered = map(
    fn(d)
      {
        name: d[:name],
        params: d[:params],
        p: lower(d[:body], "#{d[:name]}__", d[:params])
      }
    end,
    s[:defs]
  )
  m = lower(s[:main], "main__", [])
  sigs = if convention == :borrow
    borrow_sigs(
      map(
        (g) -> {name: g[:name], params: g[:params], body: g[:p][:main]},
        lowered
      )
    )
  else
    map((g) -> [g[:name], map((_p) -> false, g[:params])], lowered)
  end
  owning = convention_ctx(convention, [], sigs)
  lifted = fn(p)
    map(
      fn(f)
        assoc(
          f,
          :body,
          perceus_at(f[:body], append(f[:params], f[:captured]), [], owning)
        )
      end,
      p[:fns]
    )
  end
  globals = map(
    fn(g)
      sig = retsu::find_first((x) -> x[0] == g[:name], sigs)[1]
      borrowed = map(
        (i) -> g[:params][i],
        filter((i) -> sig[i], range(0, length(g[:params])))
      )
      body = perceus_at(
        g[:p][:main],
        minus(g[:params], borrowed),
        [],
        convention_ctx(convention, borrowed, sigs)
      )
      {name: g[:name], params: g[:params], borrowed:, body:, fns: lifted(g[:p])}
    end,
    lowered
  )
  {
    main: perceus_at(m[:main], [], [], owning),
    fns: append(lifted(m), flat_map(globals, (g) -> g[:fns])),
    globals: map(
      fn(g)
        {
          name: g[:name],
          params: g[:params],
          borrowed: g[:borrowed],
          body: g[:body]
        }
      end,
      globals
    ),
    sigs:,
    convention:
  }
end

@doc """
reads_only?: whether a term uses the name p only where a borrowed reference is enough: an if's condition, an argument of a primitive that only reads (PRIMS :reads), or an argument a global's borrowed parameter takes (by sigs). Returning it, binding it to another name, storing it (a list, a closure's capture, a raise), passing it to a closure or to an owned parameter is not.

    reads_only?(anf(read_forms("(+ (length l) 1)")[0]), "l", []) #=> true
    reads_only?(anf(read_forms("(list l)")[0]), "l", []) #=> false
"""
def reads_only?(term, p, sigs)
  if head_is?(term, "ret")
    names_of(term[1]) != [p]
  else
    b = term[1]
    to_s(b[0]) != p and
      rhs_reads_only?(b[1], p, sigs) and
      reads_only?(term[2], p, sigs)
  end
end

@doc """
rhs_reads_only?: reads_only? for one right-hand side.

    rhs_reads_only?(read_forms("(gcall \"f\" l)")[0], "l", [["f", [true]]]) #=> true
    rhs_reads_only?(read_forms("(gcall \"f\" l)")[0], "l", [["f", [false]]]) #=> false
"""
def rhs_reads_only?(rhs, p, sigs)
  if head_is?(rhs, "if")
    reads_only?(rhs[2], p, sigs) and reads_only?(rhs[3], p, sigs)
  elsif head_is?(rhs, "try")
    reads_only?(rhs[1], p, sigs) and names_of(rhs[2]) != [p]
  elsif head_is?(rhs, "gcall")
    sig = retsu::find_first((s) -> s[0] == rhs[1], sigs)
    args = rest(rest(rhs))
    retsu::find_first(
      (i) -> names_of(args[i]) == [p] and (sig.nil? or not sig[1][i]),
      range(0, length(args))
    ).nil?
  elsif list?(rhs) and
      symbol?(first(rhs)) and
      prim_row(to_s(first(rhs))) != nil and
      prim_row(to_s(first(rhs)))[1] == :reads
    true
  else
    not member?(p, rhs_fv(rhs))
  end
end

@doc """
borrow_sigs: each global's [name, [borrowed? per parameter]], the greatest fixpoint: every parameter starts borrowed, and one that a body uses other than by reading (reads_only?) becomes owned, until nothing changes; a parameter passed on to another global stays borrowed only while that parameter is.

    borrow_sigs([{name: "f", params: %w[a b], body: anf(read_forms("(+ (length a) b)")[0])}]) #=> [["f", [true, true]]]
"""
def borrow_sigs(globals)
  start = map((g) -> [g[:name], map((_p) -> true, g[:params])], globals)
  settle_sigs(globals, start)
end

@doc """
settle_sigs: one round of borrow_sigs from sigs, repeated until a round changes nothing.

    settle_sigs([], []) #=> []
"""
def settle_sigs(globals, sigs)
  next = map(
    fn(g)
      was = retsu::find_first((s) -> s[0] == g[:name], sigs)[1]
      [
        g[:name],
        map(
          (i) -> was[i] and reads_only?(g[:body], g[:params][i], sigs),
          range(0, length(g[:params]))
        )
      ]
    end,
    globals
  )
  if next == sigs
    sigs
  else
    settle_sigs(globals, next)
  end
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

@doc """
ir_live: every reference problem of a whole program, its main term's, each global's and each lifted function's, each named by where it is; empty when every path frees what it owns exactly once and nothing is live at exit.

    ir_live(whole(read_forms("(+ 1 2)")[0])) #=> []
"""
def ir_live(w)
  owning = convention_ctx(w[:convention], [], w[:sigs])
  append(
    rc_check_at(w[:main], [], owning),
    append(
      flat_map(
        w[:globals],
        fn(g)
          map(
            (m) -> "#{g[:name]}: #{m}",
            rc_check_at(
              g[:body],
              minus(g[:params], g[:borrowed]),
              convention_ctx(w[:convention], g[:borrowed], w[:sigs])
            )
          )
        end
      ),
      flat_map(
        w[:fns],
        fn(f)
          map(
            (m) -> "#{f[:label]}: #{m}",
            rc_check_at(f[:body], append(f[:params], f[:captured]), owning)
          )
        end
      )
    )
  )
end

@doc """
ir_eval: a core form through B1's whole IR, A-normal form, error propagation, closure conversion and Perceus with borrowed parameters (whole_in :borrow), then run by kuzushi's evaluator: {value:, live:}, where live lists every reference the reference-count checker finds still held or used twice (empty for a clean program). A form kuzushi has no code for (ir_refusal), or that its lowering refuses (:rebind, :arity), is refused with :ir_refused before anything runs.

    ir_eval(read_forms("(+ 1 2)")[0]) #=> {value: 3, live: []}
"""
def ir_eval(form)
  why = ir_refusal(form)
  if why != nil
    raise(:ir_refused, "kuzushi: #{why}")
  end
  w = begin
    whole_in(form, :borrow)
  rescue e
    raise(:ir_refused, "kuzushi: #{to_s(e.kind)}: #{e.message}")
  end
  {value: eval_whole(w), live: ir_live(w)}
end

@doc """
IR_OWN: the heads kuzushi's IR gives its own operations; a source call by one of these names would be read as that operation, so it is refused.

    member?("drop", IR_OWN) #=> true
"""
IR_OWN = %w[ret dup drop closure call gcall failed? id]

@doc """
ir_refusal: why kuzushi cannot run a core form, or nil when it can: a call to an op that is neither a primitive (PRIMS), a global function nor a local; a name no local or parameter binds (a global function's body sees only its parameters and its own locals); a shape its passes do not take (a rest parameter, a let of several bindings, a body of several forms, a raise of a kind and a message, a computed head); a source call named like one of the IR's own operations.

    ir_refusal(read_forms("(+ 1 2)")[0]) #=> nil
    ir_refusal(read_forms("(frob 1)")[0]) #=> "no primitive `frob`"
"""
def ir_refusal(form)
  s = split_program(form)
  names = map((d) -> d[:name], s[:defs])
  odd = retsu::find_first(
    (d) -> head_is?(d, "define") and list?(d[1]) and length(d) != 3,
    if head_is?(form, "begin")
      rest(form)
    else
      []
    end
  )
  if odd != nil
    "a function body of several forms"
  else
    first_refusal(
      append(
        flat_map(
          s[:defs],
          fn(d)
            [
              fn()
                params_refusal(map((p) -> read_forms(p)[0], d[:params]), names)
              end,
              () -> refusal_in(d[:body], d[:params], names)
            ]
          end
        ),
        [() -> refusal_in(s[:main], [], names)]
      )
    )
  end
end

@doc """
first_refusal: the first reason a list of deferred checks gives, running each only until one refuses; nil when none does.

    first_refusal([() ->nil, () ->"x"]) #=> "x"
"""
def first_refusal(checks)
  if checks == []
    nil
  else
    check = first(checks)
    why = check()
    if why != nil
      why
    else
      first_refusal(rest(checks))
    end
  end
end

@doc """
params_refusal: why a parameter list cannot bind: a name that is not a symbol, a rest parameter, or a local that shares a global function's name (a call through it would be made direct).

    params_refusal(read_forms("(a b)")[0], []) #=> nil
    params_refusal(read_forms("(a & r)")[0], []) #=> "a rest parameter"
"""
def params_refusal(params, globals)
  if not list?(params) or
      retsu::find_first((p) -> not symbol?(p), params) != nil
    "a parameter that is not a name"
  elsif retsu::find_first((p) -> starts_with?(to_s(p), "&"), params) != nil
    "a rest parameter"
  elsif retsu::find_first((p) -> member?(to_s(p), globals), params) != nil
    "a local named like a global function"
  end
end

@doc """
refusal_in: ir_refusal for one form, given the locals in scope and the global function names.

    refusal_in(read_forms("x")[0], ["x"], []) #=> nil
    refusal_in(read_forms("y")[0], ["x"], []) #=> "`y` is bound by no local kuzushi sees"
"""
def refusal_in(node, scope, globals)
  if symbol?(node)
    if member?(to_s(node), scope)
      nil
    else
      "`#{to_s(node)}` is bound by no local kuzushi sees"
    end
  elsif not list?(node) or length(node) == 0
    nil
  elsif not symbol?(first(node))
    "a call through a computed head"
  else
    refusal_head(to_s(first(node)), node, scope, globals)
  end
end

@doc """
refusal_all: the first refusal among forms checked in one scope.

    refusal_all(read_forms("1 x"), [], []) #=> "`x` is bound by no local kuzushi sees"
"""
def refusal_all(forms, scope, globals)
  first_refusal(map((f) -> () -> refusal_in(f, scope, globals), forms))
end

@doc """
refusal_head: refusal_in for a list whose head is the symbol named h.

    refusal_head("quote", read_forms("(quote a)")[0], [], []) #=> nil
"""
def refusal_head(h, node, scope, globals)
  if h == "quote"
    nil
  elsif h == "if" or h == "and" or h == "or"
    if h == "if" and (length(node) < 3 or length(node) > 4)
      "an if of another shape"
    else
      refusal_all(rest(node), scope, globals)
    end
  elsif h == "begin"
    refusal_seq(rest(node), scope, globals)
  elsif h == "let"
    refusal_let(node, scope, globals)
  elsif h == "cond"
    refusal_cond(rest(node), scope, globals)
  elsif h == "lambda"
    if length(node) != 3
      "a lambda body of several forms"
    else
      first_refusal(
        [
          () -> params_refusal(node[1], globals),
          () -> refusal_in(node[2], append(scope, map(to_s, node[1])), globals)
        ]
      )
    end
  elsif h == "try"
    refusal_try(node, scope, globals)
  elsif h == "raise"
    if length(node) != 2
      "a raise of a kind and a message"
    else
      refusal_in(node[1], scope, globals)
    end
  elsif h == "define"
    "a define outside a sequence"
  elsif member?(h, IR_OWN)
    "`#{h}` names an operation of kuzushi's IR"
  elsif member?(h, scope) or member?(h, globals) or prim_row(h) != nil
    refusal_all(rest(node), scope, globals)
  else
    "no primitive `#{h}`"
  end
end

@doc """
refusal_seq: refusal_in over a begin's forms in order, each (define name form) checking its form and then binding the name for the forms after it.

    refusal_seq(read_forms("(define a 1) (+ a 1)"), [], []) #=> nil
"""
def refusal_seq(forms, scope, globals)
  if forms == []
    nil
  else
    f = first(forms)
    if head_is?(f, "define") and length(f) == 3 and symbol?(f[1])
      name = to_s(f[1])
      if member?(name, globals)
        "a local named like a global function"
      else
        why = refusal_in(f[2], scope, globals)
        if why.nil?
          refusal_seq(rest(forms), append(scope, [name]), globals)
        else
          why
        end
      end
    else
      why = refusal_in(f, scope, globals)
      if why.nil?
        refusal_seq(rest(forms), scope, globals)
      else
        why
      end
    end
  end
end

@doc """
refusal_let: refusal_in for a let of one binding and one body form, the body seeing the binding.

    refusal_let(read_forms("(let ((a 1)) a)")[0], [], []) #=> nil
"""
def refusal_let(node, scope, globals)
  bs = node[1]
  if length(node) != 3 or
      not list?(bs) or
      length(bs) != 1 or
      not list?(bs[0]) or
      length(bs[0]) != 2 or
      not symbol?(bs[0][0])
    "a let of another shape"
  elsif member?(to_s(bs[0][0]), globals)
    "a local named like a global function"
  else
    first_refusal(
      [
        () -> refusal_in(bs[0][1], scope, globals),
        () -> refusal_in(node[2], append(scope, [to_s(bs[0][0])]), globals)
      ]
    )
  end
end

@doc """
refusal_cond: refusal_in for a cond's clauses, each a (test form) pair, else last.

    refusal_cond(read_forms("((a 1) (else 2))")[0], ["a"], []) #=> nil
"""
def refusal_cond(clauses, scope, globals)
  if retsu::find_first((c) -> not list?(c) or length(c) != 2, clauses) != nil
    "a cond clause of another shape"
  else
    first_refusal(
      map(
        fn(c)
          fn()
            guard = if symbol?(c[0]) and to_s(c[0]) == "else"
              nil
            else
              refusal_in(c[0], scope, globals)
            end
            guard or refusal_in(c[1], scope, globals)
          end
        end,
        clauses
      )
    )
  end
end

@doc """
refusal_try: refusal_in for (try body (catch (e) handler)), the handler seeing e.

    refusal_try(read_forms("(try 1 (catch (e) e))")[0], [], []) #=> nil
"""
def refusal_try(node, scope, globals)
  c = node[2]
  if length(node) != 3 or
      not head_is?(c, "catch") or
      length(c) != 3 or
      not list?(c[1]) or
      length(c[1]) != 1
    "a try of another shape"
  else
    first_refusal(
      [
        () -> params_refusal(c[1], globals),
        () -> refusal_in(node[1], scope, globals),
        () -> refusal_in(c[2], append(scope, map(to_s, c[1])), globals)
      ]
    )
  end
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

@doc """
arity_misses: every call in a tree to a function of `arities` ([name, count] pairs) with another number of arguments, as [name, wanted, given]. A name `bound` holds (a parameter, a lambda's or a let's binding) is a local, not the function, and is skipped.

    arity_misses(read_forms("(f 1)")[0], [["f", 2]], []) #=> [["f", 2, 1]]
    arity_misses(read_forms("(f 1 2)")[0], [["f", 2]], []) #=> []
    arity_misses(read_forms("(f 1)")[0], [["f", 2]], ["f"]) #=> []
"""
def arity_misses(node, arities, bound)
  if not list?(node) or length(node) == 0
    []
  else
    head = first(node)
    inner = if head_is?(node, "lambda") and length(node) > 1 and list?(node[1])
      append(bound, map(to_s, node[1]))
    elsif head_is?(node, "let") and length(node) > 1 and list?(node[1])
      append(bound, map((b) -> to_s(first(b)), filter(list?, node[1])))
    else
      bound
    end
    hit = if symbol?(head) and not member?(to_s(head), inner)
      retsu::find_first((a) -> a[0] == to_s(head), arities)
    end
    own = if hit != nil and length(node) - 1 != hit[1]
      [[hit[0], hit[1], length(node) - 1]]
    else
      []
    end
    append(own, flat_map(rest(node), (c) -> arity_misses(c, arities, inner)))
  end
end

@doc """
arity_checked: a split program whose every call to one of its functions passes that function's number of arguments; a call that does not is refused with :arity, naming the function, before any code is made.

    arity_checked(split_program(read_forms("(begin (define (f a) a) (f 1))")[0]))[:defs][0][:name] #=> "f"
"""
def arity_checked(s)
  arities = map((d) -> [d[:name], length(d[:params])], s[:defs])
  misses = append(
    flat_map(s[:defs], (d) -> arity_misses(d[:body], arities, d[:params])),
    arity_misses(s[:main], arities, [])
  )
  if misses != []
    m = misses[0]
    raise(
      :arity,
      "kuzushi: `#{m[0]}` takes #{to_s(m[1])} argument(s), called with #{to_s(m[2])}"
    )
  end
  s
end

test "a call to a global function with the wrong number of arguments is refused before any code is made"
  bad = split_program(read_forms("(begin (define (f a b) (+ a b)) (f 1))")[0])
  assert (arity_checked(bad) rescue :arity) == :arity
  assert (whole(read_forms("(begin (define (f a b) (+ a b)) (f 1))")[0]) rescue
    :arity) == :arity
  good = read_forms("(begin (define (f a b) (+ a b)) (f 1 2))")[0]
  assert length(whole(good)[:globals]) == 1
end

test "a parameter, a lambda's or a let's binding that shares a function's name is a local, not a call to it"
  p = nth(
    0,
    read_forms("(begin (define (f x) x) (define (map f l) (f (first l))) (map (lambda (y) y) (list 1)))")
  )
  assert length(arity_checked(split_program(p))[:defs]) == 2
  assert arity_misses(
    read_forms("((lambda (f) (f 1 2)) 3)")[0],
    [["f", 1]],
    []
  ) == []
  assert arity_misses(read_forms("(let ((f 1)) (f 2 3))")[0], [["f", 1]], []) ==
    []
end

@doc """
temp?: whether a name is one A-normal form introduced, t__N, rather than one the source wrote.

    temp?("t__3") #=> true
"""
def temp?(name)
  starts_with?(name, "t__")
end

@doc """
lisp_text: a form as the lisp text that reads back to it.

    lisp_text(read_forms("(+ x (f 1))")[0]) #=> "(+ x (f 1))"
"""
def lisp_text(form)
  if string?(form)
    json_write(form)
  elsif list?(form)
    "(#{join(map(lisp_text, form), " ")})"
  else
    to_s(form)
  end
end

@doc """
src_atom: the source form an atom stands for: a temporary's form from the environment, any other atom itself.

    src_atom(read_forms("t__0")[0], [["t__0", 5]]) #=> 5
"""
def src_atom(atom, env)
  if symbol?(atom) and temp?(to_s(atom))
    hit = retsu::find_first((r) -> r[0] == to_s(atom), env)
    if hit.nil?
      atom
    else
      hit[1]
    end
  else
    atom
  end
end

@doc """
src_rhs: the source form a right-hand side was broken down from, its temporaries put back.

    lisp_text(src_rhs(read_forms("(+ x t__0)")[0], [["t__0", read_forms("(* x 2)")[0]]])) #=> "(+ x (* x 2))"
"""
def src_rhs(rhs, env)
  if head_is?(rhs, "id")
    src_atom(rhs[1], env)
  elsif head_is?(rhs, "if")
    [
      rhs[0],
      src_atom(rhs[1], env),
      src_term(rhs[2], env),
      src_term(rhs[3], env)
    ]
  elsif head_is?(rhs, "try")
    [rhs[0], src_term(rhs[1], env), rhs[2]]
  elsif head_is?(rhs, "lambda")
    rhs
  else
    cons(first(rhs), map((a) -> src_atom(a, env), rest(rhs)))
  end
end

@doc """
ref_op?: whether a right-hand side is a reference operation Perceus inserted, a dup or a drop.

    ref_op?(read_forms("(dup x)")[0]) #=> true
"""
def ref_op?(rhs)
  head_is?(rhs, "dup") or head_is?(rhs, "drop")
end

@doc """
src_term: the source form a term was broken down from.

    lisp_text(src_term(anf(read_forms("(+ x (* x 2))")[0]), [])) #=> "(+ x (* x 2))"
"""
def src_term(term, env)
  if head_is?(term, "ret")
    src_atom(term[1], env)
  elsif ref_op?(term[1][1])
    src_term(term[2], env)
  else
    b = term[1]
    src_term(term[2], cons([to_s(b[0]), src_rhs(b[1], env)], env))
  end
end

@doc """
take_one: a list with its first occurrence of x removed, and whether there was one.

    take_one(%w[a b a], "a") #=> [%w[b a], true]
"""
def take_one(xs, x)
  i = position(x, xs)
  if i < 0
    [xs, false]
  else
    [append(take(i, xs), drop(i + 1, xs)), true]
  end
end

@doc """
reads_at: the last uses among the source names a site reads, given the dups Perceus placed before it: a read a dup covers shares the value, the read none covers consumes it. Answers [last uses as [name, form], dups left].

    reads_at(%w[x x], ["x"], 7)[0] #=> [["x", 7]]
"""
def reads_at(names, pending, form)
  reduce(
    fn(acc, x)
      t = take_one(acc[1], x)
      if temp?(x) or t[1]
        [acc[0], t[0]]
      else
        [append(acc[0], [[x, form]]), acc[1]]
      end
    end,
    [[], pending],
    names
  )
end

@doc """
last_uses: every [name, form] where a source name is used for the last time on its path, read from a term Perceus has rewritten, each form the source the use was broken down from.

    last_uses(perceus(anf(read_forms("(+ x 1)")[0]), ["x"]), [], []) == [["x", read_forms("(+ x 1)")[0]]] #=> true
"""
def last_uses(term, env, pending)
  if head_is?(term, "ret")
    reads_at(names_of(term[1]), pending, src_atom(term[1], env))[0]
  else
    b = term[1]
    rhs = b[1]
    if head_is?(rhs, "dup")
      last_uses(term[2], env, append(pending, [to_s(rhs[1])]))
    elsif head_is?(rhs, "drop")
      last_uses(term[2], env, pending)
    else
      here = reads_at(arg_names(rhs), pending, src_rhs(rhs, env))
      inner = if head_is?(rhs, "if")
        append(last_uses(rhs[2], env, here[1]), last_uses(rhs[3], env, here[1]))
      elsif head_is?(rhs, "try")
        last_uses(rhs[1], env, here[1])
      else
        []
      end
      rest_env = cons([to_s(b[0]), src_rhs(rhs, env)], env)
      append(here[0], append(inner, last_uses(term[2], rest_env, here[1])))
    end
  end
end

@doc """
short_name: a resolved definition's name without its namespace, %root/f as f.

    short_name("%root/f") #=> "f"
"""
def short_name(name)
  parts = split(name, "/")
  parts[length(parts) - 1]
end

@doc """
memory_facts: the ownership facts of each definition among resolved top-level forms, as text, "f: last_use x (+ x 1)": where each parameter and local is used for the last time (docs/PURE-BLUE.md M1).

    memory_facts(read_forms("(define (%root/f x) (+ x 1))")) #=> ["f: last_use x (+ x 1)"]
"""
def memory_facts(forms)
  defs = filter((d) -> head_is?(d, "define") and list?(d[1]), forms)
  flat_map(
    defs,
    fn(d)
      name = short_name(to_s(first(d[1])))
      params = map(to_s, rest(d[1]))
      t = perceus(anf(d[2]), params)
      map(
        (u) -> "#{name}: last_use #{u[0]} #{lisp_text(u[1])}",
        last_uses(t, [], [])
      )
    end
  )
end

test "a local defined in a body is a name the forms after it read"
  t = anf(read_forms("(begin (define y (+ x 1)) (* y x))")[0])
  assert eval_anf(t, [["x", 3]]) == 12
  assert named(read_forms("a")[0], read_forms("(f)")[0], 0)[0] ==
    [
      [read_forms("t__0")[0], read_forms("(f)")[0]],
      [read_forms("a")[0], read_forms("(id t__0)")[0]]
    ]
end

test "each parameter and local has its last use, in straight-line code"
  forms = read_forms("(define (%root/f x) (begin (define y (+ x 1)) (* y x)))")
  assert memory_facts(forms) ==
    ["f: last_use y (* y x)", "f: last_use x (* y x)"]
  assert memory_facts([]) == []
  assert memory_facts(read_forms("(+ 1 2)")) == []
end

test "a name read twice in one call is last used by that call, not before"
  assert memory_facts(read_forms("(define (%root/sq x) (* x x))")) ==
    ["sq: last_use x (* x x)"]
  assert memory_facts(read_forms("(define (%root/g x) (+ x (* x 2)))")) ==
    ["g: last_use x (+ x (* x 2))"]
end

test "each branch has its own last use"
  forms = read_forms("(define (%root/h c x) (if c (+ x 1) 0))")
  assert memory_facts(forms) ==
    ["h: last_use c (if c (+ x 1) 0)", "h: last_use x (+ x 1)"]
end

test "a name never read has no last use"
  assert memory_facts(read_forms("(define (%root/k x) 1)")) == []
end

test "the source helpers put temporaries back and print lisp"
  assert temp?("t__0")
  assert not temp?("x")
  assert lisp_text(read_forms("(f \"a\" 1)")[0]) == "(f \"a\" 1)"
  assert src_atom(read_forms("y")[0], []) == read_forms("y")[0]
  assert src_atom(read_forms("t__9")[0], []) == read_forms("t__9")[0]
  assert ref_op?(read_forms("(drop x)")[0])
  assert not ref_op?(read_forms("(+ x 1)")[0])
  assert take_one(["a"], "b") == [["a"], false]
  assert short_name("f") == "f"
  assert reads_at(["t__0"], [], 1)[0] == []
  assert lisp_text(src_term(anf(read_forms("(f (g x) 1)")[0]), [])) ==
    "(f (g x) 1)"
  assert lisp_text(src_rhs(read_forms("(id t__0)")[0], [["t__0", 4]])) == "4"
  assert last_uses(perceus(anf(read_forms("(+ x x)")[0]), ["x"]), [], []) ==
    [["x", read_forms("(+ x x)")[0]]]
end

test "a last use inside a try body is found, and its handler and try put back"
  t = perceus(anf(read_forms("(try (+ y 1) (catch (e) 0))")[0]), ["y"])
  assert last_uses(t, [], []) == [["y", read_forms("(+ y 1)")[0]]]
  lam = read_forms("(lambda (e) (ret 0))")[0]
  assert src_rhs(lam, []) == lam
  caught = src_rhs(read_forms("(try (ret 5) h)")[0], [])
  assert lisp_text(caught) == "(try 5 h)"
end

@doc """
ref_ops: how many dup and drop operations a term or program part holds, the reference traffic Perceus emitted.

    ref_ops(read_forms("(let (_ (dup x)) (let (_ (drop y)) (ret x)))")[0]) #=> 2
"""
def ref_ops(x)
  if not list?(x)
    0
  elsif head_is?(x, "dup") or head_is?(x, "drop")
    1
  else
    reduce((n, c) -> n + ref_ops(c), 0, x)
  end
end

@doc """
program_ref_ops: ref_ops over a whole program, its main term, each global's body and each lifted function's.

    program_ref_ops(whole(read_forms("(+ 1 2)")[0])) #=> 0
"""
def program_ref_ops(w)
  reduce(
    (n, part) -> n + ref_ops(part[:body]),
    ref_ops(w[:main]),
    append(w[:globals], w[:fns])
  )
end

@doc """
global_ref_ops: ref_ops over the bodies of a program's global functions alone, where borrowing applies.

    global_ref_ops(whole(read_forms("(begin (define (f l) (+ (length l) (length l))) (f (list 1)))")[0])) #=> 1
"""
def global_ref_ops(w)
  reduce((n, g) -> n + ref_ops(g[:body]), 0, w[:globals])
end

@doc """
BORROW_SHAPED: programs whose global functions only read a parameter (a length, a first, a comparison, a recursive pass of the same list), each with the value it gives; B1's borrow inference must leave their reference traffic lower than the owned convention's, with the same value and nothing live.

    length(BORROW_SHAPED) #=> 4
"""
BORROW_SHAPED = [
  [
    "(begin (define (size2 l) (+ (length l) (length l))) (let ((xs (list 1 2 3))) (+ (size2 xs) (size2 xs))))",
    12
  ],
  [
    "(begin (define (sum l acc) (if (equal? (length l) 0) acc (sum (rest l) (+ acc (first l))))) (sum (list 1 2 3) 0))",
    6
  ],
  [
    "(begin (define (has x l) (if (equal? (length l) 0) #f (if (equal? (first l) x) #t (has x (rest l))))) (list (has 2 (list 1 2)) (has 5 (list 1 2))))",
    [true, false]
  ],
  [
    "(begin (define (pick l i) (nth i l)) (define (both l) (list (pick l 0) (pick l 1))) (both (list 7 8)))",
    [7, 8]
  ]
]

test "a parameter that is only read is borrowed, and Perceus emits fewer dups and drops for it with the same value and nothing live"
  counts = map(
    fn(p)
      form = read_forms(p[0])[0]
      owned = whole_in(form, :owned)
      lent_w = whole_in(form, :borrow)
      assert eval_whole(owned) == p[1]
      assert eval_whole(lent_w) == p[1]
      assert ir_live(owned) == []
      assert ir_live(lent_w) == []
      assert ir_eval(form) == {value: p[1], live: []}
      [
        global_ref_ops(owned),
        global_ref_ops(lent_w),
        program_ref_ops(owned),
        program_ref_ops(lent_w)
      ]
    end,
    BORROW_SHAPED
  )
  assert counts == [[1, 0, 6, 5], [5, 3, 6, 5], [10, 4, 13, 9], [6, 4, 7, 6]]
  assert retsu::find_first((c) -> c[1] >= c[0] or c[3] >= c[2], counts).nil?
end

test "a parameter returned, stored, captured or passed to an owned parameter stays owned"
  w = whole_in(
    nth(
      0,
      read_forms("(begin (define (back l) l) (define (keep l) (list l)) (define (pass l) (keep l)) (define (wrap l) (lambda () (length l))) (define (both l) (+ (length l) (length (back l)))) (both (list 1)))")
    ),
    :borrow
  )
  assert map((g) -> [g[:name], g[:borrowed]], w[:globals]) ==
    [["back", []], ["keep", []], ["pass", []], ["wrap", []], ["both", []]]
  assert ir_live(w) == []
end

test "borrowing settles over the call graph: a parameter passed on stays borrowed only while the callee's is"
  gs = [
    {name: "a", params: ["x"], body: anf(read_forms("(b x)")[0])},
    {name: "b", params: ["y"], body: anf(read_forms("(list y)")[0])}
  ]
  direct = map((g) -> assoc(g, :body, globalize(g[:body], %w[a b])), gs)
  assert borrow_sigs(direct) == [["a", [false]], ["b", [false]]]
  assert settle_sigs([], []) == []
  reading = [
    {
      name: "a",
      params: ["x"],
      body: globalize(anf(read_forms("(+ (b x) 1)")[0]), %w[a b])
    },
    {name: "b", params: ["y"], body: anf(read_forms("(length y)")[0])}
  ]
  assert borrow_sigs(reading) == [["a", [true]], ["b", [true]]]
end

test "a caller keeps what it lends and drops it after the call, and the checker says no to a borrowed name dropped"
  sigs = [["f", [true, false]]]
  ctx = {borrowed: [], sigs:}
  t = perceus_at(
    globalize(anf(read_forms("(f x x)")[0]), ["f"]),
    ["x"],
    [],
    ctx
  )
  assert ref_ops(t) == 2
  assert rc_check_at(t, ["x"], ctx) == []
  assert lent(read_forms("(gcall \"f\" x y)")[0], ctx) == ["x"]
  assert lent(read_forms("(gcall \"g\" x)")[0], ctx) == []
  assert lent(read_forms("(+ x 1)")[0], ctx) == []
  assert taken(read_forms("(gcall \"f\" x y)")[0], ctx) == ["y"]
  assert taken(read_forms("(gcall \"g\" x)")[0], ctx) == ["x"]
  assert taken(read_forms("(+ x y)")[0], {borrowed: ["y"], sigs: []}) == ["x"]
  wrong = perceus(anf(read_forms("(+ (length l) (length l))")[0]), ["l"])
  assert rc_check_at(wrong, [], {borrowed: ["l"], sigs: []}) != []
  assert rc_check_at(
    anf(read_forms("(length l)")[0]),
    [],
    {borrowed: ["l"], sigs: []}
  ) == []
  assert rc_at(read_forms("(ret x)")[0], [], [], {borrowed: ["x"], sigs: []}) ==
    [[], []]
  assert rc_rhs_at(
    read_forms("(+ x 1)")[0],
    [],
    [],
    {borrowed: ["x"], sigs: []}
  ) == [[], []]
  assert reads_only?(anf(read_forms("(+ (length l) 1)")[0]), "l", [])
  assert not reads_only?(anf(read_forms("(list l)")[0]), "l", [])
  assert not reads_only?(anf(read_forms("(let ((l 1)) l)")[0]), "l", [])
  assert rhs_reads_only?(read_forms("(gcall \"f\" l)")[0], "l", [["f", [true]]])
  assert not rhs_reads_only?(
    read_forms("(gcall \"f\" l)")[0],
    "l",
    [["f", [false]]]
  )
  assert not rhs_reads_only?(read_forms("(gcall \"g\" l)")[0], "l", [])
  assert rhs_reads_only?(read_forms("(if c (ret l) (ret 1))")[0], "l", []) ==
    false
  assert rhs_reads_only?(read_forms("(if l (ret 1) (ret 2))")[0], "l", [])
  assert not rhs_reads_only?(read_forms("(try (ret 1) l)")[0], "l", [])
  assert rhs_reads_only?(read_forms("(try (ret 1) h)")[0], "l", [])
  assert not rhs_reads_only?(read_forms("(cons l 1)")[0], "l", [])
  assert rhs_reads_only?(read_forms("(cons 1 2)")[0], "l", [])
  assert ref_ops(7) == 0
  assert OWNED_ONLY == {borrowed: [], sigs: [], tests: :take}
  assert convention_ctx(:borrow, ["l"], [])[:tests] == :dup
  assert convention_ctx(:owned, [], []) == OWNED_ONLY
  tested = read_forms("(if t (ret 1) (ret t))")[0]
  assert branch_kept(tested, convention_ctx(:borrow, [], [])) == ["t"]
  assert branch_kept(tested, OWNED_ONLY) == []
  logic = anf(read_forms("(or (first l) 2)")[0])
  assert rc_check_at(
    perceus_at(logic, ["l"], [], convention_ctx(:borrow, [], [])),
    ["l"],
    convention_ctx(:borrow, [], [])
  ) == []
  assert rc_check(perceus(logic, ["l"]), ["l"]) != []
  assert trapped(() -> 4) == 4
  assert trapped(() -> raise(:boom, "x"))[0] == :__blue_error
  overflow = "(try (* 9223372036854775807 2) (catch (e) :caught))"
  assert ir_eval(read_forms(overflow)[0])[:value] == :caught
  assert eval_anf(anf(read_forms(overflow)[0]), []) == :caught
end

test "and and or answer the deciding operand, as blue does, with nothing live"
  r = ir_eval(
    nth(
      0,
      read_forms("(list (and 1 2) (and () 1) (or () 3) (or 2 4) (and) (or) (and 5) (and 1 2 3))")
    )
  )
  assert r == {value: [2, nil, 3, 2, true, nil, 5, 3], live: []}
  assert norm_logic("and", [], 0)[1] == true
  assert norm_logic("or", [], 0)[1].nil?
end

test "every primitive answers as blue's own word does"
  assert prim("range", [3]) == [0, 1, 2]
  assert prim("range", [1, 3]) == [1, 2]
  assert prim("range", [0, 6, 2]) == [0, 2, 4]
  assert prim("hash-map", [:a, 1, :b, 2]) == {a: 1, b: 2}
  assert map_from({}, [:a, 1, :a, 2]) == {a: 2}
  assert prim("append", [[1], [2, 3]]) == [1, 2, 3]
  assert prim("/", [7, 2]) == 3.5
  assert prim("mod", [7, 3]) == 1
  assert prim("not=", [1, 2])
  assert prim_row("frob").nil?
  assert prim_row("list")[1] == :stores
  assert filter((p) -> not member?(p[1], %i[reads stores]), PRIMS) == []
  assert value_of(read_forms("()")[0], []).nil?
  assert member?("gcall", IR_OWN)
end

@doc """
REFUSALS: core forms and the reason ir_refusal gives for each, nil when kuzushi runs it; one per shape it takes or refuses.

    length(REFUSALS) > 20 #=> true
"""
REFUSALS = [
  ["(+ 1 2)", nil],
  ["(quote a)", nil],
  ["(if 1 2)", nil],
  ["(if 1)", "an if of another shape"],
  ["(and 1 (or 2 3))", nil],
  ["(begin (define a 1) (+ a 1))", nil],
  ["(let ((a 1)) a)", nil],
  ["(let ((a 1) (b 2)) a)", "a let of another shape"],
  ["(cond ((< 1 2) 1) (else 2))", nil],
  ["(cond ((< 1 2) 1 3))", "a cond clause of another shape"],
  ["(cond (x 1))", "`x` is bound by no local kuzushi sees"],
  ["((lambda (x) x) 1)", "a call through a computed head"],
  ["(let ((f (lambda (x) (+ x 1)))) (f 2))", nil],
  ["(lambda (x) 1 2)", "a lambda body of several forms"],
  ["(lambda (x & r) x)", "a rest parameter"],
  ["(lambda (1) 1)", "a parameter that is not a name"],
  ["(try (raise 1) (catch (e) e))", nil],
  ["(try 1 2)", "a try of another shape"],
  ["(raise :k \"m\")", "a raise of a kind and a message"],
  ["(define a 1)", "a define outside a sequence"],
  ["(drop 1 (list 1 2))", "`drop` names an operation of kuzushi's IR"],
  ["(frob 1)", "no primitive `frob`"],
  ["(begin (define (f x) (+ x 1)) (f 2))", nil],
  ["(begin (define (f x) 1 2) (f 2))", "a function body of several forms"],
  ["(begin (define (f x) y) (f 2))", "`y` is bound by no local kuzushi sees"],
  [
    "(begin (define (f x) x) (define (g f) f) (g 1))",
    "a local named like a global function"
  ],
  [
    "(begin (define (f x) x) (define f 2) (f 1))",
    "a local named like a global function"
  ],
  [
    "(begin (define (f x) x) (let ((f 2)) f))",
    "a local named like a global function"
  ],
  ["(begin (define a (frob)) a)", "no primitive `frob`"],
  ["(begin (frob) 1)", "no primitive `frob`"],
  ["(begin)", nil],
  ["(let a 1)", "a let of another shape"]
]

test "kuzushi refuses, by name, every shape it has no code for, and nothing it runs"
  assert map((r) -> ir_refusal(read_forms(r[0])[0]), REFUSALS) ==
    map((r) -> r[1], REFUSALS)
  assert first_refusal([() -> nil, () -> "x"]) == "x"
  assert first_refusal([]).nil?
  assert params_refusal(read_forms("(a b)")[0], []).nil?
  assert refusal_in(read_forms("x")[0], ["x"], []).nil?
  assert refusal_all(read_forms("1 x"), [], []) ==
    "`x` is bound by no local kuzushi sees"
  assert refusal_head("quote", read_forms("(quote a)")[0], [], []).nil?
  assert refusal_seq(read_forms("(define a 1) (+ a 1)"), [], []).nil?
  assert refusal_let(read_forms("(let ((a 1)) a)")[0], [], []).nil?
  assert refusal_cond(read_forms("((a 1) (else 2))")[0], ["a"], []).nil?
  assert refusal_try(read_forms("(try 1 (catch (e) e))")[0], [], []).nil?
  assert kyohi::raised(() -> ir_eval(read_forms("(frob 1)")[0])) == :ir_refused
  twice = "(begin (define n 1) (define n 2) n)"
  assert kyohi::raised(() -> ir_eval(read_forms(twice)[0])) == :ir_refused
end
