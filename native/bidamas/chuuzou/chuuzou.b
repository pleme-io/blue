@moduledoc """
chuuzou (鋳造, casting): blue's native backend. A checked blue program and a
board spec go in; a Rust crate the board's rustc builds as no_std comes out,
with no evaluator and no collector in it.

theory/BLUE-NATIVE.md is the design; this is milestone N0 (§7). Plan, fixed
before the code (blue-development-cycle stage 1):

| Need | Exists | Move |
|---|---|---|
| parse, resolve, check the program | `blue check`, `blue ast --resolved` (the pipeline) | reuse, through `self_exe()`: the backend never sees an unchecked tree |
| qualified names (L1) | the resolved tree names every definition `%root/f` and every package word `kiban/mmio_write` | reuse |
| a typed Rust AST, rendered once | tatara-rust-ast 0.1.8 (`File`, typed control flow), its `tatara-rust-emit` CLI | reuse across a process boundary; the tree is JSON built here |
| board facts | kiban's specs | reuse |
| reading the tree's text | nothing in blue reads an S-expression | `cz_read` below; the first instance, so it stays here until a second reader appears |

The shape: read → lower (L1 qualify, L5 represent, tail calls to loops, L8
the AST) → emit. The passes the design names and N0 lacks (closure
conversion, monomorphisation, partial evaluation, placement, discharge) are
absent because the N0 subset does not produce their input: every refusal
below names the construct and the rule, so a program outside the subset is a
compile error, never a wrong image.

The subset, and what each lowers to (W is the board word: u32 on a board,
i64 on the host board `host64`):

  def f(x: Int) -> Int      fn bl_f<I: Io>(io: &mut I, p_x: W) -> W
  NAME = <constant expr>    const BL_NAME: W, built from literals and constants
  NAME = <expr>             a local of the top level, read by later top-level forms
  + - * mod                 kiban_io::checked(a.checked_op(b)): overflow is a fault
  floor(a / b)              kiban_io::floor_div (i64) or checked_div (u32)
  wrapping_add(a, b)        a.wrapping_add(b), on the 32-bit word only
  == != < <= > >= not and or  comparisons and logic
  if / begin                if / blocks; an `if` with no else where its value is dropped
  a tail call to itself     a loop (the parameters rebound, then continue)
  a call that recurses      a frame per level under the board's max_depth; a board
                            with none refuses it, mutual recursion included
  f(g(x)) where g reaches   every argument bound first, so `io` is borrowed
  the board                 by one call at a time
  mmio_write(a, 8|32, v)    io.write8 / io.write32, through the board's seam
  top-level expressions     pub fn main, called by the seam

On a board, Int lowers to u32 (L5 minimal): the checker has no fixed-width
types yet (BLUE-NATIVE.md §5.1), so a negative value or one past 2^32 - 1 is
a fault on the board where the interpreter would carry on. On the host, Int
is i64 with checked arithmetic, as the interpreter's Int, and the corpus in
native/corpus holds the two executions to one output.

The first pass reads the resolved tree's text into nodes:

    cz_read("(define %root/X 5)") #=> [[{sym: "define"}, {sym: "%root/X"}, 5]]
"""

use("kiban", [:kb_board])

# ── Reading the resolved tree ─────────────────────────────────────────────
#
# A node is an Int, a list of nodes, or a map: {sym: name}, {str: text},
# {kw: name}.

def cz_delims()
  %w[( )]
end

@doc """
cz_tokens: Split S-expression text into tokens: "(", ")", atoms, and strings kept with
their quotes. A fold over the characters, so length never costs depth.
"""
def cz_tokens(text)
  start = {toks: [], cur: "", in_str: false, esc: false}
  step = fn(st, c)
    if st[:in_str]
      if st[:esc]
        assoc(assoc(st, :cur, concat(st[:cur], c)), :esc, false)
      elsif c == "\\"
        assoc(assoc(st, :cur, concat(st[:cur], c)), :esc, true)
      elsif c == "\""
        {
          toks: append(st[:toks], [concat(st[:cur], c)]),
          cur: "",
          in_str: false,
          esc: false
        }
      else
        assoc(st, :cur, concat(st[:cur], c))
      end
    elsif c == "\""
      assoc(assoc(cz_flush(st), :cur, "\""), :in_str, true)
    elsif member?(c, cz_delims)
      f = cz_flush(st)
      assoc(f, :toks, append(f[:toks], [c]))
    elsif c == " " or c == line_break or c == "\t"
      cz_flush(st)
    else
      assoc(st, :cur, concat(st[:cur], c))
    end
  end
  cz_flush(reduce(step, start, chars(text)))[:toks]
end

def cz_flush(st)
  if st[:cur] == ""
    st
  else
    assoc(assoc(st, :toks, append(st[:toks], [st[:cur]])), :cur, "")
  end
end

@doc """
cz_atom: One atom's node.
"""
def cz_atom(tok)
  n = to_int(tok)
  if n != nil
    n
  elsif starts_with?(tok, "\"")
    {str: cz_unescape(butlast(rest(chars(tok))))}
  elsif starts_with?(tok, ":")
    {kw: join(rest(chars(tok)), "")}
  else
    {sym: tok}
  end
end

@doc """
cz_unescape: The characters of a string literal's body with its escapes resolved.
"""
def cz_unescape(cs)
  st = reduce(
    fn(acc, c)
      if acc[:esc]
        ch = if c == "n"
          line_break
        elsif c == "t"
          "\t"
        else
          c
        end
        {out: concat(acc[:out], ch), esc: false}
      elsif c == "\\"
        assoc(acc, :esc, true)
      else
        assoc(acc, :out, concat(acc[:out], c))
      end
    end,
    {out: "", esc: false},
    cs
  )
  st[:out]
end

@doc """
cz_read: The forms in `text`. A stack of open lists, folded over the tokens; an
unbalanced text is refused.

    cz_read("") #=> []
"""
def cz_read(text)
  st = reduce(
    fn(stack, tok)
      if tok == "("
        append(stack, [[]])
      elsif tok == ")"
        if count(stack) < 2
          raise(:chuuzou, "unbalanced `)` in the resolved tree")
        end
        done = last(stack)
        rest_ = butlast(stack)
        append(butlast(rest_), [append(last(rest_), [done])])
      else
        append(butlast(stack), [append(last(stack), [cz_atom(tok)])])
      end
    end,
    [[]],
    cz_tokens(text)
  )
  if count(st) != 1
    raise(:chuuzou, "unbalanced `(` in the resolved tree")
  end
  first(st)
end

# ── Node predicates ────────────────────────────────────────────────────────

def cz_sym?(n)
  map?(n) and n[:sym] != nil
end

def cz_sym(n)
  if cz_sym?(n)
    n[:sym]
  end
end

def cz_head(n)
  if list?(n) and count(n) > 0
    cz_sym(first(n))
  end
end

def cz_refuse(what)
  raise(:chuuzou, what)
end

# ── Names (L1: already qualified by the resolver) ─────────────────────────

def cz_local(name)
  if starts_with?(name, "%root/")
    join(drop(6, chars(name)), "")
  else
    cz_refuse(
      "`#{name}` is not a definition of this program; at N0 a native program uses its own definitions and its board's words only"
    )
  end
end

def cz_ident_ok?(s)
  every?(
    fn(c)
      member?(
        c,
        chars("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
      )
    end,
    chars(s)
  )
end

def cz_checked_ident(s, why)
  if s == "" or not cz_ident_ok?(s)
    cz_refuse(
      "`#{s}` cannot be a Rust identifier (#{why}); name it with letters, digits and _"
    )
  end
  s
end

def cz_fn_name(qualified)
  concat("bl_", cz_checked_ident(cz_local(qualified), "a function"))
end

def cz_const_name(qualified)
  concat("BL_", upcase(cz_checked_ident(cz_local(qualified), "a constant")))
end

def cz_param_name(name)
  concat("p_", cz_checked_ident(name, "a parameter"))
end

# ── The Rust AST, as tatara-rust-ast's JSON (the only way nodes are made) ─

def rs_path(name)
  {kind: "path", segments: [name]}
end

def rs_u32(n)
  if not integer?(n) or n < 0 or n > 4_294_967_295
    cz_refuse("the literal #{n} does not fit the board word (u32)")
  end
  {kind: "int", value: n, suffix: "u32"}
end

@doc """
rs_word: An integer literal in the board's word: u32 on a 32-bit board, i64 on the
64-bit host, where a negative literal is the negation of its magnitude.

    rs_word(5, 64) #=> {kind: "int", value: 5, suffix: "i64"}
    rs_word(-5, 64)[:op] #=> "neg"
"""
def rs_word(n, word)
  if word == 32
    rs_u32(n)
  elsif not integer?(n)
    cz_refuse("`#{to_s(n)}` is not an integer of the board word (i64)")
  elsif n < 0
    {kind: "unary", op: "neg", expr: {kind: "int", value: -n, suffix: "i64"}}
  else
    {kind: "int", value: n, suffix: "i64"}
  end
end

def cz_word_ty(word)
  if word == 64
    "i64"
  else
    "u32"
  end
end

def rs_call(path, args)
  {kind: "call", func: path, args:}
end

def rs_method(receiver, method, args)
  {kind: "method-call", receiver:, method:, args:}
end

def rs_binary(op, a, b)
  {kind: "binary", op:, lhs: a, rhs: b}
end

def rs_block(stmts)
  {stmts:}
end

def rs_semi(e)
  {kind: "semi", expr: e}
end

def rs_tail(e)
  {kind: "tail", expr: e}
end

def rs_if(c, t, e)
  if e.nil?
    {kind: "if", cond: c, then_branch: t}
  else
    {kind: "if", cond: c, then_branch: t, else_branch: e}
  end
end

def rs_ty(name)
  {ident: name}
end

def rs_io_param()
  {name: "io", ty: {ident: "I", reference: {kind: "mut"}}}
end

def rs_generics()
  {type_params: [{name: "I", bounds: [rs_ty("Io")]}]}
end

def rs_depth_param()
  {name: "d", ty: rs_ty("u32")}
end

def rs_fn(vis, name, params, ret, body)
  sig = {name:, generics: rs_generics, params: append([rs_io_param], params)}
  sig_ = if ret.nil?
    sig
  else
    assoc(sig, :return_type, ret)
  end
  {kind: "fn", vis:, item: {sig: sig_, body:}}
end

# ── Lowering (L5 represent; tail calls; L8 emit) ──────────────────────────

@doc """
cz_type: The type a signature names, at this board: Int is the board word.
"""
def cz_type(n, word)
  if cz_sym(n) == "Int"
    rs_ty(cz_word_ty(word))
  else
    cz_refuse(
      "the type `#{cz_sym(n) or n}` has no native representation yet; Int is the board word"
    )
  end
end

def cz_arith()
  [
    %w[+ checked_add],
    %w[- checked_sub],
    %w[* checked_mul],
    %w[mod checked_rem_euclid],
    %w[modulo checked_rem_euclid],
    %w[rem checked_rem_euclid]
  ]
end

def cz_compare()
  [%w[equal? eq], %w[not= ne], %w[< lt], %w[<= le], %w[> gt], %w[>= ge]]
end

def cz_logic()
  [%w[and and], %w[or or]]
end

def cz_lookup(key, pairs)
  hit = find(pairs, (p) -> first(p) == key)
  if hit.nil?
    nil
  else
    second(hit)
  end
end

@doc """
cz_expr: An expression in value position. `ctx`: {self, params, fns, consts}.
"""
def cz_expr(n, ctx)
  if integer?(n)
    rs_word(n, ctx[:word])
  elsif cz_sym?(n)
    s = cz_sym(n)
    if member?(s, ctx[:params])
      rs_path(cz_param_name(s))
    elsif member?(s, ctx[:consts])
      rs_path(cz_const_name(s))
    elsif member?(s, ctx[:bindings]) and ctx[:self].nil?
      rs_path(cz_binding_name(s))
    elsif member?(s, ctx[:bindings])
      cz_refuse(
        "`#{cz_local(s)}` is computed when the top level runs; a definition reads constants and its parameters only"
      )
    else
      cz_refuse("`#{s}` is not a parameter or a constant here")
    end
  elsif list?(n) and count(n) > 0
    cz_call(n, ctx)
  else
    cz_refuse(
      "`#{to_s(n)}` has no native form at N0 (strings, keywords and floats are build-time only)"
    )
  end
end

def cz_call(n, ctx)
  h = cz_head(n)
  args = rest(n)
  arith = cz_lookup(h, cz_arith)
  cmp = cz_lookup(h, cz_compare)
  logic = cz_lookup(h, cz_logic)
  if h.nil?
    cz_refuse("a call through a computed function has no native form (every call is direct at the monomorphic position)")
  elsif arith != nil
    if count(args) < 2
      cz_refuse("`#{h}` with #{count(args)} operands has no native form at N0")
    end
    reduce(
      fn(acc, b)
        rs_call(
          %w[kiban_io checked],
          [rs_method(acc, arith, [cz_expr(b, ctx)])]
        )
      end,
      cz_expr(first(args), ctx),
      rest(args)
    )
  elsif cmp != nil
    if count(args) != 2
      cz_refuse("`#{h}` compares exactly two operands at N0")
    end
    rs_binary(cmp, cz_expr(first(args), ctx), cz_expr(second(args), ctx))
  elsif logic != nil
    reduce(
      (acc, b) -> rs_binary(logic, acc, cz_expr(b, ctx)),
      cz_expr(first(args), ctx),
      rest(args)
    )
  elsif h == "floor"
    cz_floor(args, ctx)
  elsif h == "/"
    cz_refuse("`/` answers a Float when it does not divide, and floats have no native form; integer division is floor(a / b)")
  elsif h == "not"
    {kind: "unary", op: "not", expr: cz_expr(first(args), ctx)}
  elsif h == "if"
    if count(args) != 3
      cz_refuse("an `if` whose value is used needs an else branch")
    end
    {
      kind: "block",
      block: rs_block(
        [
          rs_tail(
            rs_if(
              cz_expr(first(args), ctx),
              rs_block([rs_tail(cz_expr(second(args), ctx))]),
              rs_block([rs_tail(cz_expr(third(args), ctx))])
            )
          )
        ]
      )
    }
  elsif h == "begin"
    {kind: "block", block: rs_block(cz_body(args, ctx))}
  elsif h == "kiban/mmio_write"
    cz_mmio(args, ctx)
  elsif h == "kiban/wrapping_add" and ctx[:word] != 32
    cz_refuse(
      "wrapping_add wraps at 2^32, the 32-bit board word; the #{ctx[:word]}-bit word has no wrapping word"
    )
  elsif h == "kiban/wrapping_add"
    rs_method(
      cz_expr(first(args), ctx),
      "wrapping_add",
      [cz_expr(second(args), ctx)]
    )
  elsif member?(h, ctx[:fns])
    lead = if member?(h, ctx[:rec])
      [rs_path("io"), ctx[:depth]]
    else
      [rs_path("io")]
    end
    cz_direct((xs) -> rs_call([cz_fn_name(h)], append(lead, xs)), args, ctx)
  else
    cz_refuse(
      "`#{h}` has no native form: it is not a definition of this program or a word of its board (the native position's Reach, §2.3)"
    )
  end
end

@doc """
cz_mmio: mmio_write(addr, width, value): the width is a literal, so the store is
chosen at compile time.
"""
def cz_mmio(args, ctx)
  if count(args) != 3
    cz_refuse("mmio_write takes an address, a width and a value")
  end
  w = second(args)
  method = if w == 8
    "write8"
  elsif w == 32
    "write32"
  else
    cz_refuse("mmio_write's width must be the literal 8 or 32, got #{to_s(w)}")
  end
  cz_direct(
    fn(xs)
      rs_method(
        rs_path("io"),
        method,
        [
          rs_call(%w[kiban_io reg], [first(xs)]),
          rs_call(%w[kiban_io reg], [second(xs)])
        ]
      )
    end,
    [first(args), third(args)],
    ctx
  )
end

@doc """
cz_effectful?: Whether lowering `n` reaches the board: a call of a definition or a
board word, anywhere inside it.
"""
def cz_effectful?(n, ctx)
  h = cz_head(n)
  if not list?(n)
    false
  elsif h == "kiban/mmio_write" or member?(h, ctx[:fns])
    true
  else
    any?((x) -> cz_effectful?(x, ctx), n)
  end
end

@doc """
cz_direct: A call whose arguments are lowered first. When an argument reaches the
board itself, every argument is bound to a local before the call, so the
board is borrowed by one call at a time (a nested call would otherwise hold
`io` twice, E0499). `build` makes the call from the argument expressions.
"""
def cz_direct(build, args, ctx)
  if any?((a) -> cz_effectful?(a, ctx), args)
    idx = range(count(args))
    temps = map(
      (i) -> {kind: "local", name: "a_#{i}", value: cz_expr(args[i], ctx)},
      idx
    )
    {
      kind: "block",
      block: rs_block(
        append(temps, [rs_tail(build(map((i) -> rs_path("a_#{i}"), idx)))])
      )
    }
  else
    build(map((a) -> cz_expr(a, ctx), args))
  end
end

@doc """
cz_floor: floor(a / b), the interpreter's integer division: rounded toward negative
infinity in the signed host word, the plain quotient in the unsigned board
word. A divisor of zero is a fault, as the interpreter raises.
"""
def cz_floor(args, ctx)
  q = first(args)
  if count(args) != 1 or cz_head(q) != "/" or count(q) != 3
    cz_refuse("floor has a native form only as integer division, floor(a / b); floats have none")
  end
  a = cz_expr(second(q), ctx)
  b = cz_expr(third(q), ctx)
  if ctx[:word] == 64
    rs_call(%w[kiban_io floor_div], [a, b])
  else
    rs_call(%w[kiban_io checked], [rs_method(a, "checked_div", [b])])
  end
end

@doc """
cz_stmt: A form whose value is dropped. An `if` with no else branch is a statement
here, where its missing value is never read.
"""
def cz_stmt(n, ctx)
  if cz_head(n) == "if" and count(n) == 3
    rs_semi(
      rs_if(cz_expr(second(n), ctx), rs_block([cz_stmt(third(n), ctx)]), nil)
    )
  else
    rs_semi(cz_expr(n, ctx))
  end
end

@doc """
cz_body: A sequence in value position: every form but the last as a statement.
"""
def cz_body(forms, ctx)
  append(
    map((f) -> cz_stmt(f, ctx), butlast(forms)),
    [rs_tail(cz_expr(last(forms), ctx))]
  )
end

@doc """
cz_tail_self?: Whether `n`, in tail position, calls `self`.
"""
def cz_tail_self?(n, name)
  h = cz_head(n)
  if h == name
    true
  elsif h == "if"
    any?((b) -> cz_tail_self?(b, name), drop(2, n))
  elsif h == "begin"
    cz_tail_self?(last(rest(n)), name)
  else
    false
  end
end

@doc """
cz_tail: A form in tail position of a looping function, as statements that always
leave: `return`, or the parameters rebound and `continue`.
"""
def cz_tail(n, ctx)
  h = cz_head(n)
  if h == ctx[:self]
    params = ctx[:params]
    args = rest(n)
    if count(args) != count(params)
      cz_refuse(
        "`#{cz_local(h)}` takes #{count(params)} arguments, given #{count(args)}"
      )
    end
    temps = map(
      (i) -> {kind: "local", name: "t_#{i}", value: cz_expr(args[i], ctx)},
      range(count(args))
    )
    rebinds = map(
      fn(i)
        rs_semi(
          {
            kind: "assign",
            target: cz_param_name(params[i]),
            value: rs_path("t_#{i}")
          }
        )
      end,
      range(count(args))
    )
    append(temps, rebinds, [rs_semi({kind: "continue"})])
  elsif h == "if"
    c = cz_expr(second(n), ctx)
    t = rs_block(cz_tail(third(n), ctx))
    e = if count(n) > 3
      rs_block(cz_tail(fourth(n), ctx))
    else
      cz_refuse("an `if` in tail position needs an else branch")
    end
    [rs_semi(rs_if(c, t, e))]
  elsif h == "begin"
    forms = rest(n)
    append(
      map((f) -> cz_stmt(f, ctx), butlast(forms)),
      cz_tail(last(forms), ctx)
    )
  else
    [rs_semi({kind: "return", value: cz_expr(n, ctx)})]
  end
end

@doc """
cz_calls: The definitions `n` calls, in `fns`. A call of `me` in tail position is
left out: that function loops instead (`me` is nil when it does not).
"""
def cz_calls(n, fns, me, tail)
  h = cz_head(n)
  if not list?(n) or count(n) == 0
    []
  elsif h == "if"
    reduce(
      (acc, b) -> append(acc, cz_calls(b, fns, me, tail)),
      cz_calls(second(n), fns, me, false),
      drop(2, n)
    )
  elsif h == "begin"
    forms = rest(n)
    reduce(
      (acc, f) -> append(acc, cz_calls(f, fns, me, false)),
      cz_calls(last(forms), fns, me, tail),
      butlast(forms)
    )
  else
    own = if member?(h, fns) and not (tail and h == me)
      [h]
    else
      []
    end
    reduce((acc, a) -> append(acc, cz_calls(a, fns, me, false)), own, rest(n))
  end
end

@doc """
cz_reach: Every definition reachable from `frontier` through the call graph
`graph` ([name, callees] pairs).

    cz_reach(["a"], [], [["a", ["b"]], ["b", ["a"]]]) #=> ["a", "b"]
"""
def cz_reach(frontier, seen, graph)
  if empty?(frontier)
    seen
  elsif member?(first(frontier), seen)
    cz_reach(rest(frontier), seen, graph)
  else
    cz_reach(
      append(rest(frontier), cz_lookup(first(frontier), graph) or []),
      append(seen, [first(frontier)]),
      graph
    )
  end
end

@doc """
cz_recursive: The definitions that reach themselves through a call that is not a tail
call to themselves: each needs a stack frame per level, so each runs under
the board's declared depth bound.
"""
def cz_recursive(fn_forms, fns)
  graph = map(
    fn(f)
      name = cz_sym(first(second(f)))
      body = fourth(f)
      me = if cz_tail_self?(body, name)
        name
      end
      [name, cz_calls(body, fns, me, true)]
    end,
    fn_forms
  )
  filter(
    (name) -> member?(name, cz_reach(cz_lookup(name, graph), [], graph)),
    fns
  )
end

@doc """
cz_fn: (define-typed (name (p T) …) R body) → a generic fn over the board. `env`:
{fns, consts, bindings, rec, word, bound}. A recursive definition takes its
depth `d` and enters one level deeper, faulting past the bound.
"""
def cz_fn(form, env)
  sig = second(form)
  name = cz_sym(first(sig))
  params = map((p) -> cz_sym(first(p)), rest(sig))
  word = env[:word]
  ret = cz_type(third(form), word)
  body = fourth(form)
  rec = member?(name, env[:rec])
  depth = if rec
    rs_path("d")
  else
    rs_u32(0)
  end
  ctx = assoc(assoc(assoc(env, :self, name), :params, params), :depth, depth)
  rparams = map(
    fn(p)
      {name: cz_param_name(cz_sym(first(p))), ty: cz_type(second(p), word)}
    end,
    rest(sig)
  )
  enter = if rec
    [
      {
        kind: "local",
        name: "d",
        value: rs_call(%w[kiban_io deeper], [rs_path("d"), rs_u32(env[:bound])])
      }
    ]
  else
    []
  end
  stmts = if cz_tail_self?(body, name)
    rebind = map(
      fn(p)
        {
          kind: "local",
          name: cz_param_name(p),
          mutable: true,
          value: rs_path(cz_param_name(p))
        }
      end,
      params
    )
    append(
      enter,
      rebind,
      [rs_semi({kind: "loop", body: rs_block(cz_tail(body, ctx))})]
    )
  else
    append(enter, [rs_tail(cz_expr(body, ctx))])
  end
  lead = if rec
    [rs_depth_param]
  else
    []
  end
  rs_fn(
    "private",
    cz_fn_name(name),
    append(lead, rparams),
    ret,
    rs_block(stmts)
  )
end

@doc """
cz_constant?: Whether `n` is computed from literals and earlier constants alone, so
it is a Rust constant evaluated when the image is built.
"""
def cz_constant?(n, consts)
  h = cz_head(n)
  if integer?(n)
    true
  elsif cz_sym?(n)
    member?(cz_sym(n), consts)
  elsif h != nil and (cz_lookup(h, cz_arith) != nil or h == "floor" or h == "/")
    every?((a) -> cz_constant?(a, consts), rest(n))
  else
    false
  end
end

def cz_const(form, env)
  {
    kind: "const",
    name: cz_const_name(cz_sym(second(form))),
    ty: rs_ty(cz_word_ty(env[:word])),
    value: cz_expr(third(form), assoc(assoc(env, :fns, []), :params, []))
  }
end

def cz_binding_name(qualified)
  concat("g_", downcase(cz_checked_ident(cz_local(qualified), "a binding")))
end

@doc """
cz_kind: What a top-level form is: a use, a typed definition, a constant (from
literals and the constants before it), a binding the top level computes when
it runs, an untyped definition, or an expression.
"""
def cz_kind(form, consts)
  h = cz_head(form)
  if h == "use"
    :use
  elsif h == "define-typed"
    :fn
  elsif h == "define" and
      cz_sym?(second(form)) and
      cz_constant?(third(form), consts)
    :const
  elsif h == "define" and cz_sym?(second(form))
    :binding
  elsif h == "define"
    :untyped
  else
    :expr
  end
end

@doc """
cz_check_use: The one package a native program may use at N0 is its board's.
"""
def cz_check_use(form)
  pkg = second(form)[:str]
  if pkg != "kiban"
    cz_refuse(
      "use(\"#{pkg}\"): at N0 a native program uses only its board's words (kiban)"
    )
  end
  nil
end

def cz_attr(path, args)
  {path: [path], args:}
end

@doc """
cz_kinds: Each top-level form with its kind, in order; a constant is known to the
forms after it.
"""
def cz_kinds(forms)
  st = reduce(
    fn(acc, f)
      k = cz_kind(f, acc[:consts])
      consts = if k == :const
        append(acc[:consts], [cz_sym(second(f))])
      else
        acc[:consts]
      end
      {consts:, kinds: append(acc[:kinds], [[k, f]])}
    end,
    {consts: [], kinds: []},
    forms
  )
  st[:kinds]
end

@doc """
cz_main_stmt: One top-level form of the program's main: a binding becomes a local the
later top-level forms read; an expression a statement.
"""
def cz_main_stmt(kf, ctx)
  f = second(kf)
  if first(kf) == :binding
    {
      kind: "local",
      name: cz_binding_name(cz_sym(second(f))),
      value: cz_expr(third(f), ctx)
    }
  else
    cz_stmt(f, ctx)
  end
end

@doc """
cz_lower: The lowered program: a typed Rust `File` (as data), for `board`.
"""
def cz_lower(forms, board)
  word = board[:word]
  if word != 32 and word != 64
    cz_refuse(
      "chuuzou lowers to a 32-bit board word or the 64-bit host word; #{board[:name]} has #{word}"
    )
  end
  kinds = cz_kinds(forms)
  pick = (k) -> map((p) -> second(p), filter((p) -> first(p) == k, kinds))
  map(cz_check_use, pick(:use))
  if not empty?(pick(:untyped))
    cz_refuse(
      "`#{cz_local(cz_sym(first(second(first(pick(:untyped))))))}` is untyped; the native position is restricted, so every definition is typed (constraint C4)"
    )
  end
  fn_forms = pick(:fn)
  const_forms = pick(:const)
  fns = map((f) -> cz_sym(first(second(f))), fn_forms)
  consts = map((f) -> cz_sym(second(f)), const_forms)
  bindings = map((f) -> cz_sym(second(f)), pick(:binding))
  rec = cz_recursive(fn_forms, fns)
  if not empty?(rec) and board[:max_depth].nil?
    cz_refuse(
      "`#{cz_local(first(rec))}` calls itself again before it returns; #{board[:name]} declares no recursion depth bound (max_depth), so only a tail call to itself, a loop, compiles for it"
    )
  end
  env = {
    self: nil,
    params: [],
    fns:,
    consts:,
    bindings:,
    rec:,
    word:,
    bound: board[:max_depth],
    depth: rs_u32(0)
  }
  main_body = rs_block(
    map(
      (kf) -> cz_main_stmt(kf, env),
      filter((kf) -> first(kf) == :binding or first(kf) == :expr, kinds)
    )
  )
  {
    attrs: [cz_attr("no_std", []), cz_attr("forbid", ["unsafe_code"])],
    items: append(
      [{kind: "use", item: {path: %w[kiban_io Io]}}],
      map((f) -> cz_const(f, env), const_forms),
      map((f) -> cz_fn(f, env), fn_forms),
      [rs_fn("pub", "main", [], nil, main_body)]
    )
  }
end

# ── The driver ────────────────────────────────────────────────────────────

def cz_capture(args)
  r = exec_capture(*args)
  {
    status: second(first(r)),
    stdout: second(second(r)),
    stderr: second(third(r))
  }
end

@doc """
cz_emit: The emitted Rust for the blue program at `path`, built for the board named
`board_name`. The program is checked by blue's own pipeline first; a program
that does not check produces no Rust.
"""
def cz_emit(path, board_name)
  board = kb_board(board_name)
  if board.nil?
    cz_refuse("no board named #{board_name}")
  end
  blue = self_exe
  checked = cz_capture([blue, "check", path])
  if checked[:status] != 0
    cz_refuse(
      join_lines(
        ["#{path} does not check:", "#{checked[:stdout]}#{checked[:stderr]}"]
      )
    )
  end
  tree = cz_capture([blue, "ast", "--resolved", path])
  if tree[:status] != 0
    cz_refuse("blue ast failed: #{tree[:stderr]}")
  end
  file = cz_lower(cz_read(tree[:stdout]), board)
  r = exec_with_stdin(json_stringify(file), "tatara-rust-emit")
  if second(first(r)) != 0
    cz_refuse("tatara-rust-emit refused the tree: #{second(third(r))}")
  end
  second(second(r))
end

# ── Linking and measuring an image ────────────────────────────────────────

@doc """
cz_link_script: The linker script, from the board's memory regions: the entry first, every
section in RAM, the stack at the top of RAM. Generated, never hand-written
(BLUE-NATIVE.md §1.6); a board with no `ram` region is refused.
"""
def cz_link_script(board)
  ram = find(board[:memory], (r) -> r[:name] == :ram)
  if ram.nil?
    cz_refuse("#{board[:name]} declares no ram region")
  end
  lines = [
    "OUTPUT_ARCH(riscv)",
    "ENTRY(_start)",
    "MEMORY { ram : ORIGIN = #{ram[:origin]}, LENGTH = #{ram[:length]} }",
    "SECTIONS {",
    "  .text : { KEEP(*(.text.start)) *(.text .text.*) } > ram",
    "  .rodata : { *(.rodata .rodata.*) } > ram",
    "  .data : { *(.data .data.* .sdata .sdata.*) } > ram",
    "  .bss (NOLOAD) : { *(.bss .bss.* .sbss .sbss.*) } > ram",
    "  /DISCARD/ : { *(.eh_frame .eh_frame.*) }",
    "}",
    "__stack_top = ORIGIN(ram) + LENGTH(ram);",
    ""
  ]
  join(lines, line_break)
end

@doc """
cz_rustc_flags: The rustc flags every crate of an image shares. A board: its target, size
first, abort on panic (the seam's handler is on_fault). The host (no
`rust_target`): its own target, speed first, and a fault that unwinds so the
seam flushes what was printed.
"""
def cz_rustc_flags(board)
  if board[:rust_target].nil?
    %w[--edition 2021 -C opt-level=3 -C codegen-units=1]
  else
    [
      "--edition",
      "2021",
      "--target",
      board[:rust_target],
      "-C",
      "opt-level=z",
      "-C",
      "panic=abort",
      "-C",
      "codegen-units=1"
    ]
  end
end

def cz_run(args, what)
  r = cz_capture(args)
  if r[:status] != 0
    cz_refuse(join_lines(["#{what} failed:", r[:stderr]]))
  end
  r
end

@doc """
cz_link: Build the image `name` from the emitted Rust at `rs`, for the board named
`board_name`, with the seam sources under `seam` (kiban_io.rs and
<board>/seam.rs), into the directory `out`. Three crates: kiban_io (safe),
the program (emitted, #![forbid(unsafe_code)]), and the seam, the one crate
where unsafe compiles, linked with LTO. Answers the ELF's path.
"""
def cz_link(rs, board_name, seam, out, name)
  board = kb_board(board_name)
  flags = cz_rustc_flags(board)
  mkdir_p(out)
  script = path_join(out, "link.x")
  link = if board[:rust_target].nil?
    []
  else
    write_file(script, cz_link_script(board))
    ["-C", "link-arg=-T#{script}"]
  end
  io = path_join(out, "libkiban_io.rlib")
  prog = path_join(out, "libprogram.rlib")
  elf = path_join(out, "#{name}.elf")
  cz_run(
    append(
      ["rustc"],
      flags,
      [
        "--crate-type",
        "rlib",
        "--crate-name",
        "kiban_io",
        "-o",
        io,
        path_join(seam, "kiban_io.rs")
      ]
    ),
    "rustc kiban_io"
  )
  cz_run(
    append(
      ["rustc"],
      flags,
      [
        "--crate-type",
        "rlib",
        "--crate-name",
        "program",
        "--extern",
        "kiban_io=#{io}",
        "-o",
        prog,
        rs
      ]
    ),
    "rustc program"
  )
  cz_run(
    append(
      ["rustc"],
      flags,
      [
        "-C",
        "lto=fat",
        "--crate-type",
        "bin",
        "--crate-name",
        cz_crate_name(name),
        "--extern",
        "kiban_io=#{io}",
        "--extern",
        "program=#{prog}",
        "-L",
        out
      ],
      link,
      ["-o", elf, path_join(seam, board[:name], "seam.rs")]
    ),
    "rustc seam"
  )
  elf
end

@doc """
cz_host_image: The blue program at `program` compiled for the host board: its Rust
emitted beside the image in `out`, linked with the seams under `seam`.
Answers the executable's path.
"""
def cz_host_image(program, seam, out)
  name = replace(path_basename(program), ".b", "")
  mkdir_p(out)
  rs = path_join(out, "#{name}.rs")
  write_file(rs, cz_emit(program, "host64"))
  cz_link(rs, "host64", seam, out, name)
end

def cz_crate_name(name)
  join(
    map(
      fn(c)
        if c == "-"
          "_"
        else
          c
        end
      end,
      chars(name)
    ),
    ""
  )
end

@doc """
cz_section: One section's size from `llvm-size -A` output, read by name (0 when the
image has no such section).
"""
def cz_section(size_text, section)
  row = find(
    split(size_text, line_break),
    (l) -> starts_with?(l, "#{section} ")
  )
  if row.nil?
    0
  else
    to_int!(second(filter((f) -> f != "", split(row, " "))))
  end
end

@doc """
cz_measure: The image's size (text, data, bss) and whether any core::fmt symbol is in
it (BLUE-NATIVE.md, Review §4): one row of the size ledger.
"""
def cz_measure(elf)
  sized = cz_run(["llvm-size", "-A", elf], "llvm-size")[:stdout]
  syms = cz_run(["llvm-nm", "-C", elf], "llvm-nm")[:stdout]
  fmt = filter((l) -> contains?(l, "core::fmt"), split(syms, line_break))
  {
    text: cz_section(sized, ".text"),
    rodata: cz_section(sized, ".rodata"),
    data: cz_section(sized, ".data"),
    bss: cz_section(sized, ".bss"),
    fmt_symbols: count(fmt)
  }
end

@doc """
cz_size_tsv: The size ledger row as TSV (a header and one line), for DuckDB.
"""
def cz_size_tsv(program, board_name, m)
  head = join(%w[program board text rodata data bss fmt_symbols], "\t")
  row = join(
    [
      program,
      board_name,
      m[:text],
      m[:rodata],
      m[:data],
      m[:bss],
      m[:fmt_symbols]
    ],
    "\t"
  )
  unlines([head, row])
end

# ── Tests ─────────────────────────────────────────────────────────────────

test "the reader reads the resolved tree's atoms and nesting"
  forms = cz_read(join_lines(["(define %root/X 5)", "(f \"a b\" :k (g))"]))
  assert count(forms) == 2
  assert first(forms) == [{sym: "define"}, {sym: "%root/X"}, 5]
  assert second(forms) == [{sym: "f"}, {str: "a b"}, {kw: "k"}, [{sym: "g"}]]
  assert cz_read("") == []
  assert (cz_read("(a") rescue :refused) == :refused
  assert (cz_read("a)") rescue :refused) == :refused
end

def cz_test_env(word)
  {
    self: nil,
    params: %w[a b],
    fns: [],
    consts: [],
    bindings: [],
    rec: [],
    word:,
    bound: 100_000,
    depth: rs_u32(0)
  }
end

def cz_test_lower(text, board_name)
  cz_lower(cz_read(text), kb_board(board_name))
end

def cz_test_items(text)
  cz_test_lower(text, "host64")[:items]
end

test "arithmetic lowers checked, and wrapping only where asked"
  ctx = cz_test_env(32)
  e = cz_expr(first(cz_read("(+ a b)")), ctx)
  assert e[:func] == %w[kiban_io checked]
  assert first(e[:args])[:method] == "checked_add"
  w = cz_expr(first(cz_read("(kiban/wrapping_add a b)")), ctx)
  assert w[:method] == "wrapping_add"
  assert (cz_expr(
    first(cz_read("(kiban/wrapping_add a b)")),
    cz_test_env(64)
  ) rescue
    :refused) == :refused
end

test "mod, inequality, and, or and integer division lower; a bare quotient is refused"
  ctx = cz_test_env(64)
  m = cz_expr(first(cz_read("(mod a b)")), ctx)
  assert first(m[:args])[:method] == "checked_rem_euclid"
  assert cz_expr(first(cz_read("(not= a b)")), ctx)[:op] == "ne"
  assert get(
    cz_expr(first(cz_read("(and (< a b) (> a b) (equal? a b))")), ctx),
    :op
  ) == "and"
  assert cz_expr(first(cz_read("(or (< a b) (> a b))")), ctx)[:op] == "or"
  assert cz_expr(first(cz_read("(floor (/ a b))")), ctx)[:func] ==
    %w[kiban_io floor_div]
  assert get(
    first(cz_expr(first(cz_read("(floor (/ a b))")), cz_test_env(32))[:args]),
    :method
  ) == "checked_div"
  assert (cz_expr(first(cz_read("(/ a b)")), ctx) rescue :refused) == :refused
  assert (cz_expr(first(cz_read("(floor a)")), ctx) rescue :refused) == :refused
end

test "a literal is in the board word: u32 on a board, i64 on the host"
  assert rs_word(7, 64) == {kind: "int", value: 7, suffix: "i64"}
  assert rs_word(-7, 64)[:expr][:value] == 7
  assert (rs_word(-7, 32) rescue :refused) == :refused
end

test "a literal past the board word is a compile error"
  assert rs_u32(4_294_967_295)[:value] == 4_294_967_295
  assert (rs_u32(4_294_967_296) rescue :refused) == :refused
  assert (rs_u32(-1) rescue :refused) == :refused
end

test "a call whose argument reaches the board binds its arguments first"
  ctx = assoc(cz_test_env(64), :fns, %w[%root/f %root/g])
  nested = cz_expr(first(cz_read("(%root/f (%root/g a) b)")), ctx)
  assert nested[:kind] == "block"
  stmts = nested[:block][:stmts]
  assert map((x) -> x[:name], butlast(stmts)) == %w[a_0 a_1]
  assert last(stmts)[:expr][:args] ==
    [rs_path("io"), rs_path("a_0"), rs_path("a_1")]
  flat = cz_expr(first(cz_read("(%root/f a (+ b 1))")), ctx)
  assert flat[:kind] == "call"
  mmio = cz_expr(first(cz_read("(kiban/mmio_write a 8 (%root/g b))")), ctx)
  assert mmio[:kind] == "block"
end

test "a tail self-call becomes a loop"
  env = assoc(cz_test_env(32), :fns, ["%root/down"])
  looped = cz_fn(
    first(
      cz_read("(define-typed (%root/down (n Int)) Int (if (equal? n 0) n (%root/down (- n 1))))")
    ),
    env
  )
  stmts = looped[:item][:body][:stmts]
  assert last(stmts)[:expr][:kind] == "loop"
end

test "recursion is found through the call graph, tail self-calls aside"
  forms = cz_read(
    join_lines(
      [
        "(define-typed (%root/f (n Int)) Int (+ 1 (%root/f n)))",
        "(define-typed (%root/down (n Int)) Int (if (equal? n 0) n (%root/down (- n 1))))",
        "(define-typed (%root/even (n Int)) Int (if (equal? n 0) 1 (%root/odd (- n 1))))",
        "(define-typed (%root/odd (n Int)) Int (if (equal? n 0) 0 (%root/even (- n 1))))",
        "(define-typed (%root/leaf (n Int)) Int (%root/down n))"
      ]
    )
  )
  fns = map((f) -> cz_sym(first(second(f))), forms)
  assert cz_recursive(forms, fns) == %w[%root/f %root/even %root/odd]
  assert cz_recursive([], []) == []
end

test "a recursive definition takes its depth and runs under the board's bound"
  items = cz_test_items(
    join_lines(
      [
        "(define-typed (%root/fib (n Int)) Int (if (< n 2) n (+ (%root/fib (- n 1)) (%root/fib (- n 2)))))",
        "(%root/fib 20)"
      ]
    )
  )
  f = second(items)[:item]
  assert second(f[:sig][:params]) == rs_depth_param
  enter = first(f[:body][:stmts])
  assert enter[:value][:func] == %w[kiban_io deeper]
  assert last(enter[:value][:args]) == rs_u32(100_000)
  main_call = first(last(items)[:item][:body][:stmts])[:expr]
  assert second(main_call[:args]) == rs_u32(0)
end

test "a definition outside every cycle calls a recursive one from depth zero"
  items = cz_test_items(
    join_lines(
      [
        "(define-typed (%root/down (n Int)) Int (if (equal? n 0) n (+ 1 (%root/down (- n 1)))))",
        "(define-typed (%root/top (n Int)) Int (%root/down n))"
      ]
    )
  )
  top = third(items)[:item]
  assert count(top[:sig][:params]) == 2
  assert second(last(top[:body][:stmts])[:expr][:args]) == rs_u32(0)
end

test "a board with no depth bound refuses recursion, mutual recursion included"
  odd_even = join_lines(
    [
      "(define-typed (%root/even (n Int)) Int (if (equal? n 0) 1 (%root/odd (- n 1))))",
      "(define-typed (%root/odd (n Int)) Int (if (equal? n 0) 0 (%root/even (- n 1))))"
    ]
  )
  assert (cz_test_lower(odd_even, "qemu-virt32") rescue :refused) == :refused
  assert count(cz_test_items(odd_even)) == 4
end

test "a constant may be computed from constants; a call makes a top-level binding"
  items = cz_test_items(
    join_lines(
      [
        "(define %root/A 6)",
        "(define %root/B (floor (/ (* %root/A 7) 2)))",
        "(define-typed (%root/sq (n Int)) Int (* n n))",
        "(define %root/K (%root/sq %root/B))",
        "(%root/sq %root/K)"
      ]
    )
  )
  assert map((i) -> i[:kind], items) == %w[use const const fn fn]
  assert third(items)[:name] == "BL_B"
  main_stmts = last(items)[:item][:body][:stmts]
  assert first(main_stmts)[:name] == "g_k"
  assert second(main_stmts)[:expr][:args] == [rs_path("io"), rs_path("g_k")]
  reads = join_lines(
    [
      "(define-typed (%root/sq (n Int)) Int (* n n))",
      "(define %root/K (%root/sq 3))",
      "(define-typed (%root/k (n Int)) Int (+ n %root/K))"
    ]
  )
  assert (cz_test_items(reads) rescue :refused) == :refused
end

test "an if with no else is a statement where its value is dropped"
  s = cz_stmt(
    first(cz_read("(if (< a b) (kiban/mmio_write a 8 b))")),
    cz_test_env(64)
  )
  assert s[:kind] == "semi"
  assert s[:expr][:else_branch].nil?
  assert (cz_expr(first(cz_read("(if (< a b) a)")), cz_test_env(64)) rescue
    :refused) == :refused
end

test "outside the N0 subset is refused, naming the rule"
  board = kb_board("qemu-virt32")
  assert (cz_lower(cz_read("(define (%root/f x) x)"), board) rescue :refused) ==
    :refused
  assert (cz_lower(cz_read("(use \"retsu\" (list :first))"), board) rescue
    :refused) == :refused
  assert (cz_lower(cz_read("(eval 1)"), board) rescue :refused) == :refused
  assert (cz_lower([], {name: "wide", word: 16}) rescue :refused) == :refused
end

test "the host builds for speed and unwinds; a board builds for size and aborts"
  host = cz_rustc_flags(kb_board("host64"))
  assert member?("opt-level=3", host)
  assert not member?("--target", host)
  virt = cz_rustc_flags(kb_board("qemu-virt32"))
  assert member?("riscv32imac-unknown-none-elf", virt)
  assert member?("panic=abort", virt)
end

test "the linker script comes from the board's ram region"
  script = cz_link_script(kb_board("qemu-virt32"))
  assert contains?(script, "ORIGIN = 2147483648, LENGTH = 131072")
  assert (cz_link_script({name: "bare", memory: []}) rescue :refused) ==
    :refused
end

test "a section's size is read by name"
  out = unlines(
    [
      "x.elf  :",
      "section   size   addr",
      ".text       64   2147483648",
      ".comment   153   0"
    ]
  )
  assert cz_section(out, ".text") == 64
  assert cz_section(out, ".data") == 0
end
