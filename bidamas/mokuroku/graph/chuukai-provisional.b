space("chuukai?", {status: :provisional})

verb(
  "chuukai?",
  "authorize",
  {
    kind: :pure,
    shape: "authorize(request, policy) -> decision",
    laterals: %w[capability error],
    fleet: nil,
    today: "absent",
    meaning: "Decide whether a caller may reach a route.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "chuukai?",
  "drain",
  {
    kind: :effect,
    shape: "drain(target) -> nil",
    laterals: %w[cancel deadline],
    fleet: nil,
    today: "absent",
    meaning: "Stop new traffic to a target; finish in-flight.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "chuukai?",
  "eject",
  {
    kind: :effect,
    shape: "eject(upstream, target, duration) -> nil",
    laterals: ["switch"],
    fleet: nil,
    today: "absent",
    meaning: "Remove an unhealthy target for a while.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "chuukai?",
  "forward",
  {
    kind: :effect,
    shape: "forward(request, upstream, opts) -> response",
    laterals: %w[deadline error retry trace],
    fleet: nil,
    today: "absent",
    meaning: "Pass a request to an upstream and return its answer.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "chuukai?",
  "mirror",
  {
    kind: :effect,
    shape: "mirror(request, upstream) -> nil",
    laterals: ["trace"],
    fleet: nil,
    today: "absent",
    meaning: "Copy traffic to another upstream and drop the answer.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "chuukai?",
  "pick",
  {
    kind: :pure,
    shape: "pick(upstream, strategy, request) -> target",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "Choose a target: round robin, least load or hash.",
    wave: 2,
    origin: "C",
    contract: "pick(upstream, strategy, opts) -> target"
  }
)

verb(
  "chuukai?",
  "policy",
  {
    kind: :decl,
    shape: "policy(mesh, rule) -> mesh",
    laterals: %w[capability config],
    fleet: "tatara-mesh",
    today: "absent",
    meaning: "Declare retry, timeout, mTLS and identity for a mesh.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "chuukai?",
  "probe",
  {
    kind: :effect,
    shape: "probe(target, probe) -> record",
    laterals: ["deadline"],
    fleet: nil,
    today: "absent",
    meaning: "Probe a target's health.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "chuukai?",
  "purge",
  {
    kind: :effect,
    shape: "purge(cdn, target) -> count",
    laterals: %w[cache idempotent],
    fleet: nil,
    today: "absent",
    meaning: "Drop cached objects by URL, tag or prefix.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "chuukai?",
  "rewrite",
  {
    kind: :pure,
    shape: "rewrite(request, rule) -> request",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "Change path, host or headers by a rule.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "chuukai?",
  "route",
  {
    kind: :decl,
    shape: "route(match, upstream, opts) -> rule",
    laterals: ["validate"],
    fleet: "tatara-mesh",
    today: "absent",
    meaning: "Declare which requests go to which upstream.",
    wave: 2,
    origin: "C",
    contract: "route(match, upstream) -> rule"
  }
)

verb(
  "chuukai?",
  "stats",
  {
    kind: :effect,
    shape: "stats(upstream) -> record",
    laterals: ["trace"],
    fleet: nil,
    today: "absent",
    meaning: "Requests, errors and latency per target.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "chuukai?",
  "terminate",
  {
    kind: :effect,
    shape: "terminate(listener, certificates) -> listener",
    laterals: ["capability"],
    fleet: nil,
    today: "absent",
    meaning: "Accept TLS and pass plain traffic on.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "chuukai?",
  "ttl",
  {
    kind: :decl,
    shape: "ttl(rule, duration) -> rule",
    laterals: %w[cache time],
    fleet: nil,
    today: "absent",
    meaning: "Declare how long an edge may keep a response.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "chuukai?",
  "tunnel",
  {
    kind: :effect,
    shape: "tunnel(client, target) -> info",
    laterals: %w[cancel resource],
    fleet: nil,
    today: "absent",
    meaning: "Relay raw bytes between two connections (CONNECT).",
    wave: 3,
    origin: "C"
  }
)

verb(
  "chuukai?",
  "upstream",
  {
    kind: :decl,
    shape: "upstream(name, targets, opts) -> upstream",
    laterals: ["config"],
    fleet: nil,
    today: "absent",
    meaning: "Declare a named set of backend targets.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "chuukai?",
  "warm",
  {
    kind: :effect,
    shape: "warm(cdn, urls) -> count",
    laterals: ["cache"],
    fleet: nil,
    today: "absent",
    meaning: "Fetch URLs so the edge holds them before traffic.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "chuukai?",
  "weigh",
  {
    kind: :decl,
    shape: "weigh(upstreams, weights) -> rule",
    laterals: ["config"],
    fleet: nil,
    today: "absent",
    meaning: "Divide traffic by weight, for canary or blue-green.",
    wave: 3,
    origin: "C"
  }
)

edge("chuukai?::forward", :composes, "chuukai?::pick", "choose a target")

edge(
  "chuukai?::route",
  :composes,
  "kyuuji::route",
  "gateway rule over a server route"
)

edge("chuukai?::tunnel", :composes, "sokketto?::pipe", "byte relay")

edge(
  "chuukai?::terminate",
  :composes,
  "sokketto?::secure",
  "TLS on the listener side"
)

edge(
  "chuukai?::forward",
  :composes,
  "tsuushin::request",
  "sends the request on"
)

edge("chuukai?::policy", :generalizes, "chuukai?::route", "mesh-wide rules")

edge(
  "chuukai?::authorize",
  :guards,
  "chuukai?::forward",
  "decision before forwarding"
)

edge("chuukai?::pick", :guards, "chuukai?::forward", "a healthy target only")

edge(
  "chuukai?::rewrite",
  :guards,
  "chuukai?::forward",
  "applied before forwarding"
)

edge(
  "chuukai?::upstream",
  :inverse,
  "chuukai?::eject",
  "removes a declared target"
)

edge("chuukai?::warm", :inverse, "chuukai?::purge", "drop and fill the edge")

edge(
  "chuukai?::eject",
  :inverse,
  "chuukai?::upstream",
  "removes a declared target"
)

edge("chuukai?::purge", :inverse, "chuukai?::warm", "drop and fill the edge")
edge("chuukai?::stats", :lifts, "kyuuji::observe", "per-target metrics")

edge(
  "chuukai?::probe",
  :pairs,
  "chuukai?::eject",
  "failed probe leads to eject"
)

edge("chuukai?::upstream", :pairs, "chuukai?::route", "targets and rules")
edge("chuukai?::purge", :pairs, "chuukai?::ttl", "invalidation beside expiry")

edge(
  "chuukai?::forward",
  :pairs,
  "kyoujin?::protect",
  "upstream calls pass a breaker"
)

edge(
  "chuukai?::stats",
  :pairs,
  "shihyou::error_ratio",
  "edge metrics feed objectives"
)

edge(
  "chuukai?::terminate",
  :pairs,
  "sokketto?::certificate",
  "certificates at the edge"
)

edge("chuukai?::pick", :pairs, "toutatsu?::find", "targets come from discovery")
edge("chuukai?::ttl", :pairs, "tsuushin::fresh?", "server sets, client judges")

edge(
  "chuukai?::mirror",
  :refines,
  "chuukai?::forward",
  "forward that drops the reply"
)

edge("chuukai?::weigh", :refines, "chuukai?::route", "weighted route")
edge("chuukai?::drain", :refines, "kyoujin?::drain", "drain for one target")
edge("chuukai?::probe", :refines, "kyoujin?::probe", "a probe of one target")

edge(
  "chuukai?::eject",
  :requires,
  "chuukai?::probe",
  "ejects what checks failed"
)

edge(
  "chuukai?::forward",
  :requires,
  "chuukai?::route",
  "a route picks the upstream"
)

edge(
  "chuukai?::pick",
  :requires,
  "chuukai?::upstream",
  "chooses within an upstream"
)
