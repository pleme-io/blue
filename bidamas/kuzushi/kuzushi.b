@moduledoc """
kuzushi (崩し) — blue's core forms broken down into A-normal form, and an interpreter for the result: the first level of the compiler's IR (docs/PURE-BLUE.md B1).

In A-normal form every call's arguments are atoms (a literal or a name) and every intermediate value is named by a `let`, so evaluation order is explicit and each name has one use site a later pass can count. A term is `(ret atom)`, `(let (v rhs) term)`, where an rhs is `(op atom...)` or `(if atom term term)`. The source is the core `blue ast --resolved` prints: literals, names, `if`, `begin` and calls. `eval_anf` runs a term, so a pass can be checked against the tree-walker on the same program.

    eval_anf(anf(read_forms("(+ 1 (+ 2 3))")[0]), []) #=> 6
"""

use("retsu", %i[first rest])

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
