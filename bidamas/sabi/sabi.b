@moduledoc """
sabi (錆): Rust source from blue data. Build the items as values, render once.

Blue generates Rust the way the fleet's typed-emission rule asks: a program
builds a TREE of Rust items (constants, enums, structs, impls, match arms), and
one renderer turns the tree into text. No caller ever pastes Rust together
from strings, so escaping, indentation and identifier checks live in exactly
one place (this file) and are tested once.

The first consumer is blue itself: blue-lang-syntax's character tables are
authored in blue (crates/blue-lang-syntax/gen/kigou.b) and rendered into the
crate's Rust by this package, with a freshness gate in `nix flake check`.

Every node is a map with a `kind` and named fields. Constructors below are the
only way nodes are made, so a renderer arm and its constructor stay together.

  types   rs_ty(name)  rs_ty_ref(t)  rs_ty_slice(t)  rs_ty_tuple(ts)
  exprs   rs_str  rs_char  rs_int  rs_bool  rs_slice  rs_tuple  rs_path
          rs_match(scrutinee, arms) with rs_arm(pattern, expr)
  items   rs_const  rs_enum(+ rs_variant)  rs_struct(+ rs_field)
          rs_impl(+ rs_fn, rs_param, rs_self_param)
  file    rs_file(source, items), rendered by render_rust

    valid_ident?("") #=> false
"""

use(
  "retsu",
  %i[concat_lists contains count_where first flat_map is_empty repeat]
)

legacy_names("0.1.1", "rs")

# ── types ──────────────────────────────────────────────────────────────────

def ty(name)
  {kind: :ty_name, name:}
end

def ty_ref(inner)
  {kind: :ty_ref, inner:}
end

def ty_slice(inner)
  {kind: :ty_slice, inner:}
end

def ty_tuple(items)
  {kind: :ty_tuple, items:}
end

def render_ty(t)
  k = t[:kind]
  if k == :ty_name
    t[:name]
  elsif k == :ty_ref
    "&#{render_ty(t[:inner])}"
  elsif k == :ty_slice
    "[#{render_ty(t[:inner])}]"
  else
    "(#{join(map(render_ty, t[:items]), ", ")})"
  end
end

# ── expressions ────────────────────────────────────────────────────────────

def str(s)
  {kind: :str, value: s}
end

def char(c)
  {kind: :char, value: c}
end

def int(n)
  {kind: :int, value: n}
end

def bool(b)
  {kind: :bool, value: b}
end

@doc """
slice: `&[a, b, …]`, one element per line.
"""
def slice(items)
  {kind: :slice, items:}
end

def tuple(items)
  {kind: :tuple, items:}
end

@doc """
path: `A::B::C`.
"""
def path(segments)
  {kind: :path, segments:}
end

# waive B0013: `match` is a builtin sabi also uses, so the prefix stays; sabi::match names it too
def rs_match(scrutinee, arms)
  {kind: :match, scrutinee:, arms:}
end

def arm(pattern, expr)
  {kind: :arm, pattern:, expr:}
end

@doc """
escape_str: A Rust string literal's body: backslash first, so the escapes added after it
are not themselves escaped.
"""
def escape_str(s)
  replace(
    replace(
      replace(
        replace(replace(s, "\\", "\\\\"), "\"", "\\\""),
        line_break,
        "\\n"
      ),
      "\t",
      "\\t"
    ),
    "\r",
    "\\r"
  )
end

def escape_char(c)
  if c == "'"
    "\\'"
  elsif c == "\\"
    "\\\\"
  elsif c == line_break
    "\\n"
  elsif c == "\t"
    "\\t"
  else
    c
  end
end

def pad(level)
  join(repeat("    ", level), "")
end

@doc """
render_expr: An expression at an indentation level (the level of the line it starts on).

    render_expr(char("'"), 0) #=> "'\\''"
"""
def render_expr(e, level)
  k = e[:kind]
  if k == :str
    "\"#{escape_str(e[:value])}\""
  elsif k == :char
    "'#{escape_char(e[:value])}'"
  elsif k == :int
    to_s(e[:value])
  elsif k == :bool
    if e[:value]
      "true"
    else
      "false"
    end
  elsif k == :tuple
    "(#{join(map((i) -> render_expr(i, level), e[:items]), ", ")})"
  elsif k == :path
    join(e[:segments], "::")
  elsif k == :slice
    rows = map(
      (i) -> "#{pad(level + 1)}#{render_expr(i, level + 1)},",
      e[:items]
    )
    join_lines(["&[", join(rows, line_break), "#{pad(level)}]"])
  else
    arms = map(
      fn(a)
        "#{pad(level + 1)}#{render_expr(a[:pattern], level + 1)} => #{render_expr(a[:expr], level + 1)},"
      end,
      e[:arms]
    )
    join_lines(
      [
        "match #{render_expr(e[:scrutinee], level)} {",
        join(arms, line_break),
        "#{pad(level)}}"
      ]
    )
  end
end

# ── items ──────────────────────────────────────────────────────────────────

# waive B0013: `const` is a builtin sabi also uses, so the prefix stays; sabi::const names it too
def rs_const(name, ty, value, doc)
  {kind: :const, name:, ty:, value:, doc:}
end

def variant(name, doc)
  {kind: :variant, name:, doc:}
end

def enum(name, derives, variants, doc)
  {kind: :enum, name:, derives:, variants:, doc:}
end

def field(name, ty, doc)
  {kind: :field, name:, ty:, doc:}
end

def struct(name, derives, fields, doc)
  {kind: :struct, name:, derives:, fields:, doc:}
end

def param(name, ty)
  {kind: :param, name:, ty:}
end

@doc """
self_param: `&self`.
"""
def self_param()
  {kind: :self_param}
end

# waive B0013: `fn` is a reserved word, so the prefix stays; sabi::fn names it too
def rs_fn(name, params, ret, body, doc)
  {kind: :fn, name:, params:, ret:, body:, doc:}
end

def impl(ty_name, fns)
  {kind: :impl, name: ty_name, fns:}
end

def doc_line(line, level, marker)
  if line == ""
    "#{pad(level)}#{marker}"
  else
    "#{pad(level)}#{marker} #{line}"
  end
end

def doc_lines(doc, level, marker)
  map((line) -> doc_line(line, level, marker), doc)
end

def derive_line(derives, level)
  if is_empty(derives)
    []
  else
    ["#{pad(level)}#[derive(#{join(derives, ", ")})]"]
  end
end

def render_param(p)
  if p[:kind] == :self_param
    "&self"
  else
    "#{p[:name]}: #{render_ty(p[:ty])}"
  end
end

def render_fn(f, level)
  sig = "#{pad(level)}pub fn #{f[:name]}(#{join(map(render_param, f[:params]), ", ")}) -> #{render_ty(f[:ret])} {"
  body = "#{pad(level + 1)}#{render_expr(f[:body], level + 1)}"
  join(
    concat_lists(
      doc_lines(f[:doc], level, "///"),
      [sig, body, "#{pad(level)}}"]
    ),
    line_break
  )
end

def render_item(item)
  k = item[:kind]
  doc = doc_lines(get_or_empty(item, :doc), 0, "///")
  if k == :const
    join(
      concat_lists(
        doc,
        [
          "pub const #{item[:name]}: #{render_ty(item[:ty])} = #{render_expr(item[:value], 0)};"
        ]
      ),
      line_break
    )
  elsif k == :enum
    variants = flat_map(
      item[:variants],
      (v) -> concat_lists(doc_lines(v[:doc], 1, "///"), ["    #{v[:name]},"])
    )
    join(
      concat_lists(
        concat_lists(doc, derive_line(item[:derives], 0)),
        concat_lists(
          ["pub enum #{item[:name]} {"],
          concat_lists(variants, ["}"])
        )
      ),
      line_break
    )
  elsif k == :struct
    fields = flat_map(
      item[:fields],
      fn(f)
        concat_lists(
          doc_lines(f[:doc], 1, "///"),
          ["    pub #{f[:name]}: #{render_ty(f[:ty])},"]
        )
      end
    )
    join(
      concat_lists(
        concat_lists(doc, derive_line(item[:derives], 0)),
        concat_lists(
          ["pub struct #{item[:name]} {"],
          concat_lists(fields, ["}"])
        )
      ),
      line_break
    )
  else
    fns = map((f) -> render_fn(f, 1), item[:fns])
    join(
      concat_lists(
        ["impl #{item[:name]} {"],
        concat_lists([join(fns, unlines(["", ""]))], ["}"])
      ),
      line_break
    )
  end
end

def get_or_empty(m, key)
  v = get(m, key)
  if v.nil?
    []
  else
    v
  end
end

# ── identifiers ────────────────────────────────────────────────────────────

def keywords()
  %w[
    as
    async
    await
    break
    const
    continue
    crate
    dyn
    else
    enum
    extern
    false
    fn
    for
    if
    impl
    in
    let
    loop
    match
    mod
    move
    mut
    pub
    ref
    return
    self
    Self
    static
    struct
    super
    trait
    true
    type
    unsafe
    use
    where
    while
  ]
end

def ident_start_chars()
  chars("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_")
end

def ident_chars()
  concat_lists(ident_start_chars, chars("0123456789"))
end

@doc """
valid_ident?: An ASCII Rust identifier that is not a keyword.

    valid_ident?("") #=> false
"""
def valid_ident?(s)
  cs = chars(s)
  if is_empty(cs)
    false
  elsif contains(ident_start_chars, first(cs)) == false
    false
  elsif contains(keywords, s)
    false
  else
    count_where((c) -> contains(ident_chars, c) == false, cs) == 0
  end
end

@doc """
item_names: Every name an item declares.
"""
def item_names(item)
  k = item[:kind]
  if k == :enum
    cons(item[:name], map((v) -> v[:name], item[:variants]))
  elsif k == :struct
    cons(item[:name], map((f) -> f[:name], item[:fields]))
  elsif k == :impl
    cons(item[:name], map((f) -> f[:name], item[:fns]))
  else
    [item[:name]]
  end
end

@doc """
invalid_names: The names in a file that are not valid Rust identifiers. Empty when clean.
"""
def invalid_names(file)
  filter((n) -> valid_ident?(n) == false, flat_map(file[:items], item_names))
end

# ── files ──────────────────────────────────────────────────────────────────

@doc """
file: `source` names the blue program that generated the file, for the header.
"""
def file(source, items)
  {kind: :file, source:, items:}
end

def render_rust(file)
  header = "// @generated by #{file[:source]} (sabi). Do not edit: regenerate from the source."
  unlines([header, "", join(map(render_item, file[:items]), unlines(["", ""]))])
end

# ── tests ──────────────────────────────────────────────────────────────────

test "a table constant renders one row per line"
  t = ty_ref(ty_slice(ty_tuple([ty("char"), ty_ref(ty("str"))])))
  c = rs_const(
    "PAIRS",
    t,
    slice([tuple([char("≠"), str("!=")]), tuple([char("×"), str("*")])]),
    ["Pairs."]
  )
  expected = join_lines(
    [
      "/// Pairs.",
      "pub const PAIRS: &[(char, &str)] = &[",
      "    ('≠', \"!=\"),",
      "    ('×', \"*\"),",
      "];"
    ]
  )
  assert render_item(c) == expected
end

test "strings and chars are escaped, backslash first"
  assert render_expr(str(join_lines(["a\"b\\c", "d"])), 0) ==
    "\"a\\\"b\\\\c\\nd\""
  assert render_expr(char("'"), 0) == "'\\''"
  assert render_expr(char("\\"), 0) == "'\\\\'"
end

test "an enum with an impl renders a derive, variants and a match"
  e = enum(
    "Mood",
    %w[Debug Clone Copy],
    [variant("Calm", ["Quiet."]), variant("Loud", [])],
    ["A mood."]
  )
  body = rs_match(
    path(["self"]),
    [
      arm(path(%w[Mood Calm]), str("calm")),
      arm(path(%w[Mood Loud]), str("loud"))
    ]
  )
  i = impl(
    "Mood",
    [
      rs_fn(
        "as_str",
        [self_param],
        ty_ref(ty("'static str")),
        body,
        ["Its name."]
      )
    ]
  )
  out = render_rust(file("test.b", [e, i]))
  assert contains?(
    out,
    join_lines(
      [
        "#[derive(Debug, Clone, Copy)]",
        "pub enum Mood {",
        "    /// Quiet.",
        "    Calm,",
        "    Loud,",
        "}"
      ]
    )
  ) == true
  assert contains?(
    out,
    join_lines(
      [
        "    pub fn as_str(&self) -> &'static str {",
        "        match self {",
        "            Mood::Calm => \"calm\",",
        "            Mood::Loud => \"loud\",",
        "        }",
        "    }"
      ]
    )
  ) == true
  assert starts_with?(out, "// @generated by test.b (sabi).") == true
end

test "a struct renders its fields"
  s = struct(
    "Point",
    ["Debug"],
    [field("x", ty("i64"), ["Across."]), field("y", ty("i64"), [])],
    []
  )
  assert render_item(s) ==
    join_lines(
      [
        "#[derive(Debug)]",
        "pub struct Point {",
        "    /// Across.",
        "    pub x: i64,",
        "    pub y: i64,",
        "}"
      ]
    )
end

test "identifiers are checked: a keyword, a leading digit and a hyphen are refused"
  assert valid_ident?("OPERATOR_ALIASES") == true
  assert valid_ident?("_x9") == true
  assert valid_ident?("match") == false
  assert valid_ident?("9lives") == false
  assert valid_ident?("max-replicas") == false
  assert valid_ident?("") == false
  bad = file(
    "t.b",
    [
      rs_const("fn", ty("i64"), int(1), []),
      rs_const("OK", ty("i64"), int(2), [])
    ]
  )
  assert invalid_names(bad) == ["fn"]
end

test "an empty doc emits no doc lines, and an empty doc line keeps the marker"
  assert render_item(rs_const("N", ty("i64"), int(3), [])) ==
    "pub const N: i64 = 3;"
  assert doc_lines(["a", "", "b"], 0, "///") == ["/// a", "///", "/// b"]
end
