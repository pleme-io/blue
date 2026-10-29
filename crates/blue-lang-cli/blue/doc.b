use(
  "mokuroku",
  %i[
    blue_path_roots
    catalog_of
    entries_of_text
    package_text
    pkg_dir
    pkg_entries
    pkg_gloss
    pkg_name
    pkg_needs
    pkg_tests
    pkg_version
    test_blocks_of_text
  ]
)

use("retsu", %i[first flat_map last])

# blue doc: what a name is, where it lives and how it is called.
#
#   blue doc NAME [--file FILE] [--json]
#   blue doc PKG [--json]
#
# NAME is a builtin, `pkg::name`, or a bare name, which is looked up among the
# builtins and every bidama on BLUE_PATH. With --file, the file's own
# definitions are searched too, and each answer's tier is how that file
# reaches the name: `own`, `imported` (a `use` lists it), `qualified` (the
# file uses the package; write `pkg::name`), `not-imported`, or `builtin`.
# PKG, a bidama's name, lists the package.
#
# The tool is blue. It reads the bidamas as mokuroku reads them for the
# catalogue, asks the blue running it for the builtins (`blue reference`) and
# for a file's imports (`blue ast --resolved --json`), and takes a builtin's
# examples from the conformance rows compiled into that blue (`blue doc
# --rows`).

def run_blue(args)
  exec_capture(*cons(self_exe, args))
end

def captured(args)
  r = run_blue(args)
  if r[0][1] != 0
    raise(:doc, "blue #{join(args, " ")}: #{r[2][1]}")
  end
  r[1][1]
end

# The value after `flag` in the arguments, or nil.
def flag_value(args, flag)
  at = filter((i) -> args[i] == flag, range(length(args)))
  if empty?(at) or first(at) + 1 >= length(args)
    nil
  else
    args[first(at) + 1]
  end
end

# ── what is documented ─────────────────────────────────────────────────────

def builtins()
  json_get(json_parse(captured(["reference"])), :names)
end

# [id, program, expectation] for every conformance row covering the builtin.
def rows_for(name)
  filter(
    (r) -> member?("builtin:#{name}", json_get(r, :covers)),
    json_parse(captured(%w[doc --rows]))
  )
end

def builtin_entry(b, tier)
  name = json_get(b, :name)
  rows = rows_for(name)
  example = if empty?(rows)
    nil
  else
    row = first(rows)
    {
      from: "spec row #{json_get(row, "id")}",
      code: [json_get(row, :src), "=> #{json_get(row, "expect")}"]
    }
  end
  {
    name:,
    namespace: "blue",
    tier:,
    kind: json_get(b, :arbiter),
    topic: json_get(b, :topic),
    signature: json_get(b, :signature),
    doc: [json_get(b, :doc)],
    example:
  }
end

# Does `line` call `name`: `name(` not preceded by a name character?
def calls?(line, name)
  parts = split(line, "#{name}(")
  length(parts) > 1 and
    any?(
      fn(before)
        cs = chars(before)
        empty?(cs) or not name_char?(cs[length(cs) - 1])
      end,
      take(length(parts) - 1, parts)
    )
end

def name_char?(c)
  contains?(
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_?!:",
    c
  )
end

# The first test in `text` that calls `name`, as an example, or nil.
def test_example(text, name)
  blocks = filter(
    (b) -> any?((l) -> calls?(l, name), last(b)),
    test_blocks_of_text(text)
  )
  if empty?(blocks)
    nil
  else
    b = first(blocks)
    {
      from: "test \"#{first(b)}\"",
      code: map((l) -> blue::trim(l), take(8, last(b)))
    }
  end
end

# The entry for definition `e` ([name, signature, doc_lines, waivers]) of the
# package `pkg` (a mokuroku record, or nil for the file's own script).
def derived_of(pkg, name)
  r = run_blue(
    ["doc", name, "--file", "#{pkg_dir(pkg)}/#{pkg_name(pkg)}.b", "--derived"]
  )
  if r[0][1] == 0
    json_parse(r[1][1])
  end
end

def def_entry(pkg, e, text, tier)
  name = first(e)
  qualifier = if pkg.nil?
    ""
  else
    "#{pkg_name(pkg)}::"
  end
  {
    name: "#{qualifier}#{name}",
    namespace: if pkg.nil?
      nil
    else
      pkg_name(pkg)
    end,
    tier:,
    kind: "definition",
    topic: nil,
    signature: "#{qualifier}#{e[1]}",
    doc: e[2],
    example: test_example(text, name),
    derived: if pkg.nil?
      nil
    else
      derived_of(pkg, name)
    end
  }
end

# ── tiers ──────────────────────────────────────────────────────────────────

# How the file described by `ctx` reaches `name` in package `pkg`.
def tier_in(ctx, pkg, name)
  if ctx.nil?
    "qualified"
  elsif json_get(ctx, :namespace) == pkg
    "own"
  else
    uses = filter((u) -> json_get(u, :package) == pkg, json_get(ctx, :imports))
    if empty?(uses)
      "not-imported"
    elsif any?((u) -> member?(name, json_get(u, :names)), uses)
      "imported"
    else
      "qualified"
    end
  end
end

# ── lookup ─────────────────────────────────────────────────────────────────

def lookup(name, file, records)
  ctx = if file.nil?
    nil
  else
    json_parse(captured(["ast", "--resolved", "--json", file]))
  end
  parts = split(name, "::")
  qualifier = if length(parts) == 2
    first(parts)
  end
  bare = last(parts)
  own = if file.nil? or json_get(ctx, :namespace) != nil
    []
  else
    text = read_file(file)
    map(
      (e) -> def_entry(nil, e, text, "own"),
      filter((e) -> first(e) == bare, entries_of_text(text))
    )
  end
  from_bidamas = flat_map(
    filter((r) -> qualifier.nil? or qualifier == pkg_name(r), records),
    fn(r)
      text = package_text(pkg_dir(r))
      map(
        (e) -> def_entry(r, e, text, tier_in(ctx, pkg_name(r), bare)),
        filter((e) -> first(e) == bare, pkg_entries(r))
      )
    end
  )
  from_builtins = if qualifier.nil? or qualifier == "blue"
    map(
      (b) -> builtin_entry(b, "builtin"),
      filter((b) -> json_get(b, :name) == bare, builtins)
    )
  else
    []
  end
  append(own, from_bidamas, from_builtins)
end

# ── rendering ──────────────────────────────────────────────────────────────

def entry_text(e)
  where = if e[:namespace] == "blue"
    "builtin #{e[:kind]} · #{e[:topic]}"
  elsif e[:namespace].nil?
    "defined in the file"
  else
    "bidama #{e[:namespace]}"
  end
  example = e[:example]
  derived = e[:derived]
  lines = append(
    [e[:signature], "  #{where} · tier: #{e[:tier]}"],
    map((l) -> "  #{l}", e[:doc]),
    if derived.nil?
      []
    else
      map((l) -> "  · #{l}", json_get(derived, :lines))
    end,
    if example.nil?
      []
    else
      append(
        ["  example (#{example[:from]}):"],
        map((l) -> "    #{l}", example[:code])
      )
    end
  )
  join(lines, line_break)
end

def package_entry(r)
  {
    package: pkg_name(r),
    version: pkg_version(r),
    needs: pkg_needs(r),
    gloss: pkg_gloss(r),
    tests: pkg_tests(r),
    definitions: map(
      fn(e)
        {
          name: first(e),
          signature: e[1],
          doc: if empty?(e[2])
            ""
          else
            first(e[2])
          end
        }
      end,
      pkg_entries(r)
    )
  }
end

def package_text_view(p)
  needs = if empty?(p[:needs])
    "—"
  else
    join(p[:needs], ", ")
  end
  head = [
    "#{p[:package]} #{p[:version]} · needs: #{needs} · #{to_s(p[:tests])} tests",
    "  #{p[:gloss]}",
    ""
  ]
  defs = map(
    fn(d)
      signature = "  #{p[:package]}::#{d[:signature]}"
      if d[:doc] == ""
        signature
      else
        join_lines([signature, "      #{d[:doc]}"])
      end
    end,
    p[:definitions]
  )
  join(append(head, defs), line_break)
end

# What the doc says, written to stdout; true when something was found. The
# binary exits non-zero on false.
def main(args)
  if empty?(args) or starts_with?(first(args), "--")
    raise(:usage, "usage: blue doc NAME [--file FILE] [--json]")
  end
  name = first(args)
  json? = member?("--json", args)
  file = flag_value(args, "--file")
  records = catalog_of(
    blue_path_roots("#{getenv("BLUE_PATH", "")}:#{getenv("BLUE_DIST", "")}")
  )
  packages = filter((r) -> pkg_name(r) == name, records)
  if not contains?(name, "::") and not empty?(packages)
    p = package_entry(first(packages))
    if json?
      write_stdout(unlines([json_stringify(p)]))
    else
      write_stdout(unlines([package_text_view(p)]))
    end
    true
  else
    found = lookup(name, file, records)
    if empty?(found)
      where = if empty?(records)
        "the builtins (BLUE_PATH names no bidama)"
      else
        "the builtins and #{to_s(length(records))} bidamas on BLUE_PATH"
      end
      write_stderr(unlines(["blue doc: no `#{name}` in #{where}"]))
      false
    elsif json?
      map((e) -> write_stdout(unlines([json_stringify(e)])), found)
      true
    else
      write_stdout(unlines([join(map(entry_text, found), unlines(["", ""]))]))
      true
    end
  end
end

main(argv)
