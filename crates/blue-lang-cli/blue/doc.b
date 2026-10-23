use(
  "mokuroku",
  [
    :blue_path_roots,
    :catalog_of,
    :entries_of_text,
    :package_text,
    :pkg_dir,
    :pkg_entries,
    :pkg_gloss,
    :pkg_name,
    :pkg_needs,
    :pkg_tests,
    :pkg_version,
    :test_blocks_of_text
  ]
)

use("retsu", [:first, :flat_map, :last])

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
  if nth(1, nth(0, r)) != 0
    raise(:doc, "blue #{join(args, " ")}: #{nth(1, nth(2, r))}")
  end
  nth(1, nth(1, r))
end

# The value after `flag` in the arguments, or nil.
def flag_value(args, flag)
  at = filter((i) -> nth(i, args) == flag, range(length(args)))
  if empty?(at) or first(at) + 1 >= length(args)
    nil
  else
    nth(first(at) + 1, args)
  end
end

# ── what is documented ─────────────────────────────────────────────────────

def builtins()
  json_get(json_parse(captured(["reference"])), "names")
end

# [id, program, expectation] for every conformance row covering the builtin.
def rows_for(name)
  filter(
    (r) -> member?("builtin:#{name}", json_get(r, "covers")),
    json_parse(captured(["doc", "--rows"]))
  )
end

def builtin_entry(b, tier)
  name = json_get(b, "name")
  rows = rows_for(name)
  example = if empty?(rows)
    nil
  else
    row = first(rows)
    {
      from: "spec row #{json_get(row, "id")}",
      code: [json_get(row, "src"), "=> #{json_get(row, "expect")}"]
    }
  end
  {
    name:,
    namespace: "blue",
    tier:,
    kind: json_get(b, "arbiter"),
    topic: json_get(b, "topic"),
    signature: json_get(b, "signature"),
    doc: [json_get(b, "doc")],
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
        empty?(cs) or not name_char?(nth(length(cs) - 1, cs))
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
    {from: "test \"#{first(b)}\"", code: map((l) -> blue::trim(l), take(8, last(b)))}
  end
end

# The entry for definition `e` ([name, signature, doc_lines, waivers]) of the
# package `pkg` (a mokuroku record, or nil for the file's own script).
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
    signature: "#{qualifier}#{nth(1, e)}",
    doc: nth(2, e),
    example: test_example(text, name)
  }
end

# ── tiers ──────────────────────────────────────────────────────────────────

# How the file described by `ctx` reaches `name` in package `pkg`.
def tier_in(ctx, pkg, name)
  if ctx.nil?
    "qualified"
  elsif json_get(ctx, "namespace") == pkg
    "own"
  else
    uses = filter(
      (u) -> json_get(u, "package") == pkg,
      json_get(ctx, "imports")
    )
    if empty?(uses)
      "not-imported"
    elsif any?((u) -> member?(name, json_get(u, "names")), uses)
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
  own = if file.nil? or json_get(ctx, "namespace") != nil
    []
  else
    text = read_file(file)
    map(
      (e) -> def_entry(nil, e, text, "own"),
      filter((e) -> first(e) == bare, entries_of_text(text))
    )
  end
  from_bidamas = flat_map(
    fn(r)
      text = package_text(pkg_dir(r))
      map(
        (e) -> def_entry(r, e, text, tier_in(ctx, pkg_name(r), bare)),
        filter((e) -> first(e) == bare, pkg_entries(r))
      )
    end,
    filter((r) -> qualifier.nil? or qualifier == pkg_name(r), records)
  )
  from_builtins = if qualifier.nil? or qualifier == "blue"
    map(
      (b) -> builtin_entry(b, "builtin"),
      filter((b) -> json_get(b, "name") == bare, builtins)
    )
  else
    []
  end
  append(own, from_bidamas, from_builtins)
end

# ── rendering ──────────────────────────────────────────────────────────────

def entry_text(e)
  where = if get(e, :namespace) == "blue"
    "builtin #{get(e, :kind)} · #{get(e, :topic)}"
  elsif get(e, :namespace).nil?
    "defined in the file"
  else
    "bidama #{get(e, :namespace)}"
  end
  example = get(e, :example)
  lines = append(
    [get(e, :signature), "  #{where} · tier: #{get(e, :tier)}"],
    map((l) -> "  #{l}", get(e, :doc)),
    if example.nil?
      []
    else
      append(
        ["  example (#{get(example, :from)}):"],
        map((l) -> "    #{l}", get(example, :code))
      )
    end
  )
  join(lines, "\n")
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
          signature: nth(1, e),
          doc: if empty?(nth(2, e))
            ""
          else
            first(nth(2, e))
          end
        }
      end,
      pkg_entries(r)
    )
  }
end

def package_text_view(p)
  needs = if empty?(get(p, :needs))
    "—"
  else
    join(get(p, :needs), ", ")
  end
  head = [
    "#{get(p, :package)} #{get(p, :version)} · needs: #{needs} · #{to_s(get(p, :tests))} tests",
    "  #{get(p, :gloss)}",
    ""
  ]
  defs = map(
    fn(d)
      signature = "  #{get(p, :package)}::#{get(d, :signature)}"
      if get(d, :doc) == ""
        signature
      else
        "#{signature}\n      #{get(d, :doc)}"
      end
    end,
    get(p, :definitions)
  )
  join(append(head, defs), "\n")
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
  records = catalog_of(blue_path_roots(getenv("BLUE_PATH", "")))
  packages = filter((r) -> pkg_name(r) == name, records)
  if not contains?(name, "::") and not empty?(packages)
    p = package_entry(first(packages))
    if json?
      write_stdout("#{json_stringify(p)}\n")
    else
      write_stdout("#{package_text_view(p)}\n")
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
      write_stderr("blue doc: no `#{name}` in #{where}\n")
      false
    elsif json?
      map((e) -> write_stdout("#{json_stringify(e)}\n"), found)
      true
    else
      write_stdout("#{join(map(entry_text, found), "\n\n")}\n")
      true
    end
  end
end

main(argv)
