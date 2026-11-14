@moduledoc """
obligation-debt: the registry's debt per code, one row per change that moved one, appended by `blue obligations history` when the registry moved since the last row; discovery reads it for trades and fixes made together (docs/OBLIGATION-GRAPH.md).

    size(history_rows(debt_text("/nonexistent/obligation-debt.tsv"))) #=> 1
"""

use("gaisou", [:history_rows])
use("retsu", %i[first size])
use("shisutemu", %i[status_of stderr_of stdout_of])

@doc """
debt_text: the history file `file` holds with this build's registry appended when it moved, as `blue obligations history` prints it.

    starts_with?(debt_text("/nonexistent/obligation-debt.tsv"), "# seq") #=> true
"""
def debt_text(file)
  cap = exec_capture(self_exe, "obligations", "history", file)
  if status_of(cap) != 0
    raise(:history, "blue obligations history failed: #{stderr_of(cap)}")
  end
  stdout_of(cap)
end

def main()
  write_file(
    getenv("GEN_OUT", "gen/obligation-debt.tsv"),
    debt_text(path_join(getenv("GEN_ROOT", "."), "gen/obligation-debt.tsv"))
  )
end

test "the history reads back, and a second render appends nothing", {
  kind: :rendering
}
  dir = temp_dir("obligation-debt")
  file = path_join(dir, "obligation-debt.tsv")
  once = debt_text(file)
  rows = history_rows(once)
  assert size(rows) == 1
  assert first(rows)["B0090"] != nil
  write_file(file, once)
  assert debt_text(file) == once
end
