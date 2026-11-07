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
rules_fact: The text the `rules` hon block becomes; any other fact is refused.

    rules_fact([], ["rules", []]) #=> join_lines(["| code | slug | severity | law |", "|---|---|---|---|"])
"""
def rules_fact(rules, fact)
  if fact[0] != "rules"
    raise(
      :unknown_fact,
      "gen/diagnostics.md names the fact `#{fact[0]}`; this page renders only `rules`"
    )
  end
  join_lines(codes_table(rules))
end

def reference_rules()
  cap = exec_capture(self_exe, "reference")
  if status_of(cap) != 0
    raise(:reference, "blue reference failed: #{stderr_of(cap)}")
  end
  json_read(stdout_of(cap))["rules"]
end

def main()
  source = read_file(path_join(getenv("GEN_ROOT", "."), "gen/diagnostics.md"))
  rules = reference_rules
  write_file(
    getenv("GEN_OUT", "docs/DIAGNOSTICS.md"),
    with_facts(source, (f) -> rules_fact(rules, f))
  )
end
