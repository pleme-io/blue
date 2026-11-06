@moduledoc """
tree: move flat bidamas under a root, as docs/BIDAMA-COHESION.md section 6
lays out. `blue gen/tree.b move ROOT CHILD...` moves each child to
`bidamas/ROOT/CHILD` without its Bluefile, writes the root's Bluefile with one
`legacy_packages` row per child, and runs `blue check --fix --only B0074` on
every `.b` file that names a child, so callers move to the new path. A root that
already exists keeps its own rows and takes its new levels' `needs` and `reach`
(`adopted_bluefile`). The root's
`@moduledoc`, its NAMES.md row and `zenbu` stay the author's.
"""

use("junjo", [:sort])
use("moji", %i[after_first before_first lines])
use("retsu", %i[concat_lists first last size take_while])
use("shisutemu", %i[status_of stderr_of])

@doc """
legacy_rows: the `legacy_packages` rows of a root over its children.

    contains?(legacy_rows("fam", %w[a b]), "fam/b") #=> true
"""
def legacy_rows(root, children)
  "[#{join(map((c) -> "[\"#{c}\", \"#{root}/#{c}\"]", children), ", ")}]"
end

@doc """
root_bluefile: the Bluefile of a new root over its children, at 0.1.0.

    starts_with?(root_bluefile("fam", ["a"], "0.1.2"), "package(") #=> true
"""
def root_bluefile(root, children, version)
  unlines(
    [
      "package(\"#{root}\", \"#{version}\")",
      "legacy_packages(\"#{version}\", #{legacy_rows(root, children)})"
    ]
  )
end

@doc """
version_rank: a version as one number that orders as the version does.

    version_rank("0.1.10") > version_rank("0.1.9") #=> true
"""
def reach_words(text)
  rows = filter((l) -> starts_with?(l, "reach("), lines(text))
  if rows == []
    []
  else
    filter(
      (w) -> w != "",
      split(before_first(after_first(first(rows), "%i["), "]"), " ")
    )
  end
end

def first_per_name(rows)
  reduce(
    fn(acc, r)
      if member?(row_name(r, "needs("), map((a) -> row_name(a, "needs("), acc))
        acc
      else
        concat_lists(acc, [r])
      end
    end,
    [],
    rows
  )
end

@doc """
adopted_bluefile: an existing root's Bluefile once its children move under it:
its own rows, one `legacy_packages` row, every child's `needs` but on a sibling
or the root, and one `reach` over every capability the tree held.

    starts_with?(adopted_bluefile("", "k", ["a"], [], "0.1.1"), "package(") #=> true
"""
def adopted_bluefile(root_text, root, children, child_texts, version)
  rows = lines(root_text)
  head? = fn(l)
    any?((h) -> starts_with?(l, h), %w[package( needs( reach( legacy_packages(])
  end
  outside = fn(r)
    not member?(row_name(r, "needs("), concat_lists(children, [root]))
  end
  needs = sort(
    first_per_name(
      filter(
        outside,
        filter(
          (l) -> starts_with?(l, "needs("),
          concat_lists(rows, retsu::flat_map(child_texts, lines))
        )
      )
    )
  )
  reach = sort(
    distinct(
      retsu::flat_map(concat_lists([root_text], child_texts), reach_words)
    )
  )
  reach_row = if reach == []
    []
  else
    ["reach(%i[#{join(reach, " ")}])"]
  end
  head = [
    "package(\"#{root}\", \"#{version}\")",
    "legacy_packages(\"#{version}\", #{legacy_rows(root, children)})"
  ]
  unlines(
    concat_lists(
      concat_lists(head, needs),
      concat_lists(reach_row, filter((l) -> l != "" and not head?(l), rows))
    )
  )
end

test "an adopted root keeps its rows, drops needs on its new levels and gains theirs"
  root = unlines(
    [
      "package(\"kaaneru\", \"0.1.0\")",
      "needs(\"baito\", \"^0.1\")",
      "needs(\"bpf\", \"^0.1\")",
      "needs(\"retsu\", \"^0.1\")",
      "reach(%i[filesystem kernel_bpf])"
    ]
  )
  bpf = unlines(
    [
      "package(\"bpf\", \"0.1.0\")",
      "needs(\"btf\", \"^0.1\")",
      "needs(\"jisho\", \"^0.1\")",
      "needs(\"retsu\", \"^0.2\")"
    ]
  )
  btf = unlines(["package(\"btf\", \"0.1.0\")", "reach(%i[filesystem net])"])
  out = lines(
    adopted_bluefile(root, "kaaneru", %w[bpf btf], [bpf, btf], "0.1.1")
  )
  assert out[0] == "package(\"kaaneru\", \"0.1.1\")"
  assert starts_with?(
    out[1],
    "legacy_packages(\"0.1.1\", [[\"bpf\", \"kaaneru/bpf\"]"
  )
  assert member?("needs(\"jisho\", \"^0.1\")", out)
  assert member?("needs(\"retsu\", \"^0.1\")", out)
  assert not member?("needs(\"retsu\", \"^0.2\")", out)
  assert not any?(
    (l) -> contains?(l, "needs(\"bpf\"") or contains?(l, "needs(\"btf\""),
    out
  )
  assert member?("reach(%i[filesystem kernel_bpf net])", out)
  assert nth(
    0,
    lines(adopted_bluefile("package(\"k\", \"0.1.0\")", "k", [], [], "0.1.0"))
  ) == "package(\"k\", \"0.1.0\")"
end

def version_rank(v)
  parts = map(to_int, split(v, "."))
  parts[0] * 1_000_000 + parts[1] * 1000 + parts[2]
end

@doc """
root_version: the version a root takes over its children: the highest, so
every child's `legacy_names` window stays open under it.

    root_version(%w[0.1.0 0.1.2 0.1.1]) #=> "0.1.2"
"""
def root_version(versions)
  last(junjo::sort_by(version_rank, versions))
end

def package_version(dir)
  text = read_file(path_join(dir, "Bluefile"))
  before_first(after_first(after_first(text, ","), "\""), "\"")
end

@doc """
names_a_child?: whether a file's text names one of the children by `use` or a qualifier.

    names_a_child?("a::x", ["a"]) #=> true
    names_a_child?("b::x", ["a"]) #=> false
"""
def names_a_child?(text, children)
  any?(
    (c) -> contains?(text, "\"#{c}\"") or contains?(text, "#{c}::"),
    children
  )
end

@doc """
row_name: the package a `use("…")` or `needs("…")` line names, or nil.

    row_name("# waive", "use(") #=> nil
"""
def row_name(line, head)
  if starts_with?(line, "#{head}\"")
    before_first(after_first(line, "\""), "\"")
  end
end

def peel_waivers(head, tail)
  if head != [] and starts_with?(last(head), "# waive")
    peel_waivers(take(size(head) - 1, head), concat_lists([last(head)], tail))
  else
    [head, tail]
  end
end

@doc """
with_root_row: lines with every row of a child (bare or under the root) gone and
one row for the root in sorted place, before the waivers of the row it precedes.

    with_root_row(%w[x y], "use(", "f", ["k"], "e") rescue :refused #=> :refused
"""
def with_root_row(lines, head, root, children, entry)
  gone = concat_lists(children, map((c) -> "#{root}/#{c}", children))
  child_row? = (l) -> member?(row_name(l, head), gone)
  lines = filter((l) -> row_name(l, head) != root, lines)
  listed = sort(
    map(
      (l) -> "#{head}\"#{root}/#{after_first(after_first(l, "\""), "/")}",
      filter((l) -> child_row?(l) and not ends_with?(l, "\")"), lines)
    )
  )
  kept = reduce(
    fn(acc, l)
      if child_row?(l)
        first(peel_waivers(acc, []))
      else
        concat_lists(acc, [l])
      end
    end,
    [],
    lines
  )
  before = take_while(
    fn(l)
      n = row_name(l, head)
      n.nil? or n != root and first(sort([n, root])) == n
    end,
    kept
  )
  if size(before) == size(kept)
    raise(:tree, "no #{head} row sorts after #{root}; place it by hand")
  end
  split_at = peel_waivers(before, [])
  concat_lists(
    first(split_at),
    concat_lists(
      concat_lists([entry], listed),
      concat_lists(last(split_at), drop(size(before), kept))
    )
  )
end

@doc """
level_note: a child's ledger row read as one level of its root: name, kanji and the gloss's head word.

    level_note("| `a` | エー | aye — more | 2026 | KEEP | s |") #=> "`a` (エー, aye)"
"""
def level_note(row)
  cells = split(row, " | ")
  "#{after_first(first(cells), "| ")} (#{cells[1]}, #{before_first(cells[2], " — ")})"
end

@doc """
ledger_rows: the ledger with each child's row folded into one row for the root, where the first child's row was.

    ledger_rows(["x"], "r", "ア", "2026", "g", "s", ["c"]) #=> ["x"]
"""
def ledger_rows(rows, root, kanji, date, gloss, sweep, children)
  h = position("## The ledger", rows) + 1
  concat_lists(
    map((l) -> keyed_under(l, root, children), take(h, rows)),
    fold_rows(drop(h, rows), root, kanji, date, gloss, sweep, children)
  )
end

@doc """
keyed_under: a prefix or moved-name row of a child, keyed by its level path, its targets rehomed; any other line as it is.

    keyed_under("| `k` | `old` | `k::new` | 0.1.1 |", "f", ["k"]) #=> "| `f/k` | `old` | `f::k::new` | 0.1.1 |"
    keyed_under("| `z` | `old` | `k::new` | 0.1.1 |", "f", ["k"]) #=> "| `z` | `old` | `k::new` | 0.1.1 |"
"""
def keyed_under(line, root, children)
  child = retsu::find_first((c) -> starts_with?(line, "| `#{c}` |"), children)
  if child.nil?
    line
  else
    rest = after_first(line, "| `#{child}` |")
    "| `#{root}/#{child}` |#{rehome(rest, root, children)}"
  end
end

def fold_rows(rows, root, kanji, date, gloss, sweep, children)
  mine = (l) -> any?((c) -> starts_with?(l, "| `#{c}` |"), children)
  notes = map(level_note, filter(mine, rows))
  if notes == []
    rows
  else
    row = "| `#{root}` | #{kanji} | #{gloss}. Its levels: #{join(notes, ", ")} | #{date} | KEEP | #{sweep} |"
    at = size(take_while((l) -> not mine(l), rows))
    concat_lists(
      take(at, rows),
      concat_lists([row], filter((l) -> not mine(l), drop(at, rows)))
    )
  end
end

def ledger(root, kanji, date, gloss, sweep, children)
  path = "bidamas/NAMES.md"
  write_file(
    path,
    unlines(
      ledger_rows(
        lines(read_file(path)),
        root,
        kanji,
        date,
        gloss,
        sweep,
        children
      )
    )
  )
end

@doc """
rehome: text with every `child::` that starts a path written `root::child::`, so
the strings a fix cannot see (a `legacy_names` target, a doc's example) follow the move.

    rehome("see `kid::go` and fam::kid::x", "fam", ["kid"]) #=> "see `fam::kid::go` and fam::kid::x"
"""
def rehome(text, root, children)
  reduce(
    fn(acc, c)
      pieces = split(acc, "#{c}::")
      reduce(
        fn(out, piece)
          tail = chars(out)
          escaped = size(tail) >= 2 and
            tail[size(tail) - 2] == "\\" and
            member?(last(tail), %w[n t])
          starts_path = tail == [] or
            escaped or
            not member?(
              last(tail),
              chars("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_:/")
            )
          if starts_path
            "#{out}#{root}::#{c}::#{piece}"
          else
            "#{out}#{c}::#{piece}"
          end
        end,
        first(pieces),
        drop(1, pieces)
      )
    end,
    text,
    children
  )
end

@doc """
callers_of: every `.b` file under bidamas/, gen/, examples/, nix/ and native/ that names a child, the verb graph's rows aside: they name spaces, not paths.

    callers_of([]) #=> []
"""
def callers_of(children)
  filter(
    fn(p)
      ends_with?(p, ".b") and
        not contains?(p, "/target/") and
        not contains?(p, "mokuroku/graph/") and
        names_a_child?(read_file(p), children)
    end,
    retsu::flat_map(
      filter(is_dir?, %w[bidamas gen examples nix native crates spec]),
      walk_dir
    )
  )
end

@doc """
debt_rows: test-beside's recorded rows with each child's `untested: c N` folded
into one row for the root, holding their sum, in sorted place.

    debt_rows(["def recorded()"], "f", ["k"]) #=> ["def recorded()"]
"""
def debt_rows(lines, root, children)
  count = fn(l)
    words = split(after_first(l, "untested: "), " ")
    if member?(first(words), children)
      to_int(before_first(words[1], "\""))
    else
      0
    end
  end
  child? = (l) -> contains?(l, "\"untested: ") and count(l) > 0
  total = reduce((acc, l) -> acc + count(l), 0, lines)
  kept = filter((l) -> not child?(l), lines)
  if total == 0
    kept
  else
    row = "      \"untested: #{root} #{to_s(total)}\","
    at = size(
      take_while(
        fn(l)
          not contains?(l, "\"untested: ") or
            first(
              sort([before_first(after_first(l, "untested: "), " "), root])
            ) != root
        end,
        kept
      )
    )
    concat_lists(take(at, kept), concat_lists([row], drop(at, kept)))
  end
end

def debt(root, children)
  path = "gen/test-beside.b"
  write_program(
    path,
    unlines(debt_rows(lines(read_file(path)), root, children))
  )
end

def mutation_sets(root, children)
  dir = "bidamas/heni/mutations"
  map(
    fn(c)
      from = path_join(dir, "#{c}.json")
      if is_file?(from)
        mkdir_p(path_join(dir, root))
        must(
          exec_capture("git", "mv", from, path_join(dir, "#{root}/#{c}.json")),
          "git mv #{from}"
        )
      end
    end,
    children
  )
  map(
    (p) -> write_file(p, rehome(read_file(p), root, children)),
    filter((p) -> ends_with?(p, ".json"), walk_dir(dir))
  )
end

@doc """
moved_paths: text with each `bidamas/<child>/` written `bidamas/<root>/<child>/`.

    moved_paths("see bidamas/kid/x.b and bidamas/fam/kid/y", "fam", ["kid"]) #=> "see bidamas/fam/kid/x.b and bidamas/fam/kid/y"
"""
def moved_paths(text, root, children)
  reduce(
    (acc, c) -> replace(acc, "bidamas/#{c}/", "bidamas/#{root}/#{c}/"),
    text,
    children
  )
end

@doc """
embedded_uses: text with each `use` of a child written by its level path, as
code (`use("kid"`) and inside a string (`use(\\"kid\\"`), so a program held in
a string follows the move as code does.

    embedded_uses("no import here", "fam", ["kid"]) #=> "no import here"
"""
def embedded_uses(text, root, children)
  reduce(
    fn(acc, c)
      reduce(
        fn(t, q)
          replace(
            replace(t, "use(#{q}#{c}#{q}", "use(#{q}#{root}/#{c}#{q}"),
            "use(#{q}#{c}/",
            "use(#{q}#{root}/#{c}/"
          )
        end,
        acc,
        ["\"", "\\\""]
      )
    end,
    text,
    children
  )
end

def strings(root, children)
  map(
    fn(p)
      text = read_file(p)
      moved = rehome(embedded_uses(text, root, children), root, children)
      if moved != text
        write_file(p, moved)
      end
    end,
    filter(
      (p) -> ends_with?(p, ".rs") or starts_with?(p, "spec/"),
      tracked_text
    )
  )
end

def tracked_text()
  out = shisutemu::stdout_of(
    must(exec_capture("git", "ls-files"), "git ls-files")
  )
  filter(
    fn(p)
      not ends_with?(p, ".lock") and
        not ends_with?(p, "CATALOG.md") and
        not contains?(p, "llms") and
        not member?(p, %w[AGENTS.md CLAUDE.md]) and
        any?(
          (x) -> ends_with?(p, x),
          %w[.b .rs .md .nix .json Bluefile .yml .tsv]
        )
    end,
    filter((p) -> p != "", lines(out))
  )
end

def paths(root, children)
  map(
    fn(p)
      text = read_file(p)
      moved = moved_paths(text, root, children)
      if moved != text
        write_file(p, moved)
      end
    end,
    tracked_text
  )
end

def rewrite_callers(blue, root, children)
  callers = callers_of(children)
  map(
    fn(p)
      exec_capture(blue, "check", "--fix", "--only", "B0074", p)
      write_file(p, rehome(read_file(p), root, children))
      exec_capture(blue, "check", "--fix", "--only", "B0015", p)
      exec_capture(blue, "fmt", "--write", p)
    end,
    callers
  )
  callers
end

def facade(root, children)
  b = "bidamas/zenbu/zenbu.b"
  write_program(
    b,
    unlines(
      with_root_row(
        lines(read_file(b)),
        "use(",
        root,
        children,
        "use(\"#{root}\")"
      )
    )
  )
  m = "bidamas/zenbu/Bluefile"
  write_file(
    m,
    unlines(
      with_root_row(
        lines(read_file(m)),
        "needs(",
        root,
        children,
        "needs(\"#{root}\", \"^0.1\")"
      )
    )
  )
end

def must(r, what)
  if status_of(r) != 0
    write_stderr(unlines(["❌ tree: #{what}", stderr_of(r)]))
    exit_with(1)
  end
  r
end

def move(blue, root, children)
  dir = path_join("bidamas", root)
  existing = is_file?(path_join(dir, "Bluefile"))
  mkdir_p(dir)
  child_texts = map(
    (c) -> read_file(path_join("bidamas", c, "Bluefile")),
    children
  )
  version = root_version(
    concat_lists(
      map((c) -> package_version(path_join("bidamas", c)), children),
      if existing
        [package_version(dir)]
      else
        []
      end
    )
  )
  root_text = if existing
    adopted_bluefile(
      read_file(path_join(dir, "Bluefile")),
      root,
      children,
      child_texts,
      version
    )
  else
    root_bluefile(root, children, version)
  end
  map(
    fn(c)
      from = path_join("bidamas", c)
      must(
        exec_capture(
          "git",
          "rm",
          "-q",
          "-f",
          path_join(from, "Bluefile"),
          path_join(from, "Bluefile.lock")
        ),
        "git rm #{from}/Bluefile"
      )
      must(exec_capture("git", "mv", from, path_join(dir, c)), "git mv #{from}")
    end,
    children
  )
  write_file(path_join(dir, "Bluefile"), root_text)
  if not is_file?(path_join(dir, "#{root}.b"))
    write_program(
      path_join(dir, "#{root}.b"),
      unlines(
        ["@moduledoc \"\"\"", "#{root}: #{join(children, ", ")}.", "\"\"\""]
      )
    )
  end
  callers = rewrite_callers(blue, root, children)
  facade(root, children)
  debt(root, children)
  mutation_sets(root, children)
  paths(root, children)
  strings(root, children)
  must(exec_capture(blue, "lock", dir, "bidamas/zenbu"), "blue lock #{dir}")
  write_stderr(
    unlines(
      [
        "✅ tree: #{join(children, ", ")} under #{root}; #{to_s(size(callers))} file(s) rewritten through B0074",
        "   next: the root's @moduledoc, one NAMES.md row, zenbu's use and needs, blue lock, gen/regen.b"
      ]
    )
  )
end

def main()
  verb = argv_get(0, "")
  if verb == "move" and size(argv) >= 3
    move(getenv("BLUE", "blue"), argv_get(1), drop(2, argv))
  elsif verb == "facade" and size(argv) >= 3
    facade(argv_get(1), drop(2, argv))
  elsif verb == "callers" and size(argv) >= 3
    rewrite_callers(getenv("BLUE", "blue"), argv_get(1), drop(2, argv))
  elsif verb == "gates" and size(argv) >= 3
    debt(argv_get(1), drop(2, argv))
    mutation_sets(argv_get(1), drop(2, argv))
    paths(argv_get(1), drop(2, argv))
    strings(argv_get(1), drop(2, argv))
  elsif verb == "rehome" and size(argv) >= 3
    map(
      (p) -> write_file(p, rehome(read_file(p), argv_get(1), drop(2, argv))),
      callers_of(drop(2, argv))
    )
  elsif verb == "ledger" and size(argv) >= 7
    ledger(
      argv_get(1),
      argv_get(2),
      argv_get(3),
      argv_get(4),
      argv_get(5),
      drop(6, argv)
    )
  else
    write_stderr(unlines(["usage: blue gen/tree.b move|facade ROOT CHILD..."]))
    exit_with(64)
  end
end

test "a needs row names its package, a comment names none"
  assert row_name("needs(\"kazu\", \"^0.1\")", "needs(") == "kazu"
  assert row_name("use(\"f/k\")", "use(") == "f/k"
end

test "the root's row replaces its children's, before the waiver of the row after it"
  rows = ["use(\"a\")", "use(\"f/k\")", "# waive B0016: kept", "use(\"z\")"]
  assert with_root_row(rows, "use(", "f", ["k"], "use(\"f\")") ==
    ["use(\"a\")", "use(\"f\")", "# waive B0016: kept", "use(\"z\")"]
  listing = ["use(\"a\")", "use(\"f/k\", [:x])", "use(\"g\")"]
  assert with_root_row(listing, "use(", "f", ["k"], "use(\"f\")") ==
    ["use(\"a\")", "use(\"f\")", "use(\"f/k\", [:x])", "use(\"g\")"]
  waived = [
    "use(\"a\")",
    "# waive B0016: kept for k",
    "use(\"k\")",
    "use(\"g\")"
  ]
  assert with_root_row(waived, "use(", "f", ["k"], "use(\"f\")") ==
    ["use(\"a\")", "use(\"f\")", "use(\"g\")"]
  needs = [
    "needs(\"a\", \"^0.1\")",
    "needs(\"f\", \"^0.1.0\")",
    "needs(\"k\", \"^0.1\")",
    "needs(\"z\", \"^0.1\")"
  ]
  assert with_root_row(needs, "needs(", "f", ["k"], "needs(\"f\", \"^0.1\")") ==
    [
      "needs(\"a\", \"^0.1\")",
      "needs(\"f\", \"^0.1\")",
      "needs(\"z\", \"^0.1\")"
    ]
end

test "a family's ledger rows fold into one row where the first stood"
  prefixes = ["| `a` | `a_` | 0.1.1 |", "## The ledger"]
  rows = [
    "| `a` | エー | aye — the first | 2026-10-01 | KEEP | swept |",
    "| `m` | エム | em — between | 2026-10-01 | KEEP | swept |",
    "| `b` | ビー | bee — the second | 2026-10-02 | KEEP | swept |"
  ]
  folded = ledger_rows(
    concat_lists(prefixes, rows),
    "r",
    "ア",
    "2026-11-05",
    "root",
    "new sweep",
    %w[a b]
  )
  assert size(folded) == 4
  assert take(2, folded) == ["| `r/a` | `a_` | 0.1.1 |", "## The ledger"]
  assert folded[2] ==
    "| `r` | ア | root. Its levels: `a` (エー, aye), `b` (ビー, bee) | 2026-11-05 | KEEP | new sweep |"
  assert last(folded) == rows[1]
end

test "a family's test debt folds into one row for its root, in sorted place"
  rows = [
    "      \"untested: a 1\",",
    "      \"untested: k 2\",",
    "      \"untested: m 4\",",
    "      \"untested: z 3\""
  ]
  assert debt_rows(rows, "f", %w[k m]) ==
    [
      "      \"untested: a 1\",",
      "      \"untested: f 6\",",
      "      \"untested: z 3\""
    ]
  assert debt_rows(rows, "f", ["q"]) == rows
end

test "a use held in a string or in code follows the move"
  assert embedded_uses("use(\"kid\")", "fam", ["kid"]) == "use(\"fam/kid\")"
  assert embedded_uses("\"use(\\\"kid\\\", [:x])\"", "fam", ["kid"]) ==
    "\"use(\\\"fam/kid\\\", [:x])\""
  assert embedded_uses("use(\"kid/sub\")", "fam", ["kid"]) ==
    "use(\"fam/kid/sub\")"
  assert embedded_uses("use(\"kidney\")", "fam", ["kid"]) == "use(\"kidney\")"
end

test "a qualifier after a newline escape in a string starts a path"
  assert rehome("\"use(x)\\nkid::go\"", "fam", ["kid"]) ==
    "\"use(x)\\nfam::kid::go\""
  assert rehome("lankid::go", "fam", ["kid"]) == "lankid::go"
end
