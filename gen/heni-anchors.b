use("kazu", [:min])
use("retsu", [:last, :take_while])
use("shisutemu", [:status_of, :stdout_of])

# A canonical rewrite (B0065, B0066, …) changes the text heni's mutations
# anchor on, and the gate then refuses them: "find occurs 0 times". This
# re-anchors each such mutation from the program it was written against: the
# mutation is applied to the file at BASE, both sides are formatted as blue
# writes them now, and the lines that differ become the new find and replace,
# widened until the find occurs once. A mutation it cannot place is listed,
# and its entry is left as it was.
#
#   blue run gen/heni-anchors.b -- BASE     (BASE: the commit before the rewrite)

def occurrences(text, part)
  length(split(text, part)) - 1
end

def replace_once(text, part, by)
  pieces = split(text, part)
  concat(pieces[0], by, join(drop(1, pieces), part))
end

def canonical(text)
  path = path_join(getenv("TMPDIR", "/tmp"), "heni-anchors-#{to_s(now_ns)}.b")
  write_program(path, text)
  read_file(path)
end

def common_prefix(a, b)
  bound = min(length(a), length(b))
  length(take_while((i) -> a[i] == b[i], range(0, bound)))
end

def common_suffix(a, b, prefix)
  bound = min(length(a), length(b)) - prefix
  length(
    take_while(
      (i) -> a[length(a) - 1 - i] == b[length(b) - 1 - i],
      range(0, bound)
    )
  )
end

def span(lines, from, to)
  join(map((i) -> concat(lines[i], line_break), range(from, to)), "")
end

def widened(now, a, b, from, a_to, b_to)
  find = span(a, from, a_to)
  if find != "" and occurrences(now, find) == 1
    [find, span(b, from, b_to)]
  elsif from == 0 and a_to == length(a)
    nil
  elsif from == 0
    widened(now, a, b, from, a_to + 1, b_to + 1)
  else
    widened(now, a, b, from - 1, a_to, b_to)
  end
end

def reanchored(now, old, find, replace)
  if occurrences(old, find) != 1
    nil
  else
    before = canonical(old)
    after = canonical(replace_once(old, find, replace))
    a = split(before, line_break)
    b = split(after, line_break)
    p = common_prefix(a, b)
    s = common_suffix(a, b, p)
    widened(now, a, b, p, length(a) - s, length(b) - s)
  end
end

def field(entry, key)
  json_get(entry, key)
end

def with_anchor(entry, find, replace)
  map(
    fn(pair)
      if pair[0] == "find"
        ["find", find]
      elsif pair[0] == "replace"
        ["replace", replace]
      else
        pair
      end
    end,
    entry
  )
end

def key_order()
  ["name", "file", "find", "replace"]
end

def ordered(entry)
  known = filter(
    (pair) -> pair != nil,
    map((k) -> find(entry, (pair) -> pair[0] == k), key_order)
  )
  rest = filter((pair) -> not member?(pair[0], key_order), entry)
  retsu::concat_lists(known, rest)
end

def entry_text(entry)
  fields = map(
    (pair) -> "    #{json_stringify(pair[0])}: #{json_stringify(pair[1])}",
    ordered(entry)
  )
  join_lines(["  {", join(fields, unlines([","])), "  }"])
end

def spec_text(entries)
  unlines(["[", join(map(entry_text, entries), unlines([","])), "]"])
end

def old_text(base, path)
  cap = exec_capture("git", "show", "#{base}:#{path}")
  if status_of(cap) == 0
    stdout_of(cap)
  end
end

def placed(base, package, entry)
  path = path_join(path_join("bidamas", package), field(entry, "file"))
  now = read_file(path)
  find = field(entry, "find")
  if occurrences(now, find) == 1
    [:kept, entry]
  else
    old = old_text(base, path)
    anchor = if old.nil?
      nil
    else
      reanchored(now, old, find, field(entry, "replace"))
    end
    if anchor.nil?
      [:unplaced, entry]
    else
      [:moved, with_anchor(entry, anchor[0], anchor[1])]
    end
  end
end

def package_of(spec)
  replace(last(split(spec, "/")), ".json", "")
end

def rebase_spec(base, spec)
  package = package_of(spec)
  results = map((e) -> placed(base, package, e), json_parse(read_file(spec)))
  moved = filter((r) -> r[0] == :moved, results)
  unplaced = filter((r) -> r[0] == :unplaced, results)
  if moved != []
    write_file(spec, spec_text(map((r) -> r[1], results)))
  end
  map(
    (r) -> write_stdout(unlines(["unplaced #{spec}: #{field(r[1], "name")}"])),
    unplaced
  )
  [length(moved), length(unplaced)]
end

def main()
  base = argv_get(0) or "HEAD"
  specs = filter(
    (p) -> ends_with?(p, ".json"),
    walk_dir("bidamas/heni/mutations")
  )
  counts = map((s) -> rebase_spec(base, s), specs)
  moved = reduce((acc, c) -> acc + c[0], 0, counts)
  unplaced = reduce((acc, c) -> acc + c[1], 0, counts)
  write_stdout(unlines(["moved #{moved}, unplaced #{unplaced}"]))
  if unplaced > 0
    exit_with(1)
  end
end
