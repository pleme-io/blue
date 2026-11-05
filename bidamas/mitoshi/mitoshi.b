@moduledoc """
mitoshi (見通し, a clear view ahead) — what a running program shows of itself.

Three levels: `mitoshi/rogu` writes structured log lines, `mitoshi/tsuiseki`
traces spans of work, and `mitoshi/keisoku` keeps counters, gauges and
histograms. The root defines nothing; a `use("mitoshi")` brings all three.
"""
