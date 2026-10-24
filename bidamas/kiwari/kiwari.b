@moduledoc """
kiwari (木割): one grammar spec, every syntax artifact emitted from it.

木割 is the proportioning rule-book of Japanese carpentry: every member's
dimensions derive from one base module, so no two pieces of the house can
disagree. A grammar is the member most often cut twice: once in the
compiler's parser and again in an editor's grammar, with nothing holding the
two equal. Here it is cut once. A grammar is data, built with the vocabulary
below; every artifact a tool wants is rendered from that one value:

  grammar.js         tree_sitter_js(g)      the tree-sitter grammar
  tree-sitter.json   tree_sitter_json(g)    its metadata
  highlights.scm     highlights(g)          from rule and field roles
  folds.scm          folds(g)               from the rules a closer ends
  indents.scm        indents(g)             the same rules, closers, arms
  locals.scm         locals(g)              from scopes and definitions
  *.kiwari.json      spec_json(g)           operators, keywords and each
                                            rule's lowering, for Rust

Each rule carries how its node LOWERS to the language's tree (a template:
`["list", ["sym", "define"], ["field", "name"], …]`), so the spec says what
a construct means beside how it parses. blue's own grammar is `blue()`, and
blue-lang-kiwari's differential holds the parser emitted from it to blue's
parser on every corpus file and every prefix of one.

Grammar nodes are maps with a `kind`, made only by the constructors here, so
each renderer arm sits beside the constructor it reads.

    parts(choice([])) #=> []
"""

use("retsu", [:concat_lists, :contains, :first, :flat_map, :is_empty, :last])

# ── the vocabulary ─────────────────────────────────────────────────────────

@doc """
seq: items in order.
"""
def seq(items)
  {kind: :seq, items:}
end

@doc """
choice: exactly one of the items.

    choice([]) #=> {kind: :choice, items: []}
"""
def choice(items)
  {kind: :choice, items:}
end

@doc """
rep: zero or more of an item.

    rep(lit("a")) #=> {kind: :rep, item: lit("a")}
"""
def rep(item)
  {kind: :rep, item:}
end

def rep1(item)
  {kind: :rep1, item:}
end

@doc """
opt: an item or nothing.
"""
def opt(item)
  {kind: :opt, item:}
end

@doc """
lit: A literal token: the exact text.
"""
def lit(text)
  {kind: :lit, text:}
end

@doc """
pat: A pattern token: a regular expression in tree-sitter's dialect.
"""
def pat(source)
  {kind: :pat, source:}
end

def ref(name)
  {kind: :ref, name:}
end

@doc """
field: name a part of a node.
"""
def field(name, item)
  {kind: :field, name:, item:, role: "", defines: ""}
end

@doc """
painted: A field whose node is painted `role` (a tree-sitter capture name) and, when
`defines` is not "", names a local of that kind.
"""
def painted(name, item, role, defines)
  {kind: :field, name:, item:, role:, defines:}
end

@doc """
painted_as: A field painted `role` on the named kinds listed, for an item that is a
hidden choice (a callee may be any postfix chain; only a name is painted).
"""
def painted_as(name, item, kinds, role)
  {kind: :field, name:, item:, role:, defines: "", kinds:}
end

@doc """
painted_kinds: The kinds a field's role or definition applies to.
"""
def painted_kinds(f)
  if get(f, :kinds).nil?
    kinds_of(get(f, :item))
  else
    get(f, :kinds)
  end
end

def alias(item, name)
  {kind: :alias, item:, name:}
end

def token(item)
  {kind: :token, item:}
end

def immediate(item)
  {kind: :immediate, item:}
end

def prec(n, item)
  {kind: :prec, assoc: :none, level: n, item:}
end

def prec_left(n, item)
  {kind: :prec, assoc: :left, level: n, item:}
end

def prec_right(n, item)
  {kind: :prec, assoc: :right, level: n, item:}
end

@doc """
rule: A rule: its name, its body, and how its node lowers (nil for a hidden rule,
whose node never appears, or for a part only its parent's template reads).
"""
def rule(name, body, lower)
  {name:, body:, lower:, role: "", arm: false, scope: false, reference: false}
end

@doc """
with: The same rule, with `key` set: `role` (paint the whole node), `arm` (a
branch of the form around it, as `else` is), `scope` (opens a local scope),
`reference` (names a local).
"""
def with(r, key, value)
  assoc(r, key, value)
end

def hidden?(name)
  starts_with?(name, "_")
end

# ── reading a grammar ──────────────────────────────────────────────────────

def parts(e)
  k = get(e, :kind)
  if k == :seq or k == :choice
    get(e, :items)
  elsif k == :lit or k == :pat or k == :ref
    []
  else
    [get(e, :item)]
  end
end

def literals_of(e)
  if get(e, :kind) == :lit
    [get(e, :text)]
  else
    flat_map(parts(e), literals_of)
  end
end

@doc """
literals: Every literal token the grammar's rules use, once each.

    literals({rules: []}) #=> []
"""
def literals(g)
  distinct(flat_map(get(g, :rules), (r) -> literals_of(get(r, :body))))
end

def fields_of(e)
  here = if get(e, :kind) == :field
    [e]
  else
    []
  end
  concat_lists(here, flat_map(parts(e), fields_of))
end

@doc """
kinds_of: The named node kinds a field's item can be: a visible rule it refers to, or
the name it is aliased to.
"""
def kinds_of(e)
  k = get(e, :kind)
  if k == :ref
    if hidden?(get(e, :name))
      []
    else
      [get(e, :name)]
    end
  elsif k == :alias
    [get(e, :name)]
  elsif k == :lit or k == :pat
    []
  else
    flat_map(parts(e), kinds_of)
  end
end

def aliases_of(e)
  here = if get(e, :kind) == :alias and get(get(e, :item), :kind) == :ref
    [[get(get(e, :item), :name), get(e, :name)]]
  else
    []
  end
  concat_lists(here, flat_map(parts(e), aliases_of))
end

@doc """
node_name: The name a rule's node carries in a tree: its own, or for a hidden rule the
name it is aliased to, or nil when it never appears as a node.
"""
def node_name(g, r)
  if hidden?(get(r, :name))
    found = filter(
      (a) -> first(a) == get(r, :name),
      flat_map(get(g, :rules), (x) -> aliases_of(get(x, :body)))
    )
    if is_empty(found)
      nil
    else
      nth(1, first(found))
    end
  else
    get(r, :name)
  end
end

@doc """
field_patterns: One pattern per field with `key` set, over every rule its node can carry.
"""
def field_patterns(g, key, line)
  distinct(
    flat_map(
      get(g, :rules),
      fn(r)
        name = node_name(g, r)
        if name.nil?
          []
        else
          flat_map(
            filter((f) -> get(f, key) != "", fields_of(get(r, :body))),
            (f) -> map((kind) -> line(name, f, kind), painted_kinds(f))
          )
        end
      end
    )
  )
end

@doc """
bare: The body with precedence wrappers taken off.
"""
def bare(e)
  if get(e, :kind) == :prec
    bare(get(e, :item))
  else
    e
  end
end

def first_lit(r)
  b = bare(get(r, :body))
  if get(b, :kind) == :seq and get(first(get(b, :items)), :kind) == :lit
    get(first(get(b, :items)), :text)
  end
end

@doc """
closer: The literal that closes a rule, if its body opens with a literal and ends in
one of `closers`.
"""
def closer(g, r)
  b = bare(get(r, :body))
  if get(b, :kind) == :seq and get(first(get(b, :items)), :kind) == :lit
    t = last(get(b, :items))
    if get(t, :kind) == :lit and contains(get(g, :closers), get(t, :text))
      get(t, :text)
    end
  end
end

def visible(g)
  filter((r) -> not hidden?(get(r, :name)), get(g, :rules))
end

@doc """
literal_roles: The role of every literal: a keyword's, an operator's or punctuation's. A
literal with no row is returned by `unpainted`, and the renderers refuse a
grammar that has one, so a new token cannot ship without a decision.
"""
def literal_roles(g)
  concat_lists(
    concat_lists(get(g, :keywords_painted), get(g, :punctuation)),
    map((op) -> [op, "operator"], operator_spellings(g))
  )
end

def operator_spellings(g)
  concat_lists(
    flat_map(
      concat_lists(get(g, :infix), get(g, :unary)),
      (row) -> concat_lists([get(row, :op)], get(row, :aliases))
    ),
    pipe_spellings(get(g, :pipe))
  )
end

def pipe_spellings(pipe)
  if pipe.nil?
    []
  else
    [get(pipe, :op)]
  end
end

def role_of_literal(g, text)
  row = filter((r) -> first(r) == text, literal_roles(g))
  if is_empty(row)
    nil
  else
    nth(1, first(row))
  end
end

def unpainted(g)
  filter((t) -> role_of_literal(g, t).nil?, literals(g))
end

def checked(g)
  bad = unpainted(g)
  if is_empty(bad)
    g
  else
    raise(:kiwari_unpainted, "literals with no role: #{join(bad, " ")}")
  end
end

# ── tree-sitter: grammar.js ────────────────────────────────────────────────

def js_string(s)
  "'#{replace(replace(replace(s, "\\", "\\\\"), "'", "\\'"), "\n", "\\n")}'"
end

def js(e)
  k = get(e, :kind)
  if k == :seq
    "seq(#{join(map(js, get(e, :items)), ", ")})"
  elsif k == :choice
    "choice(#{join(map(js, get(e, :items)), ", ")})"
  elsif k == :rep
    "repeat(#{js(get(e, :item))})"
  elsif k == :rep1
    "repeat1(#{js(get(e, :item))})"
  elsif k == :opt
    "optional(#{js(get(e, :item))})"
  elsif k == :lit
    js_string(get(e, :text))
  elsif k == :pat
    "/#{replace(get(e, :source), "/", "\\/")}/u"
  elsif k == :ref
    "$.#{get(e, :name)}"
  elsif k == :field
    "field(#{js_string(get(e, :name))}, #{js(get(e, :item))})"
  elsif k == :alias
    "alias(#{js(get(e, :item))}, $.#{get(e, :name)})"
  elsif k == :token
    "token(#{js(get(e, :item))})"
  elsif k == :immediate
    "token.immediate(#{js(get(e, :item))})"
  elsif get(e, :assoc) == :left
    "prec.left(#{to_s(get(e, :level))}, #{js(get(e, :item))})"
  elsif get(e, :assoc) == :right
    "prec.right(#{to_s(get(e, :level))}, #{js(get(e, :item))})"
  else
    "prec(#{to_s(get(e, :level))}, #{js(get(e, :item))})"
  end
end

def generated_by(comment)
  "#{comment} Generated from bidamas/kiwari by gen/kiwari/. Edit the spec and run `nix run .#regen`."
end

def conflict_lines(conflicts)
  if conflicts.nil? or is_empty(conflicts)
    []
  else
    sets = map((c) -> "[#{join(map((n) -> "$.#{n}", c), ", ")}]", conflicts)
    ["  conflicts: $ => [#{join(sets, ", ")}],"]
  end
end

def tree_sitter_js(grammar)
  g = checked(grammar)
  rules = map(
    (r) -> "    #{get(r, :name)}: $ => #{js(get(r, :body))},",
    get(g, :rules)
  )
  lines = concat_lists(
    [
      generated_by("//"),
      "module.exports = grammar({",
      "  name: #{js_string(get(g, :name))},",
      "  word: $ => $.#{get(g, :word)},",
      "  extras: $ => [#{join(map(js, get(g, :extras)), ", ")}],"
    ],
    concat_lists(conflict_lines(get(g, :conflicts)), ["  rules: {"])
  )
  lines = concat_lists(lines, concat_lists(rules, ["  },", "});", ""]))
  join(lines, "\n")
end

def tree_sitter_json(g)
  json_stringify(
    {
      grammars: [
        {
          name: get(g, :name),
          camelcase: get(g, :camelcase),
          scope: get(g, :scope),
          path: ".",
          "file-types" => get(g, :file_types)
        }
      ],
      metadata: {
        version: get(g, :version),
        license: "MIT",
        description: get(g, :description),
        links: {repository: get(g, :repository)}
      }
    }
  )
end

# ── tree-sitter: queries ───────────────────────────────────────────────────

def scm_string(s)
  "\"#{replace(replace(s, "\\", "\\\\"), "\"", "\\\"")}\""
end

def query_lines(header, body)
  join(
    concat_lists([generated_by(";"), header], concat_lists(body, [""])),
    "\n"
  )
end

@doc """
literal_groups: One line per role, its literals in brackets, in the order roles first appear.
"""
def literal_groups(g, roles)
  painted_lits = filter(
    (t) -> contains(roles, role_of_literal(g, t)),
    literals(g)
  )
  in_order = distinct(map((t) -> role_of_literal(g, t), painted_lits))
  map(
    fn(role)
      lits = filter((t) -> role_of_literal(g, t) == role, painted_lits)
      "[#{join(map(scm_string, lits), " ")}] @#{role}"
    end,
    in_order
  )
end

def literal_role_names(g)
  filter((r) -> r != "", distinct(map((row) -> nth(1, row), literal_roles(g))))
end

def highlights(grammar)
  g = checked(grammar)
  whole = map(
    (r) -> "(#{get(r, :name)}) @#{get(r, :role)}",
    filter((r) -> get(r, :role) != "", get(g, :rules))
  )
  fielded = field_patterns(
    g,
    :role,
    (node, f, kind) -> "(#{node} #{get(f, :name)}: (#{kind}) @#{get(f, :role)})"
  )
  query_lines(
    "; The general first: neovim lets the last matching pattern win.",
    concat_lists(
      concat_lists(whole, fielded),
      literal_groups(g, literal_role_names(g))
    )
  )
end

def closed_rules(g)
  filter((r) -> closer(g, r) != nil, visible(g))
end

def node_list(rules)
  "[#{join(map((r) -> "(#{get(r, :name)})", rules), " ")}]"
end

def folds(grammar)
  g = checked(grammar)
  query_lines(
    "; Every form a closer ends.",
    ["#{node_list(closed_rules(g))} @fold"]
  )
end

def indents(grammar)
  g = checked(grammar)
  closers = map(scm_string, get(g, :closers))
  arms = map(
    (r) -> scm_string(first_lit(r)),
    filter((r) -> get(r, :arm), get(g, :rules))
  )
  query_lines(
    "; A closed form indents its inside; its closer and its arms dedent.",
    [
      "#{node_list(closed_rules(g))} @indent.begin",
      "[#{join(closers, " ")}] @indent.end",
      "[#{join(concat_lists(closers, arms), " ")}] @indent.branch",
      "(comment) @indent.auto"
    ]
  )
end

def locals(grammar)
  g = checked(grammar)
  scopes = map(
    (r) -> "(#{get(r, :name)}) @local.scope",
    filter((r) -> get(r, :scope), get(g, :rules))
  )
  definitions = field_patterns(
    g,
    :defines,
    fn(node, f, kind)
      "(#{node} #{get(f, :name)}: (#{kind}) @local.definition.#{get(f, :defines)})"
    end
  )
  references = map(
    (r) -> "(#{get(r, :name)}) @local.reference",
    filter((r) -> get(r, :reference), get(g, :rules))
  )
  query_lines(
    "; Scopes, the names they define, and the names that refer.",
    concat_lists(concat_lists(scopes, definitions), references)
  )
end

# ── the spec for Rust ──────────────────────────────────────────────────────

def spec_json(grammar)
  g = checked(grammar)
  json_stringify(
    {
      name: get(g, :name),
      infix: get(g, :infix),
      pipe: get(g, :pipe),
      unary: get(g, :unary),
      keywords: get(g, :reserved),
      lower: map(
        (r) -> [get(r, :name), get(r, :lower)],
        filter((r) -> get(r, :lower) != nil, get(g, :rules))
      )
    }
  )
end

@doc """
artifacts: Every artifact, by the file name it is written to.
"""
def artifacts(g)
  [
    ["grammar.js", () -> tree_sitter_js(g)],
    ["tree-sitter.json", () -> "#{tree_sitter_json(g)}\n"],
    ["highlights.scm", () -> highlights(g)],
    ["folds.scm", () -> folds(g)],
    ["indents.scm", () -> indents(g)],
    ["locals.scm", () -> locals(g)],
    ["#{get(g, :name)}.kiwari.json", () -> "#{spec_json(g)}\n"]
  ]
end

@doc """
render: The artifact a file named `file` holds, or a refusal naming the ones there are.
"""
def render(g, file)
  row = filter((a) -> first(a) == file, artifacts(g))
  if is_empty(row)
    raise(
      :kiwari_artifact,
      "kiwari renders #{join(map((a) -> first(a), artifacts(g)), ", ")}, not #{file}"
    )
  end
  nth(1, first(row))()
end

# ── blue ───────────────────────────────────────────────────────────────────
#
# blue's surface as blue-lang-syntax parses it (lex.rs, parse.rs). Where a
# rule is shaped by a decision of that parser, the note says which one.

def nl()
  rep(ref("_newline"))
end

def comma_sep(item)
  opt(seq([item, nl, rep(seq([lit(","), nl, item, nl]))]))
end

def map_entry()
  choice([ref("pair"), ref("pun_pair"), ref("rocket_pair")])
end

def positional()
  choice([ref("_expression"), ref("splat")])
end

@doc """
lines: Statements, one per line; the first may share the header's line
(`fn(x) x * 2 end`), and the block may end on a statement's own line.
"""
def lines(stmt)
  choice([seq([rep1(seq([stmt, rep1(ref("_newline"))])), opt(stmt)]), stmt])
end

def block(stmt)
  choice([seq([rep1(ref("_newline")), opt(lines(stmt))]), lines(stmt)])
end

@doc """
ident_pattern: An identifier: an ASCII letter or `_`, or any character outside ASCII that
is not an operator alias, whitespace or a control character (kigou), then
letters, digits, `_` or anything outside ASCII, then one `?` or `!`.
"""
def ident_pattern(aliases)
  "(?:[A-Za-z_]|[^\\x00-\\x7F\\p{White_Space}\\p{Cc}#{join(aliases, "")}])[A-Za-z0-9_\\u{80}-\\u{10FFFF}]*[?!]?"
end

def infix_rows()
  [
    {op: "or", aliases: ["||", "∨"], power: [1, 2], callee: "or"},
    {op: "and", aliases: ["&&", "∧"], power: [3, 4], callee: "and"},
    {op: "==", aliases: ["≡"], power: [5, 6], callee: "equal?"},
    {op: "!=", aliases: ["≠"], power: [5, 6], callee: "not="},
    {op: "<", aliases: [], power: [5, 6], callee: "<"},
    {op: "<=", aliases: ["≤"], power: [5, 6], callee: "<="},
    {op: ">", aliases: [], power: [5, 6], callee: ">"},
    {op: ">=", aliases: ["≥"], power: [5, 6], callee: ">="},
    {op: "+", aliases: [], power: [7, 8], callee: "+"},
    {op: "-", aliases: ["−"], power: [7, 8], callee: "-"},
    {op: "*", aliases: ["×"], power: [9, 10], callee: "*"},
    {op: "/", aliases: ["÷"], power: [9, 10], callee: "/"},
    {op: "%", aliases: [], power: [9, 10], callee: "mod"}
  ]
end

@doc """
unary_rows: A prefix operator's operand is parsed at power 11 (`expr(11)`): above every
infix row, so it is a postfix chain, never a binary.
"""
def unary_rows()
  [
    {
      op: "-",
      aliases: ["−"],
      power: 11,
      head: ["seq", ["sym", "-"], ["int", 0]]
    },
    {op: "not", aliases: ["!", "¬"], power: 11, head: ["sym", "not"]}
  ]
end

def spellings(row)
  concat_lists([get(row, :op)], get(row, :aliases))
end

@doc """
binary_rule: One binary rule per binding power, left-associative when the right power is
the higher, so the table above is the only statement of precedence.
"""
def binary_rule(rows)
  powers = distinct(map((r) -> get(r, :power), rows))
  choice(
    map(
      fn(p)
        ops = flat_map(filter((r) -> get(r, :power) == p, rows), spellings)
        body = seq(
          [
            field("left", ref("_expression")),
            field("operator", choice(map(lit, ops))),
            nl,
            field("right", ref("_expression"))
          ]
        )
        if nth(1, p) > first(p)
          prec_left(first(p), body)
        else
          prec_right(first(p), body)
        end
      end,
      powers
    )
  )
end

def if_like(head)
  seq(
    [
      lit(head),
      field("condition", ref("_expression")),
      opt(field("consequence", alias(ref("_body_if"), "body"))),
      opt(field("alternative", choice([ref("elsif"), ref("else")])))
    ]
  )
end

def plain_parameters()
  prec(
    1,
    seq(
      [
        lit("("),
        nl,
        comma_sep(
          painted(
            "parameter",
            ref("identifier"),
            "variable.parameter",
            "parameter"
          )
        ),
        lit(")")
      ]
    )
  )
end

def arrow_parameters()
  seq(
    [
      lit("("),
      opt(
        seq(
          [
            painted(
              "parameter",
              ref("identifier"),
              "variable.parameter",
              "parameter"
            ),
            rep(
              seq(
                [
                  lit(","),
                  painted(
                    "parameter",
                    ref("identifier"),
                    "variable.parameter",
                    "parameter"
                  )
                ]
              )
            )
          ]
        )
      ),
      lit(")")
    ]
  )
end

def nil_or(f)
  ["field", f, ["nil"]]
end

def rescued()
  ["sym", "rescued-error"]
end

def bound_to_rescued(handler)
  [
    "if_any",
    [["binder"]],
    [
      "list",
      ["sym", "let"],
      ["list", ["list", ["field", "binder"], rescued]],
      handler
    ],
    handler
  ]
end

def rescue_lowering()
  kind_clause = [
    "list",
    [
      "list",
      ["sym", "blue-rescues?"],
      rescued,
      ["each", ["kind"], ["keyword"]]
    ],
    bound_to_rescued(nil_or("body"))
  ]
  otherwise = [
    "if_any",
    [["otherwise"]],
    ["each", ["otherwise"], bound_to_rescued(nil_or("body"))],
    ["list", ["sym", "blue-reraise"], rescued]
  ]
  by_kind = [
    "list",
    ["sym", "try"],
    nil_or("body"),
    [
      "list",
      ["sym", "catch"],
      ["list", rescued],
      [
        "list",
        ["sym", "cond"],
        ["each", ["clause"], kind_clause],
        ["list", ["sym", "else"], otherwise]
      ]
    ]
  ]
  catch_all = [
    "list",
    ["sym", "try"],
    nil_or("body"),
    [
      "list",
      ["sym", "catch"],
      ["list", ["each", ["otherwise", "binder"], ["symbol"]]],
      ["each", ["otherwise"], nil_or("body")]
    ]
  ]
  protected = [
    "if_any",
    [["clause"]],
    by_kind,
    ["if_any", [["otherwise"]], catch_all, nil_or("body")]
  ]
  [
    "if_any",
    [["ensure"]],
    [
      "list",
      ["sym", "blue-ensure"],
      [
        "list",
        ["sym", "try"],
        ["list", ["sym", "blue-attempted"], protected],
        [
          "list",
          ["sym", "catch"],
          ["list", rescued],
          ["list", ["sym", "blue-failed"], rescued]
        ]
      ],
      [
        "list",
        ["sym", "lambda"],
        ["list"],
        ["each", ["ensure"], nil_or("body")]
      ]
    ],
    protected
  ]
end

def def_body()
  [
    "if_any",
    [["clause"], ["otherwise"], ["ensure"]],
    rescue_lowering,
    nil_or("body")
  ]
end

def rescue_clauses()
  choice(
    [
      seq(
        [
          rep1(field("clause", ref("rescue_clause"))),
          opt(field("otherwise", ref("rescue_all"))),
          opt(field("ensure", ref("ensure_clause")))
        ]
      ),
      seq(
        [
          field("otherwise", ref("rescue_all")),
          opt(field("ensure", ref("ensure_clause")))
        ]
      ),
      field("ensure", ref("ensure_clause"))
    ]
  )
end

def ended_lines(stmt)
  ended = rep1(seq([stmt, rep1(ref("_newline"))]))
  choice([seq([rep1(ref("_newline")), opt(ended)]), ended])
end

def if_lowering(condition)
  [
    "list",
    ["sym", "if"],
    condition,
    nil_or("consequence"),
    ["field?", "alternative"]
  ]
end

def blue()
  aliases = filter(
    (a) -> not member?(a, ["||", "&&", "!"]),
    flat_map(concat_lists(infix_rows, unary_rows), (r) -> get(r, :aliases))
  )
  ident = ident_pattern(aliases)
  powers = map((r) -> get(r, :power), infix_rows)
  postfix = reduce((m, p) -> blue::max(m, nth(1, p)), 0, powers) + 1
  unary = reduce((m, p) -> blue::min(m, first(p)), 0, powers) - 1
  pipe = {op: "|>", power: [0, 1]}
  {
    name: "blue",
    camelcase: "Blue",
    scope: "source.blue",
    file_types: ["b", "Bluefile"],
    version: "0.1.0",
    description: "blue, emitted from its one grammar spec (kiwari)",
    repository: "https://github.com/pleme-io/blue",
    word: "identifier",
    extras: [pat("[ \\t\\r]"), ref("comment")],
    conflicts: [
      ["_primary", "_arrow_parameters"],
      ["_arrow_parameters", "_plain_parameters"],
      ["_arrow_parameters", "parameters"],
      ["pun_pair", "pair"]
    ],
    infix: infix_rows,
    unary: unary_rows,
    pipe:,
    reserved: {
      surface: [
        "if",
        "begin",
        "unless",
        "def",
        "defmacro",
        "quote",
        "unquote",
        "unquote_splice",
        "test",
        "assert",
        "fn",
        "case"
      ],
      block: [
        "do",
        "end",
        "else",
        "elsif",
        "rescue",
        "ensure",
        "true",
        "false",
        "nil"
      ]
    },
    closers: ["end", ")", "]", "}"],
    keywords_painted: [
      ["if", "keyword.conditional"],
      ["unless", "keyword.conditional"],
      ["elsif", "keyword.conditional"],
      ["else", "keyword.conditional"],
      ["case", "keyword.conditional"],
      ["when", "keyword.conditional"],
      ["def", "keyword.function"],
      ["defmacro", "keyword.function"],
      ["fn", "keyword.function"],
      ["end", "keyword"],
      ["test", "keyword"],
      ["assert", "keyword"],
      ["quote", "keyword"],
      ["unquote", "keyword"],
      ["unquote_splice", "keyword"],
      ["begin", "keyword.exception"],
      ["rescue", "keyword.exception"],
      ["ensure", "keyword.exception"],
      ["as", "keyword.exception"],
      ["and", "keyword.operator"],
      ["or", "keyword.operator"],
      ["not", "keyword.operator"],
      ["true", ""],
      ["false", ""],
      ["nil", ""]
    ],
    punctuation: [
      ["(", "punctuation.bracket"],
      [")", "punctuation.bracket"],
      ["[", "punctuation.bracket"],
      ["]", "punctuation.bracket"],
      ["{", "punctuation.bracket"],
      ["}", "punctuation.bracket"],
      [",", "punctuation.delimiter"],
      [".", "punctuation.delimiter"],
      ["::", "punctuation.delimiter"],
      [concat("#", "{"), "punctuation.special"],
      ["=", "operator"],
      ["=>", "operator"],
      ["**", "operator"],
      ["->", "operator"],
      [":", ""],
      ["#", ""],
      ["\"", ""],
      ["\n", ""]
    ],
    rules: [
      rule("source_file", opt(block(ref("_statement"))), ["named"]),
      rule("_newline", lit("\n"), nil),
      with(
        rule("comment", token(seq([lit("#"), pat("[^\\n]*")])), nil),
        :role,
        "comment"
      ),
      with(
        with(rule("identifier", pat(ident), ["symbol"]), :role, "variable"),
        :reference,
        true
      ),
      rule("_statement", choice([ref("binding"), ref("_expression")]), nil),
      # `x = v` is a statement, never an expression (parse.rs `statement`).
      rule(
        "binding",
        seq(
          [
            painted("name", ref("identifier"), "variable", "var"),
            lit("="),
            nl,
            field("value", ref("_expression"))
          ]
        ),
        ["list", ["sym", "define"], ["field", "name"], ["field", "value"]]
      ),
      rule(
        "_expression",
        choice(
          [
            ref("binary_expression"),
            ref("pipe_expression"),
            ref("rescue_expression"),
            ref("_operand")
          ]
        ),
        nil
      ),
      rule(
        "rescue_expression",
        prec_left(
          -1,
          seq(
            [
              field("left", ref("_expression")),
              lit("rescue"),
              nl,
              field("right", ref("_expression"))
            ]
          )
        ),
        [
          "list",
          ["sym", "try"],
          ["field", "left"],
          ["list", ["sym", "catch"], ["list", ["sym", "_"]], ["field", "right"]]
        ]
      ),
      rule("_operand", choice([ref("unary_expression"), ref("_postfix")]), nil),
      # Postfix applies to a postfix chain only: blue's Pratt loop lets the
      # innermost expression take `.name` and `(…)`.
      rule(
        "_postfix",
        choice([ref("call"), ref("send"), ref("_primary")]),
        nil
      ),
      rule(
        "_primary",
        choice(
          map(
            ref,
            [
              "integer",
              "float",
              "string",
              "symbol",
              "true",
              "false",
              "nil",
              "identifier",
              "qualified_name",
              "list",
              "map",
              "parenthesized_expression",
              "if",
              "begin",
              "unless",
              "def",
              "defmacro",
              "case",
              "lambda",
              "arrow_lambda",
              "test",
              "assert",
              "quote",
              "unquote",
              "unquote_splice"
            ]
          )
        ),
        nil
      ),
      rule(
        "binary_expression",
        binary_rule(infix_rows),
        ["list", ["callee", "operator"], ["field", "left"], ["field", "right"]]
      ),
      rule(
        "pipe_expression",
        prec_left(
          first(get(pipe, :power)),
          seq(
            [
              field("left", ref("_expression")),
              lit(get(pipe, :op)),
              nl,
              field("right", ref("_expression"))
            ]
          )
        ),
        ["thread", "left", "right"]
      ),
      # Below every infix row: after an expression header (`if a - b`) the
      # binary reading wins, as blue's greedy header does.
      rule(
        "unary_expression",
        prec(
          unary,
          seq(
            [
              field(
                "operator",
                choice(map(lit, flat_map(unary_rows, spellings)))
              ),
              field("operand", ref("_operand"))
            ]
          )
        ),
        ["list", ["unary", "operator"], ["field", "operand"]]
      ),
      rule(
        "call",
        prec(
          postfix,
          seq(
            [
              painted_as(
                "function",
                ref("_postfix"),
                ["identifier", "qualified_name"],
                "function.call"
              ),
              field("arguments", ref("arguments"))
            ]
          )
        ),
        [
          "if_any",
          [["arguments", "*", "list"]],
          [
            "list",
            ["sym", "apply"],
            ["field", "function"],
            ["field?", "arguments"]
          ],
          ["list", ["field", "function"], ["field?", "arguments"]]
        ]
      ),
      rule(
        "send",
        prec_right(
          postfix,
          seq(
            [
              field("receiver", ref("_postfix")),
              lit("."),
              painted("method", ref("identifier"), "function.method.call", ""),
              opt(field("arguments", ref("arguments")))
            ]
          )
        ),
        [
          "if_any",
          [["arguments", "*", "list"]],
          [
            "list",
            ["sym", "apply"],
            ["field", "method"],
            ["field", "receiver"],
            ["field?", "arguments"]
          ],
          [
            "if_any",
            [["arguments"]],
            [
              "list",
              ["field", "method"],
              ["field", "receiver"],
              ["field?", "arguments"]
            ],
            [
              "list",
              ["sym", "blue-field"],
              ["field", "receiver"],
              ["each", ["method"], ["keyword"]]
            ]
          ]
        ]
      ),
      # `f (x)` after a header is a call, not a header and a body.
      rule(
        "arguments",
        prec(
          1,
          seq(
            [
              lit("("),
              nl,
              opt(
                choice(
                  [
                    seq(
                      [
                        positional,
                        nl,
                        rep(seq([lit(","), nl, positional, nl])),
                        opt(seq([lit(","), nl, ref("keyword_arguments")]))
                      ]
                    ),
                    ref("keyword_arguments")
                  ]
                )
              ),
              lit(")")
            ]
          )
        ),
        ["named"]
      ),
      rule(
        "splat",
        seq([lit("*"), field("list", ref("_expression"))]),
        ["field", "list"]
      ),
      rule(
        "begin",
        seq(
          [
            lit("begin"),
            opt(field("body", alias(ref("_protected_body"), "body"))),
            rescue_clauses,
            lit("end")
          ]
        ),
        rescue_lowering
      ),
      with(
        rule(
          "rescue_clause",
          seq(
            [
              lit("rescue"),
              seq(
                [
                  field("kind", ref("symbol")),
                  rep(seq([lit(","), nl, field("kind", ref("symbol"))]))
                ]
              ),
              opt(seq([lit("as"), field("binder", ref("identifier"))])),
              opt(field("body", alias(ref("_body_rescue"), "body")))
            ]
          ),
          nil
        ),
        :arm,
        true
      ),
      with(
        rule(
          "rescue_all",
          seq(
            [
              lit("rescue"),
              field("binder", ref("identifier")),
              opt(field("body", alias(ref("_body_rescue"), "body")))
            ]
          ),
          nil
        ),
        :arm,
        true
      ),
      with(
        rule(
          "ensure_clause",
          seq(
            [
              lit("ensure"),
              opt(field("body", alias(ref("_body_rescue"), "body")))
            ]
          ),
          nil
        ),
        :arm,
        true
      ),
      rule(
        "parenthesized_expression",
        seq(
          [lit("("), nl, field("expression", ref("_expression")), nl, lit(")")]
        ),
        ["field", "expression"]
      ),
      rule(
        "list",
        seq([lit("["), nl, comma_sep(ref("_expression")), lit("]")]),
        ["list", ["sym", "list"], ["named"]]
      ),
      rule(
        "keyword_arguments",
        seq(
          [
            choice(
              [
                field("spread", ref("spread")),
                seq(
                  [
                    choice([ref("pair"), ref("pun_pair")]),
                    nl,
                    rep(seq([lit(","), nl, map_entry, nl])),
                    lit(","),
                    nl,
                    field("spread", ref("spread"))
                  ]
                )
              ]
            ),
            nl,
            rep(
              seq(
                [
                  lit(","),
                  nl,
                  choice([field("spread", ref("spread")), map_entry]),
                  nl
                ]
              )
            )
          ]
        ),
        ["list", ["sym", "blue-kwargs"], ["runs", "spread", "hash-map"]]
      ),
      rule(
        "spread",
        seq([lit("**"), field("map", ref("_expression"))]),
        ["list", ["sym", "blue-splice"], ["field", "map"]]
      ),
      rule(
        "map",
        seq(
          [
            lit("{"),
            nl,
            comma_sep(choice([field("spread", ref("spread")), map_entry])),
            lit("}")
          ]
        ),
        [
          "if_any",
          [["spread"]],
          ["list", ["sym", "blue-merge"], ["runs", "spread", "hash-map"]],
          ["list", ["sym", "hash-map"], ["named"]]
        ]
      ),
      rule(
        "pun_pair",
        field("key", ref("label")),
        ["seq", ["field", "key"], ["symbol_of", "key"]]
      ),
      rule(
        "pair",
        seq(
          [field("key", ref("label")), nl, field("value", ref("_expression"))]
        ),
        ["seq", ["field", "key"], ["field", "value"]]
      ),
      rule(
        "rocket_pair",
        seq(
          [
            field("key", ref("_expression")),
            nl,
            lit("=>"),
            nl,
            field("value", ref("_expression"))
          ]
        ),
        ["seq", ["field", "key"], ["field", "value"]]
      ),
      # One token, so `{def: 1}` is a label although `def` is a keyword.
      with(
        rule("label", token(seq([pat(ident), lit(":")])), ["keyword"]),
        :role,
        "property"
      ),
      # `pkg::` as one token too, so a label cannot take `pkg:` in `{pkg::x => 1}`.
      rule(
        "qualified_name",
        seq(
          [
            choice(
              [
                seq(
                  [
                    painted("package", ref("identifier"), "module", ""),
                    lit("::")
                  ]
                ),
                painted(
                  "package",
                  alias(token(seq([pat(ident), lit("::")])), "package"),
                  "module",
                  ""
                )
              ]
            ),
            field(
              "name",
              choice([ref("identifier"), ref("true"), ref("false"), ref("nil")])
            )
          ]
        ),
        ["qualify", "package", "name"]
      ),
      with(rule("integer", pat("[0-9][0-9_]*"), ["lexeme"]), :role, "number"),
      with(
        rule(
          "float",
          token(
            choice(
              [
                pat("[0-9][0-9_]*\\.[0-9][0-9_]*([eE][+-]?[0-9][0-9_]*)?"),
                pat("[0-9][0-9_]*[eE][+-]?[0-9][0-9_]*")
              ]
            )
          ),
          ["lexeme"]
        ),
        :role,
        "number.float"
      ),
      with(
        rule("symbol", token(seq([lit(":"), pat(ident)])), ["keyword"]),
        :role,
        "string.special.symbol"
      ),
      with(rule("true", lit("true"), ["lexeme"]), :role, "boolean"),
      with(rule("false", lit("false"), ["lexeme"]), :role, "boolean"),
      with(rule("nil", lit("nil"), ["lexeme"]), :role, "constant.builtin"),
      with(
        rule(
          "string",
          seq(
            [
              lit("\""),
              rep(
                choice(
                  [
                    ref("string_content"),
                    ref("escape_sequence"),
                    ref("interpolation")
                  ]
                )
              ),
              immediate(lit("\""))
            ]
          ),
          ["interpolate", "concat", "interpolation"]
        ),
        :role,
        "string"
      ),
      rule(
        "_plain_string",
        seq(
          [
            lit("\""),
            rep(choice([ref("string_content"), ref("escape_sequence")])),
            immediate(lit("\""))
          ]
        ),
        nil
      ),
      rule(
        "string_content",
        choice(
          [immediate(prec(1, pat("[^\"\\\\#]+"))), immediate(prec(1, lit("#")))]
        ),
        nil
      ),
      with(
        rule(
          "escape_sequence",
          immediate(prec(1, pat("\\\\([ntr\\\\\"0]|u\\{[0-9a-fA-F]+\\})"))),
          nil
        ),
        :role,
        "string.escape"
      ),
      # The inside of `#{…}` is a program of one statement (parse.rs `parse_expr`).
      with(
        rule(
          "interpolation",
          seq(
            [
              immediate(prec(1, lit(concat("#", "{")))),
              nl,
              field("expression", ref("_statement")),
              nl,
              lit("}")
            ]
          ),
          ["field", "expression"]
        ),
        :role,
        "none"
      ),
      rule(
        "if",
        seq(concat_lists(get(if_like("if"), :items), [lit("end")])),
        if_lowering(["field", "condition"])
      ),
      rule(
        "unless",
        seq(concat_lists(get(if_like("unless"), :items), [lit("end")])),
        if_lowering(["list", ["sym", "not"], ["field", "condition"]])
      ),
      with(
        rule("elsif", if_like("elsif"), if_lowering(["field", "condition"])),
        :arm,
        true
      ),
      with(
        rule(
          "else",
          seq([lit("else"), opt(field("body", ref("body")))]),
          nil_or("body")
        ),
        :arm,
        true
      ),
      # A typed signature lowers to `define-typed`, an untyped one to `define`.
      with(
        rule(
          "def",
          seq(
            [
              lit("def"),
              painted("name", ref("identifier"), "function", "function"),
              opt(field("parameters", ref("parameters"))),
              opt(seq([lit("->"), nl, field("return_type", ref("type"))])),
              choice(
                [
                  opt(field("body", ref("body"))),
                  seq(
                    [
                      opt(field("body", alias(ref("_protected_body"), "body"))),
                      rescue_clauses
                    ]
                  )
                ]
              ),
              lit("end")
            ]
          ),
          [
            "if_any",
            [["return_type"], ["parameters", "*", "type"]],
            [
              "list",
              ["sym", "define-typed"],
              [
                "list",
                ["field", "name"],
                [
                  "each_param",
                  ["parameters", "*"],
                  [
                    "if_kind",
                    "identifier",
                    ["list", ["param_symbol"], ["sym", "dyn"]],
                    [
                      "list",
                      ["each", ["name"], ["param_symbol"]],
                      ["field", "type"]
                    ]
                  ]
                ]
              ],
              ["field", "return_type", ["sym", "dyn"]],
              def_body
            ],
            [
              "list",
              ["sym", "define"],
              [
                "list",
                ["field", "name"],
                ["each_param", ["parameters", "*"], ["param_symbol"]]
              ],
              def_body
            ]
          ]
        ),
        :scope,
        true
      ),
      rule(
        "parameters",
        prec(
          1,
          seq(
            [
              lit("("),
              nl,
              comma_sep(
                choice(
                  [
                    painted(
                      "parameter",
                      ref("identifier"),
                      "variable.parameter",
                      "parameter"
                    ),
                    ref("typed_parameter")
                  ]
                )
              ),
              lit(")")
            ]
          )
        ),
        ["named"]
      ),
      rule(
        "typed_parameter",
        seq(
          [
            painted("name", ref("label"), "variable.parameter", ""),
            nl,
            field("type", ref("type"))
          ]
        ),
        nil
      ),
      rule(
        "type",
        prec_right(
          0,
          seq(
            [
              painted("name", ref("identifier"), "type", ""),
              opt(field("arguments", ref("arguments")))
            ]
          )
        ),
        [
          "if_any",
          [["arguments"]],
          ["list", ["field", "name"], ["field", "arguments"]],
          ["field", "name"]
        ]
      ),
      with(
        rule(
          "defmacro",
          seq(
            [
              lit("defmacro"),
              painted("name", ref("identifier"), "function.macro", "macro"),
              opt(
                field(
                  "parameters",
                  alias(ref("_plain_parameters"), "parameters")
                )
              ),
              opt(field("body", ref("body"))),
              lit("end")
            ]
          ),
          [
            "list",
            ["sym", "defmacro"],
            ["field", "name"],
            ["list", ["field?", "parameters"]],
            nil_or("body")
          ]
        ),
        :scope,
        true
      ),
      rule("_plain_parameters", plain_parameters, nil),
      rule("_arrow_parameters", arrow_parameters, nil),
      # `case` compares with `equal?` against a subject bound once.
      rule(
        "case",
        seq(
          [
            lit("case"),
            field("subject", ref("_expression")),
            nl,
            choice(
              [
                seq(
                  [
                    rep1(field("arm", ref("when"))),
                    opt(field("default", ref("else")))
                  ]
                ),
                field("default", ref("else"))
              ]
            ),
            lit("end")
          ]
        ),
        [
          "list",
          ["sym", "let"],
          ["list", ["list", ["sym", "case-subject"], ["field", "subject"]]],
          [
            "list",
            ["sym", "cond"],
            [
              "each",
              ["arm"],
              [
                "list",
                [
                  "list",
                  ["sym", "equal?"],
                  ["sym", "case-subject"],
                  ["field", "pattern"]
                ],
                nil_or("body")
              ]
            ],
            ["list", ["sym", "else"], ["field", "default", ["nil"]]]
          ]
        ]
      ),
      with(
        rule(
          "when",
          seq(
            [
              lit("when"),
              nl,
              field("pattern", ref("_expression")),
              opt(field("body", alias(ref("_body_when"), "body")))
            ]
          ),
          nil
        ),
        :arm,
        true
      ),
      with(
        rule(
          "lambda",
          seq(
            [
              lit("fn"),
              opt(
                field(
                  "parameters",
                  alias(ref("_plain_parameters"), "parameters")
                )
              ),
              opt(field("body", ref("body"))),
              lit("end")
            ]
          ),
          [
            "list",
            ["sym", "lambda"],
            ["list", ["field?", "parameters"]],
            nil_or("body")
          ]
        ),
        :scope,
        true
      ),
      with(
        rule(
          "arrow_lambda",
          prec_right(
            0,
            seq(
              [
                field(
                  "parameters",
                  alias(ref("_arrow_parameters"), "parameters")
                ),
                lit("->"),
                nl,
                field("body", ref("_expression"))
              ]
            )
          ),
          [
            "list",
            ["sym", "lambda"],
            ["list", ["field?", "parameters"]],
            ["field", "body"]
          ]
        ),
        :scope,
        true
      ),
      rule(
        "test",
        seq(
          [
            lit("test"),
            field("name", alias(ref("_plain_string"), "string")),
            opt(field("body", ref("body"))),
            lit("end")
          ]
        ),
        ["list", ["sym", "deftest"], ["field", "name"], nil_or("body")]
      ),
      rule(
        "assert",
        prec_right(
          0,
          seq([lit("assert"), field("expression", ref("_expression"))])
        ),
        [
          "list",
          ["sym", "blue-assert"],
          ["quote", ["field", "expression"]],
          ["field", "expression"]
        ]
      ),
      rule(
        "quote",
        seq([lit("quote"), opt(field("body", ref("body"))), lit("end")]),
        ["quasiquote", nil_or("body")]
      ),
      rule(
        "unquote",
        seq(
          [
            lit("unquote"),
            lit("("),
            nl,
            field("expression", ref("_expression")),
            nl,
            lit(")")
          ]
        ),
        ["unquote", ["field", "expression"]]
      ),
      rule(
        "unquote_splice",
        seq(
          [
            lit("unquote_splice"),
            lit("("),
            nl,
            field("expression", ref("_expression")),
            nl,
            lit(")")
          ]
        ),
        ["unquote_splice", ["field", "expression"]]
      ),
      rule("body", block(ref("_statement")), ["block", "begin"]),
      rule("_body_if", block(ref("_statement")), nil),
      rule("_body_when", block(ref("_statement")), nil),
      rule("_body_rescue", block(ref("_statement")), nil),
      rule("_protected_body", ended_lines(ref("_statement")), nil)
    ]
  }
end

# ── tests ──────────────────────────────────────────────────────────────────

def tiny(rules, punctuation)
  {
    name: "tiny",
    word: "word",
    extras: [pat("\\s")],
    infix: [],
    unary: [],
    pipe: {op: "|>", power: [0, 1]},
    reserved: {surface: [], block: []},
    closers: ["end"],
    keywords_painted: [],
    punctuation:,
    rules:
  }
end

test "a grammar with no rules renders the frame and nothing in it"
  js = tree_sitter_js(tiny([], []))
  assert contains?(js, "module.exports = grammar({")
  assert contains?(js, "  rules: {\n  },")
  assert unpainted(tiny([], [])) == []
end

test "a rule renders as the tree-sitter call its constructor names"
  r = rule(
    "word",
    prec_left(2, seq([lit("a'\\"), opt(pat("x/y")), field("f", ref("_z"))])),
    nil
  )
  assert js(get(r, :body)) ==
    "prec.left(2, seq('a\\'\\\\', optional(/x\\/y/u), field('f', $._z)))"
end

test "blue's grammar paints every literal it uses, and folds each closed form"
  g = blue
  assert unpainted(g) == []
  assert contains?(folds(g), "(def)")
  assert contains?(folds(g), "(case)")
  assert contains?(folds(g), "(interpolation)") == false
end

test "every visible rule of blue's lowers, but the parts its parent reads"
  g = blue
  parts = map(
    (r) -> get(r, :name),
    filter((r) -> get(r, :lower).nil?, visible(g))
  )
  assert parts ==
    [
      "comment",
      "rescue_clause",
      "rescue_all",
      "ensure_clause",
      "string_content",
      "escape_sequence",
      "typed_parameter",
      "when"
    ]
end

test "a literal with no role is refused by every renderer"
  bad = tiny([rule("word", lit("?!"), nil)], [])
  assert unpainted(bad) == ["?!"]
  assert begin
    highlights(bad)
  rescue e
    error?(e)
  end == true
  assert begin
    tree_sitter_js(bad)
  rescue e
    error?(e)
  end == true
  assert unpainted(tiny([rule("word", lit("?!"), nil)], [["?!", ""]])) == []
end

test "render names the artifacts it makes when asked for another"
  assert begin
    render(blue, "grammar.json")
  rescue e
    error?(e)
  end == true
  assert starts_with?(render(blue, "folds.scm"), "; Generated")
end

test "choice and rep build the node their name says and expose their parts"
  assert choice([lit("a"), ref("b")]) ==
    {kind: :choice, items: [lit("a"), ref("b")]}
  assert choice([]) == {kind: :choice, items: []}
  assert rep(lit("a")) == {kind: :rep, item: lit("a")}
  assert parts(choice([lit("a"), ref("b")])) == [lit("a"), ref("b")]
  assert parts(choice([])) == []
  assert parts(rep(ref("x"))) == [ref("x")]
end

test "choice and rep render as the tree-sitter calls they are named for"
  assert js(choice([lit("a"), ref("b")])) == "choice('a', $.b)"
  assert js(rep(lit("a"))) == "repeat('a')"
  assert js(rep(choice([lit("a"), lit("b")]))) == "repeat(choice('a', 'b'))"
  assert js(choice([lit("a")])) == "choice('a')"
end

test "literals lists each literal the rules use once, in first-use order"
  g = {
    rules: [
      rule("a", seq([lit("x"), lit("y"), lit("x")]), nil),
      rule("b", choice([lit("y"), pat("p"), opt(lit("z"))]), nil),
      rule("c", rep(field("f", prec_left(1, lit("w")))), nil)
    ]
  }
  assert literals(g) == ["x", "y", "z", "w"]
end

test "literals of a grammar with no rule, or only patterns and refs, is empty"
  assert literals({rules: []}) == []
  assert literals({rules: [rule("a", seq([pat("p"), ref("b")]), nil)]}) == []
end

test "blue's grammar uses its keywords as literals"
  ls = literals(blue)
  assert member?("def", ls)
  assert member?("end", ls)
  assert distinct(ls) == ls
end

test "a grammar with no pipe operator paints its literals without one"
  g = assoc(
    tiny([rule("word", lit("x"), nil)], [["x", "punctuation"]]),
    :pipe,
    nil
  )
  assert operator_spellings(g) == []
  assert unpainted(g) == []
  assert operator_spellings(tiny([], [])) == ["|>"]
end
