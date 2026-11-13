use("hon", [:with_facts])
use("mokuroku", [:md_cell])
use("shisutemu", %i[status_of stderr_of stdout_of])

@doc """
rule_row: The codes-table row of one rule from `blue reference`.

    rule_row({"code" => "B0001", "slug" => "s", "severity" => "error", "law" => "a | b"}) #=> "| B0001 | s | error | a \\| b |"
"""
def rule_row(r)
  "| #{r["code"]} | #{r["slug"]} | #{r["severity"]} | #{md_cell(r["law"])} |"
end

@doc """
codes_table: The codes table: a header, then one row per rule in registry order.

    codes_table([])[1] #=> "|---|---|---|---|"
"""
def codes_table(rules)
  append(
    ["| code | slug | severity | law |", "|---|---|---|---|"],
    map(rule_row, rules)
  )
end

@doc """
obligation_row: The obligations-table row of one obligation from `blue reference`: its refusal, or `design` and what blocks it.

    obligation_row({"id" => "point/effect", "when" => "w", "evidence" => "integration", "detector" => "static", "refusal" => "B0071", "profile" => "default", "held" => 3, "blocked" => nil}) #=> "| point/effect | w | integration | static | B0071 | default | 3 |"
    obligation_row({"id" => "flow/loop", "when" => "w", "evidence" => "branch", "detector" => "dynamic", "refusal" => "design", "profile" => "strict", "held" => 0, "blocked" => "CV5"}) #=> "| flow/loop | w | branch | dynamic | design: CV5 | strict | 0 |"
"""
def obligation_row(o)
  refusal = if o["blocked"].nil?
    o["refusal"]
  else
    "design: #{o["blocked"]}"
  end
  "| #{o["id"]} | #{md_cell(o["when"])} | #{o["evidence"]} | #{o["detector"]} | #{md_cell(refusal)} | #{o["profile"]} | #{to_s(o["held"])} |"
end

@doc """
obligations_table: The obligations table: a header, then one row per obligation in registry order.

    obligations_table([])[1] #=> "|---|---|---|---|---|---|---|"
"""
def obligations_table(rows)
  append(
    [
      "| obligation | when blue sees | evidence | detector | refusal | profile | held |",
      "|---|---|---|---|---|---|---|"
    ],
    map(obligation_row, rows)
  )
end

@doc """
reference_fact: The text a hon block of this page becomes: `rules` or `obligations`, from one `blue reference`; any other fact is refused.

    reference_fact({"rules" => [], "obligations" => []}, ["rules", []]) #=> join_lines(["| code | slug | severity | law |", "|---|---|---|---|"])
    (reference_fact({}, ["verbs", []]) rescue :refused) #=> :refused
"""
def reference_fact(reference, fact)
  if fact[0] == "rules"
    join_lines(codes_table(reference["rules"]))
  elsif fact[0] == "obligations"
    join_lines(obligations_table(reference["obligations"]))
  else
    raise(
      :unknown_fact,
      "gen/diagnostics.md names the fact `#{fact[0]}`; this page renders `rules` and `obligations`"
    )
  end
end

def reference()
  cap = exec_capture(self_exe, "reference")
  if status_of(cap) != 0
    raise(:reference, "blue reference failed: #{stderr_of(cap)}")
  end
  json_read(stdout_of(cap))
end

def main()
  source = read_file(path_join(getenv("GEN_ROOT", "."), "gen/diagnostics.md"))
  r = reference
  write_file(
    getenv("GEN_OUT", "docs/DIAGNOSTICS.md"),
    with_facts(source, (f) -> reference_fact(r, f))
  )
end
