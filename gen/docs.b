use(
  "hon",
  %i[
    address_refusals
    doc_pages
    fact_refusals
    front_matter_refusals
    generated_files
    kind_refusals
    project_at
    run_blocks
    runnable_page?
  ]
)

use("kyohi", [:why])
use("retsu", [:flat_map])

def project_root()
  getenv("GEN_ROOT", ".")
end

def pages()
  doc_pages(project_root)
end

test "every page under docs/ declares one Diátaxis kind"
  found = kind_refusals(pages)
  if found != []
    write_stderr(unlines(map(why, found)))
  end
  assert length(pages) > 30
  assert found == []
end

test "every page's front matter is YAML that reads back as the text it shows"
  found = front_matter_refusals(pages)
  if found != []
    write_stderr(unlines(map(why, found)))
  end
  assert found == []
end

test "every hon block of every page names a fact hon renders, and every include finds its section"
  found = fact_refusals(project_at(project_root))
  if found != []
    write_stderr(unlines(map(why, found)))
  end
  assert found == []
end

test "every block of every tutorial and how-to runs as the page shows it"
  if self_exe != nil
    runnable = filter(runnable_page?, project_at(project_root)[:pages])
    found = flat_map(
      runnable,
      (p) -> run_blocks(self_exe, getenv("TMPDIR", "/tmp"), p)
    )
    if found != []
      write_stderr(unlines(found))
    end
    assert length(runnable) >= 19
    assert found == []
  end
end

test "no page and no generated file links where a reader cannot follow"
  root = project_root
  rendered = generated_files(project_at(root))
  seen = filter((p) -> path_exists(path_join(root, p)), rendered)
  unseen = filter((p) -> not member?(p, seen), rendered)
  if unseen != []
    write_stderr(
      "check(\"docs\") cannot read #{join(unseen, ", ")}: add it to the check's inputs in the Bluefile"
    )
  end
  files = append(pages, map((p) -> [p, read_file(path_join(root, p))], seen))
  found = address_refusals(files)
  if found != []
    write_stderr(unlines(map(why, found)))
  end
  assert length(rendered) > 20
  assert unseen == []
  assert found == []
end
