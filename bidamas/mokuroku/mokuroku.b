use("retsu")
use("junjo")
use("shuugou")
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
  needs = map(fn(part) first(split(part, "\"")) end, rest(split(text, "needs(\"")))
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
  join(take_while(fn(c) c != "(" && c != " " end, drop(4, chars(line))), "")
end

# [def_name, signature, doc_lines] for every top-level def in a source text.
# A comment block documents a def only when it sits directly above it; a blank
# line or any code in between resets it, so section banners attach to nothing.
def entries_of_text(text)
  state = reduce(fn(acc, line)
    pending = first(acc)
    found = last(acc)
    if starts_with?(line, "#")
      [push(pending, comment_text(line)), found]
    elsif starts_with?(line, "def ")
      [[], push(found, [defined_name(line), join(drop(4, chars(line)), ""), pending])]
    else
      [[], found]
    end
  end, [[], []], split(text, "\n"))
  last(state)
end

# The package's gloss: the first comment line of its source.
def gloss_of_text(text)
  comment = find_first(fn(l) starts_with?(l, "#") end, split(text, "\n"))
  if comment == nil
    ""
  else
    comment_text(comment)
  end
end

def tests_in_text(text)
  count_where(fn(l) starts_with?(l, "test \"") end, split(text, "\n"))
end

# ── reading a root ─────────────────────────────────────────────────────────

def blue_path_roots(blue_path)
  filter(fn(r) r != "" end, split(blue_path, ":"))
end

# Package directories under a root: any directory holding a Bluefile.
def package_dirs(root)
  map(fn(p) path_dirname(p) end, filter(fn(p) ends_with?(p, "/Bluefile") end, walk_dir(root)))
end

def package_record(dir)
  manifest = parse_manifest(read_file(concat(dir, "/Bluefile")))
  texts = map(fn(p) read_file(p) end, filter(fn(p) ends_with?(p, ".b") && path_dirname(p) == dir end, walk_dir(dir)))
  all_text = join(texts, "\n")
  [nth(0, manifest), nth(1, manifest), nth(2, manifest), gloss_of_text(all_text), entries_of_text(all_text), tests_in_text(all_text)]
end

# Every package under the roots, sorted by name. When two roots hold the same
# package, the earlier root wins, as it does for the loader.
def catalog_of(roots)
  records = flat_map(fn(root) map(fn(d) package_record(d) end, package_dirs(root)) end, roots)
  firsts = reduce(fn(acc, r)
    if contains(map(fn(x) first(x) end, acc), first(r))
      acc
    else
      push(acc, r)
    end
  end, [], records)
  sort_by(fn(r) first(r) end, firsts)
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

def catalog_def_count(records)
  reduce(fn(acc, r) acc + size(pkg_entries(r)) end, 0, records)
end

# ── the namespace gates ────────────────────────────────────────────────────

# [def_name, owner] for every definition, once per package.
def definition_owners(records)
  flat_map(fn(r) map(fn(n) [n, pkg_name(r)] end, unique(map(fn(e) first(e) end, pkg_entries(r)))) end, records)
end

# [def_name, [packages…]] for every name more than one package defines.
def name_collisions(records)
  pairs = definition_owners(records)
  names = unique(map(fn(p) first(p) end, pairs))
  groups = map(fn(n) [n, map(fn(p) last(p) end, filter(fn(p) first(p) == n end, pairs))] end, names)
  filter(fn(g) size(last(g)) > 1 end, groups)
end

# The collisions that involve at least one of `owned` (a private distribution
# checking itself against everything it composes with).
def name_collisions_touching(records, owned)
  filter(fn(g) some(fn(pkg) contains(owned, pkg) end, last(g)) end, name_collisions(records))
end

# [def_name, package] for every definition that reuses one of `names`.
def names_shadowing(records, names)
  filter(fn(p) contains(names, first(p)) end, definition_owners(records))
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

def def_row(e)
  "| `#{md_cell(nth(1, e))}` | #{md_cell(first_line_or_blank(last(e)))} |"
end

def package_section(r)
  rows = map(fn(e) def_row(e) end, pkg_entries(r))
  join(concat_lists(["## #{pkg_name(r)}", "", "`#{pkg_name(r)}` #{pkg_version(r)} · needs: #{pkg_needs_text(r)}", "", md_cell(pkg_gloss(r)), "", "| definition | what it does |", "|---|---|"], rows), "\n")
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
  body = map(fn(r) package_section(r) end, records)
  "#{join(concat_lists(header, map(fn(r) pkg_summary_row(r) end, records)), "\n")}\n\n#{join(body, "\n\n")}\n"
end

# Write the catalogue of every root on BLUE_PATH to `path`.
def write_catalog(path)
  write_file(path, render_markdown(catalog_of(blue_path_roots(getenv("BLUE_PATH", "")))))
end

# ── tests ──────────────────────────────────────────────────────────────────

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
  assert first(es) == ["inc", "inc(x)", ["Adds one.", "Twice as useful."]]
  assert is_empty(last(last(es))) == true
end

test "the gloss is the first comment line"
  assert gloss_of_text("use(\"retsu\")\n# kazu (数): numbers.\n# more\n") == "kazu (数): numbers."
  assert gloss_of_text("def f()\n  1\nend\n") == ""
end

test "tests are counted by their opening line"
  assert tests_in_text("test \"a\"\n  assert 1 == 1\nend\ntest \"b\"\nend\n") == 2
end

test "two packages defining one name is a collision; distinct names are not"
  a = ["a", "0.1.0", [], "", [["size", "size(xs)", []], ["only_a", "only_a()", []]], 0]
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
  a = ["a", "0.1.0", [], "", [["member", "member(x)", []], ["fine", "fine()", []]], 0]
  assert names_shadowing([a], ["member", "get"]) == [["member", "a"]]
end

test "a pipe inside a table cell is escaped"
  assert md_cell("a || b") == "a \\|\\| b"
end

test "the rendered catalogue names every package and counts its definitions"
  a = ["alpha", "0.2.0", ["retsu"], "alpha: first.", [["f", "f(x)", ["Does f."]]], 1]
  md = render_markdown([a])
  assert contains?(md, "1 packages and 1 definitions") == true
  assert contains?(md, "## alpha") == true
  assert contains?(md, "| `f(x)` | Does f. |") == true
end
