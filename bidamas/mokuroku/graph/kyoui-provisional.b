space("kyoui?", {status: :provisional})

verb(
  "kyoui?",
  "alert",
  {
    kind: :effect,
    shape: "alert(hit, sink, opts) -> nil",
    laterals: %w[idempotent log ratelimit],
    fleet: "tameshi",
    today: "absent",
    meaning: "send a deduplicated alert",
    wave: 2,
    origin: "D"
  }
)

verb(
  "kyoui?",
  "baseline",
  {
    kind: :pure,
    shape: "baseline(events, opts) -> profile",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "learn normal behaviour of an actor or service",
    wave: 3,
    origin: "D"
  }
)

verb(
  "kyoui?",
  "correlate",
  {
    kind: :pure,
    shape: "correlate(alerts, window) -> [incident]",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "group alerts of one actor or asset in a window",
    wave: 3,
    origin: "D"
  }
)

verb(
  "kyoui?",
  "detect",
  {
    kind: :stream,
    shape: "detect(events, rules, opts) -> [alert]",
    laterals: %w[cancel log],
    fleet: "bm-guard",
    today: "absent",
    meaning: "match a stream of events; alerts as they occur",
    wave: 2,
    origin: "D"
  }
)

verb(
  "kyoui?",
  "deviates?",
  {
    kind: :pure,
    shape: "deviates?(event, baseline) -> Bool",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "event lies outside the learned normal",
    wave: 3,
    origin: "D"
  }
)

verb(
  "kyoui?",
  "honeytoken",
  {
    kind: :effect,
    shape: "honeytoken(kind, place) -> token",
    laterals: %w[capability log],
    fleet: nil,
    today: "absent",
    meaning: "plant a fake secret whose use raises an alert",
    wave: 4,
    origin: "D"
  }
)

verb(
  "kyoui?",
  "hunt",
  {
    kind: :effect,
    shape: "hunt(store, indicators) -> [hit]",
    laterals: %w[deadline resource],
    fleet: nil,
    today: "absent",
    meaning: "search stored events for indicators",
    wave: 3,
    origin: "D"
  }
)

verb(
  "kyoui?",
  "indicator",
  {
    kind: :decl,
    shape: "indicator(kind, value, opts) -> indicator",
    laterals: %w[config time],
    fleet: "kagemusha",
    today: "absent",
    meaning: "a known-bad hash, address or domain, with expiry",
    wave: 3,
    origin: "D"
  }
)

verb(
  "kyoui?",
  "match",
  {
    kind: :pure,
    shape: "match(rules, event) -> [hit]",
    laterals: ["validate"],
    fleet: "guardrail",
    today: "absent",
    meaning: "the rules an event triggers",
    wave: 1,
    origin: "D"
  }
)

verb(
  "kyoui?",
  "model",
  {
    kind: :decl,
    shape: "model(system, assets, boundaries) -> model",
    laterals: ["config"],
    fleet: nil,
    today: "absent",
    meaning: "a system as assets, flows and trust boundaries",
    wave: 2,
    origin: "D"
  }
)

verb(
  "kyoui?",
  "playbook",
  {
    kind: :decl,
    shape: "playbook(name, steps) -> playbook",
    laterals: ["config"],
    fleet: nil,
    today: "absent",
    meaning: "ordered, reversible steps that contain an incident",
    wave: 4,
    origin: "D"
  }
)

verb(
  "kyoui?",
  "rank",
  {
    kind: :pure,
    shape: "rank(threats, opts) -> [threat]",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "threats ordered by impact and likelihood",
    wave: 2,
    origin: "D"
  }
)

verb(
  "kyoui?",
  "respond",
  {
    kind: :effect,
    shape: "respond(incident, playbook, opts) -> run",
    laterals: %w[idempotent log process],
    fleet: nil,
    today: "absent",
    meaning: "run a playbook against an incident, logging each step",
    wave: 4,
    origin: "D"
  }
)

verb(
  "kyoui?",
  "rule",
  {
    kind: :decl,
    shape: "rule(name, match, opts) -> rule",
    laterals: ["config"],
    fleet: "guardrail",
    today: "absent",
    meaning: "a detection rule: pattern, severity, tags",
    wave: 1,
    origin: "D"
  }
)

verb(
  "kyoui?",
  "threats",
  {
    kind: :pure,
    shape: "threats(model, method) -> [threat]",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "threats per element by a method such as STRIDE",
    wave: 2,
    origin: "D"
  }
)

verb(
  "kyoui?",
  "triage",
  {
    kind: :pure,
    shape: "triage(alert, context) -> verdict",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "decide: ignore, watch or page",
    wave: 3,
    origin: "D"
  }
)

verb(
  "kyoui?",
  "uncovered",
  {
    kind: :pure,
    shape: "uncovered(model, controls) -> [threat]",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "threats with no control against them",
    wave: 2,
    origin: "D"
  }
)

verb(
  "kyoui?",
  "witness",
  {
    kind: :decl,
    shape: "witness(rule, positive, negative) -> witness",
    laterals: ["test"],
    fleet: "guardrail",
    today: "absent",
    meaning: "samples a rule must fire on and must not",
    wave: 1,
    origin: "D"
  }
)

edge("kyoui?::honeytoken", :composes, "kyoui?::alert", "any use alerts")

edge(
  "kyoui?::honeytoken",
  :composes,
  "kyoui?::indicator",
  "its use is an indicator"
)

edge(
  "kyoui?::alert",
  :composes,
  "nisshi::audit",
  "alerts also reach the audit log"
)

edge("kyoui?::respond", :composes, "nisshi::audit", "every step logged")
edge("kyoui?::hunt", :composes, "nisshi::query", "search the audit log")

edge(
  "kyoui?::rule",
  :guards,
  "jouka?::hostile",
  "hostile strings are rule samples"
)

edge("kyoui?::witness", :guards, "kyoui?::rule", "rule must fire and must not")
edge("kyoui?::detect", :lifts, "kyoui?::match", "match over a stream")
edge("kyoui?::hunt", :lifts, "kyoui?::match", "match stored events")
edge("kyoui?::baseline", :pairs, "kyoui?::deviates?", "learned then compared")
edge("kyoui?::indicator", :pairs, "kyoui?::hunt", "known bad, searched for")
edge("kyoui?::playbook", :pairs, "kyoui?::respond", "declared then run")
edge("kyoui?::model", :pairs, "kyoui?::threats", "declared then analysed")

edge(
  "kyoui?::rule",
  :pairs,
  "kyoui?::witness",
  "every rule carries its samples"
)

edge(
  "kyoui?::uncovered",
  :requires,
  "junshu?::list",
  "controls to compare with"
)

edge("kyoui?::correlate", :requires, "kyoui?::alert", "group alerts")
edge("kyoui?::deviates?", :requires, "kyoui?::baseline", "compares to normal")
edge("kyoui?::triage", :requires, "kyoui?::correlate", "judge an incident")
edge("kyoui?::alert", :requires, "kyoui?::match", "alert on a hit")
edge("kyoui?::threats", :requires, "kyoui?::model", "per element of the model")
edge("kyoui?::match", :requires, "kyoui?::rule", "apply the rules")
edge("kyoui?::rank", :requires, "kyoui?::threats", "orders the threats")

edge(
  "kyoui?::uncovered",
  :requires,
  "kyoui?::threats",
  "threats without controls"
)

edge("kyoui?::respond", :requires, "kyoui?::triage", "respond after a verdict")
