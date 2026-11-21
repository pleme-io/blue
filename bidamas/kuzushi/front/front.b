@moduledoc """
kuzushi/front: the IR front over blue's resolved tree, the passes a backend reads before it makes code (docs/PURE-BLUE.md B1). The tree is read into nodes: an Int, a list of nodes, or {sym:}, {str:}, {kw:}, {flt:}. Over them: names, records and their field kinds, the type two branches share, read counts, the call graph and the definitions that recurse, and the least value of an expression and the Int parameters never below zero. Each pass answers a fact, nil where there is none; a backend refuses what it cannot represent (chuuzou, the IR to Rust AST backend, is the first).

    front("(define (%root/f x) x)")[:fns] #=> ["%root/f"]
"""

@doc """
node_of: a form read_forms gives, as a node of the front's tree: an Int as itself, a list as its nodes, and {sym:}, {str:}, {kw:} or {flt:} for a symbol, a string, a keyword or a Float. A boolean is the symbol the resolved tree writes for it, #t or #f.

    node_of(read_forms("(f :k \"s\" 2.5 7)")[0]) #=> [{sym: "f"}, {kw: "k"}, {str: "s"}, {flt: 2.5}, 7]
"""
def node_of(form)
  if list?(form)
    map(node_of, form)
  elsif symbol?(form)
    {sym: to_s(form)}
  elsif keyword?(form)
    {kw: to_s(form)}
  elsif string?(form)
    {str: form}
  elsif float?(form)
    {flt: form}
  elsif form == true
    {sym: "#t"}
  elsif form == false
    {sym: "#f"}
  else
    form
  end
end

@doc """
tree_read: the forms of a resolved tree's text, as nodes. The front reads with blue's own reader, so an unbalanced text is refused as blue refuses it (:parse_error).

    tree_read("(define %root/X 5)") #=> [[{sym: "define"}, {sym: "%root/X"}, 5]]
"""
def tree_read(text)
  map(node_of, read_forms(text))
end

@doc """
node_sym?: whether a node is a symbol.

    node_sym?({sym: "f"}) #=> true
"""
def node_sym?(n)
  node_sym(n) != nil
end

@doc """
node_sym: a symbol node's name, nil for any other node.

    node_sym({sym: "f"}) #=> "f"
"""
def node_sym(n)
  if not map?(n)
    nil
  else
    n[:sym]
  end
end

@doc """
node_head: the name of the symbol a list node starts with, nil for any other node.

    node_head(tree_read("(if c 1 2)")[0]) #=> "if"
"""
def node_head(n)
  if list?(n) and count(n) > 0
    node_sym(first(n))
  end
end

@doc """
pair_value: the value of the first [key, value] pair whose key is key, nil when none is.

    pair_value("b", [["a", 1], ["b", 2]]) #=> 2
"""
def pair_value(key, pairs)
  hit = find(pairs, (p) -> first(p) == key)
  if hit.nil?
    nil
  else
    second(hit)
  end
end

@doc """
local_of: a qualified name's local part, for a definition of the program itself (%root/...), nil for any other.

    local_of("%root/f") #=> "f"
"""
def local_of(name)
  if starts_with?(name, "%root/")
    join(drop(6, chars(name)), "")
  end
end

@doc """
field_kind: the IR's type for a record field's declared type: :word, :bool, :float, :str or :list (of Ints), nil for a type no field kind holds.

    field_kind(tree_read("(List Int)")[0]) #=> :list
"""
def field_kind(t)
  kinds = [
    ["Int", :word],
    ["Bool", :bool],
    ["Float", :float],
    ["Str", :str],
    ["List", :list]
  ]
  if node_sym?(t)
    pair_value(node_sym(t), kinds)
  elsif list?(t) and
      count(t) == 2 and
      node_sym(first(t)) == "List" and
      node_sym(second(t)) == "Int"
    :list
  end
end

@doc """
record_of: the record a resolved `(blue-record name pred :field ...)` form declares, with each field's kind: an untyped field the word, a typed one its field_kind, nil where no kind holds it (a backend refuses that field).

    record_of(tree_read("(blue-record %root/p %root/p? :x (:y Float))")[0]) #=> {name: "%root/p", pred: "%root/p?", fields: ["x", "y"], types: [:word, :float]}
"""
def record_of(form)
  pairs = map(
    fn(k)
      if list?(k)
        kind = if count(k) == 2
          field_kind(second(k))
        end
        [first(k)[:kw], kind]
      else
        [k[:kw], :word]
      end
    end,
    drop(3, form)
  )
  {
    name: node_sym(second(form)),
    pred: node_sym(third(form)),
    fields: map(first, pairs),
    types: map(second, pairs)
  }
end

@doc """
join_ty: the one type two branches share: the type itself when both are the same, :dyn when both hold records (a record's name or :dyn), nil when they share none.

    join_ty("%root/a", "%root/b") #=> :dyn
"""
def join_ty(a, b)
  if a == b
    a
  elsif (string?(a) or a == :dyn) and (string?(b) or b == :dyn)
    :dyn
  end
end

@doc """
use_count: how many times a node reads name on its longest path: an if counts its test and the larger of its branches; a call's head is not a read.

    use_count(tree_read("(if c xs (append xs (list 1)))")[0], "xs") #=> 1
"""
def use_count(n, name)
  h = node_head(n)
  if node_sym?(n)
    if node_sym(n) == name
      1
    else
      0
    end
  elsif not list?(n) or count(n) == 0
    0
  elsif h == "if"
    other = if count(n) > 3
      use_count(fourth(n), name)
    else
      0
    end
    taken = use_count(third(n), name)
    use_count(second(n), name) +
      if taken > other
        taken
      else
        other
      end
  else
    reduce((acc, a) -> acc + use_count(a, name), 0, rest(n))
  end
end

@doc """
mentions?: whether any symbol in a node, a call's head included, is one of names.

    mentions?(tree_read("(f (list 1))"), ["list"]) #=> true
"""
def mentions?(n, names)
  if node_sym?(n)
    member?(node_sym(n), names)
  elsif list?(n)
    any?((x) -> mentions?(x, names), n)
  else
    false
  end
end

@doc """
tail_calls_self?: whether a node, in tail position, calls the definition name.

    tail_calls_self?(tree_read("(if c 1 (%root/f 2))")[0], "%root/f") #=> true
"""
def tail_calls_self?(n, name)
  h = node_head(n)
  if h == name
    true
  elsif h == "if"
    any?((b) -> tail_calls_self?(b, name), drop(2, n))
  elsif h == "begin"
    tail_calls_self?(last(rest(n)), name)
  else
    false
  end
end

@doc """
calls_in: the definitions of fns a node calls. A call of me in tail position is left out, since that definition loops instead (me is nil when it does not).

    calls_in(tree_read("(+ (%root/f 1) (%root/g 2))")[0], ["%root/f"], nil, true) #=> ["%root/f"]
"""
def calls_in(n, fns, me, tail)
  h = node_head(n)
  if not list?(n) or count(n) == 0
    []
  elsif h == "if"
    reduce(
      (acc, b) -> append(acc, calls_in(b, fns, me, tail)),
      calls_in(second(n), fns, me, false),
      drop(2, n)
    )
  elsif h == "begin"
    forms = rest(n)
    reduce(
      (acc, f) -> append(acc, calls_in(f, fns, me, false)),
      calls_in(last(forms), fns, me, tail),
      butlast(forms)
    )
  else
    own = if member?(h, fns) and not (tail and h == me)
      [h]
    else
      []
    end
    reduce((acc, a) -> append(acc, calls_in(a, fns, me, false)), own, rest(n))
  end
end

@doc """
reach_from: every definition reachable from frontier through graph, a list of [name, callees] pairs, after the ones in seen.

    reach_from(["a"], [], [["a", ["b"]], ["b", ["a"]]]) #=> ["a", "b"]
"""
def reach_from(frontier, seen, graph)
  if empty?(frontier)
    seen
  elsif member?(first(frontier), seen)
    reach_from(rest(frontier), seen, graph)
  else
    reach_from(
      append(rest(frontier), pair_value(first(frontier), graph) or []),
      append(seen, [first(frontier)]),
      graph
    )
  end
end

@doc """
recursive_defs: of fns, the definitions in fn_forms (define or define-typed, the body last) that reach themselves through a call that is not a tail call to themselves: each needs a frame per level.

    recursive_defs(tree_read("(define (%root/f n) (+ 1 (%root/f n)))"), ["%root/f"]) #=> ["%root/f"]
"""
def recursive_defs(fn_forms, fns)
  graph = map(
    fn(f)
      name = node_sym(first(second(f)))
      body = last(f)
      me = if tail_calls_self?(body, name)
        name
      end
      [name, calls_in(body, fns, me, true)]
    end,
    fn_forms
  )
  filter(
    fn(name)
      member?(name, reach_from(pair_value(name, graph) or [], [], graph))
    end,
    fns
  )
end

@doc """
least_of: the least value a node can have where it stands, from literals, the [name, least] facts in ctx[:lb] and the operators that keep a bound, nil when none is known. A Euclidean remainder by a positive literal is never negative, whatever its left side.

    least_of(tree_read("(- n 1)")[0], {lb: [["n", 2]]}) #=> 1
"""
def least_of(n, ctx)
  h = node_head(n)
  bounds = (xs) -> map((x) -> least_of(x, ctx), xs)
  all_nonneg = (bs) -> every?((b) -> b != nil and b >= 0, bs)
  if integer?(n)
    n
  elsif node_sym?(n)
    pair_value(node_sym(n), ctx[:lb] or [])
  elsif not list?(n)
    nil
  elsif h == "+" and all_nonneg(bounds(rest(n)))
    reduce((a, b) -> a + b, 0, bounds(rest(n)))
  elsif h == "*" and all_nonneg(bounds(rest(n)))
    reduce((a, b) -> a * b, 1, bounds(rest(n)))
  elsif h == "-" and
      count(n) == 3 and
      integer?(third(n)) and
      least_of(second(n), ctx) != nil
    least_of(second(n), ctx) - third(n)
  elsif member?(h, %w[mod modulo rem]) and
      count(n) == 3 and
      integer?(third(n)) and
      third(n) > 0
    0
  end
end

@doc """
given: ctx inside the branch of cond taken when it is truth: a comparison of a name with a literal raises the name's least value.

    given(tree_read("(< n 2)")[0], false, {lb: []})[:lb] #=> [["n", 2]]
"""
def given(cond, truth, ctx)
  h = node_head(cond)
  lhs = if list?(cond) and count(cond) == 3
    second(cond)
  end
  k = if list?(cond) and count(cond) == 3
    third(cond)
  end
  name = node_sym(lhs)
  old = if name.nil?
    nil
  else
    pair_value(name, ctx[:lb] or [])
  end
  least = if name.nil? or not integer?(k)
    nil
  elsif truth and h == ">"
    k + 1
  elsif truth and member?(h, %w[>= equal?])
    k
  elsif not truth and h == "<"
    k
  elsif not truth and h == "<="
    k + 1
  elsif not truth and h == "equal?" and old == k
    k + 1
  end
  if h == "and" and truth
    reduce((c, x) -> given(x, true, c), ctx, rest(cond))
  elsif least.nil? or old != nil and old >= least
    ctx
  else
    {**ctx, lb: append([[name, least]], ctx[:lb] or [])}
  end
end

@doc """
call_sites: every call of a definition of fns inside a node, with the facts that hold where it is made, as [callee, arguments, ctx].

    length(call_sites(tree_read("(if (< n 2) n (%root/f (- n 1)))")[0], ["%root/f"], {lb: []})) #=> 1
"""
def call_sites(n, fns, ctx)
  h = node_head(n)
  if not list?(n) or count(n) == 0
    []
  elsif h == "if"
    c = second(n)
    append(
      call_sites(c, fns, ctx),
      call_sites(third(n), fns, given(c, true, ctx)),
      if count(n) > 3
        call_sites(fourth(n), fns, given(c, false, ctx))
      else
        []
      end
    )
  else
    own = if member?(h, fns)
      [[h, rest(n), ctx]]
    else
      []
    end
    reduce((acc, a) -> append(acc, call_sites(a, fns, ctx)), own, rest(n))
  end
end

@doc """
nonneg_params: the Int parameters of the define-typed forms fn_forms never below zero, as [definition, parameter]: the largest set such that, assuming it, every call in the definitions and in the top-level forms top passes each a value whose least is at least zero. It starts from every Int parameter and drops one a call cannot vouch for until nothing more drops, so the set left is an inductive invariant.

    nonneg_params(tree_read("(define-typed (%root/f (n Int)) Int n)"), tree_read("(%root/f 3)"), {lb: []}) #=> [["%root/f", "n"]]
"""
def nonneg_params(fn_forms, top, env)
  fns = map((f) -> node_sym(first(second(f))), fn_forms)
  start = reduce(
    fn(acc, f)
      sig = second(f)
      append(
        acc,
        map(
          (p) -> [node_sym(first(sig)), node_sym(first(p))],
          filter((p) -> node_sym(second(p)) == "Int", rest(sig))
        )
      )
    end,
    [],
    fn_forms
  )
  nonneg_from(start, fn_forms, fns, top, env)
end

@doc """
nonneg_from: one step of nonneg_params: of the pairs held, those every call site, read with held assumed, still vouches for; repeated until none drops.

    nonneg_from([["%root/f", "n"]], tree_read("(define-typed (%root/f (n Int)) Int n)"), ["%root/f"], tree_read("(%root/f (- 0 1))"), {lb: []}) #=> []
"""
def nonneg_from(held, fn_forms, fns, top, env)
  sites = append(
    reduce(
      fn(acc, f)
        sig = second(f)
        name = node_sym(first(sig))
        lb = append(
          map(
            (p) -> [node_sym(first(p)), 0],
            filter((p) -> member?([name, node_sym(first(p))], held), rest(sig))
          ),
          env[:lb] or []
        )
        append(acc, call_sites(last(f), fns, {**env, lb:}))
      end,
      [],
      fn_forms
    ),
    reduce((acc, f) -> append(acc, call_sites(f, fns, env)), [], top)
  )
  params_of = fn(g)
    map(
      (p) -> node_sym(first(p)),
      rest(second(find(fn_forms, (f) -> node_sym(first(second(f))) == g)))
    )
  end
  kept = filter(
    fn(pair)
      every?(
        fn(site)
          if first(site) != first(pair)
            true
          else
            ps = params_of(first(pair))
            i = find(range(count(ps)), (j) -> ps[j] == second(pair))
            b = least_of(second(site)[i], third(site))
            b != nil and b >= 0
          end
        end,
        sites
      )
    end,
    held
  )
  if count(kept) == count(held)
    held
  else
    nonneg_from(kept, fn_forms, fns, top, env)
  end
end

@doc """
definition?: whether a node defines a named function: (define (name params...) body) or (define-typed (name (param Type)...) Type body).

    definition?(tree_read("(define (%root/f x) x)")[0]) #=> true
"""
def definition?(n)
  member?(node_head(n), %w[define define-typed]) and list?(second(n))
end

@doc """
param_name: a definition's parameter's name, typed ((p Int)) or not (p).

    param_name(tree_read("(p Int)")[0]) #=> "p"
"""
def param_name(p)
  if list?(p)
    node_sym(first(p))
  else
    node_sym(p)
  end
end

@doc """
front: the IR front over a resolved file's text: its forms read, the definitions' names, the records, the definitions that recurse other than in their own tail, the Int parameters never below zero, and each definition's [name, reads per parameter].

    front("(define (%root/f x) (%root/f x)) (%root/f 1)")[:recursive] #=> []
"""
def front(text)
  forms = tree_read(text)
  defs = filter(definition?, forms)
  fns = map((f) -> node_sym(first(second(f))), defs)
  typed = filter((f) -> node_head(f) == "define-typed", defs)
  top = filter(
    fn(f)
      not definition?(f) and not member?(node_head(f), %w[use blue-record])
    end,
    forms
  )
  {
    forms:,
    fns:,
    records: map(
      record_of,
      filter((f) -> node_head(f) == "blue-record", forms)
    ),
    recursive: recursive_defs(defs, fns),
    nonneg: nonneg_params(typed, top, {lb: []}),
    uses: map(
      fn(f)
        [
          node_sym(first(second(f))),
          map((p) -> use_count(last(f), param_name(p)), rest(second(f)))
        ]
      end,
      defs
    )
  }
end

test "the front reads a resolved tree into nodes, and refuses an unbalanced one as blue does"
  forms = tree_read(
    join_lines(["(define %root/X 5)", "(f \"a b\" :k (g) #t #f 2.5)"])
  )
  assert length(forms) == 2
  assert forms[0] == [{sym: "define"}, {sym: "%root/X"}, 5]
  assert forms[1] ==
    [
      {sym: "f"},
      {str: "a b"},
      {kw: "k"},
      [{sym: "g"}],
      {sym: "#t"},
      {sym: "#f"},
      {flt: 2.5}
    ]
  assert tree_read("") == []
  unbalanced = map(
    fn(text)
      begin
        tree_read(text)
        nil
      rescue e
        e.kind
      end
    end,
    %w[(a a)]
  )
  assert unbalanced == %i[parse_error parse_error]
  assert node_of(read_forms("-3")[0]) == -3
end

test "a node's symbol, head and a pair's value are read by name, nil where there is none"
  assert node_sym?({sym: "f"})
  assert not node_sym?(3)
  assert node_sym({str: "s"}).nil?
  assert node_sym([]).nil?
  assert node_head(tree_read("(if c 1 2)")[0]) == "if"
  assert node_head({sym: "x"}).nil?
  assert node_head([]).nil?
  assert pair_value("b", [["a", 1], ["b", 2]]) == 2
  assert pair_value("c", [["a", 1]]).nil?
  assert local_of("%root/f") == "f"
  assert local_of("kiban/mmio_write").nil?
end

test "a record keeps each field's kind, nil for a type no field holds, and two record types join as dyn"
  rec = record_of(
    tree_read("(blue-record %root/p %root/p? :x (:y Float) (:z (List Str)))")[0]
  )
  assert rec[:fields] == %w[x y z]
  assert rec[:types] == [:word, :float, nil]
  assert get(
    record_of(tree_read("(blue-record %root/q %root/q? (:a Int Int))")[0]),
    :types
  ) == [nil]
  assert field_kind(tree_read("Bool")[0]) == :bool
  assert field_kind(tree_read("(List Int)")[0]) == :list
  assert field_kind(tree_read("(List Str)")[0]).nil?
  assert field_kind(tree_read("Point")[0]).nil?
  assert join_ty(:word, :word) == :word
  assert join_ty("%root/a", :dyn) == :dyn
  assert join_ty(:word, :bool).nil?
end

test "reads are counted on the longest path, and a mention sees a call's head"
  assert use_count(tree_read("(if c xs (append xs (list 1)))")[0], "xs") == 1
  assert use_count(tree_read("(f xs (count xs))")[0], "xs") == 2
  assert use_count(tree_read("(if c xs)")[0], "xs") == 1
  assert use_count(tree_read("(if xs 1 2)")[0], "xs") == 1
  assert use_count([], "xs") == 0
  assert use_count(4, "xs") == 0
  assert mentions?(tree_read("(f (list 1))"), ["list"])
  assert not mentions?(tree_read("(f 1)"), ["list"])
end

test "a definition that recurses outside its own tail is recursive, through the call graph, and one that loops in its tail is not"
  body = tree_read("(begin (g 1) (if c 1 (%root/f 2)))")[0]
  assert tail_calls_self?(body, "%root/f")
  assert not tail_calls_self?(tree_read("(+ 1 (%root/f 2))")[0], "%root/f")
  assert calls_in(
    tree_read("(+ (%root/f 1) (%root/g 2))")[0],
    ["%root/f"],
    nil,
    true
  ) == ["%root/f"]
  assert calls_in(body, ["%root/f"], "%root/f", true) == []
  assert calls_in(body, ["%root/f"], nil, true) == ["%root/f"]
  assert reach_from(["a"], [], [["a", ["b"]], ["b", ["a"]]]) == %w[a b]
  assert reach_from([], ["x"], []) == ["x"]
  looping = "(define-typed (%root/f (n Int)) Int (%root/f n))"
  assert recursive_defs(tree_read(looping), ["%root/f"]) == []
  mutual = "(define (%root/a n) (+ 1 (%root/b n))) (define (%root/b n) (%root/a n))"
  assert recursive_defs(tree_read(mutual), %w[%root/a %root/b]) ==
    %w[%root/a %root/b]
end

test "a least value follows literals, facts and the operators that keep a bound, and a branch's test raises it"
  assert least_of(tree_read("(- n 1)")[0], {lb: [["n", 2]]}) == 1
  assert least_of(tree_read("(mod x 3)")[0], {lb: []}) == 0
  assert least_of(tree_read("(+ n x)")[0], {lb: [["n", 0]]}).nil?
  assert least_of(tree_read("(* 2 3)")[0], {lb: []}) == 6
  assert least_of({str: "s"}, {lb: []}).nil?
  assert least_of(tree_read("(f x)")[0], {lb: []}).nil?
  assert least_of(tree_read("(- x 1)")[0], {lb: []}).nil?
  assert least_of(tree_read("(mod x y)")[0], {lb: []}).nil?
  assert least_of(tree_read("(+ 1 2)")[0], {lb: []}) == 3
  assert given(tree_read("(< n 2)")[0], false, {lb: []})[:lb] == [["n", 2]]
  assert given(tree_read("(equal? i 0)")[0], false, {lb: [["i", 0]]})[:lb] ==
    [["i", 1], ["i", 0]]
  assert given(tree_read("(> n 5)")[0], true, {lb: []})[:lb] == [["n", 6]]
  assert given(tree_read("(<= n 5)")[0], false, {lb: []})[:lb] == [["n", 6]]
  assert given(tree_read("(>= n 5)")[0], true, {lb: [["n", 9]]})[:lb] ==
    [["n", 9]]
  assert given(tree_read("(and (> n 0) (> m 1))")[0], true, {lb: []})[:lb] ==
    [["m", 2], ["n", 1]]
  site = tree_read("(if (< n 2) n (%root/f (- n 1)))")[0]
  assert length(call_sites(site, ["%root/f"], {lb: []})) == 1
  assert call_sites(site, ["%root/f"], {lb: []})[0][2][:lb] == [["n", 2]]
  assert nth(
    0,
    call_sites(tree_read("(if c (%root/f 1))")[0], ["%root/f"], {lb: []})[0]
  ) == "%root/f"
  assert call_sites(7, ["%root/f"], {lb: []}) == []
end

test "an Int parameter is never below zero when every call vouches for it, and one call that cannot drops it"
  f = tree_read("(define-typed (%root/f (n Int)) Int n)")
  assert nonneg_params(f, tree_read("(%root/f 3)"), {lb: []}) == [%w[%root/f n]]
  assert nonneg_from(
    [%w[%root/f n]],
    f,
    ["%root/f"],
    tree_read("(%root/f (- 0 1))"),
    {lb: []}
  ) == []
  down = tree_read("(define-typed (%root/d (n Int)) Int (if (< n 1) 0 (%root/d (- n 1))))")
  assert nonneg_params(down, tree_read("(%root/d 5)"), {lb: []}) ==
    [%w[%root/d n]]
  pair = tree_read("(define-typed (%root/h (n Int)) Int (%root/k n)) (define-typed (%root/k (m Int)) Int m)")
  assert nonneg_params(pair, tree_read("(%root/h 1)"), {lb: []}) ==
    [%w[%root/h n], %w[%root/k m]]
end

test "the front reads a file's definitions, records, recursion, ranges and reads in one pass"
  text = join_lines(
    [
      "(blue-record %root/p %root/p? :x)",
      "(define (%root/f x) (+ x (%root/f x)))",
      "(define-typed (%root/g (n Int)) Int (* n n))",
      "(%root/g 2)"
    ]
  )
  r = front(text)
  assert r[:fns] == %w[%root/f %root/g]
  assert r[:records][0][:name] == "%root/p"
  assert r[:recursive] == ["%root/f"]
  assert r[:nonneg] == [%w[%root/g n]]
  assert r[:uses] == [["%root/f", [2]], ["%root/g", [2]]]
  assert definition?(tree_read("(define (%root/f x) x)")[0])
  assert not definition?(tree_read("(define %root/X 1)")[0])
  assert param_name(tree_read("(p Int)")[0]) == "p"
  assert param_name({sym: "q"}) == "q"
end
