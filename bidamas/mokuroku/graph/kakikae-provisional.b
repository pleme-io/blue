space("kakikae?", {status: :provisional})

verb(
  "kakikae?",
  "apply",
  {
    kind: :effect,
    shape: "apply(edits, opts) -> nil",
    laterals: ["idempotent", "migrate"],
    fleet: "blue-lang-cli",
    today: "rust:blue-lang-cli",
    meaning: "write edits, each file only if its tree stays proven",
    wave: 1,
    origin: "F"
  }
)

verb(
  "kakikae?",
  "deprecate",
  {
    kind: :decl,
    shape: "deprecate(name, replacement, until) -> row",
    laterals: ["migrate", "switch"],
    fleet: nil,
    today: "absent",
    meaning: "mark a name as replaced, with a date it goes",
    wave: 2,
    origin: "F"
  }
)

verb(
  "kakikae?",
  "inline",
  {
    kind: :pure,
    shape: "inline(project, name) -> [edit]",
    laterals: ["migrate"],
    fleet: nil,
    today: "absent",
    meaning: "the edits that put a definition at each use",
    wave: 2,
    origin: "F"
  }
)

verb(
  "kakikae?",
  "migrate",
  {
    kind: :effect,
    shape: "migrate(files, rule) -> [file]",
    laterals: ["migrate"],
    fleet: "blue-lang-cli",
    today: "rust:blue-lang-cli",
    meaning: "move files to a new form with a proof per file",
    wave: 0,
    origin: "F"
  }
)

verb(
  "kakikae?",
  "move",
  {
    kind: :pure,
    shape: "move(project, name, to) -> [edit]",
    laterals: ["migrate"],
    fleet: nil,
    today: "absent",
    meaning: "the edits that relocate a definition and fix references",
    wave: 2,
    origin: "F",
    contract: "move(project, name, opts) -> [edit]"
  }
)

verb(
  "kakikae?",
  "outline",
  {
    kind: :pure,
    shape: "outline(tree, span, name) -> [edit]",
    laterals: ["migrate"],
    fleet: nil,
    today: "absent",
    meaning: "the edits that move a span into a new definition",
    wave: 2,
    origin: "F"
  }
)

verb(
  "kakikae?",
  "plan",
  {
    kind: :pure,
    shape: "plan(edits) -> [change]",
    laterals: ["migrate"],
    fleet: nil,
    today: "absent",
    meaning: "what applying edits would change, as data",
    wave: 1,
    origin: "F"
  }
)

verb(
  "kakikae?",
  "preserves?",
  {
    kind: :pure,
    shape: "preserves?(before, after) -> Bool",
    laterals: ["validate"],
    fleet: "blue-lang-cli",
    today: "rust:blue-lang-cli",
    meaning: "whether two sources resolve to the same tree",
    wave: 0,
    origin: "F"
  }
)

verb(
  "kakikae?",
  "rename",
  {
    kind: :pure,
    shape: "rename(project, from, to) -> [edit]",
    laterals: ["migrate"],
    fleet: "blue-lang-mondou",
    today: "rust:blue-lang-mondou",
    meaning: "the edits that rename a name and all its uses",
    wave: 1,
    origin: "F"
  }
)

verb(
  "kakikae?",
  "replace",
  {
    kind: :pure,
    shape: "replace(tree, pattern, template) -> tree",
    laterals: ["migrate"],
    fleet: nil,
    today: "absent",
    meaning: "structural search and replace over a tree",
    wave: 2,
    origin: "F"
  }
)

verb(
  "kakikae?",
  "rewrite",
  {
    kind: :pure,
    shape: "rewrite(tree, rule) -> tree",
    laterals: ["migrate"],
    fleet: nil,
    today: "rust:blue-lang-runtime",
    meaning: "apply a term rewrite rule to a tree",
    wave: 1,
    origin: "F"
  }
)

verb(
  "kakikae?",
  "undo",
  {
    kind: :effect,
    shape: "undo(edits) -> nil",
    laterals: ["migrate"],
    fleet: nil,
    today: "absent",
    meaning: "restore the files an apply changed",
    wave: 2,
    origin: "F"
  }
)

edge("kakikae?::rename", :composes, "bunmyaku?::references", "edits every use")
edge("kakikae?::migrate", :composes, "kakikae?::apply", "apply per file")
edge("kakikae?::migrate", :composes, "kakikae?::preserves?", "proof per file")
edge("kakikae?::move", :composes, "kakikae?::rename", "fixes references")

edge(
  "kakikae?::outline",
  :composes,
  "kakikae?::rewrite",
  "new definition and call"
)

edge(
  "kakikae?::preserves?",
  :composes,
  "koubun?::normalize",
  "compares normal trees"
)

edge("kakikae?::replace", :composes, "koubun?::query", "finds then replaces")
edge("kakikae?::plan", :guards, "kakikae?::apply", "preview before writing")
edge("kakikae?::undo", :inverse, "kakikae?::apply", "write and restore")
edge("kakikae?::outline", :inverse, "kakikae?::inline", "puts the body back")
edge("kakikae?::inline", :inverse, "kakikae?::outline", "puts the body back")
edge("kakikae?::apply", :inverse, "kakikae?::undo", "write and restore")

edge(
  "kakikae?::rewrite",
  :pairs,
  "hinagata?::macro",
  "a macro is a rewrite at load time"
)

edge("kakikae?::move", :pairs, "kakikae?::deprecate", "move leaves a shim")
edge("kakikae?::outline", :pairs, "kakikae?::inline", "inverse refactors")

edge(
  "kakikae?::deprecate",
  :pairs,
  "kakikae?::migrate",
  "marks, then migrates callers"
)

edge("kakikae?::replace", :pairs, "kakikae?::plan", "replace is previewed")

edge(
  "kakikae?::deprecate",
  :pairs,
  "kenshutsu?::check",
  "use of a deprecated name is a finding"
)

edge(
  "kakikae?::migrate",
  :pairs,
  "nisshi::append",
  "each migration is recorded"
)

edge("kakikae?::preserves?", :pairs, "tesuto?::run", "proof or tests")
edge("kakikae?::rename", :refines, "kakikae?::move", "rename within a scope")

edge(
  "kakikae?::replace",
  :refines,
  "kakikae?::rewrite",
  "pattern and template form"
)

edge(
  "kakikae?::undo",
  :requires,
  "kakikae?::plan",
  "undo needs the recorded change"
)

edge(
  "kakikae?::apply",
  :requires,
  "kakikae?::preserves?",
  "writes only proven files"
)

edge("kakikae?::rewrite", :requires, "koubun?::parse", "works on a tree")
