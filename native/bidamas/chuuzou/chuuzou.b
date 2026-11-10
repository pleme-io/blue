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
  record p(x, y)            #[derive(Clone, Copy, PartialEq)] struct R_p { x: W, y: W }
  p(a, b), p({x: a, y: b})  R_p { x: a, y: b }: the record's own struct, no tag
  p(**q, x: a)              q read once, then R_p { x: a, y: q.y }
  an untyped parameter      Rec: one variant per record, each holding only its record
  x.f, p?(x)                a field; on Rec a match over the variants that have it
                            (any other is a fault, as the interpreter raises); a
                            variant test on Rec, a constant where the type is known
  ==, != on records         derived PartialEq, both sides brought to one type
  [a, b], append, count,    a list of board words, on the host board only:
  nth, first                refcounted (kiban_heap::List, an Rc<Vec>) by default,
                            or a Span of a region with reclaim(:arena, "f")
  append(xs, [a])           a push onto xs: in place when nothing else holds xs
                            (refcount) or xs is its region's newest list (arena)
  a list read more than     moved where it is read once; read more, a take is an
  once                      Rc clone (a refcount, no copy)
  a call across strategies  the list copied into or out of the region; a region
                            definition called from a refcounting one gets a
                            fresh region for that call, freed when it returns
  x = e in a body           a local, seen by the forms after it
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

use("kiban", %i[kb_board kb_device_base])

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

@doc """
cz_word_ty: The Rust type of the board's word.

    cz_word_ty(64) #=> "i64"
    cz_word_ty(32) #=> "u32"
"""
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

@doc """
rs_depth_param: The depth parameter a recursive definition takes after the board.

    rs_depth_param[:name] #=> "d"
"""
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
cz_sig_ty: The type a signature names: Int is the board word (:word), Bool is :bool,
an untyped parameter (dyn) holds any record (:dyn), and a record's own name
is that record, by its qualified name.

    cz_sig_ty({sym: "Int"}, []) #=> :word
    cz_sig_ty({sym: "point"}, [{name: "%root/point", pred: "%root/point?", fields: ["x"]}]) #=> "%root/point"
"""
def cz_sig_ty(n, records)
  s = cz_sym(n)
  r = find(records, (x) -> cz_local(x[:name]) == s)
  if s == "Int"
    :word
  elsif s == "Bool"
    :bool
  elsif s == "dyn"
    :dyn
  elsif s == "List"
    :list
  elsif r != nil
    r[:name]
  else
    cz_refuse(
      "the type `#{s or to_s(n)}` has no native representation yet; Int is the board word, Bool a bool, a record its struct, dyn any record"
    )
  end
end

@doc """
cz_rs_ty: The Rust type of a lowered type: the board word, bool, `Rec` (the enum of
every record, each variant holding only its own record) or a record's struct.

    cz_rs_ty("%root/point", 64) #=> {ident: "R_point"}
    cz_rs_ty(:dyn, 64) #=> {ident: "Rec"}
"""
def cz_rs_ty(ty, word)
  if ty == :word
    rs_ty(cz_word_ty(word))
  elsif ty == :bool
    rs_ty("bool")
  elsif ty == :dyn
    rs_ty("Rec")
  elsif ty == :list
    rs_ty("List")
  elsif ty == :span
    rs_ty("Span")
  else
    rs_ty(cz_struct_name(ty))
  end
end

@doc """
cz_held_ty: A lowered type as a definition of `strategy` holds it: a list is a
refcounted `List`, or a `Span` of the definition's region.

    cz_held_ty(:list, :arena) #=> :span
    cz_held_ty(:list, :refcount) #=> :list
    cz_held_ty(:word, :arena) #=> :word
"""
def cz_held_ty(ty, strategy)
  if ty == :list and strategy == :arena
    :span
  else
    ty
  end
end

@doc """
cz_struct_name: The Rust struct, and `Rec` variant, a record lowers to.

    cz_struct_name("%root/point") #=> "R_point"
"""
def cz_struct_name(qualified)
  concat("R_", cz_checked_ident(cz_local(qualified), "a record"))
end

@doc """
cz_record_of: The record a resolved `(blue-record name pred :field …)` form declares.

    cz_record_of(first(cz_read("(blue-record %root/p %root/p? :x :y)"))) #=> {name: "%root/p", pred: "%root/p?", fields: ["x", "y"]}
"""
def cz_record_of(form)
  {
    name: cz_sym(second(form)),
    pred: cz_sym(third(form)),
    fields: map((k) -> k[:kw], drop(3, form))
  }
end

@doc """
cz_unify: The one type two branches share: the same type, or :dyn when both hold
records; anything else is refused.

    cz_unify("%root/a", "%root/b") #=> :dyn
    cz_unify(:word, :word) #=> :word
"""
def cz_unify(a, b)
  if a == b
    a
  elsif (string?(a) or a == :dyn) and (string?(b) or b == :dyn)
    :dyn
  else
    cz_refuse(
      "one branch is #{cz_ty_text(a)} and the other #{cz_ty_text(b)}; natively both branches have one type"
    )
  end
end

@doc """
cz_ty_text: A lowered type as a reader names it.

    cz_ty_text(:word) #=> "an Int"
    cz_ty_text("%root/point") #=> "a point"
"""
def cz_ty_text(t)
  if t == :word
    "an Int"
  elsif t == :bool
    "a Bool"
  elsif t == :dyn
    "any record"
  else
    "a #{cz_local(t)}"
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

@doc """
cz_logic: blue's `and` and `or` and the Rust operator each lowers to.

    cz_lookup("or", cz_logic) #=> "or"
"""
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
cz_ty: The type of `n` where it stands: what the native code holds for it.

    cz_ty(first(cz_read("(< 1 2)")), {}) #=> :bool
    cz_ty(first(cz_read("(%root/p 1)")), {records: [{name: "%root/p", pred: "%root/p?", fields: ["x"]}]}) #=> "%root/p"
"""
def cz_ty(n, ctx)
  h = cz_head(n)
  if integer?(n)
    :word
  elsif cz_sym?(n)
    cz_lookup(cz_sym(n), ctx[:types] or []) or :word
  elsif not list?(n)
    :word
  elsif member?(h, %w[not and or]) or cz_lookup(h, cz_compare) != nil
    :bool
  elsif h == "if" and count(n) == 4
    cz_unify(cz_ty(third(n), ctx), cz_ty(fourth(n), ctx))
  elsif h == "begin"
    cz_ty(last(n), cz_scope(butlast(rest(n)), ctx))
  elsif h == "list" or h == "append"
    :list
  elsif cz_record_named(ctx, h) != nil
    h
  elsif cz_record_tested(ctx, h) != nil
    :bool
  elsif cz_lookup(h, ctx[:sigs] or []) != nil
    cz_lookup(h, ctx[:sigs])[:ret]
  else
    :word
  end
end

@doc """
cz_record_named: The record whose constructor is `name`, or nil.

    cz_record_named({records: []}, "%root/p") #=> nil
"""
def cz_record_named(ctx, name)
  find(ctx[:records] or [], (r) -> r[:name] == name)
end

@doc """
cz_record_tested: The record whose predicate is `name`, or nil.

    cz_record_tested({records: [{name: "%root/p", pred: "%root/p?", fields: []}]}, "%root/p?")[:name] #=> "%root/p"
"""
def cz_record_tested(ctx, name)
  find(ctx[:records] or [], (r) -> r[:pred] == name)
end

@doc """
cz_coerce: `e`, of type `from`, where `to` is expected: a record into `Rec` is its
variant; `Rec` into a record is that variant's record, any other a fault, as
the interpreter raises reading a field the value lacks. Anything else differing
is refused.

    cz_coerce(rs_path("p"), "%root/p", :dyn)[:func] #=> ["Rec", "R_p"]
"""
def cz_coerce(e, from, to)
  if from == to or to.nil?
    e
  elsif to == :dyn and string?(from)
    rs_call(["Rec", cz_struct_name(from)], [e])
  elsif string?(to) and from == :dyn
    rs_match(
      e,
      [
        rs_arm(rs_variant_pat(to, cz_bind_pat("v")), rs_path("v")),
        rs_arm({kind: "wild"}, rs_call(%w[kiban_io fault], []))
      ]
    )
  else
    cz_refuse(
      "#{cz_ty_text(from)} cannot stand where #{cz_ty_text(to)} is expected"
    )
  end
end

@doc """
cz_as: `n` lowered and held as type `want` (nil keeps its own).

    cz_as(5, :word, {word: 64}) #=> {kind: "int", value: 5, suffix: "i64"}
"""
def cz_as(n, want, ctx)
  cz_coerce(cz_expr(n, ctx), cz_ty(n, ctx), want)
end

@doc """
rs_match: `match scrutinee { arms }`.

    rs_match(rs_path("x"), [])[:kind] #=> "match"
"""
def rs_match(scrutinee, arms)
  {kind: "match", scrutinee:, arms:}
end

@doc """
rs_arm: One arm: `pattern => body`.

    rs_arm({kind: "wild"}, rs_path("x"))[:pattern] #=> {kind: "wild"}
"""
def rs_arm(pattern, body)
  {pattern:, body:}
end

@doc """
cz_bind_pat: A pattern binding `name`.

    cz_bind_pat("v") #=> {kind: "bind", name: "v"}
"""
def cz_bind_pat(name)
  {kind: "bind", name:}
end

@doc """
rs_variant_pat: The pattern `Rec::R_record(inner)`.

    rs_variant_pat("%root/p", {kind: "wild"})[:path] #=> ["Rec", "R_p"]
"""
def rs_variant_pat(record, inner)
  {kind: "tuple-struct", path: ["Rec", cz_struct_name(record)], elems: [inner]}
end

@doc """
cz_field: `x.f`: a field of a record known here, or of `Rec`, matched by variant;
a variant without the field is a fault, as the interpreter raises.

    cz_field([{sym: "a"}, {kw: "x"}], {types: [["a", "%root/p"]], records: [{name: "%root/p", pred: "%root/p?", fields: ["x"]}], params: ["a"]})[:field] #=> "x"
"""
def cz_field(args, ctx)
  e = first(args)
  f = second(args)[:kw]
  t = cz_ty(e, ctx)
  name = cz_checked_ident(f, "a field")
  if string?(t)
    if not member?(f, cz_record_named(ctx, t)[:fields])
      cz_refuse("#{cz_ty_text(t)} has no field `#{f}`")
    end
    {kind: "field", base: cz_expr(e, ctx), field: name}
  elsif t == :dyn
    holders = filter((r) -> member?(f, r[:fields]), ctx[:records])
    if empty?(holders)
      cz_refuse("no record has a field `#{f}`")
    end
    arms = map(
      fn(r)
        rs_arm(
          rs_variant_pat(r[:name], cz_bind_pat("v")),
          {kind: "field", base: rs_path("v"), field: name}
        )
      end,
      holders
    )
    rest_arm = if count(holders) < count(ctx[:records])
      [rs_arm({kind: "wild"}, rs_call(%w[kiban_io fault], []))]
    else
      []
    end
    rs_match(cz_expr(e, ctx), append(arms, rest_arm))
  else
    cz_refuse("`.#{f}` reads a record's field, and this is #{cz_ty_text(t)}")
  end
end

@doc """
cz_is: `record?(x)`: a constant where the type is known, a variant test on `Rec`.

    cz_is({name: "%root/p"}, 1, {word: 32})[:block][:stmts] #=> [{kind: "semi", expr: {kind: "int", value: 1, suffix: "u32"}}, {kind: "tail", expr: {kind: "bool", value: false}}]
"""
def cz_is(rec, e, ctx)
  t = cz_ty(e, ctx)
  if t == :dyn
    rs_match(
      cz_expr(e, ctx),
      [
        rs_arm(
          rs_variant_pat(rec[:name], {kind: "wild"}),
          {kind: "bool", value: true}
        ),
        rs_arm({kind: "wild"}, {kind: "bool", value: false})
      ]
    )
  else
    {
      kind: "block",
      block: rs_block(
        [
          rs_semi(cz_expr(e, ctx)),
          rs_tail({kind: "bool", value: t == rec[:name]})
        ]
      )
    }
  end
end

@doc """
cz_pairs: The `[key, value]` pairs of a resolved `(hash-map :k v …)`.

    cz_pairs(first(cz_read("(hash-map :x 1 :y 2)"))) #=> [["x", 1], ["y", 2]]
"""
def cz_pairs(hm)
  kv = rest(hm)
  map((i) -> [kv[i * 2][:kw], kv[i * 2 + 1]], range(floor(count(kv) / 2)))
end

@doc """
cz_construct: A record built: by position, by name (`p({x: 1})`), or as an updated
copy (`p(**q, x: 1)`), each field a board word. The struct is the record's
own: no tag, no other record's fields.

    cz_construct({name: "%root/p", fields: ["x"]}, [1], {word: 64})[:fields] #=> [{name: "x", value: {kind: "int", value: 1, suffix: "i64"}}]
"""
def cz_construct(rec, args, ctx)
  fields = rec[:fields]
  h = cz_head(first(args))
  lit = fn(vals)
    {
      kind: "struct-lit",
      path: [cz_struct_name(rec[:name])],
      fields: map(
        (i) -> {name: cz_checked_ident(fields[i], "a field"), value: vals[i]},
        range(count(fields))
      )
    }
  end
  if count(args) == 1 and h == "blue-kwargs"
    kw = first(args)
    base = second(kw)
    if cz_head(base) != "blue-splice"
      cz_refuse(
        "an updated copy of #{cz_ty_text(rec[:name])} spreads one record first"
      )
    end
    given = cz_pairs(third(kw))
    vals = map(
      fn(f)
        v = cz_lookup(f, given)
        if v.nil?
          {
            kind: "field",
            base: rs_path("s_0"),
            field: cz_checked_ident(f, "a field")
          }
        else
          cz_as(v, :word, ctx)
        end
      end,
      fields
    )
    {
      kind: "block",
      block: rs_block(
        [
          {
            kind: "local",
            name: "s_0",
            value: cz_as(second(base), rec[:name], ctx)
          },
          rs_tail(lit(vals))
        ]
      )
    }
  elsif count(args) == 1 and h == "hash-map"
    given = cz_pairs(first(args))
    lit(
      map(
        fn(f)
          v = cz_lookup(f, given)
          if v.nil?
            cz_refuse("#{cz_ty_text(rec[:name])} is missing its field `#{f}`")
          end
          cz_as(v, :word, ctx)
        end,
        fields
      )
    )
  elsif count(args) != count(fields)
    cz_refuse(
      "#{cz_ty_text(rec[:name])} takes #{count(fields)} fields, given #{count(args)}"
    )
  else
    lit(map((a) -> cz_as(a, :word, ctx), args))
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
    if member?(s, ctx[:params]) and member?(s, ctx[:shared] or [])
      rs_method(rs_path(cz_param_name(s)), "clone", [])
    elsif member?(s, ctx[:params])
      rs_path(cz_param_name(s))
    elsif member?(s, ctx[:consts])
      rs_path(cz_const_name(s))
    elsif member?(s, ctx[:bindings]) and
        ctx[:self].nil? and
        cz_lookup(s, ctx[:types] or []) == :list
      rs_method(rs_path(cz_binding_name(s)), "clone", [])
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
  elsif cz_plain?(h, args, ctx)
    rs_binary(
      if h == "-"
        "sub"
      else
        "rem"
      end,
      cz_expr(first(args), ctx),
      cz_expr(second(args), ctx)
    )
  elsif arith == "checked_rem_euclid" and
      count(args) == 2 and
      integer?(second(args)) and
      second(args) > 0
    rs_method(
      cz_expr(first(args), ctx),
      "rem_euclid",
      [cz_expr(second(args), ctx)]
    )
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
    ta = cz_ty(first(args), ctx)
    tb = cz_ty(second(args), ctx)
    if ta == :word and tb == :word
      rs_binary(cmp, cz_expr(first(args), ctx), cz_expr(second(args), ctx))
    elsif member?(h, %w[equal? not=])
      t = cz_unify(ta, tb)
      rs_binary(cmp, cz_as(first(args), t, ctx), cz_as(second(args), t, ctx))
    else
      cz_refuse(
        "`#{h}` orders Ints; #{cz_ty_text(ta)} and #{cz_ty_text(tb)} have no order"
      )
    end
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
    t = cz_ty(n, ctx)
    {
      kind: "block",
      block: rs_block(
        [
          rs_tail(
            rs_if(
              cz_expr(first(args), ctx),
              rs_block(
                [
                  rs_tail(
                    cz_as(second(args), t, cz_given(first(args), true, ctx))
                  )
                ]
              ),
              rs_block(
                [
                  rs_tail(
                    cz_as(third(args), t, cz_given(first(args), false, ctx))
                  )
                ]
              )
            )
          )
        ]
      )
    }
  elsif h == "begin"
    {kind: "block", block: rs_block(cz_body(args, ctx))}
  elsif h == "kiban/mmio_write"
    cz_mmio(args, ctx)
  elsif h == "kiban/put_byte"
    cz_put_byte(first(args), ctx)
  elsif h == "kiban/put_int"
    cz_direct(
      fn(xs)
        rs_call(
          %w[kiban_io put_int],
          append([rs_path("io"), rs_u32(ctx[:uart])], xs)
        )
      end,
      args,
      ctx
    )
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
  elsif member?(h, %w[list append count nth first])
    cz_list_op(h, args, ctx)
  elsif h == "blue-field"
    cz_field(args, ctx)
  elsif cz_record_named(ctx, h) != nil
    cz_construct(cz_record_named(ctx, h), args, ctx)
  elsif cz_record_tested(ctx, h) != nil
    cz_is(cz_record_tested(ctx, h), first(args), ctx)
  elsif member?(h, ctx[:fns])
    lead = if member?(h, ctx[:rec])
      [rs_path("io"), ctx[:depth]]
    else
      [rs_path("io")]
    end
    sig = cz_lookup(h, ctx[:sigs] or [])
    wants = if sig.nil?
      map((_a) -> nil, args)
    else
      sig[:params]
    end
    cz_call_across(h, lead, args, wants, sig, ctx)
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
cz_put_byte: put_byte(c): `c` bound once, stored to the board's UART, and answered.

    last(cz_put_byte(65, {word: 64, uart: 4096})[:block][:stmts])[:expr] #=> {kind: "path", segments: ["b_0"]}
"""
def cz_put_byte(arg, ctx)
  b = rs_path("b_0")
  store = rs_method(
    rs_path("io"),
    "write8",
    [
      rs_call(%w[kiban_io reg], [rs_u32(ctx[:uart])]),
      rs_call(%w[kiban_io reg], [b])
    ]
  )
  {
    kind: "block",
    block: rs_block(
      [
        {kind: "local", name: "b_0", value: cz_expr(arg, ctx)},
        rs_semi(store),
        rs_tail(b)
      ]
    )
  }
end

@doc """
cz_strategy: How the definition `name` reclaims the lists it holds: :arena when the
program says so with `reclaim(:arena, "name")`, else :refcount.

    cz_strategy("%root/f", {strategies: [["%root/f", :arena]]}) #=> :arena
    cz_strategy("%root/g", {strategies: []}) #=> :refcount
"""
def cz_strategy(name, ctx)
  cz_lookup(name, ctx[:strategies] or []) or :refcount
end

@doc """
cz_region: The region the current definition's lists live in: its `rg` parameter.

    cz_region({}) #=> {kind: "path", segments: ["rg"]}
"""
def cz_region(_ctx)
  rs_path("rg")
end

@doc """
cz_borrowed: A list operand read without being taken: `&x` of a refcounted list, the
span itself in a region.

    cz_borrowed({sym: "xs"}, {params: ["xs"], strategy: :refcount, word: 64})[:kind] #=> "ref"
"""
def cz_borrowed(n, ctx)
  e = if cz_sym?(n) and member?(cz_sym(n), ctx[:params])
    rs_path(cz_param_name(cz_sym(n)))
  else
    cz_expr(n, ctx)
  end
  if ctx[:strategy] == :arena
    e
  else
    {kind: "ref", expr: e}
  end
end

@doc """
cz_temps: Each expression bound to a local `<stem>_<i>`, so a call that takes the
region or the board borrows it alone: the locals, then their paths.

    second(cz_temps("e", [rs_path("a")])) #=> [{kind: "path", segments: ["e_0"]}]
"""
def cz_temps(stem, exprs)
  idx = range(count(exprs))
  [
    map((i) -> {kind: "local", name: "#{stem}_#{i}", value: exprs[i]}, idx),
    map((i) -> rs_path("#{stem}_#{i}"), idx)
  ]
end

@doc """
rs_seq: A block of `stmts` ending in `tail`.

    rs_seq([], rs_path("x"))[:kind] #=> "block"
"""
def rs_seq(stmts, tail)
  {kind: "block", block: rs_block(append(stmts, [rs_tail(tail)]))}
end

@doc """
cz_list_op: A list word on a host with a heap: `[a, b]`, append, count, nth, first,
each on the representation the current definition's strategy holds.

    cz_list_op("count", [{sym: "xs"}], {params: ["xs"], strategy: :refcount, word: 64, heap: true})[:func] #=> ["kiban_heap", "rc_count"]
"""
def cz_list_op(h, args, ctx)
  arena = ctx[:strategy] == :arena
  if not ctx[:heap]
    cz_refuse("a list needs a heap, and this board has none; lists compile for the host board")
  elsif h == "list"
    t = cz_temps("e", map((a) -> cz_as(a, :word, ctx), args))
    if arena
      rg = cz_region(ctx)
      rs_seq(
        append(
          first(t),
          [{kind: "local", name: "s", value: rs_method(rg, "begin", [])}],
          map((e) -> rs_semi(rs_method(rg, "push", [e])), second(t))
        ),
        rs_method(rg, "end", [rs_path("s")])
      )
    else
      rs_seq(
        append(
          first(t),
          [
            {
              kind: "local",
              name: "v",
              mutable: true,
              value: rs_call(
                %w[kiban_heap vec_with],
                [{kind: "int", value: count(args), suffix: "usize"}]
              )
            }
          ],
          map((e) -> rs_semi(rs_method(rs_path("v"), "push", [e])), second(t))
        ),
        rs_call(%w[kiban_heap rc_of], [rs_path("v")])
      )
    end
  elsif h == "append" and count(args) == 2 and cz_head(second(args)) == "list"
    cz_push_words(first(args), rest(second(args)), ctx)
  elsif h == "append"
    if count(args) < 2
      cz_refuse("append joins two lists or more")
    end
    if arena
      t = cz_temps("x", map((a) -> cz_list_value(a, ctx), args))
      rs_seq(
        first(t),
        reduce(
          (acc, b) -> rs_method(cz_region(ctx), "append", [acc, b]),
          first(second(t)),
          rest(second(t))
        )
      )
    else
      reduce(
        fn(acc, b)
          rs_call(
            %w[kiban_heap rc_append],
            [acc, {kind: "ref", expr: cz_list_value(b, ctx)}]
          )
        end,
        cz_list_value(first(args), ctx),
        rest(args)
      )
    end
  elsif h == "count"
    if arena
      rs_call(%w[Region count], [cz_borrowed(first(args), ctx)])
    else
      rs_call(%w[kiban_heap rc_count], [cz_borrowed(first(args), ctx)])
    end
  else
    l = if h == "first"
      first(args)
    else
      second(args)
    end
    i = if h == "first"
      0
    else
      first(args)
    end
    if arena
      t = cz_temps("n", [cz_borrowed(l, ctx), cz_as(i, :word, ctx)])
      rs_seq(first(t), rs_method(cz_region(ctx), "nth", second(t)))
    else
      rs_call(
        %w[kiban_heap rc_nth],
        [cz_borrowed(l, ctx), cz_as(i, :word, ctx)]
      )
    end
  end
end

@doc """
cz_push_words: `append(xs, [a, b])`: the words pushed onto `xs`, one at a time, with
no list made for them: in place when `xs` is held nowhere else (refcount) or
is its region's newest list (arena).

    last(cz_push_words({sym: "xs"}, [1], {params: ["xs"], types: [["xs", :list]], strategy: :refcount, word: 64})[:block][:stmts])[:expr][:func] #=> ["kiban_heap", "rc_push"]
"""
def cz_push_words(xs, words, ctx)
  arena = ctx[:strategy] == :arena
  t = cz_temps("w", map((w) -> cz_as(w, :word, ctx), words))
  base = cz_list_value(xs, ctx)
  pushed = reduce(
    fn(acc, w)
      if arena
        rs_method(cz_region(ctx), "push_onto", [acc, w])
      else
        rs_call(%w[kiban_heap rc_push], [acc, w])
      end
    end,
    rs_path("l_0"),
    second(t)
  )
  rs_seq(append([{kind: "local", name: "l_0", value: base}], first(t)), pushed)
end

@doc """
cz_list_value: An operand that must be a list, lowered.

    cz_list_value({sym: "xs"}, {params: ["xs"], types: [["xs", :list]]}) #=> {kind: "path", segments: ["p_xs"]}
"""
def cz_list_value(n, ctx)
  t = cz_ty(n, ctx)
  if t != :list
    cz_refuse("append joins lists, and this is #{cz_ty_text(t)}")
  end
  cz_expr(n, ctx)
end

@doc """
cz_convert: A list moved between strategies at a call: into the region `rg` from a
refcounted list, or out of it into a refcounted one. Anything else as it is.

    cz_convert(rs_path("x"), :list, :refcount, :arena, rs_path("rg"))[:method] #=> "from_rc"
    cz_convert(rs_path("x"), :word, :refcount, :arena, rs_path("rg")) #=> {kind: "path", segments: ["x"]}
"""
def cz_convert(e, ty, from, to, rg)
  if ty != :list or from == to
    e
  elsif to == :arena
    rs_method(rg, "from_rc", [{kind: "ref", expr: e}])
  else
    rs_method(rg, "to_rc", [e])
  end
end

@doc """
cz_call_across: A call of the definition `h`. Arguments are brought to the types it
takes and to the strategy it holds lists by. A region definition called from a
refcounting one gets a fresh region for the call, and a list it answers is
copied out before that region is dropped; between two region definitions the
region is passed on.
"""
def cz_call_across(h, lead, args, wants, sig, ctx)
  callee = cz_strategy(h, ctx)
  caller = ctx[:strategy] or :refcount
  fresh = callee == :arena and caller != :arena
  rg = if fresh
    rs_path("rg_0")
  else
    cz_region(ctx)
  end
  rg_arg = if callee == :arena and fresh
    [{kind: "ref", mutable: true, expr: rg}]
  elsif callee == :arena
    [rg]
  else
    []
  end
  full_lead = append([first(lead)], rg_arg, rest(lead))
  lowered = map(
    fn(i)
      cz_convert(cz_as(args[i], wants[i], ctx), wants[i], caller, callee, rg)
    end,
    range(count(args))
  )
  ret = if sig.nil?
    :word
  else
    sig[:ret]
  end
  if fresh or callee == :arena or caller == :arena
    t = cz_temps("a", lowered)
    call = rs_call([cz_fn_name(h)], append(full_lead, second(t)))
    open = if fresh
      [
        {
          kind: "local",
          name: "rg_0",
          mutable: true,
          value: rs_call(%w[Region new], [])
        }
      ]
    else
      []
    end
    rs_seq(
      append(open, first(t), [{kind: "local", name: "r_0", value: call}]),
      cz_convert(rs_path("r_0"), ret, callee, caller, rg)
    )
  else
    cz_direct_with(
      (xs) -> rs_call([cz_fn_name(h)], append(full_lead, xs)),
      args,
      (i) -> lowered[i],
      ctx
    )
  end
end

@doc """
cz_uses: How many times `name` is read along the path through `n` that reads it
most: the two branches of an `if` are never both taken. A list parameter or
local read at most once is moved where it is taken; read more, a take clones
it (a refcount, not a copy), since a borrow (count, nth, first) may come after
the take in evaluation order.

    cz_uses(first(cz_read("(if c xs (append xs (list 1)))")), "xs") #=> 1
    cz_uses(first(cz_read("(f xs (count xs))")), "xs") #=> 2
"""
def cz_uses(n, name)
  h = cz_head(n)
  if cz_sym?(n)
    if cz_sym(n) == name
      1
    else
      0
    end
  elsif not list?(n) or count(n) == 0
    0
  elsif h == "if"
    other = if count(n) > 3
      cz_uses(fourth(n), name)
    else
      0
    end
    cz_uses(second(n), name) + max(cz_uses(third(n), name), other)
  else
    reduce((acc, a) -> acc + cz_uses(a, name), 0, rest(n))
  end
end

@doc """
cz_effectful?: Whether lowering `n` reaches the board: a call of a definition or a
board word, anywhere inside it.

    cz_effectful?(first(cz_read("(+ 1 (%root/f 2))")), {fns: ["%root/f"]}) #=> true
    cz_effectful?(first(cz_read("(+ 1 2)")), {fns: []}) #=> false
"""
def cz_effectful?(n, ctx)
  h = cz_head(n)
  if not list?(n)
    false
  elsif member?(
      h,
      %w[kiban/mmio_write kiban/put_byte kiban/put_int list append nth first]
    ) or member?(h, ctx[:fns])
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

    cz_direct((xs) -> rs_call(["f"], xs), [1], {word: 64, fns: []})[:args] #=> [{kind: "int", value: 1, suffix: "i64"}]
"""
def cz_direct(build, args, ctx)
  cz_direct_with(build, args, (i) -> cz_expr(args[i], ctx), ctx)
end

@doc """
cz_direct_with: cz_direct, each argument lowered by `lower(i)`.

    cz_direct_with((xs) -> rs_call(["f"], xs), [1], (_i) -> rs_path("k"), {fns: []})[:args] #=> [{kind: "path", segments: ["k"]}]
"""
def cz_direct_with(build, args, lower, ctx)
  if any?((a) -> cz_effectful?(a, ctx), args)
    idx = range(count(args))
    temps = map((i) -> {kind: "local", name: "a_#{i}", value: lower(i)}, idx)
    {
      kind: "block",
      block: rs_block(
        append(temps, [rs_tail(build(map((i) -> rs_path("a_#{i}"), idx)))])
      )
    }
  else
    build(map(lower, range(count(args))))
  end
end

@doc """
cz_floor: floor(a / b), the interpreter's integer division: rounded toward negative
infinity in the signed host word, the plain quotient in the unsigned board
word. A divisor of zero is a fault, as the interpreter raises.

    cz_floor([first(cz_read("(/ 7 2)"))], {word: 64})[:func] #=> ["kiban_io", "floor_div"]
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

    cz_stmt(first(cz_read("(if (< a b) a)")), {word: 64, params: ["a", "b"], fns: []})[:expr][:kind] #=> "if"
"""
def cz_stmt(n, ctx)
  if cz_head(n) == "if" and count(n) == 3
    rs_semi(
      rs_if(
        cz_expr(second(n), ctx),
        rs_block([cz_stmt(third(n), cz_given(second(n), true, ctx))]),
        nil
      )
    )
  else
    rs_semi(cz_expr(n, ctx))
  end
end

@doc """
cz_body: A sequence in value position: every form but the last as a statement.
"""
def cz_body(forms, ctx)
  r = cz_lead(forms, ctx)
  append(r[:stmts], [rs_tail(cz_expr(last(forms), r[:ctx]))])
end

@doc """
cz_local_def?: Whether `f` binds a local in a body: `x = e` inside a definition.

    cz_local_def?(first(cz_read("(define xs (list))"))) #=> true
    cz_local_def?(first(cz_read("(define (f x) x)"))) #=> false
"""
def cz_local_def?(f)
  cz_head(f) == "define" and cz_sym?(second(f))
end

@doc """
cz_scope: `ctx` with the locals `forms` bind, each typed by its value.

    cz_scope(cz_read("(define k 3)"), {params: [], types: []})[:types] #=> [["k", :word]]
"""
def cz_scope(forms, ctx)
  reduce(
    fn(acc, f)
      if cz_local_def?(f)
        x = cz_sym(second(f))
        {
          **acc,
          params: append(acc[:params] or [], [x]),
          types: append(acc[:types] or [], [[x, cz_ty(third(f), acc)]])
        }
      else
        acc
      end
    end,
    ctx,
    forms
  )
end

@doc """
cz_lead: Every form of a body but the last, as statements: a local binding is a
`let`, and the forms after it see it; a list local taken more than once after
it is cloned where taken (a refcount, not a copy). Answers the statements and
the context the last form sees.

    cz_lead(cz_read("(define k 3) k"), {params: [], types: [], word: 64})[:stmts] #=> [{kind: "local", name: "p_k", value: {kind: "int", value: 3, suffix: "i64"}}]
"""
def cz_lead(forms, ctx)
  lead = butlast(forms)
  reduce(
    fn(acc, i)
      f = lead[i]
      if cz_local_def?(f)
        x = cz_sym(second(f))
        c = cz_scope([f], acc[:ctx])
        later = reduce((n, g) -> n + cz_uses(g, x), 0, drop(i + 1, forms))
        shared = if cz_lookup(x, c[:types]) == :list and later > 1
          append(c[:shared] or [], [x])
        else
          c[:shared] or []
        end
        {
          stmts: append(
            acc[:stmts],
            [
              {
                kind: "local",
                name: cz_param_name(x),
                value: cz_expr(third(f), acc[:ctx])
              }
            ]
          ),
          ctx: {**c, shared:}
        }
      else
        {stmts: append(acc[:stmts], [cz_stmt(f, acc[:ctx])]), ctx: acc[:ctx]}
      end
    end,
    {stmts: [], ctx:},
    range(count(lead))
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
      fn(i)
        {
          kind: "local",
          name: "t_#{i}",
          value: cz_as(args[i], cz_lookup(params[i], ctx[:types] or []), ctx)
        }
      end,
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
    t = rs_block(cz_tail(third(n), cz_given(second(n), true, ctx)))
    e = if count(n) > 3
      rs_block(cz_tail(fourth(n), cz_given(second(n), false, ctx)))
    else
      cz_refuse("an `if` in tail position needs an else branch")
    end
    [rs_semi(rs_if(c, t, e))]
  elsif h == "begin"
    forms = rest(n)
    r = cz_lead(forms, ctx)
    append(r[:stmts], cz_tail(last(forms), r[:ctx]))
  else
    [rs_semi({kind: "return", value: cz_as(n, ctx[:ret], ctx)})]
  end
end

@doc """
cz_calls: The definitions `n` calls, in `fns`. A call of `me` in tail position is
left out: that function loops instead (`me` is nil when it does not).

    cz_calls(first(cz_read("(+ (%root/f 1) (%root/g 2))")), ["%root/f"], nil, true) #=> ["%root/f"]
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

    cz_recursive(cz_read("(define-typed (%root/f (n Int)) Int (%root/f n))"), ["%root/f"]) #=> []
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
  records = env[:records] or []
  strategy = cz_strategy(name, env)
  ret_ty = cz_sig_ty(third(form), records)
  ret = cz_rs_ty(cz_held_ty(ret_ty, strategy), word)
  types = map(
    (p) -> [cz_sym(first(p)), cz_sig_ty(second(p), records)],
    rest(sig)
  )
  body = fourth(form)
  shared = map(
    first,
    filter((t) -> second(t) == :list and cz_uses(body, first(t)) > 1, types)
  )
  rec = member?(name, env[:rec])
  depth = if rec
    rs_path("d")
  else
    rs_u32(0)
  end
  ctx = {
    **env,
    self: name,
    params:,
    depth:,
    types:,
    ret: ret_ty,
    strategy:,
    shared:,
    lb: append(
      map(
        (p) -> [p, 0],
        filter((p) -> member?([name, p], env[:nonneg] or []), params)
      ),
      env[:lb] or []
    )
  }
  rparams = map(
    fn(t)
      {
        name: cz_param_name(first(t)),
        ty: cz_rs_ty(cz_held_ty(second(t), strategy), word)
      }
    end,
    types
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
    append(enter, [rs_tail(cz_as(body, ret_ty, ctx))])
  end
  region = if strategy == :arena
    [{name: "rg", ty: {ident: "Region", reference: {kind: "mut"}}}]
  else
    []
  end
  lead = if rec
    [rs_depth_param]
  else
    []
  end
  rs_fn(
    "private",
    cz_fn_name(name),
    append(region, lead, rparams),
    ret,
    rs_block(stmts)
  )
end

@doc """
cz_constant?: Whether `n` is computed from literals and earlier constants alone, so
it is a Rust constant evaluated when the image is built.

    cz_constant?(first(cz_read("(* %root/A 2)")), ["%root/A"]) #=> true
    cz_constant?(first(cz_read("(%root/f 2)")), []) #=> false
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

@doc """
cz_binding_name: The Rust local a computed top-level binding becomes.

    cz_binding_name("%root/K") #=> "g_k"
"""
def cz_binding_name(qualified)
  concat("g_", downcase(cz_checked_ident(cz_local(qualified), "a binding")))
end

@doc """
cz_kind: What a top-level form is: a use, a typed definition, a constant (from
literals and the constants before it), a binding the top level computes when
it runs, an untyped definition, or an expression.

    cz_kind(first(cz_read("(define %root/X (+ %root/A 1))")), ["%root/A"]) #=> :const
    cz_kind(first(cz_read("(define %root/X (+ %root/A 1))")), []) #=> :binding
"""
def cz_kind(form, consts)
  h = cz_head(form)
  if h == "use"
    :use
  elsif h == "blue-record"
    :record
  elsif h == "kiban/reclaim"
    :reclaim
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

    map(first, cz_kinds(cz_read("(define %root/A 1) (define %root/B %root/A)"))) #=> [:const, :const]
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

    cz_main_stmt([:binding, first(cz_read("(define %root/K 2)"))], {word: 64})[:name] #=> "g_k"
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
cz_reclaim_of: The strategy `reclaim(:arena, "name")` gives a definition, as
[qualified name, strategy]. An unknown strategy or name is refused.

    cz_reclaim_of(first(cz_read("(kiban/reclaim :arena \"f\")")), ["%root/f"]) #=> ["%root/f", :arena]
"""
def cz_reclaim_of(form, fns)
  strategy = second(form)[:kw]
  name = "%root/#{third(form)[:str] or ""}"
  if not member?(strategy, %w[arena refcount])
    cz_refuse("reclaim takes :arena or :refcount, given #{to_s(second(form))}")
  end
  if not member?(name, fns)
    cz_refuse(
      "reclaim names `#{third(form)[:str]}`, which is not a typed definition of this program"
    )
  end
  if strategy == "arena"
    [name, :arena]
  else
    [name, :refcount]
  end
end

@doc """
cz_mentions?: Whether any symbol in `n` is one of `names`.

    cz_mentions?(cz_read("(f (list 1))"), ["list"]) #=> true
    cz_mentions?(cz_read("(f 1)"), ["list"]) #=> false
"""
def cz_mentions?(n, names)
  if cz_sym?(n)
    member?(cz_sym(n), names)
  elsif list?(n)
    any?((x) -> cz_mentions?(x, names), n)
  else
    false
  end
end

@doc """
cz_lb: The least value `n` can have where it stands, from literals, the facts
in `ctx[:lb]` and the operators that keep a bound, or nil when none is known.
A Euclidean remainder by a positive literal is never negative, whatever its
left side.

    cz_lb(first(cz_read("(- n 1)")), {lb: [["n", 2]]}) #=> 1
    cz_lb(first(cz_read("(mod x 3)")), {lb: []}) #=> 0
    cz_lb(first(cz_read("(+ n x)")), {lb: [["n", 0]]}) #=> nil
"""
def cz_lb(n, ctx)
  h = cz_head(n)
  bounds = (xs) -> map((x) -> cz_lb(x, ctx), xs)
  all_nonneg = (bs) -> every?((b) -> b != nil and b >= 0, bs)
  if integer?(n)
    n
  elsif cz_sym?(n)
    cz_lookup(cz_sym(n), ctx[:lb] or [])
  elsif not list?(n)
    nil
  elsif h == "+" and all_nonneg(bounds(rest(n)))
    reduce((a, b) -> a + b, 0, bounds(rest(n)))
  elsif h == "*" and all_nonneg(bounds(rest(n)))
    reduce((a, b) -> a * b, 1, bounds(rest(n)))
  elsif h == "-" and
      count(n) == 3 and
      integer?(third(n)) and
      cz_lb(second(n), ctx) != nil
    cz_lb(second(n), ctx) - third(n)
  elsif member?(h, %w[mod modulo rem]) and
      count(n) == 3 and
      integer?(third(n)) and
      third(n) > 0
    0
  end
end

@doc """
cz_plain?: Whether `h` applied to `args` cannot fault, so it is the plain operator:
a difference of two values never below zero cannot overflow the signed word,
and a Euclidean remainder of a value never below zero by a positive literal
is the truncating one.

    cz_plain?("-", [{sym: "n"}, 1], {word: 64, lb: [["n", 1]]}) #=> true
    cz_plain?("-", [{sym: "n"}, 1], {word: 64, lb: []}) #=> false
    cz_plain?("mod", [{sym: "i"}, 3], {word: 64, lb: [["i", 0]]}) #=> true
"""
def cz_plain?(h, args, ctx)
  nonneg = (x) -> cz_lb(x, ctx) != nil and cz_lb(x, ctx) >= 0
  if ctx[:word] != 64 or count(args) != 2
    false
  elsif h == "-"
    nonneg(first(args)) and nonneg(second(args))
  elsif member?(h, %w[mod modulo rem])
    nonneg(first(args)) and integer?(second(args)) and second(args) > 0
  else
    false
  end
end

@doc """
cz_given: `ctx` inside the branch of `cond` taken when it is `truth`: a comparison
of a name with a literal raises the name's least value.

    cz_given(first(cz_read("(< n 2)")), false, {lb: []})[:lb] #=> [["n", 2]]
    cz_given(first(cz_read("(equal? i 0)")), false, {lb: [["i", 0]]})[:lb] #=> [["i", 1], ["i", 0]]
    cz_given(first(cz_read("(> n 5)")), true, {lb: []})[:lb] #=> [["n", 6]]
"""
def cz_given(cond, truth, ctx)
  h = cz_head(cond)
  lhs = if list?(cond) and count(cond) == 3
    second(cond)
  end
  k = if list?(cond) and count(cond) == 3
    third(cond)
  end
  name = cz_sym(lhs)
  old = if name.nil?
    nil
  else
    cz_lookup(name, ctx[:lb] or [])
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
    reduce((c, x) -> cz_given(x, true, c), ctx, rest(cond))
  elsif least.nil? or old != nil and old >= least
    ctx
  else
    {**ctx, lb: append([[name, least]], ctx[:lb] or [])}
  end
end

@doc """
cz_sites: Every call of a definition in `fns` inside `n`, with the facts that hold
where it is made, as [callee, arguments, context].

    count(cz_sites(first(cz_read("(if (< n 2) n (%root/f (- n 1)))")), ["%root/f"], {lb: []})) #=> 1
"""
def cz_sites(n, fns, ctx)
  h = cz_head(n)
  if not list?(n) or count(n) == 0
    []
  elsif h == "if"
    c = second(n)
    append(
      cz_sites(c, fns, ctx),
      cz_sites(third(n), fns, cz_given(c, true, ctx)),
      if count(n) > 3
        cz_sites(fourth(n), fns, cz_given(c, false, ctx))
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
    reduce((acc, a) -> append(acc, cz_sites(a, fns, ctx)), own, rest(n))
  end
end

@doc """
cz_nonneg: The Int parameters never below zero, as [definition, parameter]: the
largest set such that, assuming it, every call anywhere passes each of them a
value whose least is at least zero. It starts from every Int parameter and
drops one that some call cannot vouch for, until nothing more drops; the
set left is an inductive invariant, so it holds on every call.

    cz_nonneg(cz_read("(define-typed (%root/f (n Int)) Int n)"), cz_read("(%root/f 3)"), {lb: []}) #=> [["%root/f", "n"]]
"""
def cz_nonneg(fn_forms, top, env)
  fns = map((f) -> cz_sym(first(second(f))), fn_forms)
  start = reduce(
    fn(acc, f)
      sig = second(f)
      append(
        acc,
        map(
          (p) -> [cz_sym(first(sig)), cz_sym(first(p))],
          filter((p) -> cz_sym(second(p)) == "Int", rest(sig))
        )
      )
    end,
    [],
    fn_forms
  )
  cz_nonneg_from(start, fn_forms, fns, top, env)
end

@doc """
cz_nonneg_from: One step of cz_nonneg: of the pairs `held`, those every call site, read
with `held` assumed, still vouches for; repeated until none drops.

    cz_nonneg_from([["%root/f", "n"]], cz_read("(define-typed (%root/f (n Int)) Int n)"), ["%root/f"], cz_read("(%root/f (- 0 1))"), {lb: []}) #=> []
"""
def cz_nonneg_from(held, fn_forms, fns, top, env)
  sites = append(
    reduce(
      fn(acc, f)
        sig = second(f)
        name = cz_sym(first(sig))
        lb = append(
          map(
            (p) -> [cz_sym(first(p)), 0],
            filter((p) -> member?([name, cz_sym(first(p))], held), rest(sig))
          ),
          env[:lb] or []
        )
        append(acc, cz_sites(fourth(f), fns, {**env, lb:}))
      end,
      [],
      fn_forms
    ),
    reduce((acc, f) -> append(acc, cz_sites(f, fns, env)), [], top)
  )
  params_of = fn(g)
    map(
      (p) -> cz_sym(first(p)),
      rest(second(find(fn_forms, (f) -> cz_sym(first(second(f))) == g)))
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
            arg = second(site)[i]
            b = cz_lb(arg, third(site))
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
    cz_nonneg_from(kept, fn_forms, fns, top, env)
  end
end

@doc """
cz_record_items: A struct per record, its fields board words, and, when there are
records, `Rec`: one variant per record, each holding only that record.

    map((i) -> i[:kind], cz_record_items([{name: "%root/p", pred: "%root/p?", fields: ["x"]}], 64)) #=> ["struct", "enum"]
    cz_record_items([], 64) #=> []
"""
def cz_record_items(records, word)
  derives = %w[Clone Copy PartialEq]
  structs = map(
    fn(r)
      {
        kind: "struct",
        name: cz_struct_name(r[:name]),
        derives:,
        fields: map(
          fn(f)
            {name: cz_checked_ident(f, "a field"), ty: rs_ty(cz_word_ty(word))}
          end,
          r[:fields]
        )
      }
    end,
    records
  )
  if empty?(records)
    []
  else
    append(
      structs,
      [
        {
          kind: "enum",
          name: "Rec",
          derives:,
          variants: map(
            fn(r)
              {
                name: cz_struct_name(r[:name]),
                elems: [rs_ty(cz_struct_name(r[:name]))]
              }
            end,
            records
          )
        }
      ]
    )
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
  records = map(cz_record_of, pick(:record))
  strategies = map((f) -> cz_reclaim_of(f, fns), pick(:reclaim))
  heap = board[:rust_target].nil?
  lists = cz_mentions?(
    filter((f) -> cz_head(f) != "use", forms),
    %w[list append List]
  )
  if lists and not heap
    cz_refuse(
      "a list needs a heap, and #{board[:name]} has none; lists compile for the host board"
    )
  end
  sigs = map(
    fn(f)
      [
        cz_sym(first(second(f))),
        {
          params: map((p) -> cz_sig_ty(second(p), records), rest(second(f))),
          ret: cz_sig_ty(third(f), records)
        }
      ]
    end,
    fn_forms
  )
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
    depth: rs_u32(0),
    uart: kb_device_base(board, :uart0),
    records:,
    sigs:,
    types: [],
    strategies:,
    heap:,
    strategy: :refcount,
    shared: []
  }
  const_lb = reduce(
    fn(acc, f)
      v = cz_lb(third(f), {lb: acc})
      if v.nil?
        acc
      else
        append(acc, [[cz_sym(second(f)), v]])
      end
    end,
    [],
    const_forms
  )
  env = {
    **env,
    lb: const_lb,
    nonneg: if word == 64
      cz_nonneg(
        fn_forms,
        map(
          second,
          filter((kf) -> first(kf) == :expr or first(kf) == :binding, kinds)
        ),
        {**env, lb: const_lb}
      )
    else
      []
    end
  }
  main_env = assoc(
    env,
    :types,
    reduce(
      fn(acc, f)
        append(
          acc,
          [[cz_sym(second(f)), cz_ty(third(f), assoc(env, :types, acc))]]
        )
      end,
      [],
      pick(:binding)
    )
  )
  main_body = rs_block(
    map(
      (kf) -> cz_main_stmt(kf, main_env),
      filter((kf) -> first(kf) == :binding or first(kf) == :expr, kinds)
    )
  )
  {
    attrs: [cz_attr("no_std", []), cz_attr("forbid", ["unsafe_code"])],
    items: append(
      [{kind: "use", item: {path: %w[kiban_io Io]}}],
      if lists
        map(
          (t) -> {kind: "use", item: {path: ["kiban_heap", t]}},
          %w[List Region Span]
        )
      else
        []
      end,
      cz_record_items(records, word),
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
  heap = path_join(out, "libkiban_heap.rlib")
  hosted = board[:rust_target].nil?
  heap_extern = if hosted
    ["--extern", "kiban_heap=#{heap}"]
  else
    []
  end
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
  if hosted
    cz_run(
      append(
        ["rustc"],
        flags,
        [
          "--crate-type",
          "rlib",
          "--crate-name",
          "kiban_heap",
          "--extern",
          "kiban_io=#{io}",
          "-o",
          heap,
          path_join(seam, "kiban_heap.rs")
        ]
      ),
      "rustc kiban_heap"
    )
  end
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
        "kiban_io=#{io}"
      ],
      heap_extern,
      ["-o", prog, rs]
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
      heap_extern,
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

    (cz_host_image("no-such-program.b", "seam", "out") rescue :refused) #=> :refused
"""
def cz_host_image(program, seam, out)
  name = replace(path_basename(program), ".b", "")
  text = cz_emit(program, "host64")
  mkdir_p(out)
  rs = path_join(out, "#{name}.rs")
  write_file(rs, text)
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

@doc """
cz_test_env: A lowering context for the tests: parameters `a` and `b`, no definitions,
the given word.

    cz_test_env(64)[:params] #=> ["a", "b"]
"""
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

@doc """
cz_test_lower: The resolved-tree `text` lowered for the board named `board_name`.

    count(cz_test_lower("", "host64")[:items]) #=> 2
"""
def cz_test_lower(text, board_name)
  cz_lower(cz_read(text), kb_board(board_name))
end

@doc """
cz_test_items: The items `text` lowers to on the host board.

    map((i) -> i[:kind], cz_test_items("")) #=> ["use", "fn"]
"""
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

test "a remainder by a positive literal cannot fault, so it is the plain rem_euclid"
  ctx = cz_test_env(64)
  plain = cz_expr(first(cz_read("(mod a 3)")), ctx)
  assert plain[:method] == "rem_euclid"
  assert cz_expr(first(cz_read("(mod a 0)")), ctx)[:func] ==
    %w[kiban_io checked]
  assert cz_expr(first(cz_read("(mod a b)")), ctx)[:func] ==
    %w[kiban_io checked]
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

test "a use form's name list is not a heap list, so a board program still compiles"
  items = get(
    cz_test_lower(
      join_lines(
        [
          "(use \"kiban\" (list :mmio_write))",
          "(kiban/mmio_write 268435456 8 104)"
        ]
      ),
      "qemu-virt32"
    ),
    :items
  )
  assert count(items) == 2
  assert (cz_test_lower(
    "(define-typed (%root/f (xs List)) Int (count xs))",
    "qemu-virt32"
  ) rescue
    :refused) == :refused
end

@doc """
cz_test_rust: The items `text` lowers to on the host board, as text to search.

    contains?(cz_test_rust(""), "main") #=> true
"""
def cz_test_rust(text)
  to_s(cz_test_items(text))
end

test "a parameter every call keeps at zero or above makes its decrement and remainder plain"
  walk = "(define-typed (%root/walk (i Int) (acc Int)) Int (if (equal? i 0) acc (%root/walk (- i 1) (+ acc (mod i 3)))))"
  safe = cz_test_rust(join_lines([walk, "(%root/walk 10 0)"]))
  assert contains?(safe, "op: \"sub\"")
  assert contains?(safe, "op: \"rem\"")
  assert contains?(safe, "checked_add")
  unsafe = cz_test_rust(
    join_lines([walk, "(%root/walk 10 0)", "(%root/walk -1 0)"])
  )
  assert not contains?(unsafe, "op: \"sub\"")
  assert contains?(unsafe, "checked_sub")
  fib = "(define-typed (%root/fib (n Int)) Int (if (< n 2) n (+ (%root/fib (- n 1)) (%root/fib (- n 2)))))"
  assert contains?(
    cz_test_rust(join_lines([fib, "(%root/fib 20)"])),
    "op: \"sub\""
  )
  assert contains?(
    cz_test_rust(join_lines([fib, "(%root/fib (- 0 5))"])),
    "op: \"sub\""
  )
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
