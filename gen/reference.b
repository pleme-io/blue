use("hon", [:front_matter_text])
use("mokuroku", [:catalog_of, :md_cell, :names_shadowing])
use("retsu", [:concat_lists, :find_first, :first, :is_empty, :last, :size])
use("shisutemu", [:status_of, :stderr_of, :stdout_of])

# Writes docs/REFERENCE.md from `blue reference`, the JSON the implementation
# prints from its own tables (crates/blue-lang-cli/src/reference.rs). Declared
# in the root Bluefile with generate(); `generated-reference-fresh` fails when
# the committed file is stale. Every fact below is read from that JSON or from
# the bidamas; this program only lays them out.
#
# It runs the blue that runs it (self_exe), so the reference always describes
# the build that rendered it. The bidamas are read under $GEN_ROOT, the one
# input the Bluefile declares, to say which built-in names a bidama redefines.

def repository_root()
  getenv("GEN_ROOT", ".")
end

def reference_json()
  cap = exec_capture(self_exe, "reference")
  if status_of(cap) != 0
    raise(:reference, "blue reference failed: #{stderr_of(cap)}")
  end
  json_parse(stdout_of(cap))
end

def field(obj, key)
  json_get(obj, key)
end

def text(obj, key)
  v = json_get(obj, key)
  if v.nil?
    ""
  else
    to_s(v)
  end
end

def code(s)
  "`#{md_cell(s)}`"
end

def table(head, rows)
  rule = join(map((_h) -> "---", head), "|")
  lines = concat_lists(
    ["| #{join(head, " | ")} |", "|#{rule}|"],
    map((cells) -> "| #{join(cells, " | ")} |", rows)
  )
  join(lines, line_break)
end

def forms(data)
  rows = map(
    fn(f)
      [
        code(text(f, "example")),
        code(text(f, "lowers_to")),
        md_cell(text(f, "doc"))
      ]
    end,
    field(data, "forms")
  )
  table(["write", "lowers to", "meaning"], rows)
end

def operators(data)
  rows = map(
    fn(o)
      [
        code(text(o, "op")),
        "#{text(o, "left")}, #{text(o, "right")}",
        code(text(o, "callee")),
        md_cell(text(o, "doc"))
      ]
    end,
    field(data, "operators")
  )
  table(["operator", "binding power", "lowers to", "meaning"], rows)
end

def keywords(data)
  rows = map(
    (k) -> [code(text(k, "word")), md_cell(text(k, "doc"))],
    field(data, "keywords")
  )
  table(["word", "meaning"], rows)
end

def words(data)
  rows = map(
    (w) -> [code(text(w, "signature")), md_cell(text(w, "doc"))],
    field(data, "bluefile")
  )
  table(["word", "declares"], rows)
end

# [name, [package…]] for each built-in name a bidama also defines. Inside a
# program that imports that bidama, its definition replaces the built-in.
def redefined_builtins(names)
  records = catalog_of([path_join(repository_root, "bidamas")])
  owners = names_shadowing(records, names)
  map(
    (n) -> [n, map((p) -> last(p), filter((p) -> first(p) == n, owners))],
    names
  )
end

def note(redefined, name)
  hit = find_first((r) -> first(r) == name, redefined)
  if hit.nil? or is_empty(last(hit))
    ""
  else
    " Also defined by #{join(map((p) -> "`#{p}` (`#{p}::#{name}`)", last(hit)), ", ")}: a file that lists it gets that one."
  end
end

def arity(n)
  a = text(n, "arity")
  if a == ""
    "—"
  else
    a
  end
end

def topic_section(topic, names, redefined)
  slug = text(topic, "slug")
  mine = filter((n) -> text(n, "topic") == slug, names)
  rows = map(
    fn(n)
      [
        code(text(n, "name")),
        code(text(n, "signature")),
        arity(n),
        "#{md_cell(text(n, "doc"))}#{note(redefined, text(n, "name"))}"
      ]
    end,
    mine
  )
  join_lines(
    [
      "### #{text(topic, "title")}",
      "",
      table(["name", "call", "arity", "meaning"], rows)
    ]
  )
end

def names_section(data)
  names = field(data, "names")
  redefined = redefined_builtins(map((n) -> text(n, "name"), names))
  sections = map(
    (t) -> topic_section(t, names, redefined),
    field(data, "topics")
  )
  intro = "#{to_s(size(names))} names are bound in every program, with no `use`. Arity is what the runtime declares: `2`, `1..3` (one to three), `1+` (one or more). A further #{text(data, "uncallable")} bound names cannot head a blue call: tatara-lisp's kebab-case words, and the reserved words described above."
  join_lines([intro, "", join(sections, unlines(["", ""]))])
end

def nullary(names)
  bare = filter((n) -> text(n, "arity") == "0", names)
  rows = map((n) -> [code(text(n, "name")), md_cell(text(n, "doc"))], bare)
  join_lines(
    [
      "A function that takes no parameters is CALLED where its name is written: `now_ms` is a number, `now_ms()` is the same call in a spelling the check stage refuses in a file (B0023; `blue fmt --write` rewrites it), and `fn() now_ms end` is the function itself as a value. A local or a parameter of the same name is its value, never a call. These #{to_s(size(bare))} built-in names therefore run, with their effects, wherever they are written bare:",
      "",
      table(["name", "meaning"], rows)
    ]
  )
end

def rules(data)
  rows = map(
    fn(r)
      [
        code(text(r, "code")),
        text(r, "slug"),
        md_cell(text(r, "law")),
        text(r, "fix")
      ]
    end,
    field(data, "rules")
  )
  join_lines(
    [
      "Every rule blue holds, from the registry the check stage runs (`blue explain CODE` prints the reasoning). blue has one way to write each thing: a spelling a rule names is still read, and `blue fmt --write` and `blue check --fix` rewrite it where the fix is `autofix`; `blue test` and `blue check` never write, and name that command. The inventory, with the reason for each choice, is [`CANONICAL-FORMS.md`](CANONICAL-FORMS.md).",
      "",
      table(["code", "rule", "law", "fix"], rows)
    ]
  )
end

def render(data)
  parts = [
    "# blue language reference",
    "Generated by `gen/reference.b` from `blue reference`, which reads the tables the implementation runs on. Do not edit by hand: run `nix run .#regen`, and the `generated-reference-fresh` check fails when this file is stale.",
    "Semantics that differ from Ruby are in [`bidamas/okite/RULES.md`](../bidamas/okite/RULES.md). Packages and their definitions are in [`bidamas/CATALOG.md`](../bidamas/CATALOG.md). Idiomatic programs are in [`EXAMPLES.md`](EXAMPLES.md).",
    "## Surface forms",
    forms(data),
    "## Operators",
    "Higher binding power binds tighter.",
    operators(data),
    "## Reserved words",
    keywords(data),
    "## Built-in names",
    names_section(data),
    "### Called where written bare",
    nullary(field(data, "names")),
    "## Bluefile words",
    "A Bluefile is a blue program that may call only these words.",
    words(data),
    "## Rules",
    rules(data)
  ]
  concat(
    front_matter_text(
      :reference,
      "syntax, operators, reserved words, every built-in name and the Bluefile words"
    ),
    unlines([join(parts, unlines(["", ""]))])
  )
end

write_file(getenv("GEN_OUT", "docs/REFERENCE.md"), render(reference_json))
nil
