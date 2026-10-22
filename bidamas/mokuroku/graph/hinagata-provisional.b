space("hinagata?", {status: :provisional})

verb(
  "hinagata?",
  "expand",
  {
    kind: :pure,
    shape: "expand(form, opts) -> form",
    laterals: ["trace"],
    fleet: "tatara-lisp",
    today: "rust:blue-lang-runtime",
    meaning: "a form after macros, step by step on request",
    wave: 0,
    origin: "F"
  }
)

verb(
  "hinagata?",
  "fill",
  {
    kind: :pure,
    shape: "fill(template, data) -> text",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "a template with its holes filled from data",
    wave: 1,
    origin: "F"
  }
)

verb(
  "hinagata?",
  "fresh?",
  {
    kind: :pure,
    shape: "fresh?(file, project) -> Bool",
    laterals: ["validate"],
    fleet: "blue-lang-pkg",
    today: "rust:blue-lang-pkg",
    meaning: "whether a generated file equals its generator output",
    wave: 0,
    origin: "F"
  }
)

verb(
  "hinagata?",
  "generate",
  {
    kind: :effect,
    shape: "generate(spec, target, opts) -> [file]",
    laterals: ["idempotent", "serialize"],
    fleet: "forge-gen",
    today: "absent",
    meaning: "code and docs derived from a spec",
    wave: 2,
    origin: "F"
  }
)

verb(
  "hinagata?",
  "list",
  {
    kind: :pure,
    shape: "list(kind) -> [row]",
    laterals: [],
    fleet: "repo-forge",
    today: "absent",
    meaning: "the archetypes or generators available",
    wave: 2,
    origin: "F"
  }
)

verb(
  "hinagata?",
  "macro",
  {
    kind: :decl,
    shape: "macro(name, params, body) -> macro",
    laterals: ["migrate"],
    fleet: "tatara-lisp",
    today: "rust:blue-lang-runtime",
    meaning: "declare a rewrite that runs before evaluation",
    wave: 0,
    origin: "F"
  }
)

verb(
  "hinagata?",
  "parse",
  {
    kind: :pure,
    shape: "parse(text) -> template",
    laterals: ["serialize", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "template text to a template that names its holes",
    wave: 1,
    origin: "F"
  }
)

verb(
  "hinagata?",
  "plan",
  {
    kind: :pure,
    shape: "plan(spec, target) -> [change]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "which files a generate or scaffold would write",
    wave: 1,
    origin: "F"
  }
)

verb(
  "hinagata?",
  "regen",
  {
    kind: :effect,
    shape: "regen(project) -> [file]",
    laterals: ["idempotent"],
    fleet: "blue-lang-pkg",
    today: "rust:blue-lang-pkg",
    meaning: "rewrite every generated file from its program",
    wave: 0,
    origin: "F"
  }
)

verb(
  "hinagata?",
  "scaffold",
  {
    kind: :effect,
    shape: "scaffold(archetype, dest, data) -> [file]",
    laterals: ["idempotent"],
    fleet: "repo-forge",
    today: "rust:blue-lang-cli",
    meaning: "new files from an archetype, never over existing ones",
    wave: 1,
    origin: "F"
  }
)

edge("hinagata?::scaffold", :composes, "hinagata?::fill", "fills each file")

edge(
  "hinagata?::regen",
  :composes,
  "hinagata?::generate",
  "rerun every generator"
)

edge("hinagata?::list", :generalizes, "hinagata?::plan", "inputs of both")
edge("hinagata?::plan", :guards, "hinagata?::generate", "lists files first")
edge("hinagata?::fresh?", :guards, "hinagata?::regen", "stale files need regen")

edge(
  "hinagata?::parse",
  :inverse,
  "hinagata?::fill",
  "text to template and back"
)

edge(
  "hinagata?::fill",
  :inverse,
  "hinagata?::parse",
  "text to template and back"
)

edge(
  "hinagata?::expand",
  :pairs,
  "genin?::trace",
  "expansion steps are traceable"
)

edge(
  "hinagata?::generate",
  :pairs,
  "hinagata?::fresh?",
  "generated files stay fresh"
)

edge("hinagata?::generate", :pairs, "hinagata?::plan", "preview of the files")

edge(
  "hinagata?::fresh?",
  :pairs,
  "hinagata?::regen",
  "check and fix of one file"
)

edge("hinagata?::list", :pairs, "hinagata?::scaffold", "archetypes to scaffold")
edge("hinagata?::regen", :pairs, "kaihatsu?::gate", "gate runs regen")

edge(
  "hinagata?::scaffold",
  :pairs,
  "kaihatsu?::new",
  "new project is a scaffold"
)

edge(
  "hinagata?::fill",
  :pairs,
  "kenshutsu?::format",
  "filled text is formatted"
)

edge(
  "hinagata?::macro",
  :pairs,
  "koubun?::normalize",
  "macro output is normalized"
)

edge(
  "hinagata?::generate",
  :refines,
  "hinagata?::scaffold",
  "from a spec, repeatable"
)

edge(
  "hinagata?::macro",
  :requires,
  "hinagata?::expand",
  "declared to be expanded"
)

edge("hinagata?::scaffold", :requires, "hinagata?::list", "picks an archetype")
edge("hinagata?::expand", :requires, "koubun?::parse", "rewrites forms")
