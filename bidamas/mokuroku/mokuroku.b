use("deeta", [:get_or])

use("hadome", [:failures, :measurement, :parse, :render, :shrunk])

use("junjo", [:sort_by])

use("kiwari", [:scm_string])

use("kyohi", [:kinds, :refusal, :why])

use(
  "retsu",
  [
    :concat_lists,
    :contains,
    :count_where,
    :find_first,
    :first,
    :flat_map,
    :is_empty,
    :last,
    :push,
    :reject,
    :rest,
    :size,
    :slice,
    :take_while
  ]
)

use("shuugou", [:unique])

# mokuroku (目録): the catalogue of what every bidama on a BLUE_PATH provides.
#
# Before anyone writes blue, the first question is "what do we already have?".
# Without this, the answer was a grep, and a grep cannot say what a function is
# for. mokuroku reads every package under the given roots: its manifest
# (package, version, needs), its gloss (the first comment line of its source),
# its tests, and every top-level `def` with the comment block directly above it.
# The same scan serves three consumers:
#
#   render_markdown   the catalogue a person or agent reads. Committed as
#                     bidamas/CATALOG.md, so GitHub renders it and codesearch
#                     indexes it. This is the docs.rs / pkg.go.dev role, with
#                     no documentation server.
#   name_collisions   the flat-namespace gate. blue's namespace is flat across
#                     imports, so two packages defining one name break any
#                     program that imports both, far from the cause.
#   names_shadowing   the same question asked against a list of builtin names.
#
# Because the namespace is flat, this package's own names are deliberately
# specific (md_cell, pkg_name, name_collisions): a generic `cell` or `owners`
# here would be exactly the collision it exists to catch.
#
# How it reads source: as TEXT, line by line, the same view mk-bidama.nix takes
# of a Bluefile. Every def in the distribution is a top-level `def` line, so
# the text view is exact for today's corpus. A def produced by a macro would
# not be seen; the fix is a parser-backed scan, not a cleverer split.
#
# A package record is [name, version, needs, gloss, entries, tests], and an
# entry is [def_name, signature, doc_lines].

# ── manifests ──────────────────────────────────────────────────────────────

# The first quoted field after `marker`, and the one after it, as a list.
def quoted_after(text, marker)
  parts = split(text, marker)
  if size(parts) < 2
    []
  else
    fields = split(nth(1, parts), "\"")
    [nth(0, fields), nth(2, fields)]
  end
end

# [name, version, needs] from a Bluefile's text.
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

# The name a `def` line defines: everything up to "(" or a space.
def defined_name(line)
  join(take_while((c) -> c != "(" and c != " ", drop(4, chars(line))), "")
end

# The code a `# waive CODE: reason` comment names, or nil for any other line.
def waived_code(line)
  body = comment_text(line)
  if starts_with?(body, "waive ")
    blue::trim(first(split(join(drop(6, chars(body)), ""), ":")))
  end
end

# [def_name, signature, doc_lines, waived_codes] for every top-level def in a
# source text. A comment block documents a def only when it sits directly
# above it; a blank line or any code in between resets it, so section banners
# attach to nothing. A `# waive CODE:` line in that block is not
# documentation: its code is recorded as the definition's waiver.
def entries_of_text(text)
  state = reduce(
    fn(acc, line)
      pending = first(acc)
      waivers = nth(1, acc)
      found = last(acc)
      if starts_with?(line, "#") and waived_code(line) != nil
        [pending, push(waivers, waived_code(line)), found]
      elsif starts_with?(line, "#")
        [push(pending, comment_text(line)), waivers, found]
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
          )
        ]
      else
        [[], [], found]
      end
    end,
    [[], [], []],
    joined_header_lines(split(text, "\n"))
  )
  last(state)
end

def bare_signature(signature, name)
  called = concat(name, "()")
  if starts_with?(signature, called)
    concat(name, join(drop(size(chars(called)), chars(signature)), ""))
  else
    signature
  end
end

# The prefix a `legacy_names(since, prefix)` declaration names, or nil. A
# moves declaration (`legacy_names(since, [[old, "home::new"], …])`) names no
# prefix: its line is not two strings.
def legacy_prefix_of_text(text)
  line = find_first(
    (l) -> starts_with?(l, "legacy_names(") and size(split(l, "\"")) == 5,
    split(text, "\n")
  )
  if line.nil?
    nil
  else
    nth(3, split(line, "\""))
  end
end

# The lines of a source, with each def header the formatter broke over several
# lines (a parameter list too long for 80 columns: `def f(` / `  a,` / `  b` /
# `)`) joined back onto one, so a signature reads as it would have been
# written on one line. Without this the catalogue listed `el_record(`.
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

# The package's gloss: the first comment line of its source.
def gloss_of_text(text)
  comment = find_first((l) -> starts_with?(l, "#"), split(text, "\n"))
  if comment.nil?
    ""
  else
    comment_text(comment)
  end
end

# [title, body_lines] for every top-level `test` block in a source text: a
# block runs from its `test "…"` line to the first `end` at column 0.
def test_blocks_of_text(text)
  state = reduce(
    fn(acc, line)
      open = first(acc)
      found = last(acc)
      if open.nil? and starts_with?(line, "test \"")
        [[nth(1, split(line, "\"")), []], found]
      elsif open != nil and line == "end"
        [nil, push(found, open)]
      elsif open != nil
        [[first(open), push(last(open), line)], found]
      else
        acc
      end
    end,
    [nil, []],
    split(text, "\n")
  )
  last(state)
end

def tests_in_text(text)
  count_where((l) -> starts_with?(l, "test \""), split(text, "\n"))
end

# ── reading a root ─────────────────────────────────────────────────────────

def blue_path_roots(blue_path)
  filter((r) -> r != "", split(blue_path, ":"))
end

# Package directories under a root: any directory holding a Bluefile.
def package_dirs(root)
  map(
    (p) -> path_dirname(p),
    filter((p) -> ends_with?(p, "/Bluefile"), walk_dir(root))
  )
end

# The text of every `.b` file directly in a package directory, joined.
def package_text(dir)
  join(
    map(
      (p) -> read_file(p),
      filter(
        (p) -> ends_with?(p, ".b") and path_dirname(p) == dir,
        walk_dir(dir)
      )
    ),
    "\n"
  )
end

def package_record(dir)
  manifest = parse_manifest(read_file(concat(dir, "/Bluefile")))
  all_text = package_text(dir)
  [
    nth(0, manifest),
    nth(1, manifest),
    nth(2, manifest),
    gloss_of_text(all_text),
    entries_of_text(all_text),
    tests_in_text(all_text),
    legacy_prefix_of_text(all_text),
    dir
  ]
end

# Every package under the roots, sorted by name. When two roots hold the same
# package, the earlier root wins, as it does for the loader.
def catalog_of(roots)
  records = flat_map((root) -> map(package_record, package_dirs(root)), roots)
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

# The records whose package has a row in the name ledger (NAMES.md), so a
# package that is untracked or still being named does not enter a catalogue
# the ledger has not adjudicated.
def registered_only(ledger, records)
  filter((r) -> contains?(ledger, "| `#{first(r)}` |"), records)
end

def pkg_name(r)
  nth(0, r)
end

def pkg_version(r)
  nth(1, r)
end

def pkg_needs(r)
  nth(2, r)
end

def pkg_gloss(r)
  nth(3, r)
end

def pkg_entries(r)
  nth(4, r)
end

def pkg_tests(r)
  nth(5, r)
end

# The prefix the package's definitions once carried (`legacy_names`), or nil.
def pkg_legacy_prefix(r)
  if size(r) > 6
    nth(6, r)
  end
end

# The directory the package was read from, or nil for a record built by hand.
def pkg_dir(r)
  if size(r) > 7
    nth(7, r)
  end
end

def catalog_def_count(records)
  reduce((acc, r) -> acc + size(pkg_entries(r)), 0, records)
end

# ── the namespace gates ────────────────────────────────────────────────────

# [def_name, owner] for every definition, once per package.
def definition_owners(records)
  flat_map(
    fn(r)
      map((n) -> [n, pkg_name(r)], unique(map((e) -> first(e), pkg_entries(r))))
    end,
    records
  )
end

# [def_name, [packages…]] for every name more than one package defines.
def name_collisions(records)
  pairs = definition_owners(records)
  names = unique(map((p) -> first(p), pairs))
  groups = map(
    (n) -> [n, map((p) -> last(p), filter((p) -> first(p) == n, pairs))],
    names
  )
  filter((g) -> size(last(g)) > 1, groups)
end

# The collisions that involve at least one of `owned` (a private distribution
# checking itself against everything it composes with).
def name_collisions_touching(records, owned)
  filter(
    (g) -> some((pkg) -> contains(owned, pkg), last(g)),
    name_collisions(records)
  )
end

# [package, def_name] for every name a package defines more than once: the
# collision gate under per-bidama namespaces, where two packages may share a
# name and one package may not.
def namespace_duplicates(records)
  flat_map(
    fn(r)
      names = map((e) -> first(e), pkg_entries(r))
      map(
        (n) -> [pkg_name(r), n],
        filter((n) -> size(filter((m) -> m == n, names)) > 1, unique(names))
      )
    end,
    records
  )
end

# [def_name, package] for every definition that reuses one of `names`.
def names_shadowing(records, names)
  filter((p) -> contains(names, first(p)), definition_owners(records))
end

# ── rendering ──────────────────────────────────────────────────────────────

# Markdown table cells cannot hold a raw pipe.
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

# The definition's other name, from the package's `legacy_names`: the old,
# prefixed spelling of a renamed definition (a bridge), or the stripped name
# of one that kept its prefix (a second name, for good).
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
    join(map((c) -> "`#{c}`", nth(3, e)), " ")
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
  "| `#{pkg_name(r)}::#{md_cell(nth(1, e))}` | #{other_name(r, e)} | #{shares} | #{entry_waivers(e)} | #{md_cell(first_line_or_blank(nth(2, e)))} |"
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
    "\n"
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
  "#{join(concat_lists(header, map(pkg_summary_row, records)), "\n")}\n\n#{join(body, "\n\n")}\n\n#{shared_names_section(records)}\n"
end

# The names several packages define: legal, since each is reached qualified
# (`retsu::first`, `kueri::count`), and listed so an author finds the one
# they mean.
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
    "\n"
  )
end

# Write the catalogue of every root on BLUE_PATH to `path`.
def write_catalog(path)
  write_file(
    path,
    render_markdown(catalog_of(blue_path_roots(getenv("BLUE_PATH", ""))))
  )
end

# ── the verb graph ──────────────────────────────────────────────────────────

def row_space?(c)
  c == " " or c == "\n" or c == "\t"
end

def row_digit?(c)
  contains?("0123456789", c)
end

def row_ident_char?(c)
  contains?("abcdefghijklmnopqrstuvwxyz0123456789_?!", c)
end

def row_skip(cs, i, n)
  if i < n and row_space?(nth(i, cs))
    row_skip(cs, i + 1, n)
  else
    i
  end
end

def row_ident_end(cs, i, n)
  if i < n and row_ident_char?(nth(i, cs))
    row_ident_end(cs, i + 1, n)
  else
    i
  end
end

def row_digits_end(cs, i, n)
  if i < n and row_digit?(nth(i, cs))
    row_digits_end(cs, i + 1, n)
  else
    i
  end
end

def row_text(cs, from, to)
  join(slice(cs, from, to - from), "")
end

def row_fail(cs, i, why)
  line = 1 + count_where((c) -> c == "\n", take(i, cs))
  raise(:row_syntax, "line #{to_s(line)}: #{why}")
end

def row_symbol?(v)
  list?(v) and size(v) == 2 and first(v) == :symbol
end

def row_plain(v)
  if row_symbol?(v)
    nth(1, v)
  else
    v
  end
end

def row_string(cs, i, n, from, acc)
  if i >= n
    row_fail(cs, from, "a string is not closed")
  else
    c = nth(i, cs)
    if c == "\""
      [join(acc, ""), i + 1]
    elsif c == "\\"
      d = if i + 1 < n
        nth(i + 1, cs)
      else
        ""
      end
      if d == "\"" or d == "\\"
        row_string(cs, i + 2, n, from, push(acc, d))
      else
        row_fail(cs, i, "a string holds the escapes \\\" and \\\\ only")
      end
    elsif c == "\n"
      row_fail(cs, i, "a string holds no line break")
    else
      row_string(cs, i + 1, n, from, push(acc, c))
    end
  end
end

def row_number(cs, i, n)
  from = if nth(i, cs) == "-"
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
  if j < n and nth(j, cs) == close
    [acc, j + 1]
  else
    r = row_value(cs, j, n)
    k = row_skip(cs, nth(1, r), n)
    if k < n and nth(k, cs) == ","
      row_items(cs, k + 1, n, close, push(acc, nth(0, r)))
    elsif k < n and nth(k, cs) == close
      [push(acc, nth(0, r)), k + 1]
    else
      row_fail(cs, k, "expected `,` or `#{close}`")
    end
  end
end

def row_entries(cs, i, n, acc)
  j = row_skip(cs, i, n)
  if j < n and nth(j, cs) == "}"
    [acc, j + 1]
  else
    e = row_ident_end(cs, j, n)
    if e == j or e >= n or nth(e, cs) != ":"
      row_fail(cs, j, "a map entry is `name: value`")
    else
      key = row_text(cs, j, e)
      if member?(key, map(first, map_entries(acc)))
        row_fail(cs, j, "the key `#{key}` is written twice")
      else
        r = row_value(cs, e + 1, n)
        k = row_skip(cs, nth(1, r), n)
        grown = assoc(acc, key, nth(0, r))
        if k < n and nth(k, cs) == ","
          row_entries(cs, k + 1, n, grown)
        elsif k < n and nth(k, cs) == "}"
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
    c = nth(j, cs)
    if c == "\""
      row_string(cs, j + 1, n, j + 1, [])
    elsif c == ":"
      e = row_ident_end(cs, j + 1, n)
      if e == j + 1
        row_fail(cs, j, "a symbol has a name")
      else
        [[:symbol, row_text(cs, j + 1, e)], e]
      end
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
    if e == j or e >= n or nth(e, cs) != "("
      row_fail(cs, j, "a row is `word(arguments)`")
    else
      r = row_items(cs, e + 1, n, ")", [])
      row_forms_from(
        cs,
        nth(1, r),
        n,
        push(acc, {word: row_text(cs, j, e), args: nth(0, r)})
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
      pos: [["name", "str"]],
      fields: [
        ["status", "sym:ratified,provisional", true, nil],
        ["gloss", "strnil", false, nil]
      ]
    },
    "verb" => {
      pos: [["space", "str"], ["verb", "str"]],
      fields: [
        ["kind", "sym:pure,effect,stream,decl", true, nil],
        ["shape", "str", true, nil],
        ["laterals", "strs", true, nil],
        ["fleet", "strnil", true, nil],
        ["today", "str", true, nil],
        ["meaning", "str", true, nil],
        ["wave", "int", true, nil],
        ["origin", "str", true, nil],
        ["contract", "strnil", false, nil],
        ["enabled", "bool", false, true],
        ["replaced_by", "strnil", false, nil]
      ]
    },
    "edge" => {
      pos: [
        ["from", "str"],
        ["rel", "sym:#{join(graph_rels, ",")}"],
        ["to", "str"],
        ["why", "str"]
      ],
      fields: []
    },
    "vocab" => {
      pos: [["verb", "str"]],
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
      pos: [["name", "str"]],
      fields: [["battery", "strnil", false, nil]]
    }
  }
end

def graph_rels()
  [
    "inverse",
    "composes",
    "refines",
    "generalizes",
    "requires",
    "lifts",
    "guards",
    "pairs"
  ]
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
    row_symbol?(v) and member?(nth(1, v), split(drop_chars_of(type, 4), ","))
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
  pos = get(spec, :pos)
  fields = get(spec, :fields)
  want = if is_empty(fields)
    size(pos)
  else
    size(pos) + 1
  end
  if size(args) != want
    ["#{word} takes #{to_s(want)} arguments, not #{to_s(size(args))}"]
  else
    bad_pos = flat_map(
      fn(i)
        p = nth(i, pos)
        if row_fits(nth(1, p), nth(i, args))
          []
        else
          ["#{nth(0, p)} must be #{row_type_name(nth(1, p))}"]
        end
      end,
      range(0, size(pos))
    )
    if is_empty(fields)
      bad_pos
    elsif not map?(nth(size(pos), args))
      concat_lists(bad_pos, ["the last argument is a map"])
    else
      m = nth(size(pos), args)
      known = map(first, fields)
      stray = map(
        (k) -> "`#{k}` is no field of #{word}",
        reject((k) -> member?(k, known), map(first, map_entries(m)))
      )
      absent = flat_map(
        fn(f)
          if nth(2, f) and not member?(nth(0, f), map(first, map_entries(m)))
            ["`#{nth(0, f)}` is missing"]
          else
            []
          end
        end,
        fields
      )
      wrong = flat_map(
        fn(f)
          present = member?(nth(0, f), map(first, map_entries(m)))
          if present and not row_fits(nth(1, f), get(m, nth(0, f)))
            ["`#{nth(0, f)}` must be #{row_type_name(nth(1, f))}"]
          else
            []
          end
        end,
        fields
      )
      concat_lists(concat_lists(bad_pos, stray), concat_lists(absent, wrong))
    end
  end
end

def row_values(spec, args)
  pos = get(spec, :pos)
  fields = get(spec, :fields)
  named = reduce(
    (acc, i) -> assoc(acc, nth(0, nth(i, pos)), row_plain(nth(i, args))),
    {},
    range(0, size(pos))
  )
  if is_empty(fields)
    named
  else
    m = nth(size(pos), args)
    reduce(
      fn(acc, f)
        if member?(nth(0, f), map(first, map_entries(m)))
          assoc(acc, nth(0, f), row_plain(get(m, nth(0, f))))
        else
          assoc(acc, nth(0, f), nth(3, f))
        end
      end,
      named,
      fields
    )
  end
end

def row_model(word, v)
  if word == "space"
    {
      word:,
      name: get(v, "name"),
      status: get(v, "status"),
      gloss: get(v, "gloss")
    }
  elsif word == "verb"
    {
      word:,
      space: get(v, "space"),
      verb: get(v, "verb"),
      kind: get(v, "kind"),
      shape: get(v, "shape"),
      laterals: get(v, "laterals"),
      fleet: get(v, "fleet"),
      today: get(v, "today"),
      meaning: get(v, "meaning"),
      wave: get(v, "wave"),
      origin: get(v, "origin"),
      contract: get(v, "contract"),
      enabled: get(v, "enabled"),
      replaced_by: get(v, "replaced_by")
    }
  elsif word == "edge"
    {
      word:,
      from: get(v, "from"),
      rel: get(v, "rel"),
      to: get(v, "to"),
      why: get(v, "why")
    }
  elsif word == "vocab"
    {
      word:,
      verb: get(v, "verb"),
      subject: get(v, "subject"),
      args: get(v, "args"),
      opts: get(v, "opts"),
      returns: get(v, "returns"),
      raises: get(v, "raises"),
      kind: get(v, "kind"),
      meaning: get(v, "meaning"),
      ref: get(v, "ref"),
      status: get(v, "status")
    }
  else
    {word:, name: get(v, "name"), battery: get(v, "battery")}
  end
end

def row_of(form)
  word = get(form, :word)
  spec = get(row_specs, word)
  if spec.nil?
    [
      :unknown_word,
      "`#{word}` is no row word: the words are #{join(map(first, map_entries(row_specs)), ", ")}"
    ]
  else
    problems = row_problems(word, spec, get(form, :args))
    if is_empty(problems)
      row_model(word, row_values(spec, get(form, :args)))
    else
      [:bad_row, "#{word}: #{join(problems, "; ")}"]
    end
  end
end

def row_refusal?(r)
  list?(r) and size(r) == 2 and keyword?(first(r))
end

def row_node(r)
  if get(r, :word) == "verb"
    "#{get(r, :space)}::#{get(r, :verb)}"
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
  words = map((r) -> get(r, :word), rows)
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
    spaces = filter((r) -> get(r, :word) == "space", rows)
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
      s = get(first(spaces), :name)
      wrong_verbs = map(
        fn(r)
          refusal(
            :misplaced,
            "#{name}: #{row_node(r)} is a verb of another space than #{s}"
          )
        end,
        filter((r) -> get(r, :word) == "verb" and get(r, :space) != s, rows)
      )
      wrong_edges = map(
        fn(r)
          refusal(
            :misplaced,
            "#{name}: the edge from #{get(r, :from)} belongs in the file of its `from` space, not #{s}"
          )
        end,
        filter(
          fn(r)
            get(r, :word) == "edge" and
              not starts_with?(get(r, :from), "#{s}::")
          end,
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
    (r) -> refusal(first(r), "#{name}: #{nth(1, r)}"),
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
  rows = flat_map((p) -> get(p, :rows), parts)
  {
    spaces: filter((r) -> get(r, :word) == "space", rows),
    verbs: filter((r) -> get(r, :word) == "verb", rows),
    edges: filter((r) -> get(r, :word) == "edge", rows),
    vocab: filter((r) -> get(r, :word) == "vocab", rows),
    laterals: filter((r) -> get(r, :word) == "lateral", rows),
    refusals: flat_map((p) -> get(p, :refusals), parts)
  }
end

def graph_load(dir)
  graph_assemble(
    map((p) -> file_graph(path_basename(p), read_file(p)), graph_files(dir))
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
          filter((e) -> nth(1, e) > 1, map_entries(blue::frequencies(keys)))
        )
      )
    )
  end
  concat_lists(
    keyed("verb", map(row_node, get(g, :verbs))),
    concat_lists(
      keyed("space", map((s) -> get(s, :name), get(g, :spaces))),
      concat_lists(
        keyed("vocab", map((v) -> get(v, :verb), get(g, :vocab))),
        keyed(
          "edge",
          map(
            (e) -> "#{get(e, :from)} #{get(e, :rel)} #{get(e, :to)}",
            get(g, :edges)
          )
        )
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
  reduce((acc, v) -> assoc(acc, get(v, :verb), v), {}, get(g, :vocab))
end

def vocab_least(v)
  count_where(
    (a) -> not (starts_with?(a, "~") or ends_with?(a, "?")),
    reject((a) -> a == "", map(blue::trim, get(v, :args)))
  )
end

def vocab_most(v)
  size(reject((a) -> a == "", map(blue::trim, get(v, :args))))
end

def verb_conforms(shape, v)
  if v.nil?
    "na"
  else
    n = shape_positionals(shape)
    if n >= vocab_least(v) and
        n <= vocab_most(v) and
        (get(v, :opts) or not shape_takes_opts?(shape))
      "yes"
    else
      "no"
    end
  end
end

def verb_contract_shape(row, v)
  if get(row, :contract) != nil
    get(row, :contract)
  elsif v.nil?
    ""
  else
    get(row, :shape)
  end
end

def verb_contract_default(row, v)
  if v.nil?
    ""
  else
    get(row, :shape)
  end
end

def graph_nodes(g)
  reduce((acc, r) -> assoc(acc, row_node(r), r), {}, get(g, :verbs))
end

def meaning_stops()
  [
    "a",
    "an",
    "the",
    "of",
    "to",
    "in",
    "on",
    "by",
    "for",
    "and",
    "or",
    "with",
    "as",
    "from",
    "into",
    "at",
    "its",
    "is",
    "it",
    "that"
  ]
end

def meaning_tokens(s)
  letters = "abcdefghijklmnopqrstuvwxyz0123456789"
  r = reduce(
    fn(acc, c)
      if contains?(letters, c)
        [nth(0, acc), push(nth(1, acc), c)]
      elsif is_empty(nth(1, acc))
        acc
      else
        [push(nth(0, acc), join(nth(1, acc), "")), []]
      end
    end,
    [[], []],
    chars(downcase(s))
  )
  all = if is_empty(nth(1, r))
    nth(0, r)
  else
    push(nth(0, r), join(nth(1, r), ""))
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
      if member?(get(e, :rel), rels)
        assoc(
          assoc(acc, "#{get(e, :from)} #{get(e, :to)}", true),
          "#{get(e, :to)} #{get(e, :from)}",
          true
        )
      else
        acc
      end
    end,
    {},
    get(g, :edges)
  )
end

def finds_meaning(g)
  related = graph_related(g, ["refines", "generalizes", "inverse"])
  live = filter((r) -> get(r, :enabled), get(g, :verbs))
  keyed = map(
    fn(r)
      [
        "#{get(r, :space)} #{join(meaning_tokens(get(r, :meaning)), " ")}",
        row_node(r)
      ]
    end,
    filter((r) -> not is_empty(meaning_tokens(get(r, :meaning))), live)
  )
  groups = reduce(
    fn(acc, k)
      assoc(acc, nth(0, k), push(get_or(acc, nth(0, k), []), nth(1, k)))
    end,
    {},
    keyed
  )
  flat_map(
    fn(entry)
      ids = sort_keyed((x) -> x, nth(1, entry))
      flat_map(
        fn(i)
          flat_map(
            fn(j)
              a = nth(i, ids)
              b = nth(j, ids)
              if get(related, "#{a} #{b}") == true
                []
              else
                [finding("g1-meaning", node_space(a), "#{a} #{b}")]
              end
            end,
            range(i + 1, size(ids))
          )
        end,
        range(0, size(ids))
      )
    end,
    filter((e) -> size(nth(1, e)) > 1, map_entries(groups))
  )
end

def finds_vocab(g)
  known = vocab_by_verb(g)
  map(
    (r) -> finding("g2-vocab", get(r, :space), row_node(r)),
    filter(
      (r) -> get(r, :enabled) and get(known, get(r, :verb)).nil?,
      get(g, :verbs)
    )
  )
end

def needs_edges(g)
  filter((e) -> member?(get(e, :rel), ["composes", "requires"]), get(g, :edges))
end

def adjacency(edges)
  reduce(
    fn(acc, e)
      assoc(
        acc,
        get(e, :from),
        push(get_or(acc, get(e, :from), []), get(e, :to))
      )
    end,
    {},
    edges
  )
end

def peeled(live, edges)
  kept = filter(
    (e) -> get(live, get(e, :from)) == true and get(live, get(e, :to)) == true,
    edges
  )
  heads = reduce((acc, e) -> assoc(acc, get(e, :from), true), {}, kept)
  tails = reduce((acc, e) -> assoc(acc, get(e, :to), true), {}, kept)
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
        flat_map((f) -> get_or(adj, f, []), frontier)
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
    (acc, e) -> assoc(assoc(acc, get(e, :from), true), get(e, :to), true),
    {},
    edges
  )
  live = peeled(nodes, edges)
  adj = adjacency(filter((e) -> get(live, get(e, :from)) == true, edges))
  on_cycle = filter(
    (k) -> get(reaches(adj, live, get_or(adj, k, []), {}), k) == true,
    sort_keyed((k) -> k, map(first, map_entries(live)))
  )
  map((k) -> finding("g4-cycle", node_space(k), k), on_cycle)
end

def finds_wave(g)
  nodes = graph_nodes(g)
  flat_map(
    fn(e)
      f = get(nodes, get(e, :from))
      t = get(nodes, get(e, :to))
      if f != nil and t != nil and get(t, :wave) > get(f, :wave)
        [
          finding(
            "g4-wave",
            node_space(get(e, :from)),
            "#{get(e, :from)} -> #{get(e, :to)}"
          )
        ]
      else
        []
      end
    end,
    needs_edges(g)
  )
end

def finds_inverse(g)
  pairs = distinct(
    map(
      fn(e)
        a = get(e, :from)
        b = get(e, :to)
        if compare(a, b) <= 0
          [a, b]
        else
          [b, a]
        end
      end,
      filter((e) -> get(e, :rel) == "inverse", get(g, :edges))
    )
  )
  partners = reduce(
    fn(acc, p)
      a = nth(0, p)
      b = nth(1, p)
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
    (e) -> finding("g7-inverse", node_space(nth(0, e)), nth(0, e)),
    sort_keyed(
      (e) -> nth(0, e),
      filter((e) -> size(distinct(nth(1, e))) > 1, map_entries(partners))
    )
  )
end

def finds_edges(g)
  nodes = graph_nodes(g)
  ends = distinct(flat_map((e) -> [get(e, :from), get(e, :to)], get(g, :edges)))
  dangling = map(
    (x) -> finding("g9-dangling", node_space(x), x),
    sort_keyed((x) -> x, filter((x) -> get(nodes, x).nil?, ends))
  )
  unknown = map(
    fn(e)
      finding(
        "g9-relation",
        node_space(get(e, :from)),
        "#{get(e, :from)} #{get(e, :rel)} #{get(e, :to)}"
      )
    end,
    filter((e) -> not member?(get(e, :rel), graph_rels), get(g, :edges))
  )
  concat_lists(dangling, unknown)
end

def exists_rows(g)
  filter(
    fn(r)
      get(r, :enabled) and
        starts_with?(get(r, :today), "exists") and
        not ends_with?(get(r, :space), "?")
    end,
    get(g, :verbs)
  )
end

def probe_source(g)
  rows = exists_rows(g)
  spaces = sort_keyed((s) -> s, distinct(map((r) -> get(r, :space), rows)))
  uses = join(map((s) -> "use(\"#{s}\")\n", spaces), "")
  names = join(map(row_node, rows), ", ")
  "#{uses}\ndef probe()\n  [#{names}]\nend\n"
end

def unbound_names(output)
  map(
    fn(l)
      parts = split(l, "`")
      "#{nth(1, parts)}::#{nth(3, parts)}"
    end,
    filter((l) -> contains?(l, "error[B0011]"), split(output, "\n"))
  )
end

def finds_unbound(g, unbound)
  rows = map(row_node, exists_rows(g))
  map(
    (n) -> finding("g10-unbound", node_space(n), n),
    sort_keyed((n) -> n, distinct(filter((n) -> member?(n, rows), unbound)))
  )
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
  write_file(path, src)
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
    (f) -> "#{get(f, :kind)} #{get(f, :subject)}",
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
    (f) -> "#{get(f, :kind)} #{get(f, :subject)}",
    concat_lists(graph_findings(g), finds_unbound(g, unbound_probe(g, exe)))
  )
end

def finding_kinds()
  [
    "g1-meaning",
    "g2-vocab",
    "g4-cycle",
    "g4-wave",
    "g7-inverse",
    "g9-dangling",
    "g9-relation",
    "g10-unbound"
  ]
end

def finding_measurements(findings, kind)
  counts = reduce(
    (acc, f) -> assoc(acc, get(f, :scope), get_or(acc, get(f, :scope), 0) + 1),
    {},
    filter((f) -> get(f, :kind) == kind, findings)
  )
  map(
    (e) -> measurement(nth(0, e), nth(1, e)),
    sort_keyed((e) -> nth(0, e), map_entries(counts))
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
    (k) -> failures(rows, k, finding_measurements(findings, k)),
    finding_kinds
  )
end

def graph_shrunk(findings, baseline_text)
  rows = parse(baseline_text)
  flat_map(
    fn(k)
      map(
        (m) -> "#{k}: #{get(m, :key)}",
        shrunk(rows, k, finding_measurements(findings, k))
      )
    end,
    finding_kinds
  )
end

def tsv_lines(text)
  reject((l) -> l == "", split(text, "\n"))
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
    contains?(s, "\n") or contains?(s, "\t") or contains?(s, concat("#", "{"))
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
          fields = tsv_fields(nth(i, lines))
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
  [
    "region",
    "space",
    "verb",
    "kind",
    "shape",
    "laterals",
    "fleet",
    "blue_today",
    "meaning",
    "wave",
    "contract_shape",
    "conforms"
  ]
end

def verb_header_region()
  take(10, verb_header)
end

def edge_header()
  ["from", "rel", "to", "why"]
end

def vocab_header()
  [
    "verb",
    "subject",
    "args",
    "opts",
    "returns",
    "raises",
    "kind",
    "meaning",
    "stdlib_ref",
    "status"
  ]
end

def tsv_verb(label, c, vocab)
  v = get(vocab, get(c, "verb"))
  id = "#{get(c, "space")}::#{get(c, "verb")}"
  wave = to_int(get(c, "wave"))
  row = {
    word: "verb",
    space: get(c, "space"),
    verb: get(c, "verb"),
    kind: get(c, "kind"),
    shape: get(c, "shape"),
    laterals: tsv_list(get(c, "laterals")),
    fleet: if get(c, "fleet") == "-"
      nil
    else
      get(c, "fleet")
    end,
    today: get(c, "blue_today"),
    meaning: get(c, "meaning"),
    wave:,
    origin: get(c, "region"),
    contract: nil,
    enabled: true,
    replaced_by: nil
  }
  given = get(c, "contract_shape")
  if wave.nil?
    refusal(
      :tsv_value,
      "#{label} #{id}: wave `#{get(c, "wave")}` is no whole number"
    )
  elsif not member?(get(row, :kind), ["pure", "effect", "stream", "decl"])
    refusal(:tsv_value, "#{label} #{id}: kind `#{get(row, :kind)}` is no kind")
  elsif given.nil?
    row
  elsif get(c, "conforms") != verb_conforms(get(row, :shape), v)
    refusal(
      :derived,
      "#{label} #{id}: conforms is `#{get(c, "conforms")}` and the shape says `#{verb_conforms(get(row, :shape), v)}`"
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
        verb: get(c, "verb"),
        subject: get(c, "subject"),
        args: tsv_list(get(c, "args")),
        opts: get(c, "opts") == "yes",
        returns: get_or(c, "returns", ""),
        raises: tsv_list(get(c, "raises")),
        kind: get(c, "kind"),
        meaning: get(c, "meaning"),
        ref: if get(c, "stdlib_ref") == "-"
          nil
        else
          get(c, "stdlib_ref")
        end,
        status: get(c, "status")
      }
    end,
    get(vt, :rows)
  )
  by_verb = reduce((acc, v) -> assoc(acc, get(v, :verb), v), {}, vocab)
  vr = tsv_table("verbs", verbs_text, [verb_header, verb_header_region])
  verbs_made = map((c) -> tsv_verb("verbs", c, by_verb), get(vr, :rows))
  et = tsv_table("edges", edges_text, [edge_header])
  edges = map(
    fn(c)
      {
        word: "edge",
        from: get(c, "from"),
        rel: get(c, "rel"),
        to: get(c, "to"),
        why: get(c, "why")
      }
    end,
    get(et, :rows)
  )
  verbs = reject(row_refusal?, verbs_made)
  names = distinct(sort_keyed((s) -> s, map((r) -> get(r, :space), verbs)))
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
      concat_lists(get(vt, :refusals), get(vr, :refusals)),
      concat_lists(
        filter(row_refusal?, verbs_made),
        concat_lists(get(et, :refusals), graph_duplicates(g))
      )
    )
  )
end

def tsv_join(fields)
  join(fields, "\t")
end

def tsv_text(header, rows)
  join(map((r) -> "#{tsv_join(r)}\n", concat_lists([header], rows)), "")
end

def verbs_tsv(g)
  by_verb = vocab_by_verb(g)
  rows = sort_keyed(row_node, get(g, :verbs))
  tsv_text(
    verb_header,
    map(
      fn(r)
        v = get(by_verb, get(r, :verb))
        [
          get(r, :origin),
          get(r, :space),
          get(r, :verb),
          get(r, :kind),
          get(r, :shape),
          if is_empty(get(r, :laterals))
            "-"
          else
            join(get(r, :laterals), ",")
          end,
          if get(r, :fleet).nil?
            "-"
          else
            get(r, :fleet)
          end,
          get(r, :today),
          get(r, :meaning),
          to_s(get(r, :wave)),
          verb_contract_shape(r, v),
          verb_conforms(get(r, :shape), v)
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
      (e) -> [get(e, :from), get(e, :rel), get(e, :to), get(e, :why)],
      sort_keyed(
        (e) -> "#{get(e, :from)}\t#{get(e, :rel)}\t#{get(e, :to)}",
        get(g, :edges)
      )
    )
  )
end

def vocab_tsv(g)
  tsv_text(
    vocab_header,
    map(
      fn(v)
        [
          get(v, :verb),
          get(v, :subject),
          join(get(v, :args), ","),
          if get(v, :opts)
            "yes"
          else
            "no"
          end,
          get(v, :returns),
          join(get(v, :raises), ","),
          get(v, :kind),
          get(v, :meaning),
          if get(v, :ref).nil?
            "-"
          else
            get(v, :ref)
          end,
          get(v, :status)
        ]
      end,
      sort_keyed((v) -> get(v, :verb), get(g, :vocab))
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
  "{#{join(map((p) -> "#{nth(0, p)}: #{nth(1, p)}", pairs), ", ")}}"
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
      ["kind", ":#{get(r, :kind)}"],
      ["shape", scm_string(get(r, :shape))],
      ["laterals", row_strings(get(r, :laterals))],
      ["fleet", row_scalar(get(r, :fleet))],
      ["today", scm_string(get(r, :today))],
      ["meaning", scm_string(get(r, :meaning))],
      ["wave", to_s(get(r, :wave))],
      ["origin", scm_string(get(r, :origin))]
    ],
    concat_lists(
      optional_field(
        "contract",
        if get(r, :contract).nil?
          nil
        else
          scm_string(get(r, :contract))
        end
      ),
      concat_lists(
        if get(r, :enabled)
          []
        else
          [["enabled", "false"]]
        end,
        optional_field(
          "replaced_by",
          if get(r, :replaced_by).nil?
            nil
          else
            scm_string(get(r, :replaced_by))
          end
        )
      )
    )
  )
end

def row_source(r)
  w = get(r, :word)
  if w == "space"
    fields = concat_lists(
      [["status", ":#{get(r, :status)}"]],
      optional_field(
        "gloss",
        if get(r, :gloss).nil?
          nil
        else
          scm_string(get(r, :gloss))
        end
      )
    )
    "space(#{scm_string(get(r, :name))}, #{row_fields(fields)})"
  elsif w == "verb"
    "verb(#{scm_string(get(r, :space))}, #{scm_string(get(r, :verb))}, #{row_fields(verb_fields(r))})"
  elsif w == "edge"
    "edge(#{scm_string(get(r, :from))}, :#{get(r, :rel)}, #{scm_string(get(r, :to))}, #{scm_string(get(r, :why))})"
  elsif w == "vocab"
    fields = [
      ["subject", scm_string(get(r, :subject))],
      ["args", row_strings(get(r, :args))],
      ["opts", row_scalar(get(r, :opts))],
      ["returns", scm_string(get(r, :returns))],
      ["raises", row_strings(get(r, :raises))],
      ["kind", ":#{get(r, :kind)}"],
      ["meaning", scm_string(get(r, :meaning))],
      ["ref", row_scalar(get(r, :ref))],
      ["status", ":#{get(r, :status)}"]
    ]
    "vocab(#{scm_string(get(r, :verb))}, #{row_fields(fields)})"
  else
    "lateral(#{scm_string(get(r, :name))}, #{row_fields([["battery", row_scalar(get(r, :battery))]])})"
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
    (r) -> get(r, :verb),
    filter((r) -> get(r, :space) == space, get(g, :verbs))
  )
  edges = sort_keyed(
    (e) -> "#{get(e, :rel)}\t#{get(e, :to)}\t#{get(e, :from)}",
    filter((e) -> node_space(get(e, :from)) == space, get(g, :edges))
  )
  s = first(filter((r) -> get(r, :name) == space, get(g, :spaces)))
  join(
    map(
      (r) -> "#{row_source(r)}\n",
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
              (r) -> "#{row_source(r)}\n",
              sort_keyed((v) -> get(v, :verb), get(g, :vocab))
            ),
            ""
          )
        ]
      ],
      if is_empty(get(g, :laterals))
        []
      else
        [
          [
            "laterals.b",
            join(
              map(
                (r) -> "#{row_source(r)}\n",
                sort_keyed((l) -> get(l, :name), get(g, :laterals))
              ),
              ""
            )
          ]
        ]
      end
    ),
    map(
      fn(s)
        [graph_file_name(get(s, :name)), space_file_text(g, get(s, :name))]
      end,
      sort_keyed((s) -> get(s, :name), get(g, :spaces))
    )
  )
end

def import_refusals(g)
  spaces = map((s) -> get(s, :name), get(g, :spaces))
  concat_lists(
    get(g, :refusals),
    map(
      fn(e)
        refusal(
          :orphan_edge,
          "#{get(e, :from)} #{get(e, :rel)} #{get(e, :to)}: the file of its `from` space does not exist"
        )
      end,
      filter(
        (e) -> not member?(node_space(get(e, :from)), spaces),
        get(g, :edges)
      )
    )
  )
end

# ── tests ──────────────────────────────────────────────────────────────────

test "a def header broken over lines is catalogued as one signature"
  src = "# Does it.\ndef long_one(\n  alpha,\n  beta\n) -> Int\n  1\nend\n"
  assert entries_of_text(src) ==
    [["long_one", "long_one(alpha, beta) -> Int", ["Does it."], []]]
end

test "a definition with no parameters is catalogued bare"
  src = "def alphabet()\n  1\nend\n\ndef typed() -> Int\n  1\nend\n\ndef inc(x)\n  x\nend\n"
  assert map((e) -> nth(1, e), entries_of_text(src)) ==
    ["alphabet", "typed -> Int", "inc(x)"]
end

test "a manifest yields its name, version and needs"
  m = parse_manifest("package(\"kazu\", \"0.1.0\")\nneeds(\"retsu\", \"^0.1\")\nneeds(\"moji\", \"^0.1\")\n")
  assert m == ["kazu", "0.1.0", ["retsu", "moji"]]
end

test "a manifest with no needs has an empty needs list"
  m = parse_manifest("package(\"deeta\", \"0.1.0\")\n")
  assert is_empty(nth(2, m)) == true
  assert nth(0, m) == "deeta"
end

test "a comment documents a def only when it sits directly above it"
  text = "# ── section ──\n\n# Adds one.\n# Twice as useful.\ndef inc(x)\n  x + 1\nend\n\ndef bare(y)\n  y\nend\n"
  es = entries_of_text(text)
  assert size(es) == 2
  assert first(es) == ["inc", "inc(x)", ["Adds one.", "Twice as useful."], []]
  assert is_empty(last(last(es))) == true
end

test "the gloss is the first comment line"
  assert gloss_of_text("use(\"retsu\")\n# kazu (数): numbers.\n# more\n") ==
    "kazu (数): numbers."
  assert gloss_of_text("def f()\n  1\nend\n") == ""
end

test "tests are counted by their opening line"
  assert tests_in_text("test \"a\"\n  assert 1 == 1\nend\ntest \"b\"\nend\n") ==
    2
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
  assert name_collisions([a, b, c]) == [["size", ["a", "b"]]]
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
  assert names_shadowing([a], ["member", "get"]) == [["member", "a"]]
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
  text = "legacy_names(\"0.1.1\", \"q\")\n\n# Counts.\n# waive B0013: count is a builtin\ndef q_count(xs)\n  0\nend\n\n# Joins.\ndef join_all(xs)\n  xs\nend\n"
  es = entries_of_text(text)
  assert first(es) == ["q_count", "q_count(xs)", ["Counts."], ["B0013"]]
  assert legacy_prefix_of_text(text) == "q"
  r = ["kueri", "0.1.1", [], "", es, 0, "q"]
  assert other_name(r, first(es)) == "`kueri::count`"
  assert other_name(r, last(es)) == "`q_join_all` (old)"
end

test "test blocks are read with their titles and bodies; other lines are not"
  text = "def f(x)\n  x\nend\n\ntest \"f is identity\"\n  assert f(1) == 1\n  assert f(2) == 2\nend\n\ntest \"empty\"\nend\n"
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
            nth(0, v),
            nth(1, v),
            "pure",
            "#{nth(1, v)}(value) -> value",
            "-",
            "-",
            "absent",
            nth(2, v),
            to_s(nth(3, v))
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
  map((f) -> "#{get(f, :kind)} #{get(f, :subject)}", graph_findings(g))
end

test "a catalogue keeps the packages the ledger names and skips the rest"
  ledger = "| `alpha` | a |\n| `beta` | b |\n"
  records = [["alpha", "0.1.0"], ["gamma", "0.1.0"], ["beta", "0.2.0"]]
  assert registered_only(ledger, records) ==
    [["alpha", "0.1.0"], ["beta", "0.2.0"]]
  assert registered_only(ledger, []) == []
end

test "a name that only appears inside another row's text is not registered"
  ledger = "| `alpha` | gamma and `gamma` are mentioned here |\n"
  assert registered_only(ledger, [["gamma", "0.1.0"]]) == []
end

test "a graph that breaks no gate has no finding"
  g = fx_graph(
    [
      ["a", "read", "whole content of a file", 1],
      ["a", "write", "replace a file", 1]
    ],
    [["a::write", "requires", "a::read", "needs it"]],
    ["read", "write"]
  )
  assert get(g, :refusals) == []
  assert graph_findings(g) == []
end

test "g1 names two verbs of one space whose meanings differ only in stop words and case"
  g = fx_graph(
    [
      ["a", "read", "Whole content of a file", 1],
      ["a", "slurp", "the whole content of the file", 1],
      ["b", "load", "whole content of a file", 1]
    ],
    [["a::read", "requires", "b::load", "x"]],
    ["read", "slurp", "load"]
  )
  assert fx_kinds(g) == ["g1-meaning a::read a::slurp"]
end

test "g1 keeps word order: the same words in another order are another meaning"
  g = fx_graph(
    [["a", "take", "item from list", 1], ["a", "pull", "list from item", 1]],
    [["a::take", "pairs", "a::pull", "x"]],
    ["take", "pull"]
  )
  assert graph_findings(g) == []
end

test "g1 is silenced by a refines, generalizes or inverse edge, and by nothing else"
  rows = [["a", "read", "whole content", 1], ["a", "slurp", "whole content", 1]]
  known = ["read", "slurp"]
  assert fx_kinds(fx_graph(rows, [], known)) == ["g1-meaning a::read a::slurp"]
  assert fx_kinds(
    fx_graph(rows, [["a::slurp", "refines", "a::read", "x"]], known)
  ) == []
  assert fx_kinds(
    fx_graph(rows, [["a::read", "generalizes", "a::slurp", "x"]], known)
  ) == []
  assert fx_kinds(
    fx_graph(rows, [["a::read", "inverse", "a::slurp", "x"]], known)
  ) == []
  assert fx_kinds(
    fx_graph(rows, [["a::read", "pairs", "a::slurp", "x"]], known)
  ) == ["g1-meaning a::read a::slurp"]
end

test "g2 names a verb with no vocabulary row"
  g = fx_graph(
    [["a", "read", "one", 1], ["a", "fetch", "two", 1]],
    [["a::read", "pairs", "a::fetch", "x"]],
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
      ["a::p", "composes", "a::q", "x"],
      ["a::q", "requires", "a::r", "x"],
      ["a::r", "composes", "a::p", "x"],
      ["a::s", "composes", "a::p", "enters the cycle"]
    ],
    ["p", "q", "r", "s"]
  )
  assert fx_kinds(g) == ["g4-cycle a::p", "g4-cycle a::q", "g4-cycle a::r"]
end

test "g4 names an edge to a later wave, and only for composes and requires"
  g = fx_graph(
    [["a", "p", "one", 1], ["a", "q", "two", 3]],
    [["a::p", "composes", "a::q", "x"]],
    ["p", "q"]
  )
  assert fx_kinds(g) == ["g4-wave a::p -> a::q"]
  assert fx_kinds(
    fx_graph(
      [["a", "p", "one", 1], ["a", "q", "two", 3]],
      [["a::p", "pairs", "a::q", "x"]],
      ["p", "q"]
    )
  ) == []
end

test "g7 names a verb with two inverse partners, however the edges are written"
  rows = [
    ["a", "put", "one", 1],
    ["a", "del", "two", 1],
    ["a", "has", "three", 1]
  ]
  known = ["put", "del", "has"]
  assert fx_kinds(
    fx_graph(
      rows,
      [
        ["a::put", "inverse", "a::del", "x"],
        ["a::has", "inverse", "a::put", "x"]
      ],
      known
    )
  ) == ["g7-inverse a::put"]
  assert fx_kinds(
    fx_graph(
      rows,
      [
        ["a::put", "inverse", "a::del", "x"],
        ["a::del", "inverse", "a::put", "x"]
      ],
      known
    )
  ) == []
end

test "g9 names an endpoint that is no verb and a relation outside the closed set"
  g = fx_graph(
    [["a", "p", "one", 1]],
    [["a::p", "composes", "a::gone", "x"], ["a::p", "frobs", "a::p", "x"]],
    ["p"]
  )
  assert fx_kinds(g) == ["g9-dangling a::gone", "g9-relation a::p frobs a::p"]
end

test "a retired verb keeps its row and is not held to g1 or g2"
  g = fx_graph(
    [["a", "read", "one", 1], ["a", "slurp", "one", 1]],
    [["a::read", "pairs", "a::slurp", "x"]],
    ["read"]
  )
  off = assoc(
    g,
    :verbs,
    map(
      fn(r)
        if get(r, :verb) == "slurp"
          assoc(r, :enabled, false)
        else
          r
        end
      end,
      get(g, :verbs)
    )
  )
  assert fx_kinds(off) == []
end

test "the ratchet: recorded debt holds or shrinks, and a new or grown count is a failure"
  g = fx_graph(
    [["a", "p", "one", 1], ["a", "q", "two", 1], ["b", "r", "three", 1]],
    [["a::p", "pairs", "a::q", "x"], ["a::q", "pairs", "b::r", "x"]],
    []
  )
  found = graph_findings(g)
  base = graph_baseline(found)
  assert base == "g2-vocab: a 2\ng2-vocab: b 1\n"
  assert graph_verdict(found, base) == []
  assert graph_verdict(found, "g2-vocab: a 3\ng2-vocab: b 1\n") == []
  assert graph_shrunk(found, "g2-vocab: a 3\ng2-vocab: b 1\n") ==
    ["g2-vocab: a"]
  assert kinds(graph_verdict(found, "g2-vocab: a 1\ng2-vocab: b 1\n")) ==
    [:grew]
  assert kinds(graph_verdict(found, "g2-vocab: a 2\n")) == [:unrecorded]
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
  rows = concat_lists([space], concat_lists(get(g, :verbs), get(g, :edges)))
  parsed = file_graph("a.b", join(map((r) -> "#{row_source(r)}\n", rows), ""))
  assert get(parsed, :refusals) == []
  assert get(parsed, :rows) == rows
  voc = file_graph(
    "vocab.b",
    join(map((r) -> "#{row_source(r)}\n", get(g, :vocab)), "")
  )
  assert get(voc, :refusals) == []
  assert get(voc, :rows) == get(g, :vocab)
  assert size(get(voc, :rows)) == 1
end

test "a row file is data: a word that is not a row word is refused, never run"
  r = file_graph(
    "a.b",
    "space(\"a\", {status: :ratified})\nwrite_file(\"x\", \"y\")\n"
  )
  assert kinds(get(r, :refusals)) == [:unknown_word]
  assert size(get(r, :rows)) == 1
end

test "a row file holds only literals: a name, a call or an operator in a value is a syntax refusal"
  assert kinds(
    get(file_graph("a.b", "space(\"a\", {status: ratified})\n"), :refusals)
  ) == [:row_syntax]
  assert kinds(
    get(file_graph("a.b", "space(\"a\", {status: 1 + 2})\n"), :refusals)
  ) == [:row_syntax]
  assert kinds(
    get(file_graph("a.b", "space(\"a\", {status: f(1)})\n"), :refusals)
  ) == [:row_syntax]
  assert kinds(
    get(file_graph("a.b", "space(\"a\", {status: \"x\n"), :refusals)
  ) == [:row_syntax]
end

test "a bad row is refused alone: its siblings load"
  r = file_graph(
    "a.b",
    "space(\"a\", {status: :ratified})\nspace(\"b\", {status: :nope})\nspace(\"c\", {status: :provisional, color: 1})\n"
  )
  assert size(get(r, :rows)) == 1
  assert kinds(get(r, :refusals)) == [:bad_row, :bad_row]
end

test "a file holds the rows of its own space only, and the edges that start there"
  r = file_graph(
    "a.b",
    "space(\"a\", {status: :ratified})\nedge(\"b::x\", :pairs, \"a::y\", \"w\")\nvocab(\"v\", {subject: \"s\", args: [], opts: false, returns: \"r\", raises: [], kind: :pure, meaning: \"m\", ref: nil, status: :open})\n"
  )
  assert kinds(get(r, :refusals)) == [:misplaced, :misplaced]
end

test "a duplicate verb, space, vocabulary row or edge is refused by name"
  g = fx_graph(
    [["a", "p", "one", 1], ["a", "p", "two", 1]],
    [["a::p", "pairs", "a::p", "w"], ["a::p", "pairs", "a::p", "w"]],
    ["p", "p"]
  )
  assert map(why, get(g, :refusals)) ==
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
  v = {args: ["a", "b?"], opts: false}
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
    "#{head}#{tsv_join(row)}\n",
    tsv_text(edge_header, []),
    voc
  )
  assert kinds(get(g, :refusals)) == [:derived]
  assert get(g, :verbs) == []
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
  assert get(g, :refusals) == []
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
    tsv_text(edge_header, [["b?::q", "pairs", "a::p", "w"]]),
    tsv_text(vocab_header, [])
  )
  files = graph_writes(g)
  assert map(first, files) == ["vocab.b", "a.b", "b-provisional.b"]
  b = file_graph("b-provisional.b", nth(1, nth(2, files)))
  assert get(b, :refusals) == []
  assert map((r) -> get(r, :word), get(b, :rows)) == ["space", "verb", "edge"]
  assert get(first(get(b, :rows)), :status) == "provisional"
end

def ux_graph(rows)
  graph_from_tsv(
    tsv_text(
      verb_header_region,
      map(
        fn(r)
          [
            "T",
            nth(0, r),
            nth(1, r),
            "pure",
            "#{nth(1, r)}(value) -> value",
            "-",
            "-",
            nth(2, r),
            nth(3, r),
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
    ["moji", "lower", "exists:moji", "one"],
    ["moji", "ghost", "partial:moji", "two"],
    ["moji", "void", "absent", "three"],
    ["kazu", "abs", "exists", "four"],
    ["gauge?", "gauge", "exists:moji", "five"]
  ]
end

test "the probe names every exists row of a named space, once, and nothing else"
  src = probe_source(ux_graph(ux_rows))
  assert contains?(src, "use(\"kazu\")\nuse(\"moji\")\n")
  assert contains?(src, "kazu::abs")
  assert contains?(src, "moji::lower")
  assert not contains?(src, "ghost")
  assert not contains?(src, "void")
  assert not contains?(src, "gauge")
  assert size(split(src, "moji::lower")) == 2
end

test "the probe of a graph with no exists row is an empty list"
  src = probe_source(ux_graph([["moji", "ghost", "partial:moji", "two"]]))
  assert src == "\ndef probe()\n  []\nend\n"
end

test "unbound_names reads the B0011 lines and nothing else"
  out = "typed declarations: 0\nnames resolved:     9\n/p/probe.b:3:4: error[B0011]: bidama `moji` defines no `nothere`\n  help: nothing in `moji` is close to `nothere`\n/p/probe.b:3:9: error[B0011]: bidama `retsu` defines no `zzz`\n/p/probe.b:1:1: error[B0015]: `use(\"kijun\")` is out of order\n/p/probe.b:3:2: error[B0010]: `retsu::first` is qualified by `retsu`, which this file does not `use`\n"
  assert unbound_names(out) == ["moji::nothere", "retsu::zzz"]
  assert unbound_names("") == []
  assert unbound_names("names resolved:     9\n") == []
end

test "finds_unbound reports an exists row once and ignores any other row"
  g = ux_graph(ux_rows)
  found = finds_unbound(
    g,
    [
      "moji::lower",
      "kazu::abs",
      "moji::lower",
      "moji::ghost",
      "moji::void",
      "zzz::none"
    ]
  )
  assert map((f) -> get(f, :subject), found) == ["kazu::abs", "moji::lower"]
  assert map((f) -> get(f, :kind), found) == ["g10-unbound", "g10-unbound"]
  assert map((f) -> get(f, :scope), found) == ["kazu", "moji"]
  assert finds_unbound(g, []) == []
end

test "g10-unbound is a kind the baseline measures"
  assert member?("g10-unbound", finding_kinds)
  found = finds_unbound(ux_graph(ux_rows), ["moji::lower"])
  assert map((m) -> get(m, :key), finding_measurements(found, "g10-unbound")) ==
    ["moji"]
end
