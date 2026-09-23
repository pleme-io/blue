use("retsu")
# sabi (錆): Rust source from blue data. Build the items as values, render once.
#
# Blue generates Rust the way the fleet's typed-emission rule asks: a program
# builds a TREE of Rust items (constants, enums, structs, impls, match arms), and
# one renderer turns the tree into text. No caller ever pastes Rust together
# from strings, so escaping, indentation and identifier checks live in exactly
# one place (this file) and are tested once.
#
# The first consumer is blue itself: blue-lang-syntax's character tables are
# authored in blue (crates/blue-lang-syntax/gen/kigou.b) and rendered into the
# crate's Rust by this package, with a freshness gate in `nix flake check`.
#
# Every node is a map with a `kind` and named fields. Constructors below are the
# only way nodes are made, so a renderer arm and its constructor stay together.
#
#   types   rs_ty(name)  rs_ty_ref(t)  rs_ty_slice(t)  rs_ty_tuple(ts)
#   exprs   rs_str  rs_char  rs_int  rs_bool  rs_slice  rs_tuple  rs_path
#           rs_match(scrutinee, arms) with rs_arm(pattern, expr)
#   items   rs_const  rs_enum(+ rs_variant)  rs_struct(+ rs_field)
#           rs_impl(+ rs_fn, rs_param, rs_self_param)
#   file    rs_file(source, items), rendered by render_rust

# ── types ──────────────────────────────────────────────────────────────────

def rs_ty(name)
  {kind: :ty_name, name: name}
end

def rs_ty_ref(inner)
  {kind: :ty_ref, inner: inner}
end

def rs_ty_slice(inner)
  {kind: :ty_slice, inner: inner}
end

def rs_ty_tuple(items)
  {kind: :ty_tuple, items: items}
end

def rs_render_ty(t)
  k = get(t, :kind)
  if k == :ty_name
    get(t, :name)
  elsif k == :ty_ref
    "&#{rs_render_ty(get(t, :inner))}"
  elsif k == :ty_slice
    "[#{rs_render_ty(get(t, :inner))}]"
  else
    "(#{join(map(fn(i) rs_render_ty(i) end, get(t, :items)), ", ")})"
  end
end

# ── expressions ────────────────────────────────────────────────────────────

def rs_str(s)
  {kind: :str, value: s}
end

def rs_char(c)
  {kind: :char, value: c}
end

def rs_int(n)
  {kind: :int, value: n}
end

def rs_bool(b)
  {kind: :bool, value: b}
end

# `&[a, b, …]`, one element per line.
def rs_slice(items)
  {kind: :slice, items: items}
end

def rs_tuple(items)
  {kind: :tuple, items: items}
end

# `A::B::C`.
def rs_path(segments)
  {kind: :path, segments: segments}
end

def rs_match(scrutinee, arms)
  {kind: :match, scrutinee: scrutinee, arms: arms}
end

def rs_arm(pattern, expr)
  {kind: :arm, pattern: pattern, expr: expr}
end

# A Rust string literal's body: backslash first, so the escapes added after it
# are not themselves escaped.
def rs_escape_str(s)
  replace(replace(replace(replace(replace(s, "\\", "\\\\"), "\"", "\\\""), "\n", "\\n"), "\t", "\\t"), "\r", "\\r")
end

def rs_escape_char(c)
  if c == "'"
    "\\'"
  elsif c == "\\"
    "\\\\"
  elsif c == "\n"
    "\\n"
  elsif c == "\t"
    "\\t"
  else
    c
  end
end

def rs_pad(level)
  join(repeat("    ", level), "")
end

# An expression at an indentation level (the level of the line it starts on).
def rs_render_expr(e, level)
  k = get(e, :kind)
  if k == :str
    "\"#{rs_escape_str(get(e, :value))}\""
  elsif k == :char
    "'#{rs_escape_char(get(e, :value))}'"
  elsif k == :int
    to_s(get(e, :value))
  elsif k == :bool
    if get(e, :value)
      "true"
    else
      "false"
    end
  elsif k == :tuple
    "(#{join(map(fn(i) rs_render_expr(i, level) end, get(e, :items)), ", ")})"
  elsif k == :path
    join(get(e, :segments), "::")
  elsif k == :slice
    rows = map(fn(i) "#{rs_pad(level + 1)}#{rs_render_expr(i, level + 1)}," end, get(e, :items))
    "&[\n#{join(rows, "\n")}\n#{rs_pad(level)}]"
  else
    arms = map(fn(a) "#{rs_pad(level + 1)}#{rs_render_expr(get(a, :pattern), level + 1)} => #{rs_render_expr(get(a, :expr), level + 1)}," end, get(e, :arms))
    "match #{rs_render_expr(get(e, :scrutinee), level)} {\n#{join(arms, "\n")}\n#{rs_pad(level)}}"
  end
end

# ── items ──────────────────────────────────────────────────────────────────

def rs_const(name, ty, value, doc)
  {kind: :const, name: name, ty: ty, value: value, doc: doc}
end

def rs_variant(name, doc)
  {kind: :variant, name: name, doc: doc}
end

def rs_enum(name, derives, variants, doc)
  {kind: :enum, name: name, derives: derives, variants: variants, doc: doc}
end

def rs_field(name, ty, doc)
  {kind: :field, name: name, ty: ty, doc: doc}
end

def rs_struct(name, derives, fields, doc)
  {kind: :struct, name: name, derives: derives, fields: fields, doc: doc}
end

def rs_param(name, ty)
  {kind: :param, name: name, ty: ty}
end

# `&self`.
def rs_self_param()
  {kind: :self_param}
end

def rs_fn(name, params, ret, body, doc)
  {kind: :fn, name: name, params: params, ret: ret, body: body, doc: doc}
end

def rs_impl(ty_name, fns)
  {kind: :impl, name: ty_name, fns: fns}
end

def rs_doc_line(line, level, marker)
  if line == ""
    "#{rs_pad(level)}#{marker}"
  else
    "#{rs_pad(level)}#{marker} #{line}"
  end
end

def rs_doc_lines(doc, level, marker)
  map(fn(line) rs_doc_line(line, level, marker) end, doc)
end

def rs_derive_line(derives, level)
  if is_empty(derives)
    []
  else
    ["#{rs_pad(level)}#[derive(#{join(derives, ", ")})]"]
  end
end

def rs_render_param(p)
  if get(p, :kind) == :self_param
    "&self"
  else
    "#{get(p, :name)}: #{rs_render_ty(get(p, :ty))}"
  end
end

def rs_render_fn(f, level)
  sig = "#{rs_pad(level)}pub fn #{get(f, :name)}(#{join(map(fn(p) rs_render_param(p) end, get(f, :params)), ", ")}) -> #{rs_render_ty(get(f, :ret))} {"
  body = "#{rs_pad(level + 1)}#{rs_render_expr(get(f, :body), level + 1)}"
  join(concat_lists(rs_doc_lines(get(f, :doc), level, "///"), [sig, body, "#{rs_pad(level)}}"]), "\n")
end

def rs_render_item(item)
  k = get(item, :kind)
  doc = rs_doc_lines(get_or_empty(item, :doc), 0, "///")
  if k == :const
    join(concat_lists(doc, ["pub const #{get(item, :name)}: #{rs_render_ty(get(item, :ty))} = #{rs_render_expr(get(item, :value), 0)};"]), "\n")
  elsif k == :enum
    variants = flat_map(fn(v) concat_lists(rs_doc_lines(get(v, :doc), 1, "///"), ["    #{get(v, :name)},"]) end, get(item, :variants))
    join(concat_lists(concat_lists(doc, rs_derive_line(get(item, :derives), 0)), concat_lists(["pub enum #{get(item, :name)} {"], concat_lists(variants, ["}"]))), "\n")
  elsif k == :struct
    fields = flat_map(fn(f) concat_lists(rs_doc_lines(get(f, :doc), 1, "///"), ["    pub #{get(f, :name)}: #{rs_render_ty(get(f, :ty))},"]) end, get(item, :fields))
    join(concat_lists(concat_lists(doc, rs_derive_line(get(item, :derives), 0)), concat_lists(["pub struct #{get(item, :name)} {"], concat_lists(fields, ["}"]))), "\n")
  else
    fns = map(fn(f) rs_render_fn(f, 1) end, get(item, :fns))
    join(concat_lists(["impl #{get(item, :name)} {"], concat_lists([join(fns, "\n\n")], ["}"])), "\n")
  end
end

def get_or_empty(m, key)
  v = get(m, key)
  if v == nil
    []
  else
    v
  end
end

# ── identifiers ────────────────────────────────────────────────────────────

def rs_keywords()
  ["as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return", "self", "Self", "static", "struct", "super", "trait", "true", "type", "unsafe", "use", "where", "while"]
end

def rs_ident_start_chars()
  chars("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_")
end

def rs_ident_chars()
  concat_lists(rs_ident_start_chars(), chars("0123456789"))
end

# An ASCII Rust identifier that is not a keyword.
def rs_valid_ident?(s)
  cs = chars(s)
  if is_empty(cs)
    false
  elsif contains(rs_ident_start_chars(), first(cs)) == false
    false
  elsif contains(rs_keywords(), s)
    false
  else
    count_where(fn(c) contains(rs_ident_chars(), c) == false end, cs) == 0
  end
end

# Every name an item declares.
def rs_item_names(item)
  k = get(item, :kind)
  if k == :enum
    cons(get(item, :name), map(fn(v) get(v, :name) end, get(item, :variants)))
  elsif k == :struct
    cons(get(item, :name), map(fn(f) get(f, :name) end, get(item, :fields)))
  elsif k == :impl
    cons(get(item, :name), map(fn(f) get(f, :name) end, get(item, :fns)))
  else
    [get(item, :name)]
  end
end

# The names in a file that are not valid Rust identifiers. Empty when clean.
def rs_invalid_names(file)
  filter(fn(n) rs_valid_ident?(n) == false end, flat_map(fn(i) rs_item_names(i) end, get(file, :items)))
end

# ── files ──────────────────────────────────────────────────────────────────

# `source` names the blue program that generated the file, for the header.
def rs_file(source, items)
  {kind: :file, source: source, items: items}
end

def render_rust(file)
  header = "// @generated by #{get(file, :source)} (sabi). Do not edit: regenerate from the source."
  "#{header}\n\n#{join(map(fn(i) rs_render_item(i) end, get(file, :items)), "\n\n")}\n"
end

# ── tests ──────────────────────────────────────────────────────────────────

test "a table constant renders one row per line"
  t = rs_ty_ref(rs_ty_slice(rs_ty_tuple([rs_ty("char"), rs_ty_ref(rs_ty("str"))])))
  c = rs_const("PAIRS", t, rs_slice([rs_tuple([rs_char("≠"), rs_str("!=")]), rs_tuple([rs_char("×"), rs_str("*")])]), ["Pairs."])
  expected = "/// Pairs.\npub const PAIRS: &[(char, &str)] = &[\n    ('≠', \"!=\"),\n    ('×', \"*\"),\n];"
  assert rs_render_item(c) == expected
end

test "strings and chars are escaped, backslash first"
  assert rs_render_expr(rs_str("a\"b\\c\nd"), 0) == "\"a\\\"b\\\\c\\nd\""
  assert rs_render_expr(rs_char("'"), 0) == "'\\''"
  assert rs_render_expr(rs_char("\\"), 0) == "'\\\\'"
end

test "an enum with an impl renders a derive, variants and a match"
  e = rs_enum("Mood", ["Debug", "Clone", "Copy"], [rs_variant("Calm", ["Quiet."]), rs_variant("Loud", [])], ["A mood."])
  body = rs_match(rs_path(["self"]), [rs_arm(rs_path(["Mood", "Calm"]), rs_str("calm")), rs_arm(rs_path(["Mood", "Loud"]), rs_str("loud"))])
  i = rs_impl("Mood", [rs_fn("as_str", [rs_self_param()], rs_ty_ref(rs_ty("'static str")), body, ["Its name."])])
  out = render_rust(rs_file("test.b", [e, i]))
  assert contains?(out, "#[derive(Debug, Clone, Copy)]\npub enum Mood {\n    /// Quiet.\n    Calm,\n    Loud,\n}") == true
  assert contains?(out, "    pub fn as_str(&self) -> &'static str {\n        match self {\n            Mood::Calm => \"calm\",\n            Mood::Loud => \"loud\",\n        }\n    }") == true
  assert starts_with?(out, "// @generated by test.b (sabi).") == true
end

test "a struct renders its fields"
  s = rs_struct("Point", ["Debug"], [rs_field("x", rs_ty("i64"), ["Across."]), rs_field("y", rs_ty("i64"), [])], [])
  assert rs_render_item(s) == "#[derive(Debug)]\npub struct Point {\n    /// Across.\n    pub x: i64,\n    pub y: i64,\n}"
end

test "identifiers are checked: a keyword, a leading digit and a hyphen are refused"
  assert rs_valid_ident?("OPERATOR_ALIASES") == true
  assert rs_valid_ident?("_x9") == true
  assert rs_valid_ident?("match") == false
  assert rs_valid_ident?("9lives") == false
  assert rs_valid_ident?("max-replicas") == false
  assert rs_valid_ident?("") == false
  bad = rs_file("t.b", [rs_const("fn", rs_ty("i64"), rs_int(1), []), rs_const("OK", rs_ty("i64"), rs_int(2), [])])
  assert rs_invalid_names(bad) == ["fn"]
end

test "an empty doc emits no doc lines, and an empty doc line keeps the marker"
  assert rs_render_item(rs_const("N", rs_ty("i64"), rs_int(3), [])) == "pub const N: i64 = 3;"
  assert rs_doc_lines(["a", "", "b"], 0, "///") == ["/// a", "///", "/// b"]
end
