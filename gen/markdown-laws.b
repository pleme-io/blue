use("bunsho", [:law_failures])
use("retsu", %i[first last])

test "both Markdown laws hold on every page under docs/"
  dir = path_join(getenv("GEN_ROOT", "."), "docs")
  pages = map(
    (p) -> [p, read_file(p)],
    filter((p) -> ends_with?(p, ".md"), walk_dir(dir))
  )
  found = law_failures(pages)
  if found != []
    write_stderr(unlines(map((f) -> "#{first(f)}: #{to_s(last(f))}", found)))
  end
  assert length(pages) > 30
  assert found == []
end
