space("kyuuji", {status: :ratified})

verb(
  "kyuuji",
  "body",
  {
    kind: :pure,
    shape: "body(req, format) -> value",
    laterals: ["error", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "Parse the request body into a value.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "kyuuji",
  "compress",
  {
    kind: :pure,
    shape: "compress(handler, opts) -> handler",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "Compress bodies by the client's Accept-Encoding.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "kyuuji",
  "cors",
  {
    kind: :pure,
    shape: "cors(handler, policy) -> handler",
    laterals: ["config"],
    fleet: nil,
    today: "absent",
    meaning: "Add cross-origin headers by policy.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "kyuuji",
  "events",
  {
    kind: :stream,
    shape: "events(req, f) -> response",
    laterals: ["cancel"],
    fleet: nil,
    today: "absent",
    meaning: "Answer as a server-sent event stream.",
    wave: 2,
    origin: "C",
    contract: "events(req, opts) -> response"
  }
)

verb(
  "kyuuji",
  "exposition",
  {
    kind: :pure,
    shape: "exposition(m, service) -> text",
    laterals: ["serialize"],
    fleet: "blue",
    today: "exists:kyuuji",
    meaning: "Metrics rendered in Prometheus text form.",
    wave: 0,
    origin: "C"
  }
)

verb(
  "kyuuji",
  "file",
  {
    kind: :effect,
    shape: "file(path, opts) -> response",
    laterals: ["cache", "resource"],
    fleet: nil,
    today: "absent",
    meaning: "A response serving a file with validators and ranges.",
    wave: 2,
    origin: "C",
    contract: "file(path, tier) -> response"
  }
)

verb(
  "kyuuji",
  "guard",
  {
    kind: :pure,
    shape: "guard(handler, check) -> handler",
    laterals: ["capability", "error"],
    fleet: nil,
    today: "absent",
    meaning: "Refuse requests that fail a check before the handler.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "kyuuji",
  "header",
  {
    kind: :pure,
    shape: "header(req, name) -> text or nil",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "One request header.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "kyuuji",
  "health",
  {
    kind: :pure,
    shape: "health(request, check) -> response",
    laterals: ["test"],
    fleet: nil,
    today: "exists:kyuuji",
    meaning: "answer a liveness or readiness probe from a check",
    wave: 0,
    origin: "F"
  }
)

verb(
  "kyuuji",
  "hook",
  {
    kind: :decl,
    shape: "hook(path, secret, f) -> route",
    laterals: ["capability", "idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "Receive a signed webhook and call f once per delivery.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "kyuuji",
  "json",
  {
    kind: :pure,
    shape: "json(status, value) -> response",
    laterals: ["serialize"],
    fleet: "blue",
    today: "exists:kyuuji",
    meaning: "A JSON response.",
    wave: 0,
    origin: "C"
  }
)

verb(
  "kyuuji",
  "match",
  {
    kind: :pure,
    shape: "match(app, req) -> route and params or nil",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "Find the route that serves a request.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "kyuuji",
  "metered",
  {
    kind: :effect,
    shape: "metered(request, health, handler, metrics) -> response",
    laterals: ["time"],
    fleet: nil,
    today: "exists:kyuuji",
    meaning: "answer a request and record its status and latency",
    wave: 0,
    origin: "F"
  }
)

verb(
  "kyuuji",
  "mount",
  {
    kind: :decl,
    shape: "mount(app, prefix, sub) -> app",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "Place a sub-app under a path prefix.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "kyuuji",
  "not_found",
  {
    kind: :pure,
    shape: "not_found(req) -> response",
    laterals: [],
    fleet: "blue",
    today: "exists:kyuuji",
    meaning: "The 404 response for a request.",
    wave: 0,
    origin: "C"
  }
)

verb(
  "kyuuji",
  "observe",
  {
    kind: :effect,
    shape: "observe(m, status, seconds) -> m",
    laterals: ["log", "trace"],
    fleet: "blue",
    today: "exists:kyuuji",
    meaning: "Count one request in the metrics.",
    wave: 0,
    origin: "C"
  }
)

verb(
  "kyuuji",
  "param",
  {
    kind: :pure,
    shape: "param(req, name) -> text or nil",
    laterals: [],
    fleet: "blue",
    today: "partial:kyuuji",
    meaning: "One query or path parameter.",
    wave: 0,
    origin: "C"
  }
)

verb(
  "kyuuji",
  "plain",
  {
    kind: :pure,
    shape: "plain(status, body) -> response",
    laterals: [],
    fleet: "blue",
    today: "exists:kyuuji",
    meaning: "A plain-text response.",
    wave: 0,
    origin: "C"
  }
)

verb(
  "kyuuji",
  "recover",
  {
    kind: :pure,
    shape: "recover(handler) -> handler",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "Turn a raised kind into its status response.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "kyuuji",
  "redirect",
  {
    kind: :pure,
    shape: "redirect(status, location) -> response",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "A redirect response.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "kyuuji",
  "response",
  {
    kind: :pure,
    shape: "response(status, content_type, body) -> response",
    laterals: [],
    fleet: "blue",
    today: "exists:kyuuji",
    meaning: "Build a response record.",
    wave: 0,
    origin: "C"
  }
)

verb(
  "kyuuji",
  "route",
  {
    kind: :decl,
    shape: "route(method, pattern, handler) -> route",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "Declare one method and path pattern with a handler.",
    wave: 1,
    origin: "C",
    contract: "route(method, pattern) -> route"
  }
)

verb(
  "kyuuji",
  "router",
  {
    kind: :decl,
    shape: "router(routes) -> app",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "Compose routes into one app; overlap is refused.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "kyuuji",
  "serve",
  {
    kind: :effect,
    shape: "serve(addr, app, opts) -> nil",
    laterals: [
      "cancel",
      "capability",
      "deadline",
      "error",
      "log",
      "resource",
      "trace"
    ],
    fleet: "blue",
    today: "exists:kyuuji",
    meaning: "Listen and answer requests until stopped.",
    wave: 0,
    origin: "C"
  }
)

verb(
  "kyuuji",
  "serve_once",
  {
    kind: :effect,
    shape: "serve_once(listener, app, opts) -> nil",
    laterals: ["deadline", "error"],
    fleet: "blue",
    today: "exists:kyuuji",
    meaning: "Answer one request; the test door.",
    wave: 0,
    origin: "C"
  }
)

verb(
  "kyuuji",
  "shutdown",
  {
    kind: :effect,
    shape: "shutdown(server, opts) -> nil",
    laterals: ["cancel", "deadline"],
    fleet: nil,
    today: "absent",
    meaning: "Stop accepting, drain in-flight requests, then close.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "kyuuji",
  "stream",
  {
    kind: :stream,
    shape: "stream(req, f, opts) -> response",
    laterals: ["cancel", "deadline"],
    fleet: nil,
    today: "absent",
    meaning: "Send chunks as f produces them.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "kyuuji",
  "throttle",
  {
    kind: :pure,
    shape: "throttle(handler, bucket) -> handler",
    laterals: ["ratelimit"],
    fleet: "pleme-middleware-rate-limit",
    today: "absent",
    meaning: "Answer 429 past a kyoujin bucket.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "kyuuji",
  "timeout",
  {
    kind: :pure,
    shape: "timeout(handler, duration) -> handler",
    laterals: ["deadline"],
    fleet: nil,
    today: "absent",
    meaning: "Answer 503 when the handler runs past a deadline.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "kyuuji",
  "upgrade",
  {
    kind: :effect,
    shape: "upgrade(req, f) -> response",
    laterals: ["cancel", "capability"],
    fleet: nil,
    today: "absent",
    meaning: "Switch to a WebSocket and hand it to f.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "kyuuji",
  "wrap",
  {
    kind: :pure,
    shape: "wrap(handler, middleware) -> handler",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "Surround a handler with a middleware.",
    wave: 1,
    origin: "C"
  }
)

edge("kyuuji::timeout", :composes, "heikou::timeout", "reuses the one timeout")
edge("kyuuji::metered", :composes, "keisoku?::observe", "records each request")
edge("kyuuji::metered", :composes, "keisoku?::render", "serves the exposition")

edge(
  "kyuuji::shutdown",
  :composes,
  "kyoujin?::drain",
  "stop intake, finish in-flight"
)

edge("kyuuji::hook", :composes, "kyoujin?::once", "one effect per delivery id")

edge(
  "kyuuji::health",
  :composes,
  "kyoujin?::ready?",
  "health answers from checks"
)

edge("kyuuji::wrap", :composes, "kyuuji::guard", "guard is wrap with a check")

edge(
  "kyuuji::route",
  :composes,
  "kyuuji::match",
  "a route is a match plus handler"
)

edge(
  "kyuuji::serve",
  :composes,
  "kyuuji::metered",
  "metered handler in the loop"
)

edge(
  "kyuuji::file",
  :composes,
  "kyuuji::response",
  "response whose body is a file"
)

edge(
  "kyuuji::router",
  :composes,
  "kyuuji::route",
  "a router is a set of routes"
)

edge("kyuuji::mount", :composes, "kyuuji::router", "nest one router in another")

edge(
  "kyuuji::serve",
  :composes,
  "kyuuji::serve_once",
  "serve is serve_once in a loop"
)

edge(
  "kyuuji::serve_once",
  :composes,
  "sokketto?::accept",
  "takes one connection"
)

edge("kyuuji::upgrade", :composes, "sokketto?::handshake", "websocket opening")
edge("kyuuji::serve", :composes, "sokketto?::listen", "binds a listener")
edge("kyuuji::hook", :composes, "tsuuchi?::verify?", "signature checked first")
edge("kyuuji::wrap", :generalizes, "kyuuji::recover", "middleware in general")
edge("kyuuji::wrap", :generalizes, "kyuuji::throttle", "middleware in general")
edge("kyuuji::wrap", :generalizes, "kyuuji::timeout", "middleware in general")

edge(
  "kyuuji::health",
  :guards,
  "kyuuji::serve",
  "readiness answers before traffic"
)

edge(
  "kyuuji::response",
  :inverse,
  "kyuuji::body",
  "read a body in, write one out"
)

edge(
  "kyuuji::body",
  :inverse,
  "kyuuji::response",
  "read a body in, write one out"
)

edge("kyuuji::health", :pairs, "fuka?::guard", "health is a stop condition")
edge("kyuuji::health", :pairs, "kaihatsu?::doctor", "probe versus environment")
edge("kyuuji::body", :pairs, "keiyaku?::validate", "parse then check schema")
edge("kyuuji::observe", :pairs, "kyuuji::exposition", "record then render")
edge("kyuuji::serve", :pairs, "kyuuji::health", "a server answers probes")

edge(
  "kyuuji::param",
  :pairs,
  "kyuuji::match",
  "path params come from the match"
)

edge("kyuuji::header", :pairs, "kyuuji::param", "request reading verbs")
edge("kyuuji::route", :pairs, "kyuuji::param", "a pattern defines its params")
edge("kyuuji::serve", :pairs, "kyuuji::shutdown", "start and graceful end")

edge(
  "kyuuji::events",
  :pairs,
  "messeeji?::subscribe",
  "events fed from a subscription"
)

edge("kyuuji::serve", :pairs, "rogu::info", "requests are logged")

edge(
  "kyuuji::exposition",
  :pairs,
  "shihyou::error_ratio",
  "metrics feed objectives"
)

edge(
  "kyuuji::metered",
  :pairs,
  "shihyou::indicator",
  "request metrics feed the indicator"
)

edge(
  "kyuuji::observe",
  :pairs,
  "shihyou::slow_ratio",
  "latency buckets feed indicators"
)

edge(
  "kyuuji::upgrade",
  :pairs,
  "sokketto?::stream",
  "a socket after the upgrade"
)

edge("kyuuji::serve", :pairs, "tsuiseki?::adopt", "requests continue traces")

edge(
  "kyuuji::serve_once",
  :pairs,
  "tsuushin::request",
  "test one request against a server"
)

edge(
  "kyuuji::throttle",
  :refines,
  "kyuuji::guard",
  "guard whose check is a bucket"
)

edge("kyuuji::json", :refines, "kyuuji::response", "JSON content type preset")
edge("kyuuji::not_found", :refines, "kyuuji::response", "fixed 404 response")

edge(
  "kyuuji::plain",
  :refines,
  "kyuuji::response",
  "plain-text content type preset"
)

edge("kyuuji::redirect", :refines, "kyuuji::response", "3xx with Location")
edge("kyuuji::stream", :refines, "kyuuji::response", "chunked body from f")
edge("kyuuji::upgrade", :refines, "kyuuji::response", "101 switch to a socket")
edge("kyuuji::hook", :refines, "kyuuji::route", "a route for signed callbacks")
edge("kyuuji::events", :refines, "kyuuji::stream", "stream with event framing")
edge("kyuuji::compress", :refines, "kyuuji::wrap", "body-transforming wrap")
edge("kyuuji::cors", :refines, "kyuuji::wrap", "header-adding wrap")
edge("kyuuji::guard", :refines, "kyuuji::wrap", "a wrap that can refuse")

edge(
  "kyuuji::recover",
  :refines,
  "kyuuji::wrap",
  "turns raised kinds to responses"
)

edge("kyuuji::timeout", :refines, "kyuuji::wrap", "deadline wrap")

edge(
  "kyuuji::throttle",
  :requires,
  "kyoujin?::admit",
  "asks the bucket per request"
)

edge(
  "kyuuji::body",
  :requires,
  "kyuuji::header",
  "format comes from Content-Type"
)

edge("kyuuji::match", :requires, "kyuuji::router", "matching needs the app")
edge("kyuuji::serve", :requires, "kyuuji::router", "serving needs an app")
edge("kyuuji::shutdown", :requires, "kyuuji::serve", "stops a running server")
