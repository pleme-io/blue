space("tsuushin", {status: :ratified})

verb(
  "tsuushin",
  "authenticate",
  {
    kind: :effect,
    shape: "authenticate(client, flow, opts) -> token",
    laterals: %w[cache capability error],
    fleet: nil,
    today: "absent",
    meaning: "Run an auth flow (OAuth2, basic) and keep the token.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "tsuushin",
  "cache_key",
  {
    kind: :pure,
    shape: "cache_key(request) -> text",
    laterals: ["cache"],
    fleet: nil,
    today: "absent",
    meaning: "The key a cache stores a request under.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "tsuushin",
  "create",
  {
    kind: :effect,
    shape: "create(base, key, value, opts) -> value",
    laterals: %w[error idempotent],
    fleet: nil,
    today: "absent",
    meaning: "POST a new entry; refuses to overwrite.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "tsuushin",
  "delete",
  {
    kind: :effect,
    shape: "delete(base, key, opts) -> nil",
    laterals: %w[error idempotent],
    fleet: nil,
    today: "absent",
    meaning: "DELETE an entry; absent counts as done.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "tsuushin",
  "download",
  {
    kind: :effect,
    shape: "download(url, path, opts) -> info",
    laterals: %w[deadline error resource retry],
    fleet: nil,
    today: "absent",
    meaning: "Fetch a body to a file, resuming by range.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "tsuushin",
  "etag",
  {
    kind: :pure,
    shape: "etag(body) -> text",
    laterals: ["cache"],
    fleet: nil,
    today: "absent",
    meaning: "The strong validator for a body.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "tsuushin",
  "exists?",
  {
    kind: :effect,
    shape: "exists?(url, opts) -> Bool",
    laterals: ["deadline"],
    fleet: nil,
    today: "absent",
    meaning: "HEAD probe; never raises for the condition.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "tsuushin",
  "fresh?",
  {
    kind: :pure,
    shape: "fresh?(response, now) -> Bool",
    laterals: %w[cache time],
    fleet: nil,
    today: "absent",
    meaning: "Whether a cached response may be used unchecked.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "tsuushin",
  "get",
  {
    kind: :effect,
    shape: "get(base, key, opts) -> value or nil",
    laterals: %w[deadline error],
    fleet: nil,
    today: "absent",
    meaning: "One REST entry as parsed JSON; nil on 404.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "tsuushin",
  "join",
  {
    kind: :pure,
    shape: "join(base, path) -> url",
    laterals: [],
    fleet: nil,
    today: "exists:tsuushin",
    wave: 0,
    origin: "C"
  }
)

verb(
  "tsuushin",
  "list",
  {
    kind: :effect,
    shape: "list(base, opts) -> [record]",
    laterals: %w[deadline error retry],
    fleet: nil,
    today: "absent",
    meaning: "Every entry, following next-page links to the end.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "tsuushin",
  "mock",
  {
    kind: :decl,
    shape: "mock(routes) -> client",
    laterals: ["test"],
    fleet: nil,
    today: "absent",
    meaning: "A client that answers from declared routes.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "tsuushin",
  "need",
  {
    kind: :effect,
    shape: "need(base, key, opts) -> value",
    laterals: %w[deadline error],
    fleet: nil,
    today: "absent",
    meaning: "One REST entry; raises when absent.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "tsuushin",
  "negotiate",
  {
    kind: :pure,
    shape: "negotiate(accept, offered) -> choice or nil",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "Pick the best offered type for an Accept header.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "tsuushin",
  "parse",
  {
    kind: :pure,
    shape: "parse(text, :url) -> url record",
    laterals: %w[error validate],
    fleet: nil,
    today: "exists:tsuushin",
    wave: 0,
    origin: "C"
  }
)

verb(
  "tsuushin",
  "put",
  {
    kind: :effect,
    shape: "put(base, key, value, opts) -> value",
    laterals: %w[error idempotent],
    fleet: nil,
    today: "absent",
    meaning: "PUT: create or replace an entry.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "tsuushin",
  "read",
  {
    kind: :effect,
    shape: "read(url, opts) -> body",
    laterals: %w[deadline error retry],
    fleet: "blue-lang-runtime",
    today: "rust:blue-lang-runtime",
    meaning: "GET the body; raises outside 2xx.",
    wave: 0,
    origin: "C"
  }
)

verb(
  "tsuushin",
  "render",
  {
    kind: :pure,
    shape: "render(url record, :url) -> text",
    laterals: ["serialize"],
    fleet: nil,
    today: "exists:tsuushin",
    wave: 0,
    origin: "C"
  }
)

verb(
  "tsuushin",
  "request",
  {
    kind: :effect,
    shape: "request(method, url, opts) -> response",
    laterals: %w[capability deadline error retry trace],
    fleet: "blue-lang-runtime",
    today: "exists:tsuushin",
    wave: 0,
    origin: "C"
  }
)

verb(
  "tsuushin",
  "revalidate",
  {
    kind: :effect,
    shape: "revalidate(request, cached) -> response",
    laterals: %w[cache error],
    fleet: nil,
    today: "absent",
    meaning: "Conditional GET with ETag; reuse body on 304.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "tsuushin",
  "sign",
  {
    kind: :pure,
    shape: "sign(request, credentials) -> request",
    laterals: %w[capability serialize],
    fleet: nil,
    today: "absent",
    meaning: "Add a signature or bearer header to a request.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "tsuushin",
  "stream",
  {
    kind: :stream,
    shape: "stream(url, f, opts) -> response",
    laterals: %w[cancel deadline error],
    fleet: "blue-lang-runtime",
    today: "absent",
    meaning: "Call f per chunk or line as the body arrives.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "tsuushin",
  "update",
  {
    kind: :effect,
    shape: "update(base, key, f, opts) -> value",
    laterals: %w[error retry],
    fleet: nil,
    today: "absent",
    meaning: "GET, apply f, conditional PATCH; raises conflict.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "tsuushin",
  "upload",
  {
    kind: :effect,
    shape: "upload(url, source, opts) -> response",
    laterals: %w[deadline error retry],
    fleet: nil,
    today: "absent",
    meaning: "Send a file or multipart form as the body.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "tsuushin",
  "wait",
  {
    kind: :effect,
    shape: "wait(url, opts) -> response",
    laterals: %w[deadline retry time],
    fleet: nil,
    today: "absent",
    meaning: "Poll until the URL answers a wanted status.",
    wave: 1,
    origin: "C"
  }
)

edge(
  "tsuushin::request",
  :composes,
  "sokketto?::connect",
  "a request rides a connection"
)

edge(
  "tsuushin::wait",
  :composes,
  "tsuushin::exists?",
  "poll until a probe passes"
)

edge(
  "tsuushin::list",
  :composes,
  "tsuushin::get",
  "list follows pages of entries"
)

edge(
  "tsuushin::update",
  :composes,
  "tsuushin::get",
  "read, apply f, write back"
)

edge(
  "tsuushin::create",
  :composes,
  "tsuushin::request",
  "POST with exists check"
)

edge(
  "tsuushin::delete",
  :composes,
  "tsuushin::request",
  "DELETE treating 404 as done"
)

edge(
  "tsuushin::get",
  :composes,
  "tsuushin::request",
  "get is GET mapping 404 to nil"
)

edge(
  "tsuushin::put",
  :composes,
  "tsuushin::request",
  "PUT with the entry as body"
)

edge(
  "tsuushin::read",
  :composes,
  "tsuushin::request",
  "read is request GET plus status check"
)

edge(
  "tsuushin::revalidate",
  :composes,
  "tsuushin::request",
  "conditional GET using a validator"
)

edge(
  "tsuushin::upload",
  :composes,
  "tsuushin::request",
  "request with a file or form body"
)

edge(
  "tsuushin::authenticate",
  :composes,
  "tsuushin::sign",
  "a flow yields what sign applies"
)

edge(
  "tsuushin::download",
  :composes,
  "tsuushin::stream",
  "body streamed into a file"
)

edge("tsuushin::sign", :guards, "tsuushin::request", "signed before sending")

edge(
  "tsuushin::delete",
  :inverse,
  "tsuushin::create",
  "create adds what delete removes"
)

edge(
  "tsuushin::create",
  :inverse,
  "tsuushin::delete",
  "create adds what delete removes"
)

edge(
  "tsuushin::put",
  :inverse,
  "tsuushin::delete",
  "put makes present, delete absent"
)

edge(
  "tsuushin::revalidate",
  :inverse,
  "tsuushin::fresh?",
  "fresh needs no check; stale does"
)

edge("tsuushin::render", :inverse, "tsuushin::parse", "text to record and back")

edge(
  "tsuushin::delete",
  :inverse,
  "tsuushin::put",
  "put makes present, delete absent"
)

edge("tsuushin::parse", :inverse, "tsuushin::render", "text to record and back")

edge(
  "tsuushin::fresh?",
  :inverse,
  "tsuushin::revalidate",
  "fresh needs no check; stale does"
)

edge("tsuushin::list", :lifts, "tsuushin::get", "all pages of a keyed lookup")
edge("tsuushin::stream", :lifts, "tsuushin::read", "incremental form of read")
edge("tsuushin::read", :pairs, "deeta::parse", "body then parsed value")

edge(
  "tsuushin::request",
  :pairs,
  "heikou::retry",
  "retry under a declared policy"
)

edge(
  "tsuushin::list",
  :pairs,
  "keiyaku?::paginate",
  "REST paging and operation paging"
)

edge("tsuushin::wait", :pairs, "kyoujin?::ready?", "poll a readiness endpoint")

edge(
  "tsuushin::negotiate",
  :pairs,
  "kyuuji::response",
  "server picks the type the client asks"
)

edge(
  "tsuushin::exists?",
  :pairs,
  "sokketto?::exists?",
  "URL probe and port probe"
)

edge(
  "tsuushin::stream",
  :pairs,
  "sokketto?::stream",
  "HTTP bodies and socket messages"
)

edge(
  "tsuushin::etag",
  :pairs,
  "tsuushin::revalidate",
  "validator and conditional request"
)

edge("tsuushin::download", :pairs, "tsuushin::upload", "file out and file in")

edge(
  "tsuushin::need",
  :refines,
  "tsuushin::get",
  "need raises where get gives nil"
)

edge(
  "tsuushin::exists?",
  :refines,
  "tsuushin::request",
  "HEAD request reduced to a Bool"
)

edge(
  "tsuushin::mock",
  :refines,
  "tsuushin::request",
  "same shape, canned answers"
)

edge(
  "tsuushin::request",
  :requires,
  "heikou::timeout",
  "every request has a deadline"
)

edge(
  "tsuushin::request",
  :requires,
  "kyoujin?::bucket",
  "callers share an upstream budget"
)

edge(
  "tsuushin::fresh?",
  :requires,
  "tsuushin::cache_key",
  "freshness is judged per cached key"
)

edge(
  "tsuushin::update",
  :requires,
  "tsuushin::etag",
  "conditional write needs a validator"
)

edge(
  "tsuushin::revalidate",
  :requires,
  "tsuushin::fresh?",
  "only stale entries are revalidated"
)

edge(
  "tsuushin::join",
  :requires,
  "tsuushin::parse",
  "resolution works on parsed URLs"
)

edge(
  "tsuushin::request",
  :requires,
  "tsuushin::parse",
  "a request needs a valid URL"
)
