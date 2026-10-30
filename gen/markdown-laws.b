use("bunsho", %i[extract law_failures parse])
use("moji", %i[after_first before_first])
use("retsu", %i[first flat_map last])

def docs_pages()
  dir = path_join(getenv("GEN_ROOT", "."), "docs")
  map(
    (p) -> [p, read_file(p)],
    filter((p) -> ends_with?(p, ".md"), walk_dir(dir))
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

def link_failure(page, link)
  target = link[:target]
  file = before_first(target, "#")
  anchor = after_first(target, "#")
  path = if file == ""
    first(page)
  else
    path_join(path_dirname(first(page)), file)
  end
  at = "#{first(page)}:#{to_s(link[:line])}"
  if leaves_project?(target)
    nil
  elsif not path_exists(path)
    "#{at}: `#{target}` reaches no file"
  elsif anchor != "" and
      ends_with?(path, ".md") and
      not member?(anchor, anchors_in(read_file(path)))
    "#{at}: `#{target}` names no heading `#{anchor}`"
  end
end

def link_failures(pages)
  flat_map(
    pages,
    fn(page)
      filter(
        (f) -> f != nil,
        map(
          (l) -> link_failure(page, l),
          extract(parse(last(page)), %i[link image])
        )
      )
    end
  )
end

test "both Markdown laws hold on every page under docs/"
  pages = docs_pages
  found = law_failures(pages)
  if found != []
    write_stderr(unlines(map((f) -> "#{first(f)}: #{to_s(last(f))}", found)))
  end
  assert length(pages) > 30
  assert found == []
end

test "every relative link under docs/ reaches a file, and every anchor a heading"
  pages = docs_pages
  found = link_failures(pages)
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

test "a link to nowhere and an anchor to no heading are each refused, and a good one passes"
  dir = path_join(getenv("TMPDIR", "/tmp"), "links-#{to_s(now_ns)}")
  mkdir_p(dir)
  write_file(path_join(dir, "b.md"), "# Real heading")
  a = path_join(dir, "a.md")
  text = join_lines(
    [
      "# A",
      "[good](b.md#real-heading) [web](https://example.org) [self](#a)",
      "[gone](missing.md) [lost](b.md#no-such-heading)"
    ]
  )
  write_file(a, text)
  found = link_failures([[a, text]])
  rm_rf(dir)
  assert length(found) == 2
  assert contains?(first(found), "`missing.md` reaches no file")
  assert contains?(last(found), "names no heading `no-such-heading`")
end
