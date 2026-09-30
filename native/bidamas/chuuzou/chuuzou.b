use("kiban", [:kb_board])

# chuuzou (鋳造, casting): blue's native backend. A checked blue program and a
# board spec go in; a Rust crate the board's rustc builds as no_std comes out,
# with no evaluator and no collector in it.
#
# theory/BLUE-NATIVE.md is the design; this is milestone N0 (§7). Plan, fixed
# before the code (blue-development-cycle stage 1):
#
# | Need | Exists | Move |
# |---|---|---|
# | parse, resolve, check the program | `blue check`, `blue ast --resolved` (the pipeline) | reuse, through `self_exe()`: the backend never sees an unchecked tree |
# | qualified names (L1) | the resolved tree names every definition `%root/f` and every package word `kiban/mmio_write` | reuse |
# | a typed Rust AST, rendered once | tatara-rust-ast 0.1.8 (`File`, typed control flow), its `tatara-rust-emit` CLI | reuse across a process boundary; the tree is JSON built here |
# | board facts | kiban's specs | reuse |
# | reading the tree's text | nothing in blue reads an S-expression | `cz_read` below; the first instance, so it stays here until a second reader appears |
#
# The shape: read → lower (L1 qualify, L5 represent, tail calls to loops, L8
# the AST) → emit. The passes the design names and N0 lacks (closure
# conversion, monomorphisation, partial evaluation, placement, discharge) are
# absent because the N0 subset does not produce their input: every refusal
# below names the construct and the rule, so a program outside the subset is a
# compile error, never a wrong image.
#
# The N0 subset, and what each lowers to (board word 32):
#
#   def f(x: Int) -> Int      fn bl_f<I: Io>(io: &mut I, p_x: u32) -> u32
#   NAME = <integer>          const BL_NAME: u32
#   + - *                     kiban_io::checked(a.checked_add(b)): overflow is a fault
#   wrapping_add(a, b)        a.wrapping_add(b): wrapping only where asked
#   == < <= > >= !            comparisons, not
#   if / begin                if / blocks
#   a tail call to itself     a loop (the parameters rebound, then continue)
#   mmio_write(a, 8|32, v)    io.write8 / io.write32, through the board's seam
#   top-level expressions     pub fn main, called by the seam
#
# Int lowers to u32 here (L5 minimal): the checker has no fixed-width types
# yet (BLUE-NATIVE.md §5.1), so a negative value or one past 2^32 - 1 is a
# fault on the board where the interpreter would carry on. That divergence is
# outside the N0 row and is N2's type language to close.

# ── Reading the resolved tree ─────────────────────────────────────────────
#
# A node is an Int, a list of nodes, or a map: {sym: name}, {str: text},
# {kw: name}.

def cz_delims()
  ["(", ")"]
end

# Split S-expression text into tokens: "(", ")", atoms, and strings kept with
# their quotes. A fold over the characters, so length never costs depth.
def cz_tokens(text)
  start = {toks: [], cur: "", in_str: false, esc: false}
  step = fn(st, c)
    if get(st, :in_str)
      if get(st, :esc)
        assoc(assoc(st, :cur, concat(get(st, :cur), c)), :esc, false)
      elsif c == "\\"
        assoc(assoc(st, :cur, concat(get(st, :cur), c)), :esc, true)
      elsif c == "\""
        {
          toks: append(get(st, :toks), [concat(get(st, :cur), c)]),
          cur: "",
          in_str: false,
          esc: false
        }
      else
        assoc(st, :cur, concat(get(st, :cur), c))
      end
    elsif c == "\""
      assoc(assoc(cz_flush(st), :cur, "\""), :in_str, true)
    elsif member?(c, cz_delims())
      f = cz_flush(st)
      assoc(f, :toks, append(get(f, :toks), [c]))
    elsif c == " " || c == "\n" || c == "\t"
      cz_flush(st)
    else
      assoc(st, :cur, concat(get(st, :cur), c))
    end
  end
  get(cz_flush(reduce(step, start, chars(text))), :toks)
end

def cz_flush(st)
  if get(st, :cur) == ""
    st
  else
    assoc(assoc(st, :toks, append(get(st, :toks), [get(st, :cur)])), :cur, "")
  end
end

# One atom's node.
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

# The characters of a string literal's body with its escapes resolved.
def cz_unescape(cs)
  st = reduce(
    fn(acc, c)
      if get(acc, :esc)
        ch = if c == "n"
          "\n"
        elsif c == "t"
          "\t"
        else
          c
        end
        {out: concat(get(acc, :out), ch), esc: false}
      elsif c == "\\"
        assoc(acc, :esc, true)
      else
        assoc(acc, :out, concat(get(acc, :out), c))
      end
    end,
    {out: "", esc: false},
    cs
  )
  get(st, :out)
end

# The forms in `text`. A stack of open lists, folded over the tokens; an
# unbalanced text is refused.
def cz_read(text)
  st = reduce(
    fn(stack, tok)
      if tok == "("
        append(stack, [[]])
      elsif tok == ")"
        if count(stack) < 2
          throw(error(:chuuzou, "unbalanced `)` in the resolved tree"))
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
    throw(error(:chuuzou, "unbalanced `(` in the resolved tree"))
  end
  first(st)
end

# ── Node predicates ────────────────────────────────────────────────────────

def cz_sym?(n)
  map?(n) && get(n, :sym) != nil
end

def cz_sym(n)
  if cz_sym?(n)
    get(n, :sym)
  else
    nil
  end
end

def cz_head(n)
  if list?(n) && count(n) > 0
    cz_sym(first(n))
  else
    nil
  end
end

def cz_refuse(what)
  throw(error(:chuuzou, what))
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
  if s == "" || !cz_ident_ok?(s)
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
  if !integer?(n) || n < 0 || n > 4294967295
    cz_refuse("the literal #{n} does not fit the board word (u32)")
  end
  {kind: "int", value: n, suffix: "u32"}
end

def rs_call(path, args)
  {kind: "call", func: path, args: args}
end

def rs_method(receiver, method, args)
  {kind: "method-call", receiver: receiver, method: method, args: args}
end

def rs_binary(op, a, b)
  {kind: "binary", op: op, lhs: a, rhs: b}
end

def rs_block(stmts)
  {stmts: stmts}
end

def rs_semi(e)
  {kind: "semi", expr: e}
end

def rs_tail(e)
  {kind: "tail", expr: e}
end

def rs_if(c, t, e)
  if e == nil
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

def rs_fn(vis, name, params, ret, body)
  sig = {
    name: name,
    generics: rs_generics(),
    params: append([rs_io_param()], params)
  }
  sig_ = if ret == nil
    sig
  else
    assoc(sig, :return_type, ret)
  end
  {kind: "fn", vis: vis, item: {sig: sig_, body: body}}
end

# ── Lowering (L5 represent; tail calls; L8 emit) ──────────────────────────

# The type a signature names, at this board: Int is the board word.
def cz_type(n)
  if cz_sym(n) == "Int"
    rs_ty("u32")
  else
    cz_refuse(
      "the type `#{cz_sym(n) || n}` has no native representation at N0; Int is the board word"
    )
  end
end

def cz_arith()
  [["+", "checked_add"], ["-", "checked_sub"], ["*", "checked_mul"]]
end

def cz_compare()
  [["equal?", "eq"], ["<", "lt"], ["<=", "le"], [">", "gt"], [">=", "ge"]]
end

def cz_lookup(key, pairs)
  hit = find(fn(p) first(p) == key end, pairs)
  if hit == nil
    nil
  else
    second(hit)
  end
end

# An expression in value position. `ctx`: {self, params, fns, consts}.
def cz_expr(n, ctx)
  if integer?(n)
    rs_u32(n)
  elsif cz_sym?(n)
    s = cz_sym(n)
    if member?(s, get(ctx, :params))
      rs_path(cz_param_name(s))
    elsif member?(s, get(ctx, :consts))
      rs_path(cz_const_name(s))
    else
      cz_refuse("`#{s}` is not a parameter or a constant here")
    end
  elsif list?(n) && count(n) > 0
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
  arith = cz_lookup(h, cz_arith())
  cmp = cz_lookup(h, cz_compare())
  if h == nil
    cz_refuse(
      "a call through a computed function has no native form (every call is direct at the monomorphic position)"
    )
  elsif arith != nil
    if count(args) < 2
      cz_refuse("`#{h}` with #{count(args)} operands has no native form at N0")
    end
    reduce(
      fn(acc, b)
        rs_call(
          ["kiban_io", "checked"],
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
  elsif h == "kiban/wrapping_add"
    rs_method(
      cz_expr(first(args), ctx),
      "wrapping_add",
      [cz_expr(second(args), ctx)]
    )
  elsif member?(h, get(ctx, :fns))
    if h == get(ctx, :self)
      cz_refuse(
        "`#{cz_local(h)}` calls itself outside tail position; recursion needs a declared depth bound (BLUE-NATIVE.md §2.2), which N0 cannot express"
      )
    end
    rs_call(
      [cz_fn_name(h)],
      append([rs_path("io")], map(fn(a) cz_expr(a, ctx) end, args))
    )
  else
    cz_refuse(
      "`#{h}` has no native form: it is not a definition of this program or a word of its board (the native position's Reach, §2.3)"
    )
  end
end

# mmio_write(addr, width, value): the width is a literal, so the store is
# chosen at compile time.
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
  rs_method(
    rs_path("io"),
    method,
    [cz_expr(first(args), ctx), cz_expr(third(args), ctx)]
  )
end

# A sequence in value position: every form but the last as a statement.
def cz_body(forms, ctx)
  append(
    map(fn(f) rs_semi(cz_expr(f, ctx)) end, butlast(forms)),
    [rs_tail(cz_expr(last(forms), ctx))]
  )
end

# Whether `n`, in tail position, calls `self`.
def cz_tail_self?(n, name)
  h = cz_head(n)
  if h == name
    true
  elsif h == "if"
    any?(fn(b) cz_tail_self?(b, name) end, drop(2, n))
  elsif h == "begin"
    cz_tail_self?(last(rest(n)), name)
  else
    false
  end
end

# A form in tail position of a looping function, as statements that always
# leave: `return`, or the parameters rebound and `continue`.
def cz_tail(n, ctx)
  h = cz_head(n)
  if h == get(ctx, :self)
    params = get(ctx, :params)
    args = rest(n)
    if count(args) != count(params)
      cz_refuse(
        "`#{cz_local(h)}` takes #{count(params)} arguments, given #{count(args)}"
      )
    end
    temps = map(
      fn(i)
        {kind: "local", name: "t_#{i}", value: cz_expr(nth(i, args), ctx)}
      end,
      range(count(args))
    )
    rebinds = map(
      fn(i)
        rs_semi(
          {
            kind: "assign",
            target: cz_param_name(nth(i, params)),
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
      map(fn(f) rs_semi(cz_expr(f, ctx)) end, butlast(forms)),
      cz_tail(last(forms), ctx)
    )
  else
    [rs_semi({kind: "return", value: cz_expr(n, ctx)})]
  end
end

# (define-typed (name (p T) …) R body) → a generic fn over the board.
def cz_fn(form, fns, consts)
  sig = second(form)
  name = cz_sym(first(sig))
  params = map(fn(p) cz_sym(first(p)) end, rest(sig))
  ret = cz_type(third(form))
  body = fourth(form)
  ctx = {self: name, params: params, fns: fns, consts: consts}
  rparams = map(
    fn(p) {name: cz_param_name(cz_sym(first(p))), ty: cz_type(second(p))} end,
    rest(sig)
  )
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
      rebind,
      [rs_semi({kind: "loop", body: rs_block(cz_tail(body, ctx))})]
    )
  else
    [rs_tail(cz_expr(body, ctx))]
  end
  rs_fn("private", cz_fn_name(name), rparams, ret, rs_block(stmts))
end

def cz_const(form)
  v = third(form)
  if !integer?(v)
    cz_refuse(
      "the constant `#{cz_local(cz_sym(second(form)))}` must be an integer literal at N0"
    )
  end
  {
    kind: "const",
    name: cz_const_name(cz_sym(second(form))),
    ty: rs_ty("u32"),
    value: rs_u32(v)
  }
end

def cz_kind(form)
  h = cz_head(form)
  if h == "use"
    :use
  elsif h == "define-typed"
    :fn
  elsif h == "define" && cz_sym?(second(form))
    :const
  elsif h == "define"
    :untyped
  else
    :expr
  end
end

# The one package a native program may use at N0 is its board's.
def cz_check_use(form)
  pkg = get(second(form), :str)
  if pkg != "kiban"
    cz_refuse(
      "use(\"#{pkg}\"): at N0 a native program uses only its board's words (kiban)"
    )
  end
  nil
end

def cz_attr(path, args)
  {path: [path], args: args}
end

# The lowered program: a typed Rust `File` (as data), for `board`.
def cz_lower(forms, board)
  if get(board, :word) != 32
    cz_refuse(
      "N0 lowers to a 32-bit board word; #{get(board, :name)} has #{get(board, :word)}"
    )
  end
  kinds = map(fn(f) [cz_kind(f), f] end, forms)
  pick = fn(k)
    map(fn(p) second(p) end, filter(fn(p) first(p) == k end, kinds))
  end
  map(fn(f) cz_check_use(f) end, pick(:use))
  if !empty?(pick(:untyped))
    cz_refuse(
      "`#{cz_local(cz_sym(first(second(first(pick(:untyped))))))}` is untyped; the native position is restricted, so every definition is typed (constraint C4)"
    )
  end
  fn_forms = pick(:fn)
  const_forms = pick(:const)
  fns = map(fn(f) cz_sym(first(second(f))) end, fn_forms)
  consts = map(fn(f) cz_sym(second(f)) end, const_forms)
  main_ctx = {self: nil, params: [], fns: fns, consts: consts}
  main_body = rs_block(
    map(fn(e) rs_semi(cz_expr(e, main_ctx)) end, pick(:expr))
  )
  {
    attrs: [cz_attr("no_std", []), cz_attr("forbid", ["unsafe_code"])],
    items: append(
      [{kind: "use", item: {path: ["kiban_io", "Io"]}}],
      map(fn(f) cz_const(f) end, const_forms),
      map(fn(f) cz_fn(f, fns, consts) end, fn_forms),
      [rs_fn("pub", "main", [], nil, main_body)]
    )
  }
end

# ── The driver ────────────────────────────────────────────────────────────

def cz_capture(args)
  r = apply(exec_capture, args)
  {
    status: second(first(r)),
    stdout: second(second(r)),
    stderr: second(third(r))
  }
end

# The emitted Rust for the blue program at `path`, built for the board named
# `board_name`. The program is checked by blue's own pipeline first; a program
# that does not check produces no Rust.
def cz_emit(path, board_name)
  board = kb_board(board_name)
  if board == nil
    cz_refuse("no board named #{board_name}")
  end
  blue = self_exe()
  checked = cz_capture([blue, "check", path])
  if get(checked, :status) != 0
    cz_refuse(
      "#{path} does not check:\n#{get(checked, :stdout)}#{get(checked, :stderr)}"
    )
  end
  tree = cz_capture([blue, "ast", "--resolved", path])
  if get(tree, :status) != 0
    cz_refuse("blue ast failed: #{get(tree, :stderr)}")
  end
  file = cz_lower(cz_read(get(tree, :stdout)), board)
  r = exec_with_stdin(json_stringify(file), "tatara-rust-emit")
  if second(first(r)) != 0
    cz_refuse("tatara-rust-emit refused the tree: #{second(third(r))}")
  end
  second(second(r))
end

# ── Linking and measuring an image ────────────────────────────────────────

# The linker script, from the board's memory regions: the entry first, every
# section in RAM, the stack at the top of RAM. Generated, never hand-written
# (BLUE-NATIVE.md §1.6); a board with no `ram` region is refused.
def cz_link_script(board)
  ram = find(fn(r) get(r, :name) == :ram end, get(board, :memory))
  if ram == nil
    cz_refuse("#{get(board, :name)} declares no ram region")
  end
  lines = [
    "OUTPUT_ARCH(riscv)",
    "ENTRY(_start)",
    "MEMORY { ram : ORIGIN = #{get(ram, :origin)}, LENGTH = #{get(ram, :length)} }",
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
  join(lines, "\n")
end

# The rustc flags every crate of an image shares: the board's target, size
# first, abort on panic (the seam's handler is on_fault).
def cz_rustc_flags(board)
  [
    "--edition",
    "2021",
    "--target",
    get(board, :rust_target),
    "-C",
    "opt-level=z",
    "-C",
    "panic=abort",
    "-C",
    "codegen-units=1"
  ]
end

def cz_run(args, what)
  r = cz_capture(args)
  if get(r, :status) != 0
    cz_refuse("#{what} failed:\n#{get(r, :stderr)}")
  end
  r
end

# Build the image `name` from the emitted Rust at `rs`, for the board named
# `board_name`, with the seam sources under `seam` (kiban_io.rs and
# <board>/seam.rs), into the directory `out`. Three crates: kiban_io (safe),
# the program (emitted, #![forbid(unsafe_code)]), and the seam, the one crate
# where unsafe compiles, linked with LTO. Answers the ELF's path.
def cz_link(rs, board_name, seam, out, name)
  board = kb_board(board_name)
  flags = cz_rustc_flags(board)
  mkdir_p(out)
  script = path_join(out, "link.x")
  write_file(script, cz_link_script(board))
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
        out,
        "-C",
        "link-arg=-T#{script}",
        "-o",
        elf,
        path_join(seam, get(board, :name), "seam.rs")
      ]
    ),
    "rustc seam"
  )
  elf
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

# One section's size from `llvm-size -A` output, read by name (0 when the
# image has no such section).
def cz_section(size_text, section)
  row = find(fn(l) starts_with?(l, "#{section} ") end, split(size_text, "\n"))
  if row == nil
    0
  else
    to_int!(second(filter(fn(f) f != "" end, split(row, " "))))
  end
end

# The image's size (text, data, bss) and whether any core::fmt symbol is in
# it (BLUE-NATIVE.md, Review §4): one row of the size ledger.
def cz_measure(elf)
  sized = get(cz_run(["llvm-size", "-A", elf], "llvm-size"), :stdout)
  syms = get(cz_run(["llvm-nm", "-C", elf], "llvm-nm"), :stdout)
  fmt = filter(fn(l) contains?(l, "core::fmt") end, split(syms, "\n"))
  {
    text: cz_section(sized, ".text"),
    rodata: cz_section(sized, ".rodata"),
    data: cz_section(sized, ".data"),
    bss: cz_section(sized, ".bss"),
    fmt_symbols: count(fmt)
  }
end

# The size ledger row as TSV (a header and one line), for DuckDB.
def cz_size_tsv(program, board_name, m)
  head = join(
    ["program", "board", "text", "rodata", "data", "bss", "fmt_symbols"],
    "\t"
  )
  row = join(
    [
      program,
      board_name,
      get(m, :text),
      get(m, :rodata),
      get(m, :data),
      get(m, :bss),
      get(m, :fmt_symbols)
    ],
    "\t"
  )
  "#{head}\n#{row}\n"
end

# ── Tests ─────────────────────────────────────────────────────────────────

test "the reader reads the resolved tree's atoms and nesting"
  forms = cz_read("(define %root/X 5)\n(f \"a b\" :k (g))")
  assert count(forms) == 2
  assert first(forms) == [{sym: "define"}, {sym: "%root/X"}, 5]
  assert second(forms) == [{sym: "f"}, {str: "a b"}, {kw: "k"}, [{sym: "g"}]]
  assert cz_read("") == []
  assert try(cz_read("(a"), catch(_e(), :refused)) == :refused
  assert try(cz_read("a)"), catch(_e(), :refused)) == :refused
end

test "arithmetic lowers checked, and wrapping only where asked"
  ctx = {self: nil, params: ["a", "b"], fns: [], consts: []}
  e = cz_expr(first(cz_read("(+ a b)")), ctx)
  assert get(e, :func) == ["kiban_io", "checked"]
  assert get(first(get(e, :args)), :method) == "checked_add"
  w = cz_expr(first(cz_read("(kiban/wrapping_add a b)")), ctx)
  assert get(w, :method) == "wrapping_add"
end

test "a literal past the board word is a compile error"
  assert get(rs_u32(4294967295), :value) == 4294967295
  assert try(rs_u32(4294967296), catch(_e(), :refused)) == :refused
  assert try(rs_u32(-1), catch(_e(), :refused)) == :refused
end

test "a tail self-call becomes a loop and any other self-call is refused"
  looped = cz_fn(
    first(
      cz_read(
        "(define-typed (%root/down (n Int)) Int (if (equal? n 0) n (%root/down (- n 1))))"
      )
    ),
    ["%root/down"],
    []
  )
  stmts = get(get(get(looped, :item), :body), :stmts)
  assert get(get(last(stmts), :expr), :kind) == "loop"
  deep = first(
    cz_read("(define-typed (%root/f (n Int)) Int (+ 1 (%root/f n)))")
  )
  assert try(cz_fn(deep, ["%root/f"], []), catch(_e(), :refused)) == :refused
end

test "outside the N0 subset is refused, naming the rule"
  board = kb_board("qemu-virt32")
  assert try(
    cz_lower(cz_read("(define (%root/f x) x)"), board),
    catch(_e(), :refused)
  ) ==
    :refused
  assert try(
    cz_lower(cz_read("(use \"retsu\" (list :first))"), board),
    catch(_e(), :refused)
  ) ==
    :refused
  assert try(cz_lower(cz_read("(eval 1)"), board), catch(_e(), :refused)) ==
    :refused
end

test "the linker script comes from the board's ram region"
  script = cz_link_script(kb_board("qemu-virt32"))
  assert contains?(script, "ORIGIN = 2147483648, LENGTH = 131072")
  assert try(
    cz_link_script({name: "bare", memory: []}),
    catch(_e(), :refused)
  ) ==
    :refused
end

test "a section's size is read by name"
  out = "x.elf  :\nsection   size   addr\n.text       64   2147483648\n.comment   153   0\n"
  assert cz_section(out, ".text") == 64
  assert cz_section(out, ".data") == 0
end
