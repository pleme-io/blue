use("moji", [:before_first, :strip_prefix, :trim])
use("retsu", [:concat_lists, :first, :reject])
use("shisutemu", [:status_of, :stdout_of])

def words_of(text)
  starts = filter(
    (l) -> starts_with?(l, "def ") or starts_with?(l, "defmacro "),
    split(text, "\n")
  )
  map(
    fn(l)
      rest = trim(strip_prefix(strip_prefix(l, "defmacro "), "def "))
      trim(before_first(rest, "("))
    end,
    starts
  )
end

def fixed?(word, texts)
  any?(
    (t) -> contains?(t, "legacy_names(") and contains?(t, "[\"#{word}\", "),
    texts
  )
end

def stranded(before, after)
  now = distinct(reduce(concat_lists, [], map(words_of, after)))
  gone = reject(
    (w) -> member?(w, now),
    distinct(reduce(concat_lists, [], map(words_of, before)))
  )
  reject((w) -> fixed?(w, after), gone)
end

def git(args)
  stdout_of(exec_capture("git", *args))
end

def lines_of(text)
  reject((l) -> l == "", split(text, "\n"))
end

def package_of(path)
  parts = split(path, "/")
  if count(parts) >= 3 and first(parts) == "bidamas"
    nth(1, parts)
  end
end

def texts_at(rev, pkg)
  files = filter(
    (f) -> ends_with?(f, ".b"),
    lines_of(git(["ls-tree", "-r", "--name-only", rev, "bidamas/#{pkg}/"]))
  )
  map((f) -> git(["show", "#{rev}:#{f}"]), files)
end

def findings(base, head)
  changed = lines_of(git(["diff", "--name-only", base, head, "--", "bidamas"]))
  pkgs = distinct(
    reject(
      (p) -> p.nil?,
      map(package_of, filter((f) -> ends_with?(f, ".b"), changed))
    )
  )
  reduce(
    concat_lists,
    [],
    map(
      fn(p)
        map((w) -> "#{p}::#{w}", stranded(texts_at(base, p), texts_at(head, p)))
      end,
      pkgs
    )
  )
end

def main()
  base = if count(argv) > 0
    first(argv)
  else
    "origin/main"
  end
  head = if count(argv) > 1
    nth(1, argv)
  else
    "HEAD"
  end
  if status_of(exec_capture("git", "rev-parse", "--verify", "-q", base)) != 0
    write_stderr(
      "retired: #{base} is not a revision here, so nothing is compared\n"
    )
    exit_with(2)
  end
  found = findings(base, head)
  if found == []
    nil
  else
    write_stderr(
      "retired: #{to_s(count(found))} word(s) left with no fixer: #{join(found, ", ")}. A retired word keeps a legacy_names row [old, \"home::new\", \"args\"], so blue check --fix rewrites its callers\n"
    )
    exit_with(1)
  end
end

test "a word that leaves with no legacy_names row is stranded"
  before = ["def refuse(found)\n  found\nend\n\ndef enforce(s, r, o?)\n  s\nend\n"]
  after = ["def enforce(s, r, o?)\n  s\nend\n"]
  assert stranded(before, after) == ["refuse"]
end

test "a word that leaves with its fixer row is not stranded"
  before = ["def refuse(found)\n  found\nend\n"]
  after = ["legacy_names(\n  \"0.1.2\",\n  [[\"refuse\", \"kyohi::enforce\", \"[(fs) -> fs], {kind: :first}\"]]\n)\n\ndef enforce(s, r, o?)\n  s\nend\n"]
  assert stranded(before, after) == []
end

test "a word that moves to another file of its package is not stranded"
  before = ["def a()\n  1\nend\n", ""]
  after = ["", "def a()\n  1\nend\n"]
  assert stranded(before, after) == []
end

test "an indented def is a local, not a word"
  assert words_of("def f(x)\n  def g()\n    1\n  end\nend\ndefmacro m(x)\n  x\nend\n") ==
    ["f", "m"]
end
