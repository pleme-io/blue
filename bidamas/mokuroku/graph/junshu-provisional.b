space("junshu?", {status: :provisional})

verb(
  "junshu?",
  "assess",
  {
    kind: :effect,
    shape: "assess(target, pack, opts) -> [result]",
    laterals: %w[process resource test],
    fleet: "kensa",
    today: "absent",
    meaning: "run a pack of compliance tests against a target",
    wave: 1,
    origin: "D"
  }
)

verb(
  "junshu?",
  "certify",
  {
    kind: :effect,
    shape: "certify(assessment, key) -> certificate",
    laterals: %w[capability log],
    fleet: "tameshi",
    today: "absent",
    meaning: "sign an assessment as a dated certification",
    wave: 3,
    origin: "D"
  }
)

verb(
  "junshu?",
  "collect",
  {
    kind: :effect,
    shape: "collect(source, opts) -> [evidence]",
    laterals: %w[deadline resource],
    fleet: "tameshi-watch",
    today: "absent",
    meaning: "gather results from external scanners",
    wave: 2,
    origin: "D"
  }
)

verb(
  "junshu?",
  "control",
  {
    kind: :decl,
    shape: "control(id, framework, statement, opts) -> control",
    laterals: ["config"],
    fleet: "compliance-controls",
    today: "absent",
    meaning: "a named requirement from NIST, CIS, FedRAMP or SOC2",
    wave: 2,
    origin: "D"
  }
)

verb(
  "junshu?",
  "drift",
  {
    kind: :pure,
    shape: "drift(before, after) -> [change]",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "controls whose status changed between assessments",
    wave: 2,
    origin: "D"
  }
)

verb(
  "junshu?",
  "evidence",
  {
    kind: :pure,
    shape: "evidence(result, opts) -> record",
    laterals: %w[time validate],
    fleet: "tameshi-watch",
    today: "absent",
    meaning: "a result bound to target, time, tool and digest",
    wave: 1,
    origin: "D"
  }
)

verb(
  "junshu?",
  "gap",
  {
    kind: :pure,
    shape: "gap(catalog, evidence) -> [control]",
    laterals: ["validate"],
    fleet: "tameshi",
    today: "absent",
    meaning: "controls with no passing evidence",
    wave: 2,
    origin: "D"
  }
)

verb(
  "junshu?",
  "inherit",
  {
    kind: :decl,
    shape: "inherit(control, provider) -> control",
    laterals: ["config"],
    fleet: nil,
    today: "absent",
    meaning: "a control met by a provider under shared responsibility",
    wave: 4,
    origin: "D"
  }
)

verb(
  "junshu?",
  "lapsed",
  {
    kind: :pure,
    shape: "lapsed(waivers, now) -> [waiver]",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "waivers whose end date has passed",
    wave: 2,
    origin: "D"
  }
)

verb(
  "junshu?",
  "list",
  {
    kind: :pure,
    shape: "list(framework, opts) -> [control]",
    laterals: ["config"],
    fleet: "compliance-profiles",
    today: "absent",
    meaning: "every control of a framework",
    wave: 2,
    origin: "D"
  }
)

verb(
  "junshu?",
  "mapping",
  {
    kind: :decl,
    shape: "mapping(check, controls) -> mapping",
    laterals: ["config"],
    fleet: "kensa",
    today: "absent",
    meaning: "which controls a test gives evidence for",
    wave: 2,
    origin: "D"
  }
)

verb(
  "junshu?",
  "pack",
  {
    kind: :decl,
    shape: "pack(name, tests, opts) -> pack",
    laterals: %w[config test],
    fleet: "provas",
    today: "absent",
    meaning: "a pinned set of tests with a deterministic hash",
    wave: 2,
    origin: "D"
  }
)

verb(
  "junshu?",
  "parse",
  {
    kind: :pure,
    shape: "parse(text, format) -> assessment",
    laterals: %w[serialize validate],
    fleet: "kensa",
    today: "absent",
    meaning: "OSCAL, SARIF or JUnit text to an assessment",
    wave: 3,
    origin: "D"
  }
)

verb(
  "junshu?",
  "render",
  {
    kind: :pure,
    shape: "render(assessment, format) -> text",
    laterals: ["serialize"],
    fleet: "kensa",
    today: "absent",
    meaning: "assessment as OSCAL, SARIF or JUnit text",
    wave: 2,
    origin: "D"
  }
)

verb(
  "junshu?",
  "rollup",
  {
    kind: :pure,
    shape: "rollup(results, by) -> [record]",
    laterals: ["validate"],
    fleet: "kensa",
    today: "absent",
    meaning: "pass counts per control family",
    wave: 2,
    origin: "D"
  }
)

verb(
  "junshu?",
  "waive",
  {
    kind: :decl,
    shape: "waive(control, why, until) -> waiver",
    laterals: %w[config time],
    fleet: nil,
    today: "absent",
    meaning: "time-boxed, reasoned exception to a control",
    wave: 1,
    origin: "D"
  }
)

verb(
  "junshu?",
  "watch",
  {
    kind: :stream,
    shape: "watch(sources, f, opts) -> nil",
    laterals: %w[cancel resource],
    fleet: "tameshi-watch",
    today: "absent",
    meaning: "keep assessing as new results arrive",
    wave: 3,
    origin: "D"
  }
)

edge(
  "junshu?::assess",
  :composes,
  "junshu?::evidence",
  "results become evidence"
)

edge("junshu?::assess", :composes, "junshu?::pack", "run the pack tests")
edge("junshu?::gap", :composes, "junshu?::rollup", "controls with zero passes")

edge(
  "junshu?::render",
  :composes,
  "junshu?::rollup",
  "summary in the rendered report"
)

edge("junshu?::assess", :composes, "nisshi::audit", "each run is logged")
edge("junshu?::pack", :composes, "shomei::hash", "deterministic pack hash")
edge("junshu?::certify", :composes, "shomei::sign", "signed assessment")

edge(
  "junshu?::waive",
  :guards,
  "junshu?::gap",
  "a waiver removes a control from the gap"
)

edge("junshu?::render", :inverse, "junshu?::parse", "assessment to text")
edge("junshu?::parse", :inverse, "junshu?::render", "assessment to text")
edge("junshu?::watch", :lifts, "junshu?::collect", "continuous collection")

edge(
  "junshu?::collect",
  :lifts,
  "junshu?::evidence",
  "many sources of evidence"
)

edge("junshu?::pack", :pairs, "junshu?::assess", "declared then run")
edge("junshu?::control", :pairs, "junshu?::list", "declared and listed")

edge(
  "junshu?::evidence",
  :pairs,
  "kyoukyuu?::attest",
  "evidence is signed as an attestation"
)

edge(
  "junshu?::certify",
  :pairs,
  "kyoukyuu?::verify?",
  "certificates are verified like signatures"
)

edge(
  "junshu?::inherit",
  :refines,
  "junshu?::control",
  "a control satisfied by a provider"
)

edge(
  "junshu?::drift",
  :refines,
  "kyoukyuu?::diff",
  "difference between assessments"
)

edge(
  "junshu?::list",
  :requires,
  "junshu?::control",
  "catalog of declared controls"
)

edge(
  "junshu?::mapping",
  :requires,
  "junshu?::control",
  "maps checks to controls"
)

edge("junshu?::certify", :requires, "junshu?::gap", "no gaps outside waivers")

edge(
  "junshu?::gap",
  :requires,
  "junshu?::list",
  "compares catalog and evidence"
)

edge(
  "junshu?::rollup",
  :requires,
  "junshu?::mapping",
  "group results by control family"
)

edge("junshu?::lapsed", :requires, "junshu?::waive", "waivers past their end")
