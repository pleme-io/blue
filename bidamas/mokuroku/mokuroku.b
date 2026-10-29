@moduledoc """
mokuroku (目録): the catalogue of what every bidama on a BLUE_PATH provides.

Before anyone writes blue, the first question is "what do we already have?".
Without this, the answer was a grep, and a grep cannot say what a function is
for. mokuroku reads every package under the given roots: its manifest
(package, version, needs), its gloss (the first line of its `@moduledoc`), its
tests, and every top-level `def` with its `@doc`.
The same scan serves three consumers:

  render_markdown   the catalogue a person or agent reads. Committed as
                    bidamas/CATALOG.md, so GitHub renders it and codesearch
                    indexes it. This is the docs.rs / pkg.go.dev role, with
                    no documentation server.
  name_collisions   the flat-namespace gate. blue's namespace is flat across
                    imports, so two packages defining one name break any
                    program that imports both, far from the cause.
  names_shadowing   the same question asked against a list of builtin names.

Because the namespace is flat, this package's own names are deliberately
specific (md_cell, pkg_name, name_collisions): a generic `cell` or `owners`
here would be exactly the collision it exists to catch.

How it reads source: as TEXT, line by line, the same view mk-bidama.nix takes
of a Bluefile. Every def in the distribution is a top-level `def` line, so
the text view is exact for today's corpus. A def produced by a macro would
not be seen; the fix is a parser-backed scan, not a cleverer split.

A package record is [name, version, needs, gloss, entries, tests], and an
entry is [def_name, signature, doc_lines].

    code_tokens("") #=> []
"""

use("deeta", [:get_or])

use("hadome", %i[failures measurement parse render shrunk])

use("junjo", [:sort_by])

use("kiwari", [:scm_string])

use("kyohi", %i[kinds refusal why])

use(
  "retsu",
  %i[
    concat_lists
    contains
    count_where
    drop_while
    find_first
    first
    flat_map
    is_empty
    last
    push
    reject
    rest
    size
    slice
    take_while
  ]
)

use("shuugou", [:unique])

# ── manifests ──────────────────────────────────────────────────────────────

@doc """
quoted_after: The first quoted field after `marker`, and the one after it, as a list.
"""
def quoted_after(text, marker)
  parts = split(text, marker)
  if size(parts) < 2
    []
  else
    fields = split(parts[1], "\"")
    [fields[0], fields[2]]
  end
end

@doc """
parse_manifest: [name, version, needs] from a Bluefile's text.
"""
def parse_manifest(text)
  pkg = quoted_after(text, "package(\"")
  needs = map((part) -> first(split(part, "\"")), rest(split(text, "needs(\"")))
  if is_empty(pkg)
    ["", "", needs]
  else
    [first(pkg), last(pkg), needs]
  end
end

# ── sources ────────────────────────────────────────────────────────────────

def comment_text(line)
  if starts_with?(line, "# ")
    join(drop(2, chars(line)), "")
  else
    join(drop(1, chars(line)), "")
  end
end

@doc """
defined_name: The name a `def` line defines: everything up to "(" or a space.
"""
def defined_name(line)
  join(take_while((c) -> c != "(" and c != " ", drop(4, chars(line))), "")
end

@doc """
waived_code: The code a `# waive CODE: reason` comment names, or nil for any other line.
"""
def waived_code(line)
  body = comment_text(line)
  if starts_with?(body, "waive ")
    blue::trim(first(split(join(drop(6, chars(body)), ""), ":")))
  end
end

def entries_of_text(text)
  state = reduce(
    fn(acc, line)
      pending = acc[0]
      waivers = acc[1]
      found = acc[2]
      open = acc[3]
      if open != nil
        if blue::trim(line) == "\"\"\""
          [open, waivers, found, nil]
        else
          [pending, waivers, found, push(open, line)]
        end
      elsif starts_with?(line, "@doc ") or starts_with?(line, "@moduledoc ")
        [[], waivers, found, []]
      elsif starts_with?(line, "#") and waived_code(line) != nil
        [pending, push(waivers, waived_code(line)), found, nil]
      elsif starts_with?(line, "#")
        [pending, waivers, found, nil]
      elsif starts_with?(line, "def ")
        [
          [],
          [],
          push(
            found,
            [
              defined_name(line),
              bare_signature(
                join(drop(4, chars(line)), ""),
                defined_name(line)
              ),
              pending,
              waivers
            ]
          ),
          nil
        ]
      else
        [[], [], found, nil]
      end
    end,
    [[], [], [], nil],
    joined_header_lines(split(text, line_break))
  )
  state[2]
end

def bare_signature(signature, name)
  called = concat(name, "()")
  if starts_with?(signature, called)
    concat(name, join(drop(size(chars(called)), chars(signature)), ""))
  else
    signature
  end
end

@doc """
legacy_prefix_of_text: The prefix a `legacy_names(since, prefix)` declaration names, or nil. A
moves declaration (`legacy_names(since, [[old, "home::new"], …])`) names no
prefix: its line is not two strings.
"""
def legacy_prefix_of_text(text)
  line = find_first(
    (l) -> starts_with?(l, "legacy_names(") and size(split(l, "\"")) == 5,
    split(text, line_break)
  )
  if line.nil?
    nil
  else
    split(line, "\"")[3]
  end
end

@doc """
joined_header_lines: The lines of a source, with each def header the formatter broke over several
lines (a parameter list too long for 80 columns: `def f(` / `  a,` / `  b` /
`)`) joined back onto one, so a signature reads as it would have been
written on one line. Without this the catalogue listed `el_record(`.
"""
def joined_header_lines(lines)
  state = reduce(
    fn(acc, line)
      out = first(acc)
      open = last(acc)
      t = blue::trim(line)
      if open != nil
        if starts_with?(t, ")")
          [push(out, concat(open, t)), nil]
        elsif ends_with?(open, "(")
          [out, concat(open, t)]
        else
          [out, concat(open, concat(" ", t))]
        end
      elsif starts_with?(line, "def ") and ends_with?(line, "(")
        [out, line]
      else
        [push(out, line), nil]
      end
    end,
    [[], nil],
    lines
  )
  first(state)
end

def gloss_of_text(text)
  after = drop_while(
    (l) -> not starts_with?(l, "@moduledoc "),
    split(text, line_break)
  )
  if size(after) < 2 or after[1] == "\"\"\""
    ""
  else
    after[1]
  end
end

@doc """
test_blocks_of_text: [title, body_lines] for every top-level `test` block in a source text: a
block runs from its `test "…"` line to the first `end` at column 0.

    test_blocks_of_text("") #=> []
"""
def test_blocks_of_text(text)
  state = reduce(
    fn(acc, line)
      open = first(acc)
      found = last(acc)
      if open.nil? and starts_with?(line, "test \"")
        [[split(line, "\"")[1], []], found]
      elsif open != nil and line == "end"
        [nil, push(found, open)]
      elsif open != nil
        [[first(open), push(last(open), line)], found]
      else
        acc
      end
    end,
    [nil, []],
    split(text, line_break)
  )
  last(state)
end

def tests_in_text(text)
  count_where((l) -> starts_with?(l, "test \""), split(text, line_break))
end

# ── reading a root ─────────────────────────────────────────────────────────

def blue_path_roots(blue_path)
  filter((r) -> r != "", split(blue_path, ":"))
end

@doc """
package_dirs: Package directories under a root: any directory holding a Bluefile.
"""
def package_dirs(root)
  map(
    (p) -> path_dirname(p),
    filter((p) -> ends_with?(p, "/Bluefile"), walk_dir(root))
  )
end

@doc """
package_text: The text of every `.b` file directly in a package directory, joined.
"""
def package_text(dir)
  join(
    map(
      (p) -> read_file(p),
      filter(
        (p) -> ends_with?(p, ".b") and path_dirname(p) == dir,
        walk_dir(dir)
      )
    ),
    line_break
  )
end

def package_record(dir)
  manifest = parse_manifest(read_file(concat(dir, "/Bluefile")))
  all_text = package_text(dir)
  [
    manifest[0],
    manifest[1],
    manifest[2],
    gloss_of_text(all_text),
    entries_of_text(all_text),
    tests_in_text(all_text),
    legacy_prefix_of_text(all_text),
    dir
  ]
end

@doc """
catalog_of: Every package under the roots, sorted by name. When two roots hold the same
package, the earlier root wins, as it does for the loader.
"""
def catalog_of(roots)
  records = flat_map(roots, (root) -> map(package_record, package_dirs(root)))
  firsts = reduce(
    fn(acc, r)
      if contains(map((x) -> first(x), acc), first(r))
        acc
      else
        push(acc, r)
      end
    end,
    [],
    records
  )
  sort_by((r) -> first(r), firsts)
end

@doc """
registered_only: The records whose package has a row in the name ledger (NAMES.md), so a
package that is untracked or still being named does not enter a catalogue
the ledger has not adjudicated.
"""
def registered_only(ledger, records)
  filter((r) -> contains?(ledger, "| `#{first(r)}` |"), records)
end

def pkg_name(r)
  r[0]
end

def pkg_version(r)
  r[1]
end

def pkg_needs(r)
  r[2]
end

def pkg_gloss(r)
  r[3]
end

def pkg_entries(r)
  r[4]
end

def pkg_tests(r)
  r[5]
end

@doc """
pkg_legacy_prefix: The prefix the package's definitions once carried (`legacy_names`), or nil.
"""
def pkg_legacy_prefix(r)
  if size(r) > 6
    r[6]
  end
end

@doc """
pkg_dir: The directory the package was read from, or nil for a record built by hand.
"""
def pkg_dir(r)
  if size(r) > 7
    r[7]
  end
end

def catalog_def_count(records)
  reduce((acc, r) -> acc + size(pkg_entries(r)), 0, records)
end

# ── the namespace gates ────────────────────────────────────────────────────

@doc """
definition_owners: [def_name, owner] for every definition, once per package.
"""
def definition_owners(records)
  flat_map(
    records,
    fn(r)
      map((n) -> [n, pkg_name(r)], unique(map((e) -> first(e), pkg_entries(r))))
    end
  )
end

@doc """
name_collisions: [def_name, [packages…]] for every name more than one package defines.
"""
def name_collisions(records)
  pairs = definition_owners(records)
  owners = blue::group_by(pairs, (p) -> first(p))
  groups = map(
    (n) -> [n, map((p) -> last(p), get(owners, n))],
    unique(map((p) -> first(p), pairs))
  )
  filter((g) -> size(last(g)) > 1, groups)
end

@doc """
name_collisions_touching: The collisions that involve at least one of `owned` (a private distribution
checking itself against everything it composes with).
"""
def name_collisions_touching(records, owned)
  filter(
    (g) -> some((pkg) -> contains(owned, pkg), last(g)),
    name_collisions(records)
  )
end

@doc """
namespace_duplicates: [package, def_name] for every name a package defines more than once: the
collision gate under per-bidama namespaces, where two packages may share a
name and one package may not.
"""
def namespace_duplicates(records)
  flat_map(
    records,
    fn(r)
      names = map((e) -> first(e), pkg_entries(r))
      map(
        (n) -> [pkg_name(r), n],
        filter((n) -> size(filter((m) -> m == n, names)) > 1, unique(names))
      )
    end
  )
end

@doc """
names_shadowing: [def_name, package] for every definition that reuses one of `names`.
"""
def names_shadowing(records, names)
  filter((p) -> contains(names, first(p)), definition_owners(records))
end

# ── rendering ──────────────────────────────────────────────────────────────

@doc """
md_cell: Markdown table cells cannot hold a raw pipe.

    md_cell("a || b") #=> "a \\|\\| b"
"""
def md_cell(s)
  replace(s, "|", "\\|")
end

def first_line_or_blank(lines)
  if is_empty(lines)
    ""
  else
    first(lines)
  end
end

def pkg_needs_text(r)
  if is_empty(pkg_needs(r))
    "—"
  else
    join(pkg_needs(r), ", ")
  end
end

def pkg_summary_row(r)
  "| [`#{pkg_name(r)}`](##{pkg_name(r)}) | #{pkg_version(r)} | #{md_cell(pkg_needs_text(r))} | #{to_s(pkg_tests(r))} | #{to_s(size(pkg_entries(r)))} | #{md_cell(pkg_gloss(r))} |"
end

@doc """
other_name: The definition's other name, from the package's `legacy_names`: the old,
prefixed spelling of a renamed definition (a bridge), or the stripped name
of one that kept its prefix (a second name, for good).
"""
def other_name(r, e)
  prefix = pkg_legacy_prefix(r)
  name = first(e)
  if prefix.nil?
    ""
  else
    p = "#{prefix}_"
    if starts_with?(name, p)
      "`#{pkg_name(r)}::#{join(drop(size(chars(p)), chars(name)), "")}`"
    else
      "`#{p}#{name}` (old)"
    end
  end
end

def entry_waivers(e)
  if size(e) > 3
    join(map((c) -> "`#{c}`", e[3]), " ")
  else
    ""
  end
end

def def_row(r, builtins, e)
  prefix = pkg_legacy_prefix(r)
  second = if prefix != nil and starts_with?(first(e), "#{prefix}_")
    join(drop(size(chars(prefix)) + 1, chars(first(e))), "")
  else
    first(e)
  end
  shares = if contains(builtins, first(e)) or contains(builtins, second)
    "yes"
  else
    ""
  end
  "| `#{pkg_name(r)}::#{md_cell(e[1])}` | #{other_name(r, e)} | #{shares} | #{entry_waivers(e)} | #{md_cell(first_line_or_blank(e[2]))} |"
end

def package_section(r)
  builtins = builtin_names
  rows = map((e) -> def_row(r, builtins, e), pkg_entries(r))
  join(
    concat_lists(
      [
        "## #{pkg_name(r)}",
        "",
        "`#{pkg_name(r)}` #{pkg_version(r)} · needs: #{pkg_needs_text(r)}",
        "",
        md_cell(pkg_gloss(r)),
        "",
        "| definition | other name | shares a builtin's name | waived | what it does |",
        "|---|---|---|---|---|"
      ],
      rows
    ),
    line_break
  )
end

def render_markdown(records)
  header = [
    "# Bidama catalogue",
    "",
    "Generated by `mokuroku` from #{to_s(size(records))} packages and #{to_s(catalog_def_count(records))} definitions. Do not edit by hand; regenerate it, and let the freshness check tell you when it is stale.",
    "",
    "| package | version | needs | tests | defs | what it is |",
    "|---|---|---|---|---|---|"
  ]
  body = map(package_section, records)
  unlines(
    [
      join(concat_lists(header, map(pkg_summary_row, records)), line_break),
      "",
      join(body, unlines(["", ""])),
      "",
      shared_names_section(records)
    ]
  )
end

@doc """
shared_names_section: The names several packages define: legal, since each is reached qualified
(`retsu::first`, `kueri::count`), and listed so an author finds the one
they mean.
"""
def shared_names_section(records)
  rows = map(
    fn(g)
      "| `#{md_cell(first(g))}` | #{join(map((p) -> "`#{p}::#{first(g)}`", last(g)), ", ")} |"
    end,
    name_collisions(records)
  )
  join(
    concat_lists(
      [
        "## Names several bidamas define",
        "",
        "| name | defined as |",
        "|---|---|"
      ],
      rows
    ),
    line_break
  )
end

@doc """
write_catalog: Write the catalogue of every root on BLUE_PATH to `path`.
"""
def write_catalog(path)
  write_file(
    path,
    render_markdown(catalog_of(blue_path_roots(getenv("BLUE_PATH", ""))))
  )
end

# ── the verb graph ──────────────────────────────────────────────────────────

def row_space?(c)
  c == " " or c == line_break or c == "\t"
end

def row_digit?(c)
  contains?("0123456789", c)
end

def row_ident_char?(c)
  contains?("abcdefghijklmnopqrstuvwxyz0123456789_?!", c)
end

def row_skip(cs, i, n)
  if i < n and row_space?(cs[i])
    row_skip(cs, i + 1, n)
  else
    i
  end
end

def row_ident_end(cs, i, n)
  if i < n and row_ident_char?(cs[i])
    row_ident_end(cs, i + 1, n)
  else
    i
  end
end

def row_digits_end(cs, i, n)
  if i < n and row_digit?(cs[i])
    row_digits_end(cs, i + 1, n)
  else
    i
  end
end

def row_text(cs, from, to)
  join(slice(cs, from, to - from), "")
end

def row_fail(cs, i, why)
  line = 1 + count_where((c) -> c == line_break, take(i, cs))
  raise(:row_syntax, "line #{to_s(line)}: #{why}")
end

def row_symbol?(v)
  list?(v) and size(v) == 2 and first(v) == :symbol
end

def row_plain(v)
  if row_symbol?(v)
    v[1]
  else
    v
  end
end

def row_string(cs, i, n, from, acc)
  if i >= n
    row_fail(cs, from, "a string is not closed")
  else
    c = cs[i]
    if c == "\""
      [join(acc, ""), i + 1]
    elsif c == "\\"
      d = if i + 1 < n
        cs[i + 1]
      else
        ""
      end
      if d == "\"" or d == "\\"
        row_string(cs, i + 2, n, from, push(acc, d))
      else
        row_fail(cs, i, "a string holds the escapes \\\" and \\\\ only")
      end
    elsif c == line_break
      row_fail(cs, i, "a string holds no line break")
    else
      row_string(cs, i + 1, n, from, push(acc, c))
    end
  end
end

def row_number(cs, i, n)
  from = if cs[i] == "-"
    i + 1
  else
    i
  end
  e = row_digits_end(cs, from, n)
  if e == from
    row_fail(cs, i, "a number is digits, with a leading - for a negative one")
  else
    [to_int(row_text(cs, i, e)), e]
  end
end

def row_word_value(cs, i, n)
  e = row_ident_end(cs, i, n)
  w = row_text(cs, i, e)
  if w == "nil"
    [nil, e]
  elsif w == "true"
    [true, e]
  elsif w == "false"
    [false, e]
  else
    row_fail(
      cs,
      i,
      "`#{w}` is no value: a row holds strings, symbols, numbers, nil, true, false, lists and maps"
    )
  end
end

def row_items(cs, i, n, close, acc)
  j = row_skip(cs, i, n)
  if j < n and cs[j] == close
    [acc, j + 1]
  else
    r = row_value(cs, j, n)
    k = row_skip(cs, r[1], n)
    if k < n and cs[k] == ","
      row_items(cs, k + 1, n, close, push(acc, r[0]))
    elsif k < n and cs[k] == close
      [push(acc, r[0]), k + 1]
    else
      row_fail(cs, k, "expected `,` or `#{close}`")
    end
  end
end

def row_word_char?(c)
  not row_space?(c) and not contains?(",\"'#\\[]", c)
end

def row_word_end(cs, i, n)
  if i < n and row_word_char?(cs[i])
    row_word_end(cs, i + 1, n)
  else
    i
  end
end

def row_words(cs, i, n, names, acc)
  j = row_skip(cs, i, n)
  if j >= n
    row_fail(cs, j, "a word list is not closed")
  elsif cs[j] == "]"
    [acc, j + 1]
  else
    e = row_word_end(cs, j, n)
    if e == j
      row_fail(cs, j, "a word holds no comma, quote, #, \\ or bracket")
    elsif names and row_ident_end(cs, j, n) != e
      row_fail(cs, j, "a word in %i[…] is a name")
    elsif names
      row_words(cs, e, n, names, push(acc, [:symbol, row_text(cs, j, e)]))
    else
      row_words(cs, e, n, names, push(acc, row_text(cs, j, e)))
    end
  end
end

def row_entries(cs, i, n, acc)
  j = row_skip(cs, i, n)
  if j < n and cs[j] == "}"
    [acc, j + 1]
  else
    e = row_ident_end(cs, j, n)
    if e == j or e >= n or cs[e] != ":"
      row_fail(cs, j, "a map entry is `name: value`")
    else
      key = row_text(cs, j, e)
      if member?(key, map(first, map_entries(acc)))
        row_fail(cs, j, "the key `#{key}` is written twice")
      else
        r = row_value(cs, e + 1, n)
        k = row_skip(cs, r[1], n)
        grown = assoc(acc, key, r[0])
        if k < n and cs[k] == ","
          row_entries(cs, k + 1, n, grown)
        elsif k < n and cs[k] == "}"
          [grown, k + 1]
        else
          row_fail(cs, k, "expected `,` or `}`")
        end
      end
    end
  end
end

def row_value(cs, i, n)
  j = row_skip(cs, i, n)
  if j >= n
    row_fail(cs, j, "a value is missing")
  else
    c = cs[j]
    if c == "\""
      row_string(cs, j + 1, n, j + 1, [])
    elsif c == ":"
      e = row_ident_end(cs, j + 1, n)
      if e == j + 1
        row_fail(cs, j, "a symbol has a name")
      else
        [[:symbol, row_text(cs, j + 1, e)], e]
      end
    elsif c == "%" and
        j + 2 < n and
        member?(cs[j + 1], %w[w i]) and
        cs[j + 2] == "["
      row_words(cs, j + 3, n, cs[j + 1] == "i", [])
    elsif c == "["
      row_items(cs, j + 1, n, "]", [])
    elsif c == "{"
      row_entries(cs, j + 1, n, {})
    elsif row_digit?(c) or c == "-"
      row_number(cs, j, n)
    else
      row_word_value(cs, j, n)
    end
  end
end

def row_forms_from(cs, i, n, acc)
  j = row_skip(cs, i, n)
  if j >= n
    acc
  else
    e = row_ident_end(cs, j, n)
    if e == j or e >= n or cs[e] != "("
      row_fail(cs, j, "a row is `word(arguments)`")
    else
      r = row_items(cs, e + 1, n, ")", [])
      row_forms_from(
        cs,
        r[1],
        n,
        push(acc, {word: row_text(cs, j, e), args: r[0]})
      )
    end
  end
end

def row_forms(text)
  cs = chars(text)
  row_forms_from(cs, 0, size(cs), [])
end

def row_specs()
  {
    "space" => {
      pos: [%w[name str]],
      fields: [
        ["status", "sym:ratified,provisional", true, nil],
        ["gloss", "strnil", false, nil]
      ]
    },
    "verb" => {
      pos: [%w[space str], %w[verb str]],
      fields: [
        ["kind", "sym:pure,effect,stream,decl", true, nil],
        ["shape", "str", true, nil],
        ["laterals", "strs", true, nil],
        ["fleet", "strnil", true, nil],
        ["today", "str", true, nil],
        ["meaning", "str", false, nil],
        ["wave", "int", true, nil],
        ["origin", "str", true, nil],
        ["contract", "strnil", false, nil],
        ["enabled", "bool", false, true],
        ["replaced_by", "strnil", false, nil]
      ]
    },
    "edge" => {
      pos: [
        %w[from str],
        ["rel", "sym:#{join(graph_rels, ",")}"],
        %w[to str],
        %w[why str]
      ],
      fields: []
    },
    "vocab" => {
      pos: [%w[verb str]],
      fields: [
        ["subject", "str", true, nil],
        ["args", "strs", true, nil],
        ["opts", "bool", true, nil],
        ["returns", "str", true, nil],
        ["raises", "strs", true, nil],
        ["kind", "sym:pure,effect,stream,decl,any", true, nil],
        ["meaning", "str", true, nil],
        ["ref", "strnil", true, nil],
        ["status", "sym:stdlib,decided,open", true, nil]
      ]
    },
    "lateral" => {
      pos: [%w[name str]],
      fields: [["battery", "strnil", false, nil]]
    }
  }
end

def graph_rels()
  %w[inverse composes refines generalizes requires lifts guards pairs]
end

def row_fits(type, v)
  if type == "str"
    string?(v)
  elsif type == "int"
    integer?(v)
  elsif type == "bool"
    boolean?(v)
  elsif type == "strnil"
    v.nil? or string?(v)
  elsif type == "strs"
    v != nil and list?(v) and every?(string?, v)
  elsif starts_with?(type, "sym:")
    row_symbol?(v) and member?(v[1], split(drop_chars_of(type, 4), ","))
  else
    false
  end
end

def drop_chars_of(s, n)
  join(drop(n, chars(s)), "")
end

def row_type_name(type)
  if starts_with?(type, "sym:")
    "a symbol, one of #{join(map((s) -> ":#{s}", split(drop_chars_of(type, 4), ",")), ", ")}"
  elsif type == "str"
    "a string"
  elsif type == "int"
    "a whole number"
  elsif type == "bool"
    "true or false"
  elsif type == "strnil"
    "a string or nil"
  else
    "a list of strings"
  end
end

def row_problems(word, spec, args)
  pos = spec[:pos]
  fields = spec[:fields]
  want = if is_empty(fields)
    size(pos)
  else
    size(pos) + 1
  end
  if size(args) != want
    ["#{word} takes #{to_s(want)} arguments, not #{to_s(size(args))}"]
  else
    bad_pos = flat_map(
      range(0, size(pos)),
      fn(i)
        p = pos[i]
        if row_fits(p[1], args[i])
          []
        else
          ["#{p[0]} must be #{row_type_name(p[1])}"]
        end
      end
    )
    if is_empty(fields)
      bad_pos
    elsif not map?(args[size(pos)])
      concat_lists(bad_pos, ["the last argument is a map"])
    else
      m = args[size(pos)]
      known = map(first, fields)
      stray = map(
        (k) -> "`#{k}` is no field of #{word}",
        reject((k) -> member?(k, known), map(first, map_entries(m)))
      )
      absent = flat_map(
        fields,
        fn(f)
          if f[2] and not member?(f[0], map(first, map_entries(m)))
            ["`#{f[0]}` is missing"]
          else
            []
          end
        end
      )
      wrong = flat_map(
        fields,
        fn(f)
          present = member?(f[0], map(first, map_entries(m)))
          if present and not row_fits(f[1], get(m, f[0]))
            ["`#{f[0]}` must be #{row_type_name(f[1])}"]
          else
            []
          end
        end
      )
      concat_lists(concat_lists(bad_pos, stray), concat_lists(absent, wrong))
    end
  end
end

def row_values(spec, args)
  pos = spec[:pos]
  fields = spec[:fields]
  named = reduce(
    (acc, i) -> assoc(acc, pos[i][0], row_plain(args[i])),
    {},
    range(0, size(pos))
  )
  if is_empty(fields)
    named
  else
    m = args[size(pos)]
    reduce(
      fn(acc, f)
        if member?(f[0], map(first, map_entries(m)))
          assoc(acc, f[0], row_plain(get(m, f[0])))
        else
          assoc(acc, f[0], f[3])
        end
      end,
      named,
      fields
    )
  end
end

def row_model(word, v)
  if word == "space"
    {word:, name: v["name"], status: v["status"], gloss: v["gloss"]}
  elsif word == "verb"
    {
      word:,
      space: v["space"],
      verb: v["verb"],
      kind: v["kind"],
      shape: v["shape"],
      laterals: v["laterals"],
      fleet: v["fleet"],
      today: v["today"],
      meaning: v["meaning"],
      wave: v["wave"],
      origin: v["origin"],
      contract: v["contract"],
      enabled: v["enabled"],
      replaced_by: v["replaced_by"]
    }
  elsif word == "edge"
    {word:, from: v["from"], rel: v["rel"], to: v["to"], why: v["why"]}
  elsif word == "vocab"
    {
      word:,
      verb: v["verb"],
      subject: v["subject"],
      args: v["args"],
      opts: v["opts"],
      returns: v["returns"],
      raises: v["raises"],
      kind: v["kind"],
      meaning: v["meaning"],
      ref: v["ref"],
      status: v["status"]
    }
  else
    {word:, name: v["name"], battery: v["battery"]}
  end
end

def row_of(form)
  word = form[:word]
  spec = get(row_specs, word)
  if spec.nil?
    [
      :unknown_word,
      "`#{word}` is no row word: the words are #{join(map(first, map_entries(row_specs)), ", ")}"
    ]
  else
    problems = row_problems(word, spec, form[:args])
    if is_empty(problems)
      row_model(word, row_values(spec, form[:args]))
    else
      [:bad_row, "#{word}: #{join(problems, "; ")}"]
    end
  end
end

def row_refusal?(r)
  list?(r) and size(r) == 2 and keyword?(first(r))
end

def row_node(r)
  if r[:word] == "verb"
    "#{r[:space]}::#{r[:verb]}"
  end
end

def file_kind(name)
  if name == "vocab.b"
    "vocab"
  elsif name == "laterals.b"
    "lateral"
  else
    "space"
  end
end

def file_refusals(name, rows)
  kind = file_kind(name)
  words = map((r) -> r[:word], rows)
  stray = map(
    fn(w)
      refusal(:misplaced, "#{name}: a `#{w}` row does not belong in this file")
    end,
    distinct(
      reject(
        (w) -> w == kind or kind == "space" and (w == "verb" or w == "edge"),
        words
      )
    )
  )
  if kind != "space"
    stray
  else
    spaces = filter((r) -> r[:word] == "space", rows)
    if size(spaces) != 1
      concat_lists(
        stray,
        [
          refusal(
            :misplaced,
            "#{name}: a space file holds exactly one `space` row, not #{to_s(size(spaces))}"
          )
        ]
      )
    else
      s = first(spaces)[:name]
      wrong_verbs = map(
        fn(r)
          refusal(
            :misplaced,
            "#{name}: #{row_node(r)} is a verb of another space than #{s}"
          )
        end,
        filter((r) -> r[:word] == "verb" and r[:space] != s, rows)
      )
      wrong_edges = map(
        fn(r)
          refusal(
            :misplaced,
            "#{name}: the edge from #{r[:from]} belongs in the file of its `from` space, not #{s}"
          )
        end,
        filter(
          (r) -> r[:word] == "edge" and not starts_with?(r[:from], "#{s}::"),
          rows
        )
      )
      concat_lists(stray, concat_lists(wrong_verbs, wrong_edges))
    end
  end
end

def file_graph(name, text)
  forms = row_forms(text)
  made = map(row_of, forms)
  rows = reject(row_refusal?, made)
  bad = map(
    (r) -> refusal(first(r), "#{name}: #{r[1]}"),
    filter(row_refusal?, made)
  )
  {rows:, refusals: concat_lists(bad, file_refusals(name, rows))}
rescue :row_syntax as e
  {rows: [], refusals: [refusal(:row_syntax, "#{name}: #{e.message}")]}
end

def graph_files(dir)
  sort_keyed(
    (p) -> p,
    filter((p) -> ends_with?(p, ".b") and path_dirname(p) == dir, walk_dir(dir))
  )
end

def graph_assemble(parts)
  rows = flat_map(parts, (p) -> p[:rows])
  {
    spaces: filter((r) -> r[:word] == "space", rows),
    verbs: filter((r) -> r[:word] == "verb", rows),
    edges: filter((r) -> r[:word] == "edge", rows),
    vocab: filter((r) -> r[:word] == "vocab", rows),
    laterals: filter((r) -> r[:word] == "lateral", rows),
    refusals: flat_map(parts, (p) -> p[:refusals])
  }
end

@doc """
graph_load: the verb graph of a row directory; a verb that exists takes its meaning from its bidama's `@doc` when the directory is a distribution's `mokuroku/graph`.

    get(graph_load("/nonexistent"), :verbs) #=> []
"""
def graph_load(dir)
  g = graph_assemble(
    map((p) -> file_graph(path_basename(p), read_file(p)), graph_files(dir))
  )
  meanings = if path_basename(path_dirname(dir)) == "mokuroku"
    verb_meanings(path_dirname(path_dirname(dir)))
  else
    {}
  end
  verbs = with_doc_meanings(g[:verbs], meanings)
  missing = map(
    fn(v)
      refusal(
        :no_meaning,
        "verb #{row_node(v)} has no meaning: a planned verb's row states it, an existing one's @doc does"
      )
    end,
    filter((v) -> v[:meaning].nil?, verbs)
  )
  assoc(assoc(g, :verbs, verbs), :refusals, concat_lists(g[:refusals], missing))
end

@doc """
doc_meaning: the meaning a verb's `@doc` gives the graph: the first sentence of its intent, its name and closing period taken off.

    doc_meaning("at", ["at: item at an index. More.", "", "    at([1], 0) #=> 1"]) #=> "item at an index"
"""
def doc_meaning(verb, lines)
  intent = join(
    map(
      (l) -> blue::trim(l),
      take_while((l) -> l != "" and not starts_with?(l, " "), lines)
    ),
    " "
  )
  prefix = "#{verb}: "
  bare = if starts_with?(intent, prefix)
    join(drop(size(chars(prefix)), chars(intent)), "")
  else
    intent
  end
  sentence = first(split(bare, ". "))
  if ends_with?(sentence, ".")
    join(take(size(chars(sentence)) - 1, chars(sentence)), "")
  else
    sentence
  end
end

@doc """
verb_meanings: the meaning every documented definition of a root's bidamas gives, keyed `bidama::name`.

    verb_meanings("/nonexistent") #=> {}
"""
def verb_meanings(root)
  reduce(
    fn(acc, r)
      reduce(
        fn(m, e)
          if is_empty(e[2])
            m
          else
            assoc(m, "#{pkg_name(r)}::#{first(e)}", doc_meaning(first(e), e[2]))
          end
        end,
        acc,
        pkg_entries(r)
      )
    end,
    {},
    catalog_of([root])
  )
end

@doc """
with_doc_meanings: each verb row whose verb exists in a bidama, its meaning that bidama's `@doc` gives; the others as they are.

    with_doc_meanings([{verb: "at", today: "exists:retsu"}], {"retsu::at" => "item"}) #=> [{verb: "at", today: "exists:retsu", meaning: "item"}]
"""
def with_doc_meanings(verbs, meanings)
  map(
    fn(v)
      parts = split(v[:today], ":")
      key = "#{last(parts)}::#{v[:verb]}"
      if size(parts) == 2 and
          member?(first(parts), %w[exists partial]) and
          get(meanings, key) != nil
        assoc(v, :meaning, get(meanings, key))
      else
        v
      end
    end,
    verbs
  )
end

def graph_duplicates(g)
  keyed = fn(label, keys)
    map(
      (k) -> refusal(:duplicate, "#{label} #{k} is declared twice"),
      sort_keyed(
        (k) -> k,
        map(
          first,
          filter((e) -> e[1] > 1, map_entries(blue::frequencies(keys)))
        )
      )
    )
  end
  concat_lists(
    keyed("verb", map(row_node, g[:verbs])),
    concat_lists(
      keyed("space", map((s) -> s[:name], g[:spaces])),
      concat_lists(
        keyed("vocab", map((v) -> v[:verb], g[:vocab])),
        keyed("edge", map((e) -> "#{e[:from]} #{e[:rel]} #{e[:to]}", g[:edges]))
      )
    )
  )
end

def shape_head(shape)
  at = text_index(shape, " -> ", 0)
  if at < 0
    shape
  else
    row_text(chars(shape), 0, at)
  end
end

def shape_params(shape)
  head = shape_head(shape)
  open = text_index(head, "(", 0)
  if open < 0 or not ends_with?(head, ")")
    ""
  else
    cs = chars(head)
    row_text(cs, open + 1, size(cs) - 1)
  end
end

def shape_braces?(text)
  open = text_index(text, "{", 0)
  open >= 0 and text_index(text, "}", open) >= 0
end

def shape_collapsed(text)
  open = text_index(text, "{", 0)
  if open < 0
    text
  else
    close = text_index(text, "}", open)
    if close < 0
      text
    else
      cs = chars(text)
      "#{row_text(cs, 0, open)}{}#{shape_collapsed(row_text(cs, close + 1, size(cs)))}"
    end
  end
end

def shape_names(text)
  map(blue::trim, split(text, ","))
end

def shape_positionals(shape)
  count_where(
    (x) -> x != "" and x != "opts" and x != "{}",
    shape_names(shape_collapsed(shape_params(shape)))
  )
end

def shape_takes_opts?(shape)
  member?("opts", shape_names(shape_params(shape))) or
    shape_braces?(shape_head(shape))
end

def vocab_by_verb(g)
  reduce((acc, v) -> assoc(acc, v[:verb], v), {}, g[:vocab])
end

def vocab_least(v)
  count_where(
    (a) -> not (starts_with?(a, "~") or ends_with?(a, "?")),
    reject((a) -> a == "", map(blue::trim, v[:args]))
  )
end

def vocab_most(v)
  size(reject((a) -> a == "", map(blue::trim, v[:args])))
end

def verb_conforms(shape, v)
  if v.nil?
    "na"
  else
    n = shape_positionals(shape)
    if n >= vocab_least(v) and
        n <= vocab_most(v) and
        (v[:opts] or not shape_takes_opts?(shape))
      "yes"
    else
      "no"
    end
  end
end

def verb_contract_shape(row, v)
  if row[:contract] != nil
    row[:contract]
  elsif v.nil?
    ""
  else
    row[:shape]
  end
end

def verb_contract_default(row, v)
  if v.nil?
    ""
  else
    row[:shape]
  end
end

def graph_nodes(g)
  reduce((acc, r) -> assoc(acc, row_node(r), r), {}, g[:verbs])
end

def meaning_stops()
  %w[a an the of to in on by for and or with as from into at its is it that]
end

def meaning_tokens(s)
  letters = "abcdefghijklmnopqrstuvwxyz0123456789"
  r = reduce(
    fn(acc, c)
      if contains?(letters, c)
        [acc[0], push(acc[1], c)]
      elsif is_empty(acc[1])
        acc
      else
        [push(acc[0], join(acc[1], "")), []]
      end
    end,
    [[], []],
    chars(downcase(s))
  )
  all = if is_empty(r[1])
    r[0]
  else
    push(r[0], join(r[1], ""))
  end
  reject((t) -> member?(t, meaning_stops), all)
end

def finding(kind, scope, subject)
  {kind:, scope:, subject:}
end

def node_space(id)
  first(split(id, "::"))
end

def graph_related(g, rels)
  reduce(
    fn(acc, e)
      if member?(e[:rel], rels)
        assoc(
          assoc(acc, "#{e[:from]} #{e[:to]}", true),
          "#{e[:to]} #{e[:from]}",
          true
        )
      else
        acc
      end
    end,
    {},
    g[:edges]
  )
end

def finds_meaning(g)
  related = graph_related(g, %w[refines generalizes inverse])
  live = filter((r) -> r[:enabled], g[:verbs])
  keyed = map(
    fn(r)
      ["#{r[:space]} #{join(meaning_tokens(r[:meaning]), " ")}", row_node(r)]
    end,
    filter((r) -> not is_empty(meaning_tokens(r[:meaning])), live)
  )
  groups = reduce(
    (acc, k) -> assoc(acc, k[0], push(get_or(acc, k[0], []), k[1])),
    {},
    keyed
  )
  flat_map(
    filter((e) -> size(e[1]) > 1, map_entries(groups)),
    fn(entry)
      ids = sort_keyed((x) -> x, entry[1])
      flat_map(
        range(0, size(ids)),
        fn(i)
          flat_map(
            range(i + 1, size(ids)),
            fn(j)
              a = ids[i]
              b = ids[j]
              if get(related, "#{a} #{b}") == true
                []
              else
                [finding("g1-meaning", node_space(a), "#{a} #{b}")]
              end
            end
          )
        end
      )
    end
  )
end

def finds_vocab(g)
  known = vocab_by_verb(g)
  map(
    (r) -> finding("g2-vocab", r[:space], row_node(r)),
    filter((r) -> r[:enabled] and get(known, r[:verb]).nil?, g[:verbs])
  )
end

def needs_edges(g)
  filter((e) -> member?(e[:rel], %w[composes requires]), g[:edges])
end

def adjacency(edges)
  reduce(
    (acc, e) -> assoc(acc, e[:from], push(get_or(acc, e[:from], []), e[:to])),
    {},
    edges
  )
end

def peeled(live, edges)
  kept = filter(
    (e) -> get(live, e[:from]) == true and get(live, e[:to]) == true,
    edges
  )
  heads = reduce((acc, e) -> assoc(acc, e[:from], true), {}, kept)
  tails = reduce((acc, e) -> assoc(acc, e[:to], true), {}, kept)
  next_live = reduce(
    fn(acc, k)
      if get(heads, k) == true and get(tails, k) == true
        assoc(acc, k, true)
      else
        acc
      end
    end,
    {},
    map(first, map_entries(live))
  )
  if size(map_entries(next_live)) == size(map_entries(live))
    live
  else
    peeled(next_live, kept)
  end
end

def reaches(adj, live, frontier, seen)
  if is_empty(frontier)
    seen
  else
    nexts = distinct(
      filter(
        (t) -> get(live, t) == true and get(seen, t) != true,
        flat_map(frontier, (f) -> get_or(adj, f, []))
      )
    )
    reaches(
      adj,
      live,
      nexts,
      reduce((acc, t) -> assoc(acc, t, true), seen, nexts)
    )
  end
end

def finds_cycle(g)
  edges = needs_edges(g)
  nodes = reduce(
    (acc, e) -> assoc(assoc(acc, e[:from], true), e[:to], true),
    {},
    edges
  )
  live = peeled(nodes, edges)
  adj = adjacency(filter((e) -> get(live, e[:from]) == true, edges))
  on_cycle = filter(
    (k) -> get(reaches(adj, live, get_or(adj, k, []), {}), k) == true,
    sort_keyed((k) -> k, map(first, map_entries(live)))
  )
  map((k) -> finding("g4-cycle", node_space(k), k), on_cycle)
end

def finds_wave(g)
  nodes = graph_nodes(g)
  flat_map(
    needs_edges(g),
    fn(e)
      f = get(nodes, e[:from])
      t = get(nodes, e[:to])
      if f != nil and t != nil and t[:wave] > f[:wave]
        [finding("g4-wave", node_space(e[:from]), "#{e[:from]} -> #{e[:to]}")]
      else
        []
      end
    end
  )
end

def finds_inverse(g)
  pairs = distinct(
    map(
      fn(e)
        a = e[:from]
        b = e[:to]
        if compare(a, b) <= 0
          [a, b]
        else
          [b, a]
        end
      end,
      filter((e) -> e[:rel] == "inverse", g[:edges])
    )
  )
  partners = reduce(
    fn(acc, p)
      a = p[0]
      b = p[1]
      assoc(
        assoc(acc, a, push(get_or(acc, a, []), b)),
        b,
        push(get_or(acc, b, []), a)
      )
    end,
    {},
    pairs
  )
  map(
    (e) -> finding("g7-inverse", node_space(e[0]), e[0]),
    sort_keyed(
      (e) -> e[0],
      filter((e) -> size(distinct(e[1])) > 1, map_entries(partners))
    )
  )
end

def finds_edges(g)
  nodes = graph_nodes(g)
  ends = distinct(flat_map(g[:edges], (e) -> [e[:from], e[:to]]))
  dangling = map(
    (x) -> finding("g9-dangling", node_space(x), x),
    sort_keyed((x) -> x, filter((x) -> get(nodes, x).nil?, ends))
  )
  unknown = map(
    fn(e)
      finding(
        "g9-relation",
        node_space(e[:from]),
        "#{e[:from]} #{e[:rel]} #{e[:to]}"
      )
    end,
    filter((e) -> not member?(e[:rel], graph_rels), g[:edges])
  )
  concat_lists(dangling, unknown)
end

def exists_rows(g)
  filter(
    fn(r)
      r[:enabled] and
        starts_with?(r[:today], "exists") and
        not ends_with?(r[:space], "?")
    end,
    g[:verbs]
  )
end

def probe_source(g)
  rows = exists_rows(g)
  spaces = sort_keyed((s) -> s, distinct(map((r) -> r[:space], rows)))
  uses = join(map((s) -> unlines(["use(\"#{s}\")"]), spaces), "")
  names = join(map(row_node, rows), ", ")
  unlines([uses, "def probe()", "  [#{names}]", "end"])
end

def unbound_names(output)
  map(
    fn(l)
      parts = split(l, "`")
      "#{parts[1]}::#{parts[3]}"
    end,
    filter((l) -> contains?(l, "error[B0011]"), split(output, line_break))
  )
end

def finds_unbound(g, unbound)
  rows = map(row_node, exists_rows(g))
  map(
    (n) -> finding("g10-unbound", node_space(n), n),
    sort_keyed((n) -> n, distinct(filter((n) -> member?(n, rows), unbound)))
  )
end

def token_glue()
  "\u{1}"
end

def token_gaps()
  [
    "(",
    ")",
    "[",
    "]",
    "{",
    "}",
    ",",
    ".",
    ":",
    ";",
    "=",
    "+",
    "-",
    "*",
    "/",
    "<",
    ">",
    "|",
    "&",
    "#",
    "'",
    "%",
    "^",
    "~",
    "\\",
    "`",
    "@",
    "$",
    "\t",
    line_break,
    "\r"
  ]
end

def uncommented(line)
  first(split(unquoted(line), "#"))
end

def unquoted(line)
  parts = split(line, "\"")
  at_end = length(parts) - 1
  join(
    map(
      (i) -> parts[i],
      filter((i) -> even?(i) or i == at_end, range(length(parts)))
    ),
    " "
  )
end

def code_tokens(text)
  spaced = reduce(
    (acc, c) -> replace(acc, c, " "),
    replace(text, "::", token_glue),
    token_gaps
  )
  filter((t) -> t != "", split(spaced, " "))
end

def unworded(text)
  parts = split(text, "%w[")
  join(
    concat_lists(
      [first(parts)],
      map((p) -> join(drop(1, split(p, "]")), "]"), drop(1, parts))
    ),
    " "
  )
end

def test_tokens(text)
  lines = flat_map(test_blocks_of_text(text), (b) -> last(b))
  code_tokens(unworded(join(map(uncommented, lines), line_break)))
end

def qualified_token(space, verb)
  concat(space, token_glue, verb)
end

def legacy_prefixes(packages)
  reduce(
    fn(acc, p)
      prefix = legacy_prefix_of_text(p[1])
      if string?(prefix)
        assoc(acc, first(p), prefix)
      else
        acc
      end
    end,
    {},
    packages
  )
end

def test_corpus(packages)
  toks = map((p) -> [first(p), test_tokens(p[1])], packages)
  {
    own: reduce(
      (acc, t) -> assoc(acc, first(t), blue::frequencies(t[1])),
      {},
      toks
    ),
    qualified: blue::frequencies(
      filter((t) -> contains?(t, token_glue), flat_map(toks, (t) -> t[1]))
    ),
    prefixes: legacy_prefixes(packages)
  }
end

def counted?(counts, key)
  map?(counts) and get(counts, key) != nil
end

def tested?(corpus, space, verb)
  own = get(corpus[:own], space)
  prefix = get(corpus[:prefixes], space)
  counted?(own, verb) or
    string?(prefix) and counted?(own, concat(prefix, "_", verb)) or
    counted?(corpus[:qualified], qualified_token(space, verb))
end

def finds_untested(g, corpus)
  map(
    (r) -> finding("g11-untested", r[:space], row_node(r)),
    sort_by(
      row_node,
      filter((r) -> not tested?(corpus, r[:space], r[:verb]), exists_rows(g))
    )
  )
end

def corpus_packages(roots)
  flat_map(
    roots,
    fn(root)
      map(
        fn(dir)
          [
            first(parse_manifest(read_file(concat(dir, "/Bluefile")))),
            package_text(dir)
          ]
        end,
        package_dirs(root)
      )
    end
  )
end

def untested_probe(g, roots)
  packages = corpus_packages(roots)
  if is_empty(packages)
    raise(
      :probe,
      "no bidama found under BLUE_PATH: the test probe would call every verb untested"
    )
  end
  finds_untested(g, test_corpus(packages))
end

def unbound_probe(g, exe)
  if exe.nil?
    raise(:probe, "no blue to run the unbound-name probe: self_exe is nil")
  end
  src = probe_source(g)
  path = path_join(
    getenv("TMPDIR", "/tmp"),
    "blue-unbound-#{blake3_hex(src)}.b"
  )
  write_program(path, src)
  cap = exec_capture(exe, "check", path)
  rm_rf(path)
  out = "#{json_get(cap, :stdout)}#{json_get(cap, :stderr)}"
  if not contains?(out, "names resolved:")
    raise(:probe, "blue check could not run the unbound-name probe: #{out}")
  end
  unbound_names(out)
end

def graph_findings(g)
  sort_keyed(
    (f) -> "#{f[:kind]} #{f[:subject]}",
    concat_lists(
      concat_lists(finds_meaning(g), finds_vocab(g)),
      concat_lists(
        concat_lists(finds_cycle(g), finds_wave(g)),
        concat_lists(finds_inverse(g), finds_edges(g))
      )
    )
  )
end

def graph_findings_live(g, exe)
  sort_keyed(
    (f) -> "#{f[:kind]} #{f[:subject]}",
    concat_lists(
      concat_lists(graph_findings(g), finds_unbound(g, unbound_probe(g, exe))),
      untested_probe(g, blue_path_roots(getenv("BLUE_PATH", "")))
    )
  )
end

def finding_kinds()
  %w[
    g1-meaning
    g2-vocab
    g4-cycle
    g4-wave
    g7-inverse
    g9-dangling
    g9-relation
    g10-unbound
    g11-untested
  ]
end

def finding_measurements(findings, kind)
  counts = reduce(
    (acc, f) -> assoc(acc, f[:scope], get_or(acc, f[:scope], 0) + 1),
    {},
    filter((f) -> f[:kind] == kind, findings)
  )
  map(
    (e) -> measurement(e[0], e[1]),
    sort_keyed((e) -> e[0], map_entries(counts))
  )
end

def graph_baseline(findings)
  join(
    map((k) -> render(k, finding_measurements(findings, k)), finding_kinds),
    ""
  )
end

def graph_verdict(findings, baseline_text)
  rows = parse(baseline_text)
  flat_map(
    finding_kinds,
    (k) -> failures(rows, k, finding_measurements(findings, k))
  )
end

def graph_shrunk(findings, baseline_text)
  rows = parse(baseline_text)
  flat_map(
    finding_kinds,
    fn(k)
      map(
        (m) -> "#{k}: #{m[:key]}",
        shrunk(rows, k, finding_measurements(findings, k))
      )
    end
  )
end

def tsv_lines(text)
  reject((l) -> l == "", split(text, line_break))
end

def tsv_fields(line)
  split(line, "\t")
end

def tsv_list(s)
  if s == "" or s == "-"
    []
  else
    map(blue::trim, split(s, ","))
  end
end

def text_safe?(s)
  not (
    contains?(s, line_break) or
    contains?(s, "\t") or
    contains?(s, concat("#", "{"))
  )
end

def tsv_table(label, text, header_sets)
  lines = tsv_lines(text)
  if is_empty(lines)
    {rows: [], refusals: [refusal(:tsv_header, "#{label}: no header")]}
  else
    header = tsv_fields(first(lines))
    if not member?(header, header_sets)
      {
        rows: [],
        refusals: [
          refusal(
            :tsv_header,
            "#{label}: the header is `#{join(header, " ")}`, which is no table this reads"
          )
        ]
      }
    else
      made = map(
        fn(i)
          fields = tsv_fields(lines[i])
          if size(fields) != size(header)
            refusal(
              :tsv_shape,
              "#{label} line #{to_s(i + 1)}: #{to_s(size(fields))} fields, the header has #{to_s(size(header))}"
            )
          elsif not every?(text_safe?, fields)
            refusal(
              :unsafe_text,
              "#{label} line #{to_s(i + 1)}: a field holds a line break, a tab or an interpolation, which no row file holds"
            )
          else
            zipmap(header, fields)
          end
        end,
        range(1, size(lines))
      )
      {rows: reject(row_refusal?, made), refusals: filter(row_refusal?, made)}
    end
  end
end

def verb_header()
  %w[
    region
    space
    verb
    kind
    shape
    laterals
    fleet
    blue_today
    meaning
    wave
    contract_shape
    conforms
  ]
end

def verb_header_region()
  take(10, verb_header)
end

def edge_header()
  %w[from rel to why]
end

def vocab_header()
  %w[verb subject args opts returns raises kind meaning stdlib_ref status]
end

def tsv_verb(label, c, vocab)
  v = get(vocab, c["verb"])
  id = "#{c["space"]}::#{c["verb"]}"
  wave = to_int(c["wave"])
  row = {
    word: "verb",
    space: c["space"],
    verb: c["verb"],
    kind: c["kind"],
    shape: c["shape"],
    laterals: tsv_list(c["laterals"]),
    fleet: if c["fleet"] == "-"
      nil
    else
      c["fleet"]
    end,
    today: c["blue_today"],
    meaning: c["meaning"],
    wave:,
    origin: c["region"],
    contract: nil,
    enabled: true,
    replaced_by: nil
  }
  given = c["contract_shape"]
  if wave.nil?
    refusal(
      :tsv_value,
      "#{label} #{id}: wave `#{c["wave"]}` is no whole number"
    )
  elsif not member?(row[:kind], %w[pure effect stream decl])
    refusal(:tsv_value, "#{label} #{id}: kind `#{row[:kind]}` is no kind")
  elsif given.nil?
    row
  elsif c["conforms"] != verb_conforms(row[:shape], v)
    refusal(
      :derived,
      "#{label} #{id}: conforms is `#{c["conforms"]}` and the shape says `#{verb_conforms(row[:shape], v)}`"
    )
  elsif given == verb_contract_default(row, v)
    row
  else
    assoc(row, :contract, given)
  end
end

def graph_from_tsv(verbs_text, edges_text, vocab_text)
  vt = tsv_table("vocab", vocab_text, [vocab_header])
  vocab = map(
    fn(c)
      {
        word: "vocab",
        verb: c["verb"],
        subject: c["subject"],
        args: tsv_list(c["args"]),
        opts: c["opts"] == "yes",
        returns: get_or(c, "returns", ""),
        raises: tsv_list(c["raises"]),
        kind: c["kind"],
        meaning: c["meaning"],
        ref: if c["stdlib_ref"] == "-"
          nil
        else
          c["stdlib_ref"]
        end,
        status: c["status"]
      }
    end,
    vt[:rows]
  )
  by_verb = reduce((acc, v) -> assoc(acc, v[:verb], v), {}, vocab)
  vr = tsv_table("verbs", verbs_text, [verb_header, verb_header_region])
  verbs_made = map((c) -> tsv_verb("verbs", c, by_verb), vr[:rows])
  et = tsv_table("edges", edges_text, [edge_header])
  edges = map(
    fn(c)
      {word: "edge", from: c["from"], rel: c["rel"], to: c["to"], why: c["why"]}
    end,
    et[:rows]
  )
  verbs = reject(row_refusal?, verbs_made)
  names = distinct(sort_keyed((s) -> s, map((r) -> r[:space], verbs)))
  g = {
    spaces: map(
      fn(s)
        {
          word: "space",
          name: s,
          status: if ends_with?(s, "?")
            "provisional"
          else
            "ratified"
          end,
          gloss: nil
        }
      end,
      names
    ),
    verbs:,
    edges:,
    vocab:,
    laterals: [],
    refusals: []
  }
  assoc(
    g,
    :refusals,
    concat_lists(
      concat_lists(vt[:refusals], vr[:refusals]),
      concat_lists(
        filter(row_refusal?, verbs_made),
        concat_lists(et[:refusals], graph_duplicates(g))
      )
    )
  )
end

def tsv_join(fields)
  join(fields, "\t")
end

def tsv_text(header, rows)
  join(map((r) -> unlines([tsv_join(r)]), concat_lists([header], rows)), "")
end

def verbs_tsv(g)
  by_verb = vocab_by_verb(g)
  rows = sort_keyed(row_node, g[:verbs])
  tsv_text(
    verb_header,
    map(
      fn(r)
        v = get(by_verb, r[:verb])
        [
          r[:origin],
          r[:space],
          r[:verb],
          r[:kind],
          r[:shape],
          if is_empty(r[:laterals])
            "-"
          else
            join(r[:laterals], ",")
          end,
          if r[:fleet].nil?
            "-"
          else
            r[:fleet]
          end,
          r[:today],
          r[:meaning],
          to_s(r[:wave]),
          verb_contract_shape(r, v),
          verb_conforms(r[:shape], v)
        ]
      end,
      rows
    )
  )
end

def edges_tsv(g)
  tsv_text(
    edge_header,
    map(
      (e) -> [e[:from], e[:rel], e[:to], e[:why]],
      sort_keyed((e) -> "#{e[:from]}\t#{e[:rel]}\t#{e[:to]}", g[:edges])
    )
  )
end

def vocab_tsv(g)
  tsv_text(
    vocab_header,
    map(
      fn(v)
        [
          v[:verb],
          v[:subject],
          join(v[:args], ","),
          if v[:opts]
            "yes"
          else
            "no"
          end,
          v[:returns],
          join(v[:raises], ","),
          v[:kind],
          v[:meaning],
          if v[:ref].nil?
            "-"
          else
            v[:ref]
          end,
          v[:status]
        ]
      end,
      sort_keyed((v) -> v[:verb], g[:vocab])
    )
  )
end

def row_strings(xs)
  "[#{join(map(scm_string, xs), ", ")}]"
end

def row_scalar(v)
  if v.nil?
    "nil"
  elsif boolean?(v) or integer?(v)
    to_s(v)
  else
    scm_string(v)
  end
end

def row_fields(pairs)
  "{#{join(map((p) -> "#{p[0]}: #{p[1]}", pairs), ", ")}}"
end

def optional_field(name, value)
  if value.nil?
    []
  else
    [[name, value]]
  end
end

def verb_fields(r)
  concat_lists(
    [
      ["kind", ":#{r[:kind]}"],
      ["shape", scm_string(r[:shape])],
      ["laterals", row_strings(r[:laterals])],
      ["fleet", row_scalar(r[:fleet])],
      ["today", scm_string(r[:today])],
      ["meaning", scm_string(r[:meaning])],
      ["wave", to_s(r[:wave])],
      ["origin", scm_string(r[:origin])]
    ],
    concat_lists(
      optional_field(
        "contract",
        if r[:contract].nil?
          nil
        else
          scm_string(r[:contract])
        end
      ),
      concat_lists(
        if r[:enabled]
          []
        else
          [%w[enabled false]]
        end,
        optional_field(
          "replaced_by",
          if r[:replaced_by].nil?
            nil
          else
            scm_string(r[:replaced_by])
          end
        )
      )
    )
  )
end

def row_source(r)
  w = r[:word]
  if w == "space"
    fields = concat_lists(
      [["status", ":#{r[:status]}"]],
      optional_field(
        "gloss",
        if r[:gloss].nil?
          nil
        else
          scm_string(r[:gloss])
        end
      )
    )
    "space(#{scm_string(r[:name])}, #{row_fields(fields)})"
  elsif w == "verb"
    "verb(#{scm_string(r[:space])}, #{scm_string(r[:verb])}, #{row_fields(verb_fields(r))})"
  elsif w == "edge"
    "edge(#{scm_string(r[:from])}, :#{r[:rel]}, #{scm_string(r[:to])}, #{scm_string(r[:why])})"
  elsif w == "vocab"
    fields = [
      ["subject", scm_string(r[:subject])],
      ["args", row_strings(r[:args])],
      ["opts", row_scalar(r[:opts])],
      ["returns", scm_string(r[:returns])],
      ["raises", row_strings(r[:raises])],
      ["kind", ":#{r[:kind]}"],
      ["meaning", scm_string(r[:meaning])],
      ["ref", row_scalar(r[:ref])],
      ["status", ":#{r[:status]}"]
    ]
    "vocab(#{scm_string(r[:verb])}, #{row_fields(fields)})"
  else
    "lateral(#{scm_string(r[:name])}, #{row_fields([["battery", row_scalar(r[:battery])]])})"
  end
end

def graph_file_name(space)
  if ends_with?(space, "?")
    "#{join(take(size(chars(space)) - 1, chars(space)), "")}-provisional.b"
  else
    "#{space}.b"
  end
end

def space_file_text(g, space)
  verbs = sort_keyed(
    (r) -> r[:verb],
    filter((r) -> r[:space] == space, g[:verbs])
  )
  edges = sort_keyed(
    (e) -> "#{e[:rel]}\t#{e[:to]}\t#{e[:from]}",
    filter((e) -> node_space(e[:from]) == space, g[:edges])
  )
  s = first(filter((r) -> r[:name] == space, g[:spaces]))
  join(
    map(
      (r) -> unlines([row_source(r)]),
      concat_lists([s], concat_lists(verbs, edges))
    ),
    ""
  )
end

def graph_writes(g)
  concat_lists(
    concat_lists(
      [
        [
          "vocab.b",
          join(
            map(
              (r) -> unlines([row_source(r)]),
              sort_keyed((v) -> v[:verb], g[:vocab])
            ),
            ""
          )
        ]
      ],
      if is_empty(g[:laterals])
        []
      else
        [
          [
            "laterals.b",
            join(
              map(
                (r) -> unlines([row_source(r)]),
                sort_keyed((l) -> l[:name], g[:laterals])
              ),
              ""
            )
          ]
        ]
      end
    ),
    map(
      (s) -> [graph_file_name(s[:name]), space_file_text(g, s[:name])],
      sort_keyed((s) -> s[:name], g[:spaces])
    )
  )
end

def import_refusals(g)
  spaces = map((s) -> s[:name], g[:spaces])
  concat_lists(
    g[:refusals],
    map(
      fn(e)
        refusal(
          :orphan_edge,
          "#{e[:from]} #{e[:rel]} #{e[:to]}: the file of its `from` space does not exist"
        )
      end,
      filter((e) -> not member?(node_space(e[:from]), spaces), g[:edges])
    )
  )
end

# ── tests ──────────────────────────────────────────────────────────────────

test "a def header broken over lines is catalogued as one signature"
  src = unlines(
    [
      "@doc \"\"\"",
      "long_one does it.",
      "\"\"\"",
      "def long_one(",
      "  alpha,",
      "  beta",
      ") -> Int",
      "  1",
      "end"
    ]
  )
  assert entries_of_text(src) ==
    [["long_one", "long_one(alpha, beta) -> Int", ["long_one does it."], []]]
end

test "a definition with no parameters is catalogued bare"
  src = unlines(
    [
      "def alphabet()",
      "  1",
      "end",
      "",
      "def typed() -> Int",
      "  1",
      "end",
      "",
      "def inc(x)",
      "  x",
      "end"
    ]
  )
  assert map((e) -> e[1], entries_of_text(src)) ==
    ["alphabet", "typed -> Int", "inc(x)"]
end

test "a manifest yields its name, version and needs"
  m = parse_manifest(
    unlines(
      [
        "package(\"kazu\", \"0.1.0\")",
        "needs(\"retsu\", \"^0.1\")",
        "needs(\"moji\", \"^0.1\")"
      ]
    )
  )
  assert m == ["kazu", "0.1.0", %w[retsu moji]]
end

test "a manifest with no needs has an empty needs list"
  m = parse_manifest(unlines(["package(\"deeta\", \"0.1.0\")"]))
  assert is_empty(m[2]) == true
  assert m[0] == "deeta"
end

test "a def's doc is its @doc; a comment documents nothing"
  text = unlines(
    [
      "# ── section ──",
      "",
      "@doc \"\"\"",
      "inc adds one.",
      "",
      "    inc(1) #=> 2",
      "\"\"\"",
      "def inc(x)",
      "  x + 1",
      "end",
      "",
      "# Bare.",
      "def bare(y)",
      "  y",
      "end"
    ]
  )
  es = entries_of_text(text)
  assert size(es) == 2
  assert first(es) ==
    ["inc", "inc(x)", ["inc adds one.", "", "    inc(1) #=> 2"], []]
  assert is_empty(last(es)[2]) == true
end

test "the gloss is the first line of the @moduledoc"
  assert gloss_of_text(
    unlines(
      [
        "@moduledoc \"\"\"",
        "kazu (数): numbers.",
        "more",
        "\"\"\"",
        "",
        "use(\"retsu\")"
      ]
    )
  ) == "kazu (数): numbers."
  assert gloss_of_text(
    unlines(["# kazu: a comment.", "def f()", "  1", "end"])
  ) == ""
end

test "tests are counted by their opening line"
  assert tests_in_text(
    unlines(["test \"a\"", "  assert 1 == 1", "end", "test \"b\"", "end"])
  ) == 2
end

test "two packages defining one name is a collision; distinct names are not"
  a = [
    "a",
    "0.1.0",
    [],
    "",
    [["size", "size(xs)", []], ["only_a", "only_a()", []]],
    0
  ]
  b = ["b", "0.1.0", [], "", [["size", "size(xs)", []]], 0]
  c = ["c", "0.1.0", [], "", [["only_c", "only_c()", []]], 0]
  assert name_collisions([a, b, c]) == [["size", %w[a b]]]
  assert is_empty(name_collisions([a, c])) == true
  assert size(name_collisions_touching([a, b, c], ["c"])) == 0
  assert size(name_collisions_touching([a, b, c], ["b"])) == 1
end

test "a package that defines one name twice does not collide with itself"
  a = ["a", "0.1.0", [], "", [["f", "f(x)", []], ["f", "f(x, y)", []]], 0]
  assert is_empty(name_collisions([a])) == true
end

test "shadows reports definitions that reuse a listed name"
  a = [
    "a",
    "0.1.0",
    [],
    "",
    [["member", "member(x)", []], ["fine", "fine()", []]],
    0
  ]
  assert names_shadowing([a], %w[member get]) == [%w[member a]]
end

test "a pipe inside a table cell is escaped"
  assert md_cell("a || b") == "a \\|\\| b"
end

test "the rendered catalogue names every package and counts its definitions"
  a = [
    "alpha",
    "0.2.0",
    ["retsu"],
    "alpha: first.",
    [["f", "f(x)", ["Does f."]]],
    1
  ]
  md = render_markdown([a])
  assert contains?(md, "1 packages and 1 definitions") == true
  assert contains?(md, "## alpha") == true
  assert contains?(md, "| `alpha::f(x)` |  |  |  | Does f. |") == true
end

test "a waiver is recorded, not documented; a legacy prefix names the other spelling"
  text = unlines(
    [
      "legacy_names(\"0.1.1\", \"q\")",
      "",
      "# waive B0013: count is a builtin",
      "@doc \"\"\"",
      "q_count counts.",
      "\"\"\"",
      "def q_count(xs)",
      "  0",
      "end",
      "",
      "@doc \"\"\"",
      "join_all joins.",
      "\"\"\"",
      "def join_all(xs)",
      "  xs",
      "end"
    ]
  )
  es = entries_of_text(text)
  assert first(es) == ["q_count", "q_count(xs)", ["q_count counts."], ["B0013"]]
  assert legacy_prefix_of_text(text) == "q"
  r = ["kueri", "0.1.1", [], "", es, 0, "q"]
  assert other_name(r, first(es)) == "`kueri::count`"
  assert other_name(r, last(es)) == "`q_join_all` (old)"
end

test "test blocks are read with their titles and bodies; other lines are not"
  text = unlines(
    [
      "def f(x)",
      "  x",
      "end",
      "",
      "test \"f is identity\"",
      "  assert f(1) == 1",
      "  assert f(2) == 2",
      "end",
      "",
      "test \"empty\"",
      "end"
    ]
  )
  assert test_blocks_of_text(text) ==
    [
      ["f is identity", ["  assert f(1) == 1", "  assert f(2) == 2"]],
      ["empty", []]
    ]
  assert test_blocks_of_text("") == []
end

def fx_graph(verbs, edges, known)
  graph_from_tsv(
    tsv_text(
      verb_header_region,
      map(
        fn(v)
          [
            "T",
            v[0],
            v[1],
            "pure",
            "#{v[1]}(value) -> value",
            "-",
            "-",
            "absent",
            v[2],
            to_s(v[3])
          ]
        end,
        verbs
      )
    ),
    tsv_text(edge_header, edges),
    tsv_text(
      vocab_header,
      map(
        fn(k)
          [
            k,
            "value",
            "value",
            "no",
            "value",
            "",
            "pure",
            "a value",
            "-",
            "decided"
          ]
        end,
        known
      )
    )
  )
end

def fx_kinds(g)
  map((f) -> "#{f[:kind]} #{f[:subject]}", graph_findings(g))
end

test "a catalogue keeps the packages the ledger names and skips the rest"
  ledger = unlines(["| `alpha` | a |", "| `beta` | b |"])
  records = [%w[alpha 0.1.0], %w[gamma 0.1.0], %w[beta 0.2.0]]
  assert registered_only(ledger, records) == [%w[alpha 0.1.0], %w[beta 0.2.0]]
  assert registered_only(ledger, []) == []
end

test "a name that only appears inside another row's text is not registered"
  ledger = unlines(["| `alpha` | gamma and `gamma` are mentioned here |"])
  assert registered_only(ledger, [%w[gamma 0.1.0]]) == []
end

test "a graph that breaks no gate has no finding"
  g = fx_graph(
    [
      ["a", "read", "whole content of a file", 1],
      ["a", "write", "replace a file", 1]
    ],
    [["a::write", "requires", "a::read", "needs it"]],
    %w[read write]
  )
  assert g[:refusals] == []
  assert graph_findings(g) == []
end

test "g1 names two verbs of one space whose meanings differ only in stop words and case"
  g = fx_graph(
    [
      ["a", "read", "Whole content of a file", 1],
      ["a", "slurp", "the whole content of the file", 1],
      ["b", "load", "whole content of a file", 1]
    ],
    [%w[a::read requires b::load x]],
    %w[read slurp load]
  )
  assert fx_kinds(g) == ["g1-meaning a::read a::slurp"]
end

test "g1 keeps word order: the same words in another order are another meaning"
  g = fx_graph(
    [["a", "take", "item from list", 1], ["a", "pull", "list from item", 1]],
    [%w[a::take pairs a::pull x]],
    %w[take pull]
  )
  assert graph_findings(g) == []
end

test "g1 is silenced by a refines, generalizes or inverse edge, and by nothing else"
  rows = [["a", "read", "whole content", 1], ["a", "slurp", "whole content", 1]]
  known = %w[read slurp]
  assert fx_kinds(fx_graph(rows, [], known)) == ["g1-meaning a::read a::slurp"]
  assert fx_kinds(fx_graph(rows, [%w[a::slurp refines a::read x]], known)) == []
  assert fx_kinds(
    fx_graph(rows, [%w[a::read generalizes a::slurp x]], known)
  ) == []
  assert fx_kinds(fx_graph(rows, [%w[a::read inverse a::slurp x]], known)) == []
  assert fx_kinds(fx_graph(rows, [%w[a::read pairs a::slurp x]], known)) ==
    ["g1-meaning a::read a::slurp"]
end

test "g2 names a verb with no vocabulary row"
  g = fx_graph(
    [["a", "read", "one", 1], ["a", "fetch", "two", 1]],
    [%w[a::read pairs a::fetch x]],
    ["read"]
  )
  assert fx_kinds(g) == ["g2-vocab a::fetch"]
end

test "g4 names the nodes on a cycle of composes and requires, and not those leading into it"
  g = fx_graph(
    [
      ["a", "p", "one", 1],
      ["a", "q", "two", 1],
      ["a", "r", "three", 1],
      ["a", "s", "four", 1]
    ],
    [
      %w[a::p composes a::q x],
      %w[a::q requires a::r x],
      %w[a::r composes a::p x],
      ["a::s", "composes", "a::p", "enters the cycle"]
    ],
    %w[p q r s]
  )
  assert fx_kinds(g) == ["g4-cycle a::p", "g4-cycle a::q", "g4-cycle a::r"]
end

test "g4 names an edge to a later wave, and only for composes and requires"
  g = fx_graph(
    [["a", "p", "one", 1], ["a", "q", "two", 3]],
    [%w[a::p composes a::q x]],
    %w[p q]
  )
  assert fx_kinds(g) == ["g4-wave a::p -> a::q"]
  assert fx_kinds(
    fx_graph(
      [["a", "p", "one", 1], ["a", "q", "two", 3]],
      [%w[a::p pairs a::q x]],
      %w[p q]
    )
  ) == []
end

test "g7 names a verb with two inverse partners, however the edges are written"
  rows = [
    ["a", "put", "one", 1],
    ["a", "del", "two", 1],
    ["a", "has", "three", 1]
  ]
  known = %w[put del has]
  assert fx_kinds(
    fx_graph(
      rows,
      [%w[a::put inverse a::del x], %w[a::has inverse a::put x]],
      known
    )
  ) == ["g7-inverse a::put"]
  assert fx_kinds(
    fx_graph(
      rows,
      [%w[a::put inverse a::del x], %w[a::del inverse a::put x]],
      known
    )
  ) == []
end

test "g9 names an endpoint that is no verb and a relation outside the closed set"
  g = fx_graph(
    [["a", "p", "one", 1]],
    [%w[a::p composes a::gone x], %w[a::p frobs a::p x]],
    ["p"]
  )
  assert fx_kinds(g) == ["g9-dangling a::gone", "g9-relation a::p frobs a::p"]
end

test "a retired verb keeps its row and is not held to g1 or g2"
  g = fx_graph(
    [["a", "read", "one", 1], ["a", "slurp", "one", 1]],
    [%w[a::read pairs a::slurp x]],
    ["read"]
  )
  off = assoc(
    g,
    :verbs,
    map(
      fn(r)
        if r[:verb] == "slurp"
          assoc(r, :enabled, false)
        else
          r
        end
      end,
      g[:verbs]
    )
  )
  assert fx_kinds(off) == []
end

test "the ratchet: recorded debt holds or shrinks, and a new or grown count is a failure"
  g = fx_graph(
    [["a", "p", "one", 1], ["a", "q", "two", 1], ["b", "r", "three", 1]],
    [%w[a::p pairs a::q x], %w[a::q pairs b::r x]],
    []
  )
  found = graph_findings(g)
  base = graph_baseline(found)
  assert base == unlines(["g2-vocab: a 2", "g2-vocab: b 1"])
  assert graph_verdict(found, base) == []
  assert graph_verdict(found, unlines(["g2-vocab: a 3", "g2-vocab: b 1"])) == []
  assert graph_shrunk(found, unlines(["g2-vocab: a 3", "g2-vocab: b 1"])) ==
    ["g2-vocab: a"]
  assert kinds(
    graph_verdict(found, unlines(["g2-vocab: a 1", "g2-vocab: b 1"]))
  ) == [:grew]
  assert kinds(graph_verdict(found, unlines(["g2-vocab: a 2"]))) ==
    [:unrecorded]
end

test "a row file reads its own writing, for every word"
  g = fx_graph(
    [["a", "p?", "one", 1]],
    [["a::p?", "pairs", "a::p?", "say \"hi\" \\ there"]],
    ["p?"]
  )
  space = {
    word: "space",
    name: "a",
    status: "ratified",
    gloss: "files \"and\" paths"
  }
  rows = concat_lists([space], concat_lists(g[:verbs], g[:edges]))
  parsed = file_graph(
    "a.b",
    join(map((r) -> unlines([row_source(r)]), rows), "")
  )
  assert parsed[:refusals] == []
  assert parsed[:rows] == rows
  voc = file_graph(
    "vocab.b",
    join(map((r) -> unlines([row_source(r)]), g[:vocab]), "")
  )
  assert voc[:refusals] == []
  assert voc[:rows] == g[:vocab]
  assert size(voc[:rows]) == 1
end

test "a row file is data: a word that is not a row word is refused, never run"
  r = file_graph(
    "a.b",
    unlines(["space(\"a\", {status: :ratified})", "write_file(\"x\", \"y\")"])
  )
  assert kinds(r[:refusals]) == [:unknown_word]
  assert size(r[:rows]) == 1
end

test "a word list in a row reads as the list it spells"
  assert row_forms("x(%w[a b-c], %i[d e?], %w[])") ==
    [{word: "x", args: [%w[a b-c], [[:symbol, "d"], [:symbol, "e?"]], []]}]
  assert kinds(
    file_graph("a.b", unlines(["space(\"a\", {status: %i[a-b]})"]))[:refusals]
  ) == [:row_syntax]
  assert kinds(
    file_graph("a.b", unlines(["space(\"a\", {status: %w[a"]))[:refusals]
  ) == [:row_syntax]
end

test "a row file holds only literals: a name, a call or an operator in a value is a syntax refusal"
  assert kinds(
    file_graph("a.b", unlines(["space(\"a\", {status: ratified})"]))[:refusals]
  ) == [:row_syntax]
  assert kinds(
    file_graph("a.b", unlines(["space(\"a\", {status: 1 + 2})"]))[:refusals]
  ) == [:row_syntax]
  assert kinds(
    file_graph("a.b", unlines(["space(\"a\", {status: f(1)})"]))[:refusals]
  ) == [:row_syntax]
  assert kinds(
    file_graph("a.b", unlines(["space(\"a\", {status: \"x"]))[:refusals]
  ) == [:row_syntax]
end

test "a bad row is refused alone: its siblings load"
  r = file_graph(
    "a.b",
    unlines(
      [
        "space(\"a\", {status: :ratified})",
        "space(\"b\", {status: :nope})",
        "space(\"c\", {status: :provisional, color: 1})"
      ]
    )
  )
  assert size(r[:rows]) == 1
  assert kinds(r[:refusals]) == %i[bad_row bad_row]
end

test "a file holds the rows of its own space only, and the edges that start there"
  r = file_graph(
    "a.b",
    unlines(
      [
        "space(\"a\", {status: :ratified})",
        "edge(\"b::x\", :pairs, \"a::y\", \"w\")",
        "vocab(\"v\", {subject: \"s\", args: [], opts: false, returns: \"r\", raises: [], kind: :pure, meaning: \"m\", ref: nil, status: :open})"
      ]
    )
  )
  assert kinds(r[:refusals]) == %i[misplaced misplaced]
end

test "a duplicate verb, space, vocabulary row or edge is refused by name"
  g = fx_graph(
    [["a", "p", "one", 1], ["a", "p", "two", 1]],
    [%w[a::p pairs a::p w], %w[a::p pairs a::p w]],
    %w[p p]
  )
  assert map(why, g[:refusals]) ==
    [
      "verb a::p is declared twice",
      "vocab p is declared twice",
      "edge a::p pairs a::p is declared twice"
    ]
end

test "shapes: positionals exclude opts and option maps, and a contract takes the shape's arity"
  assert shape_positionals("read(path, opts) -> text") == 1
  assert shape_positionals("run(cmd, {cwd: x, env: y}) -> record") == 1
  assert shape_positionals("now() -> instant") == 0
  assert shape_takes_opts?("read(path, opts) -> text")
  assert shape_takes_opts?("run(cmd, {cwd: x}) -> record")
  assert not shape_takes_opts?("get(store, key) -> value")
  v = {args: %w[a b?], opts: false}
  assert verb_conforms("f(a) -> x", v) == "yes"
  assert verb_conforms("f(a, b) -> x", v) == "yes"
  assert verb_conforms("f(a, b, c) -> x", v) == "no"
  assert verb_conforms("f(a, opts) -> x", v) == "no"
  assert verb_conforms("f() -> x", v) == "no"
  assert verb_conforms("f() -> x", nil) == "na"
end

test "a TSV that disagrees with its derived columns is refused, row by row"
  head = tsv_text(verb_header, [])
  row = [
    "T",
    "a",
    "p",
    "pure",
    "p(x, y) -> v",
    "-",
    "-",
    "absent",
    "m",
    "1",
    "p(x, y) -> v",
    "yes"
  ]
  voc = tsv_text(
    vocab_header,
    [["p", "s", "x", "no", "v", "", "pure", "m", "-", "decided"]]
  )
  g = graph_from_tsv(
    unlines(["#{head}#{tsv_join(row)}"]),
    tsv_text(edge_header, []),
    voc
  )
  assert kinds(g[:refusals]) == [:derived]
  assert g[:verbs] == []
end

test "a TSV round trips through the graph: export of import is the sorted input"
  verbs = [
    [
      "T",
      "a",
      "p",
      "pure",
      "p(x, opts) -> v",
      "error,time",
      "kotoba",
      "exists:retsu",
      "m one",
      "1",
      "p(x, opts) -> v",
      "yes"
    ],
    [
      "T",
      "a",
      "q",
      "effect",
      "q() -> nil",
      "-",
      "-",
      "absent",
      "m two",
      "0",
      "",
      "na"
    ],
    [
      "T",
      "b",
      "r",
      "decl",
      "r(a, b) -> t",
      "-",
      "-",
      "absent",
      "say \"hi\"",
      "4",
      "",
      "na"
    ]
  ]
  edges = [
    ["a::p", "composes", "a::q", "w one"],
    ["a::q", "pairs", "b::r", "w two"]
  ]
  vocab = [
    ["p", "s", "x", "yes", "v", "bad,worse", "pure", "m", "§3.5", "stdlib"]
  ]
  vt = tsv_text(verb_header, verbs)
  et = tsv_text(edge_header, edges)
  ct = tsv_text(vocab_header, vocab)
  g = graph_from_tsv(vt, et, ct)
  assert g[:refusals] == []
  assert verbs_tsv(g) == vt
  assert edges_tsv(g) == et
  assert vocab_tsv(g) == ct
  shuffled = graph_from_tsv(
    tsv_text(verb_header, reverse(verbs)),
    tsv_text(edge_header, reverse(edges)),
    ct
  )
  assert verbs_tsv(shuffled) == vt
  assert edges_tsv(shuffled) == et
end

test "a graph is written as one file per space, edges in the file of their from, and read back whole"
  g = graph_from_tsv(
    tsv_text(
      verb_header_region,
      [
        ["T", "a", "p", "pure", "p(x) -> v", "-", "-", "absent", "m one", "1"],
        ["T", "b?", "q", "pure", "q(x) -> v", "-", "-", "absent", "m two", "1"]
      ]
    ),
    tsv_text(edge_header, [%w[b?::q pairs a::p w]]),
    tsv_text(vocab_header, [])
  )
  files = graph_writes(g)
  assert map(first, files) == %w[vocab.b a.b b-provisional.b]
  b = file_graph("b-provisional.b", files[2][1])
  assert b[:refusals] == []
  assert map((r) -> r[:word], b[:rows]) == %w[space verb edge]
  assert first(b[:rows])[:status] == "provisional"
end

def ux_graph(rows)
  graph_from_tsv(
    tsv_text(
      verb_header_region,
      map(
        fn(r)
          [
            "T",
            r[0],
            r[1],
            "pure",
            "#{r[1]}(value) -> value",
            "-",
            "-",
            r[2],
            r[3],
            "0"
          ]
        end,
        rows
      )
    ),
    tsv_text(edge_header, []),
    tsv_text(vocab_header, [])
  )
end

def ux_rows()
  [
    %w[moji lower exists:moji one],
    %w[moji ghost partial:moji two],
    %w[moji void absent three],
    %w[kazu abs exists four],
    %w[gauge? gauge exists:moji five]
  ]
end

test "the probe names every exists row of a named space, once, and nothing else"
  src = probe_source(ux_graph(ux_rows))
  assert contains?(src, unlines(["use(\"kazu\")", "use(\"moji\")"]))
  assert contains?(src, "kazu::abs")
  assert contains?(src, "moji::lower")
  assert not contains?(src, "ghost")
  assert not contains?(src, "void")
  assert not contains?(src, "gauge")
  assert size(split(src, "moji::lower")) == 2
end

test "the probe of a graph with no exists row is an empty list"
  src = probe_source(ux_graph([%w[moji ghost partial:moji two]]))
  assert src == unlines(["", "def probe()", "  []", "end"])
end

test "unbound_names reads the B0011 lines and nothing else"
  out = unlines(
    [
      "typed declarations: 0",
      "names resolved:     9",
      "/p/probe.b:3:4: error[B0011]: bidama `moji` defines no `nothere`",
      "  help: nothing in `moji` is close to `nothere`",
      "/p/probe.b:3:9: error[B0011]: bidama `retsu` defines no `zzz`",
      "/p/probe.b:1:1: error[B0015]: `use(\"kijun\")` is out of order",
      "/p/probe.b:3:2: error[B0010]: `retsu::first` is qualified by `retsu`, which this file does not `use`"
    ]
  )
  assert unbound_names(out) == %w[moji::nothere retsu::zzz]
  assert unbound_names("") == []
  assert unbound_names(unlines(["names resolved:     9"])) == []
end

test "finds_unbound reports an exists row once and ignores any other row"
  g = ux_graph(ux_rows)
  found = finds_unbound(
    g,
    %w[moji::lower kazu::abs moji::lower moji::ghost moji::void zzz::none]
  )
  assert map((f) -> f[:subject], found) == %w[kazu::abs moji::lower]
  assert map((f) -> f[:kind], found) == %w[g10-unbound g10-unbound]
  assert map((f) -> f[:scope], found) == %w[kazu moji]
  assert finds_unbound(g, []) == []
end

test "g10-unbound is a kind the baseline measures"
  assert member?("g10-unbound", finding_kinds)
  found = finds_unbound(ux_graph(ux_rows), ["moji::lower"])
  assert map((m) -> m[:key], finding_measurements(found, "g10-unbound")) ==
    ["moji"]
end

def ut_package(name, body)
  [
    name,
    join_lines(
      [
        "package(\"#{name}\", \"0.1.0\")",
        "",
        "def lower(s)",
        "  s",
        "end",
        "",
        body
      ]
    )
  ]
end

def ut_corpus()
  test_corpus(
    [
      ut_package(
        "moji",
        unlines(
          [
            "test \"lower folds\"",
            "  assert lower(\"A\") == \"a\"",
            "end",
            "",
            "test \"upper is named only in text\"",
            "  assert \"upper(x)\" == \"upper(x)\"",
            "end"
          ]
        )
      ),
      ut_package(
        "kazu",
        unlines(
          [
            "test \"abs reaches across\"",
            "  assert moji::lower(\"A\") == \"a\"",
            "end"
          ]
        )
      )
    ]
  )
end

def ut_graph()
  ux_graph(
    [
      %w[moji lower exists:moji one],
      %w[moji upper exists:moji two],
      %w[moji title partial:moji three],
      %w[moji snake absent four],
      %w[kazu abs exists:kazu five],
      %w[kazu neg exists:kazu six],
      %w[gauge? gauge exists:moji seven]
    ]
  )
end

test "code_tokens splits on punctuation and keeps ? and ! and a qualified name whole"
  assert code_tokens("a.b(c, d) + e?(f!)") == %w[a b c d e? f!]
  assert code_tokens("moji::lower(x)") ==
    [qualified_token("moji", "lower"), "x"]
  assert code_tokens("") == []
  assert code_tokens("(),.") == []
end

test "unquoted drops a string literal and keeps the code around it"
  assert code_tokens(unquoted("f(\"g(x)\") + h")) == %w[f h]
  assert code_tokens(unquoted("f(\"a\", \"b\", c)")) == %w[f c]
  assert code_tokens(unquoted("\"\"")) == []
end

test "an unmatched quote leaves the text after it as code"
  assert code_tokens(unquoted("f(\"a\\\" g")) == %w[f g]
end

test "test_tokens reads test blocks only, and no string inside them"
  text = unlines(
    [
      "def helper()",
      "  secret(1)",
      "end",
      "",
      "test \"t\"",
      "  assert shown(\"hidden(1)\") == 1",
      "end"
    ]
  )
  assert test_tokens(text) == %w[assert shown 1]
  assert test_tokens(unlines(["def only()", "  1", "end"])) == []
  assert test_tokens("") == []
end

test "a verb is tested by a call in its own package's test, by a qualified call anywhere, and by nothing else"
  c = ut_corpus
  assert tested?(c, "moji", "lower")
  assert not tested?(c, "moji", "upper")
  assert tested?(c, "kazu", "abs") == false
  assert tested?(c, "moji", "absent_name") == false
  assert tested?(test_corpus([]), "moji", "lower") == false
end

test "a name that appears only in a def body or a string is not a test"
  c = ut_corpus
  assert not tested?(c, "moji", "s")
  assert not tested?(c, "kazu", "lower")
end

test "a word of a %w list in a test is text, not a use of a verb"
  assert unworded("f(%w[moji::a b], x)") == "f( , x)"
  assert unworded(join_lines(["a %w[x", "y] b %w[z]"])) == "a   b  "
  assert unworded("no list") == "no list"
end

test "g11 names every exists row with no test, once, sorted, and no other row"
  found = finds_untested(ut_graph, ut_corpus)
  assert map((f) -> f[:subject], found) == %w[kazu::abs kazu::neg moji::upper]
  assert map((f) -> f[:kind], found) ==
    %w[g11-untested g11-untested g11-untested]
  assert map((f) -> f[:scope], found) == %w[kazu kazu moji]
end

test "g11 is silent when every exists row has a test, and for an empty graph"
  g = ux_graph([%w[moji lower exists:moji one]])
  assert finds_untested(g, ut_corpus) == []
  assert finds_untested(ux_graph([]), ut_corpus) == []
end

test "g11-untested is a kind the baseline measures"
  assert member?("g11-untested", finding_kinds)
  found = finds_untested(ut_graph, ut_corpus)
  assert map((m) -> m[:key], finding_measurements(found, "g11-untested")) ==
    %w[kazu moji]
  assert map((m) -> m[:size], finding_measurements(found, "g11-untested")) ==
    [2, 1]
end

test "corpus_packages reads each package's name and text from a root, and the probe refuses an empty root"
  root = path_join(getenv("TMPDIR", "/tmp"), "mokuroku-ut-#{blake3_hex("g11")}")
  rm_rf(root)
  mkdir_p(path_join(root, "zed"))
  write_file(
    path_join(root, "zed/Bluefile"),
    unlines(["package(\"zed\", \"0.1.0\")"])
  )
  write_program(
    path_join(root, "zed/zed.b"),
    unlines(
      [
        "def go(x)",
        "  x",
        "end",
        "",
        "test \"go\"",
        "  assert go(1) == 1",
        "end"
      ]
    )
  )
  pkgs = corpus_packages([root])
  assert map(first, pkgs) == ["zed"]
  g = ux_graph([%w[zed go exists:zed one], %w[zed stop exists:zed two]])
  assert map((f) -> f[:subject], untested_probe(g, [root])) == ["zed::stop"]
  rm_rf(root)
  r = untested_probe(g, []) rescue "caught"
  assert r == "caught"
end

test "a comment after code, or alone on a line, names no token"
  assert code_tokens(uncommented("f(x) # g(y)")) == %w[f x]
  assert code_tokens(uncommented("# only(this)")) == []
  assert code_tokens(uncommented("f(\"#\", x)")) == %w[f x]
  assert code_tokens(uncommented("")) == []
  text = unlines(["test \"t\"", "  # hidden(1)", "  shown(2) # also(3)", "end"])
  assert test_tokens(text) == %w[shown 2]
end

def ut_prefixed()
  test_corpus(
    [
      [
        "wen",
        unlines(
          [
            "legacy_names(\"0.1.1\", \"wn\")",
            "",
            "def wn_put(s)",
            "  s",
            "end",
            "",
            "test \"put\"",
            "  assert wn_put(1) == 1",
            "end"
          ]
        )
      ],
      [
        "pla",
        unlines(
          [
            "legacy_names(\"0.1.1\", [[\"old\", \"pla::new\"]])",
            "",
            "test \"t\"",
            "  assert pla_put(1) == 1",
            "end"
          ]
        )
      ],
      ["bar", unlines(["test \"t\"", "  assert wn_put(1) == 1", "end"])]
    ]
  )
end

test "a package's legacy prefix spells its verb in a test, and no other package's does"
  c = ut_prefixed
  assert tested?(c, "wen", "put")
  assert not tested?(c, "wen", "get")
  assert not tested?(c, "bar", "put")
  assert not tested?(c, "pla", "put")
end

test "legacy_prefixes reads the two-string form only"
  assert ut_prefixed[:prefixes]["wen"] == "wn"
  assert is_empty(map_entries(ut_prefixed[:prefixes])) == false
  assert size(map_entries(ut_prefixed[:prefixes])) == 1
  assert legacy_prefixes([]) == {}
end
