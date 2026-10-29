space("kenshutsu?", {status: :provisional})

verb(
  "kenshutsu?",
  "call_graph",
  {
    kind: :pure,
    shape: "call_graph(source) -> graph",
    laterals: [],
    fleet: "blue-lang-mondou",
    today: "rust:blue-lang-mondou",
    meaning: "who calls whom in a source",
    wave: 2,
    origin: "F"
  }
)

verb(
  "kenshutsu?",
  "census",
  {
    kind: :effect,
    shape: "census(root, opts) -> counts",
    laterals: ["test"],
    fleet: "blue-lang-cli",
    today: "rust:blue-lang-cli",
    meaning: "count each ratcheted finding under a root",
    wave: 0,
    origin: "F"
  }
)

verb(
  "kenshutsu?",
  "check",
  {
    kind: :pure,
    shape: "check(source, opts) -> [finding]",
    laterals: %w[error validate],
    fleet: "blue-lang-check",
    today: "rust:blue-lang-check",
    meaning: "findings of every rule on a source, in one pass",
    wave: 0,
    origin: "F"
  }
)

verb(
  "kenshutsu?",
  "clones",
  {
    kind: :pure,
    shape: "clones(sources, opts) -> [group]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "near-duplicate code, grouped",
    wave: 2,
    origin: "F"
  }
)

verb(
  "kenshutsu?",
  "complexity",
  {
    kind: :pure,
    shape: "complexity(definition) -> number",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "a size and branching measure of one definition",
    wave: 2,
    origin: "F"
  }
)

verb(
  "kenshutsu?",
  "explain",
  {
    kind: :pure,
    shape: "explain(code) -> text",
    laterals: [],
    fleet: "blue-lang-cli",
    today: "rust:blue-lang-cli",
    meaning: "what a rule code means, with its witness",
    wave: 0,
    origin: "F"
  }
)

verb(
  "kenshutsu?",
  "fix",
  {
    kind: :pure,
    shape: "fix(findings, source) -> source",
    laterals: ["migrate"],
    fleet: "blue-lang-check",
    today: "rust:blue-lang-check",
    meaning: "apply the safe fixes that findings carry",
    wave: 1,
    origin: "F"
  }
)

verb(
  "kenshutsu?",
  "format",
  {
    kind: :pure,
    shape: "format(source, opts) -> text",
    laterals: ["serialize"],
    fleet: "blue-lang-fmt",
    today: "rust:blue-lang-fmt",
    meaning: "the one canonical layout of a source",
    wave: 0,
    origin: "F"
  }
)

verb(
  "kenshutsu?",
  "formatted?",
  {
    kind: :pure,
    shape: "formatted?(source) -> Bool",
    laterals: ["validate"],
    fleet: "blue-lang-fmt",
    today: "rust:blue-lang-fmt",
    meaning: "whether a source is already in canonical layout",
    wave: 0,
    origin: "F"
  }
)

verb(
  "kenshutsu?",
  "list",
  {
    kind: :pure,
    shape: "list(kind) -> [row]",
    laterals: [],
    fleet: "blue-lang-check",
    today: "rust:blue-lang-check",
    meaning: "the rules, with code, severity and law",
    wave: 0,
    origin: "F"
  }
)

verb(
  "kenshutsu?",
  "scan",
  {
    kind: :effect,
    shape: "scan(subject, opts) -> [finding]",
    laterals: %w[capability deadline],
    fleet: "cse-lint",
    today: "absent",
    meaning: "look for secrets, advisories or licence problems",
    wave: 2,
    origin: "F"
  }
)

verb(
  "kenshutsu?",
  "unused",
  {
    kind: :pure,
    shape: "unused(project) -> [name]",
    laterals: [],
    fleet: "blue-lang-check",
    today: "rust:blue-lang-check",
    meaning: "definitions nothing reaches",
    wave: 1,
    origin: "F"
  }
)

edge("kenshutsu?::fix", :composes, "kakikae?::apply", "edits applied safely")

edge(
  "kenshutsu?::unused",
  :composes,
  "kenshutsu?::call_graph",
  "no incoming edge"
)

edge("kenshutsu?::census", :composes, "kenshutsu?::check", "counts findings")

edge(
  "kenshutsu?::clones",
  :composes,
  "koubun?::hash",
  "equal hashes are clones"
)

edge("kenshutsu?::check", :composes, "koubun?::parse", "rules run on a tree")
edge("kenshutsu?::format", :composes, "koubun?::render", "one layout")

edge(
  "kenshutsu?::check",
  :pairs,
  "hadome::judge",
  "ratcheted rules use baselines"
)

edge(
  "kenshutsu?::scan",
  :pairs,
  "himitsu::list",
  "secret scanning versus stored secrets"
)

edge(
  "kenshutsu?::formatted?",
  :pairs,
  "kaihatsu?::gate",
  "format check in the gate"
)

edge("kenshutsu?::unused", :pairs, "kakikae?::inline", "dead code or inline it")

edge(
  "kenshutsu?::clones",
  :pairs,
  "kakikae?::outline",
  "duplicates become one definition"
)

edge("kenshutsu?::fix", :pairs, "kakikae?::plan", "fixes are planned first")
edge("kenshutsu?::explain", :pairs, "kenshutsu?::check", "code to its meaning")

edge(
  "kenshutsu?::check",
  :pairs,
  "kenshutsu?::explain",
  "finding and its meaning"
)

edge("kenshutsu?::list", :pairs, "kenshutsu?::explain", "rule table")
edge("kenshutsu?::census", :pairs, "kenshutsu?::list", "rules with ratchets")

edge(
  "kenshutsu?::scan",
  :pairs,
  "rirezu?::sbom",
  "advisories on the parts list"
)

edge("kenshutsu?::complexity", :pairs, "tesuto?::cover", "risky and untested")

edge(
  "kenshutsu?::scan",
  :refines,
  "kenshutsu?::check",
  "checks data, not rules"
)

edge(
  "kenshutsu?::formatted?",
  :refines,
  "kenshutsu?::format",
  "format equals source"
)

edge(
  "kenshutsu?::check",
  :requires,
  "bunmyaku?::infer",
  "type rules need inference"
)

edge("kenshutsu?::fix", :requires, "kenshutsu?::check", "fixes the findings")
edge("kenshutsu?::format", :requires, "koubun?::parse", "layout from the tree")

edge(
  "kenshutsu?::call_graph",
  :requires,
  "koubun?::walk",
  "edges from the tree"
)

edge("kenshutsu?::complexity", :requires, "koubun?::walk", "counts branches")
