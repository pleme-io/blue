space("bougyo", {status: :ratified})

verb(
  "bougyo",
  "audit",
  {
    kind: :decl,
    shape: "audit(opts) -> posture",
    laterals: ["config", "log"],
    fleet: nil,
    today: "absent",
    meaning: "record each decision as an audit record",
    wave: 2,
    origin: "D",
    contract: "audit(actor, action, target, outcome, opts) -> posture"
  }
)

verb(
  "bougyo",
  "authenticate",
  {
    kind: :decl,
    shape: "authenticate(opts) -> posture",
    laterals: ["config", "switch"],
    fleet: "pleme-auth-sdk",
    today: "absent",
    meaning: "attach the caller identity to each request",
    wave: 2,
    origin: "D"
  }
)

verb(
  "bougyo",
  "authorize",
  {
    kind: :decl,
    shape: "authorize(opts) -> posture",
    laterals: ["config", "switch"],
    fleet: "pleme-rbac",
    today: "absent",
    meaning: "permit or deny each request by policy",
    wave: 2,
    origin: "D"
  }
)

verb(
  "bougyo",
  "broken",
  {
    kind: :pure,
    shape: "broken(settings, request) -> record or nil",
    laterals: ["validate"],
    fleet: nil,
    today: "partial:bougyo",
    meaning: "first limit a request breaks, as status and reason",
    wave: 0,
    origin: "D"
  }
)

verb(
  "bougyo",
  "cors",
  {
    kind: :decl,
    shape: "cors(opts) -> posture",
    laterals: ["config", "switch"],
    fleet: nil,
    today: "absent",
    meaning: "cross-origin rules as an explicit allow-list",
    wave: 1,
    origin: "D"
  }
)

verb(
  "bougyo",
  "csp",
  {
    kind: :decl,
    shape: "csp(opts) -> posture",
    laterals: ["config", "switch"],
    fleet: nil,
    today: "absent",
    meaning: "content security policy with a fresh nonce per response",
    wave: 1,
    origin: "D"
  }
)

verb(
  "bougyo",
  "csrf",
  {
    kind: :decl,
    shape: "csrf(opts) -> posture",
    laterals: ["config", "switch"],
    fleet: nil,
    today: "absent",
    meaning: "state-changing requests carry a token or same-site proof",
    wave: 2,
    origin: "D"
  }
)

verb(
  "bougyo",
  "deadlines",
  {
    kind: :decl,
    shape: "deadlines(opts) -> posture",
    laterals: ["config", "deadline"],
    fleet: nil,
    today: "absent",
    meaning: "header, body and idle time limits against slow clients",
    wave: 2,
    origin: "D"
  }
)

verb(
  "bougyo",
  "headers",
  {
    kind: :decl,
    shape: "headers(opts) -> posture",
    laterals: ["config", "switch"],
    fleet: nil,
    today: "partial:bougyo",
    meaning: "security response headers, added when missing",
    wave: 0,
    origin: "D"
  }
)

verb(
  "bougyo",
  "limits",
  {
    kind: :decl,
    shape: "limits(opts) -> posture",
    laterals: ["config", "validate"],
    fleet: nil,
    today: "partial:bougyo",
    meaning: "caps on method, path, headers and body",
    wave: 0,
    origin: "D"
  }
)

verb(
  "bougyo",
  "rate",
  {
    kind: :decl,
    shape: "rate(opts) -> posture",
    laterals: ["config", "ratelimit"],
    fleet: "pleme-middleware-rate-limit",
    today: "absent",
    meaning: "requests per window per client",
    wave: 1,
    origin: "D"
  }
)

verb(
  "bougyo",
  "request_id",
  {
    kind: :decl,
    shape: "request_id(opts) -> posture",
    laterals: ["config", "log"],
    fleet: nil,
    today: "partial:bougyo",
    meaning: "request id that cannot forge a log line",
    wave: 0,
    origin: "D"
  }
)

verb(
  "bougyo",
  "safe_id?",
  {
    kind: :pure,
    shape: "safe_id?(text, max) -> Bool",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:bougyo",
    wave: 0,
    origin: "D"
  }
)

verb(
  "bougyo",
  "tls",
  {
    kind: :decl,
    shape: "tls(opts) -> posture",
    laterals: ["config", "switch"],
    fleet: nil,
    today: "absent",
    meaning: "require TLS and send strict transport security",
    wave: 2,
    origin: "D"
  }
)

verb(
  "bougyo",
  "trusted_proxy",
  {
    kind: :decl,
    shape: "trusted_proxy(opts) -> posture",
    laterals: ["config"],
    fleet: nil,
    today: "absent",
    meaning: "which forwarding hops to believe for client address",
    wave: 2,
    origin: "D"
  }
)

edge("bougyo::limits", :composes, "bougyo::broken", "find the broken limit")
edge("bougyo::request_id", :composes, "bougyo::safe_id?", "inbound id check")

edge(
  "bougyo::limits",
  :composes,
  "jouka?::bound",
  "limits are bounds on a request"
)

edge("bougyo::authorize", :composes, "kengen?::permit", "policy per request")
edge("bougyo::tls", :composes, "mimoto?::profile", "settings of the TLS level")

edge(
  "bougyo::authenticate",
  :composes,
  "ninshou?::caller",
  "identity from the request"
)

edge(
  "bougyo::audit",
  :composes,
  "nisshi::audit",
  "one audit record per decision"
)

edge("bougyo::headers", :pairs, "bougyo::csp", "csp is one of the headers")
edge("bougyo::rate", :pairs, "ninshou?::strike", "lockout and request limits")
edge("bougyo::broken", :refines, "jouka?::bound", "request-shaped bound")
edge("bougyo::safe_id?", :refines, "jouka?::fits?", "id allow-list")

edge(
  "bougyo::authorize",
  :requires,
  "bougyo::authenticate",
  "needs an identity first"
)

edge("bougyo::audit", :requires, "shisei::posture", "a posture")
edge("bougyo::authenticate", :requires, "shisei::posture", "a posture")
edge("bougyo::cors", :requires, "shisei::posture", "a posture")
edge("bougyo::csp", :requires, "shisei::posture", "a posture")
edge("bougyo::csrf", :requires, "shisei::posture", "a posture")
edge("bougyo::deadlines", :requires, "shisei::posture", "a posture")
edge("bougyo::headers", :requires, "shisei::posture", "a posture")
edge("bougyo::limits", :requires, "shisei::posture", "a posture")
edge("bougyo::rate", :requires, "shisei::posture", "a posture")
edge("bougyo::request_id", :requires, "shisei::posture", "a posture")
edge("bougyo::tls", :requires, "shisei::posture", "a posture")
edge("bougyo::trusted_proxy", :requires, "shisei::posture", "a posture")
