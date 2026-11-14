@moduledoc """
obligation-discovery: docs/OBLIGATION-DISCOVERY.md, the discovery report `blue obligations discover` prints over the paths this generate row declares as its inputs (docs/OBLIGATION-GRAPH.md). The fresh check fails when the committed report is stale against the corpus.

    paths({"generated" => {"obligation-discovery" => {"inputs" => ["Bluefile.lock", "gen"]}}}) #=> ["gen"]
"""

use("moji", %i[lines starts_with])
use("retsu", %i[flat_map is_empty size])
use("shisutemu", %i[status_of stderr_of stdout_of])

@doc """
paths: the paths discovery reads, the row's inputs other than the lock.

    paths({"generated" => {"obligation-discovery" => {"inputs" => ["Bluefile.lock", "bidamas"]}}}) #=> ["bidamas"]
"""
def paths(manifest)
  filter(
    (p) -> p != "Bluefile.lock",
    manifest["generated"]["obligation-discovery"]["inputs"]
  )
end

def root()
  getenv("GEN_ROOT", ".")
end

@doc """
report: the report over `dir`, reading `ins` under it.

    procedure?(report) #=> true
"""
def report(dir, ins)
  cap = exec_capture(
    *append(
      [self_exe, "obligations", "discover", dir],
      flat_map(ins, (p) -> ["--in", p])
    )
  )
  if status_of(cap) != 0
    raise(:discovery, "blue obligations discover failed: #{stderr_of(cap)}")
  end
  stdout_of(cap)
end

@doc """
table_widths: the cell count of each Markdown table line of a text, the shape a Markdown reader needs to be one per table.

    table_widths("| a | b |") #=> [2]
"""
def table_widths(text)
  map(
    (l) -> size(split(l, "|")) - 2,
    filter((l) -> starts_with(l, "|"), lines(text))
  )
end

def main()
  m = json_read(read_file(path_join(root, "Bluefile.lock")))["manifest"]
  write_file(
    getenv("GEN_OUT", "docs/OBLIGATION-DISCOVERY.md"),
    report(root, paths(m))
  )
end

test "the committed report's tables read as a Markdown reader reads them, each with one width per section", {
  kind: :rendering
}
  text = read_file(path_join(root, "docs/OBLIGATION-DISCOVERY.md"))
  tables = filter(
    (s) -> contains?(s, "|---"),
    flat_map(
      split(text, join_lines(["", "## "])),
      (s) -> split(s, join_lines(["", "### "]))
    )
  )
  assert size(tables) >= 3
  assert every?(
    fn(s)
      ws = table_widths(s)
      not is_empty(ws) and every?((w) -> w == ws[0], ws)
    end,
    tables
  )
end
