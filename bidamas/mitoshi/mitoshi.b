@moduledoc """
mitoshi (見通し, a clear view ahead) — what a running program shows of itself.

Three levels: `mitoshi/rogu` writes structured log lines, `mitoshi/tsuiseki`
traces spans of work, and `mitoshi/keisoku` keeps counters, gauges and
histograms. The root defines nothing; a `use("mitoshi")` brings all three.

    mitoshi::rogu::levels #=> %i[debug info warn error]
"""

test "the root reaches each of its levels by the path below it"
  assert mitoshi::rogu::levels == %i[debug info warn error]
  assert mitoshi::keisoku::read(mitoshi::keisoku::counter("probe", {}), {}) ==
    []
  assert mitoshi::tsuiseki::span("probe", (_s) -> 1, {sink: (_r) -> nil}) == 1
end
