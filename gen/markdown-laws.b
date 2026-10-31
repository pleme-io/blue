use("bunsho", %i[extract law_failures parse])
use("hon", %i[doc_pages path_in])
use("moji", %i[after_first before_first])
use("retsu", %i[first flat_map last])

def root()
  getenv("GEN_ROOT", ".")
end

def declared_inputs(at)
  get(
    get(
      get(
        json_read(read_file(path_join(at, "Bluefile.lock")))["manifest"],
        "checks"
      ),
      "markdown-laws"
    ),
    "inputs"
  )
end

def leaves_project?(target)
  target == "" or
    starts_with?(target, "/") or
    starts_with?(target, "mailto:") or
    contains?(target, "://")
end

def anchors_in(text)
  map((h) -> h[:anchor], extract(parse(text), :heading))
end

def link_failure(at, inputs, page, link)
  target = link[:target]
  file = before_first(target, "#")
  anchor = after_first(target, "#")
  rel = if file == ""
    first(page)
  else
    path_in(path_dirname(first(page)), file)
  end
  top = first(split(rel, "/"))
  path = path_join(at, rel)
  where = "#{first(page)}:#{to_s(link[:line])}"
  if leaves_project?(target) or top == ".."
    nil
  elsif not member?(top, inputs)
    "#{where}: `#{target}` leads into `#{top}`, which this check does not read; list `#{top}` in the inputs of check(\"markdown-laws\", …)"
  elsif not path_exists(path)
    "#{where}: `#{target}` reaches no file"
  elsif anchor != "" and
      ends_with?(path, ".md") and
      not member?(anchor, anchors_in(read_file(path)))
    "#{where}: `#{target}` names no heading `#{anchor}`"
  end
end

def link_failures(at, inputs, pages)
  flat_map(
    pages,
    fn(page)
      filter(
        (f) -> f != nil,
        map(
          (l) -> link_failure(at, inputs, page, l),
          extract(parse(last(page)), %i[link image])
        )
      )
    end
  )
end

test "both Markdown laws hold on every page under docs/"
  pages = doc_pages(root)
  found = law_failures(pages)
  if found != []
    write_stderr(unlines(map((f) -> "#{first(f)}: #{to_s(last(f))}", found)))
  end
  assert length(pages) > 30
  assert found == []
end

test "every relative link under docs/ reaches a file, and every anchor a heading"
  pages = doc_pages(root)
  found = link_failures(root, declared_inputs(root), pages)
  if found != []
    write_stderr(unlines(found))
  end
  inside = filter(
    (l) -> not leaves_project?(l[:target]),
    flat_map(pages, (p) -> extract(parse(last(p)), %i[link image]))
  )
  assert length(pages) > 30
  assert length(inside) > 200
  assert found == []
end

test "a link to nowhere, an anchor to no heading and a path this check does not read are each refused, and a good one passes"
  dir = path_join(getenv("TMPDIR", "/tmp"), "links-#{to_s(now_ns)}")
  mkdir_p(path_join(dir, "docs"))
  mkdir_p(path_join(dir, "unread"))
  write_file(path_join(dir, "docs/b.md"), "# Real heading")
  write_file(path_join(dir, "unread/c.md"), "# C")
  text = join_lines(
    [
      "# A",
      "[good](b.md#real-heading) [web](https://example.org) [self](#a)",
      "[gone](missing.md) [lost](b.md#no-such-heading) [unseen](../unread/c.md)"
    ]
  )
  write_file(path_join(dir, "docs/a.md"), text)
  found = link_failures(dir, ["docs"], [["docs/a.md", text]])
  rm_rf(dir)
  assert length(found) == 3
  assert contains?(found[0], "`missing.md` reaches no file")
  assert contains?(found[1], "names no heading `no-such-heading`")
  assert contains?(
    found[2],
    "leads into `unread`, which this check does not read"
  )
end
