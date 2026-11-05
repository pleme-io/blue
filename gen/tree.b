@moduledoc """
tree: move flat bidamas under a root, as docs/BIDAMA-COHESION.md section 6
lays out. `blue gen/tree.b move ROOT CHILD...` moves each child to
`bidamas/ROOT/CHILD` without its Bluefile, writes the root's Bluefile with one
`legacy_packages` row per child, and runs `blue check --fix --only B0074` on
every `.b` file that names a child, so callers move to the new path. The root's
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
  kept = filter((l) -> not child_row?(l), lines)
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
          starts_path = tail == [] or
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
callers_of: every `.b` file under bidamas/ and gen/ that names a child, the verb graph's rows aside: they name spaces, not paths.

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
    concat_lists(walk_dir("bidamas"), walk_dir("gen"))
  )
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
  if is_file?(path_join(dir, "Bluefile"))
    write_stderr(
      unlines(
        ["❌ tree: #{dir}/Bluefile exists; add its legacy_packages rows by hand"]
      )
    )
    exit_with(1)
  end
  mkdir_p(dir)
  version = root_version(
    map((c) -> package_version(path_join("bidamas", c)), children)
  )
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
  write_file(path_join(dir, "Bluefile"), root_bluefile(root, children, version))
  if not is_file?(path_join(dir, "#{root}.b"))
    write_program(
      path_join(dir, "#{root}.b"),
      unlines(
        ["@moduledoc \"\"\"", "#{root}: #{join(children, ", ")}.", "\"\"\""]
      )
    )
  end
  callers = callers_of(children)
  map(
    fn(p)
      exec_capture(blue, "check", "--fix", "--only", "B0074", p)
      write_file(p, rehome(read_file(p), root, children))
      exec_capture(blue, "check", "--fix", "--only", "B0015", p)
    end,
    callers
  )
  facade(root, children)
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
