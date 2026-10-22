space("kijun", {status: :ratified})

verb(
  "kijun",
  "check",
  {
    kind: :effect,
    shape: "check(repo, config) -> [finding]",
    laterals: ["test", "validate"],
    fleet: "kijun",
    today: "exists:kijun",
    meaning: "hold a repo to its standard, findings as data",
    wave: 0,
    origin: "E"
  }
)

verb(
  "kijun",
  "explain",
  {
    kind: :pure,
    shape: "explain(rule) -> text",
    laterals: [],
    fleet: "kijun",
    today: "partial:kijun",
    meaning: "why a rule exists and how to fix it",
    wave: 1,
    origin: "E"
  }
)

verb(
  "kijun",
  "list",
  {
    kind: :pure,
    shape: "list(config) -> [rule]",
    laterals: ["config"],
    fleet: "kijun",
    today: "partial:kijun",
    meaning: "rules a standard enforces",
    wave: 1,
    origin: "E"
  }
)

verb(
  "kijun",
  "ratchet",
  {
    kind: :effect,
    shape: "ratchet(findings, baseline) -> verdict",
    laterals: ["serialize", "validate"],
    fleet: "hadome",
    today: "exists:hadome",
    meaning: "recorded debt may shrink or hold, never grow",
    wave: 0,
    origin: "E"
  }
)

verb(
  "kijun",
  "waive",
  {
    kind: :decl,
    shape: "waive(config, rule, glob, reason) -> config",
    laterals: ["config"],
    fleet: "kijun",
    today: "exists:kijun",
    meaning: "exempt one path from one rule with a reason",
    wave: 0,
    origin: "E",
    contract: "waive(config, rule, glob) -> config"
  }
)

edge("kijun::check", :composes, "kijun::list", "runs every rule")
edge("kijun::check", :composes, "nikkusu::find", "rules query nix source")
edge("kijun::ratchet", :guards, "kijun::check", "findings may not grow")
edge("kijun::waive", :guards, "kijun::check", "exempts a path from a rule")
edge("kijun::explain", :pairs, "kijun::check", "findings link to explanations")
edge("kijun::list", :refines, "core::list", "rules of a standard")
edge("kijun::explain", :requires, "kijun::list", "rules to explain")
