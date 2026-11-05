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

    starts_with?(root_bluefile("fam", ["a"]), "package(") #=> true
"""
def root_bluefile(root, children)
  unlines(
    [
      "package(\"#{root}\", \"0.1.0\")",
      "legacy_packages(\"0.1.0\", #{legacy_rows(root, children)})"
    ]
  )
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
  kept = filter((l) -> not member?(row_name(l, head), gone), lines)
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
      [entry],
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
  write_file(path_join(dir, "Bluefile"), root_bluefile(root, children))
  if not is_file?(path_join(dir, "#{root}.b"))
    write_program(
      path_join(dir, "#{root}.b"),
      unlines(
        ["@moduledoc \"\"\"", "#{root}: #{join(children, ", ")}.", "\"\"\""]
      )
    )
  end
  callers = filter(
    fn(p)
      ends_with?(p, ".b") and
        not contains?(p, "/target/") and
        names_a_child?(read_file(p), children)
    end,
    concat_lists(walk_dir("bidamas"), walk_dir("gen"))
  )
  map(
    fn(p)
      exec_capture(blue, "check", "--fix", "--only", "B0074", p)
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
  needs = [
    "needs(\"a\", \"^0.1\")",
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
  rows = [
    "| `a` | エー | aye — the first | 2026-10-01 | KEEP | swept |",
    "| `m` | エム | em — between | 2026-10-01 | KEEP | swept |",
    "| `b` | ビー | bee — the second | 2026-10-02 | KEEP | swept |"
  ]
  folded = ledger_rows(
    rows,
    "r",
    "ア",
    "2026-11-05",
    "root",
    "new sweep",
    %w[a b]
  )
  assert size(folded) == 2
  assert first(folded) ==
    "| `r` | ア | root. Its levels: `a` (エー, aye), `b` (ビー, bee) | 2026-11-05 | KEEP | new sweep |"
  assert last(folded) == rows[1]
end
