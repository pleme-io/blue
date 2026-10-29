use("hon", %i[doc_pages kind_refusals project_at run_blocks runnable_page?])

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
    assert length(runnable) >= 11
    assert found == []
  end
end
