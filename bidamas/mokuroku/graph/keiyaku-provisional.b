space("keiyaku?", {status: :provisional})

verb(
  "keiyaku?",
  "bundle",
  {
    kind: :pure,
    shape: "bundle(specs) -> spec",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "Merge specs and resolve references into one.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "keiyaku?",
  "call",
  {
    kind: :effect,
    shape: "call(client, operation, request, opts) -> response",
    laterals: %w[deadline error idempotent retry trace],
    fleet: nil,
    today: "absent",
    meaning: "Invoke one operation; the kind of error comes from the status.",
    wave: 2,
    origin: "C",
    contract: "call(client, operation, opts) -> response"
  }
)

verb(
  "keiyaku?",
  "checksum",
  {
    kind: :pure,
    shape: "checksum(bytes, algorithm) -> integer",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "A CRC or Adler checksum of bytes.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "keiyaku?",
  "client",
  {
    kind: :decl,
    shape: "client(spec, base, opts) -> client",
    laterals: %w[capability config],
    fleet: nil,
    today: "absent",
    meaning: "Bind a spec to an endpoint.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "keiyaku?",
  "conform?",
  {
    kind: :pure,
    shape: "conform?(value, schema) -> Bool",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "Whether a value matches a schema.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "keiyaku?",
  "describe",
  {
    kind: :pure,
    shape: "describe(spec) -> [operation]",
    laterals: [],
    fleet: "openapi-forge",
    today: "absent",
    meaning: "List the operations a spec offers.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "keiyaku?",
  "diff",
  {
    kind: :pure,
    shape: "diff(old, new) -> [change]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "Spec changes, each marked breaking or compatible.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "keiyaku?",
  "federate",
  {
    kind: :decl,
    shape: "federate(specs) -> spec",
    laterals: ["validate"],
    fleet: "pleme-graphql-helpers",
    today: "absent",
    meaning: "Compose several schemas into one graph.",
    wave: 4,
    origin: "C"
  }
)

verb(
  "keiyaku?",
  "frame",
  {
    kind: :pure,
    shape: "frame(message, framing) -> bytes",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "Wrap a message with its length prefix or delimiter.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "keiyaku?",
  "generate",
  {
    kind: :pure,
    shape: "generate(spec, target) -> source",
    laterals: ["serialize"],
    fleet: "grpc-forge",
    today: "absent",
    meaning: "Produce a client, server or docs from a spec.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "keiyaku?",
  "introspect",
  {
    kind: :effect,
    shape: "introspect(url, opts) -> spec",
    laterals: %w[deadline error],
    fleet: "pleme-graphql-helpers",
    today: "absent",
    meaning: "Fetch a live endpoint's own schema.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "keiyaku?",
  "lint",
  {
    kind: :pure,
    shape: "lint(spec) -> [finding]",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "Style and safety findings on a spec.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "keiyaku?",
  "mock",
  {
    kind: :decl,
    shape: "mock(spec, examples) -> app",
    laterals: ["test"],
    fleet: nil,
    today: "absent",
    meaning: "An app that answers every operation from examples.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "keiyaku?",
  "negotiate",
  {
    kind: :pure,
    shape: "negotiate(client, server) -> agreed version",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "Pick the highest version both sides speak.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "keiyaku?",
  "pack",
  {
    kind: :pure,
    shape: "pack(value, layout) -> bytes",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "Binary-encode a value by a declared layout (varint, TLV).",
    wave: 2,
    origin: "C"
  }
)

verb(
  "keiyaku?",
  "paginate",
  {
    kind: :stream,
    shape: "paginate(client, operation, request) -> [record]",
    laterals: ["retry"],
    fleet: "pleme-graphql-helpers",
    today: "absent",
    meaning: "Follow every page of a listing operation.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "keiyaku?",
  "parse",
  {
    kind: :pure,
    shape: "parse(text, :openapi) -> spec",
    laterals: %w[error validate],
    fleet: "openapi-forge",
    today: "absent",
    meaning: "Read an OpenAPI, protobuf or GraphQL schema into a spec.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "keiyaku?",
  "render",
  {
    kind: :pure,
    shape: "render(spec, format) -> text",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "Write a spec in its format.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "keiyaku?",
  "serve",
  {
    kind: :effect,
    shape: "serve(spec, handlers, addr) -> nil",
    laterals: %w[error log trace],
    fleet: "grpc-forge",
    today: "absent",
    meaning: "Serve a spec with one handler per operation.",
    wave: 3,
    origin: "C",
    contract: "serve(spec, handlers, opts) -> nil"
  }
)

verb(
  "keiyaku?",
  "stream",
  {
    kind: :stream,
    shape: "stream(client, operation, request, f) -> nil",
    laterals: %w[cancel deadline],
    fleet: nil,
    today: "absent",
    meaning: "Call f per message of a streaming operation.",
    wave: 3,
    origin: "C",
    contract: "stream(client, operation, request, opts) -> nil"
  }
)

verb(
  "keiyaku?",
  "unframe",
  {
    kind: :pure,
    shape: "unframe(bytes, framing) -> [message] and rest",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "Split bytes into whole messages and a remainder.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "keiyaku?",
  "unpack",
  {
    kind: :pure,
    shape: "unpack(bytes, layout) -> value",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "Decode bytes by a declared layout.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "keiyaku?",
  "validate",
  {
    kind: :pure,
    shape: "validate(request, operation) -> request",
    laterals: %w[error validate],
    fleet: nil,
    today: "absent",
    meaning: "Refuse a request that does not conform to its schema.",
    wave: 2,
    origin: "C"
  }
)

edge(
  "keiyaku?::validate",
  :composes,
  "keiyaku?::conform?",
  "validate raises where conform? answers"
)

edge(
  "keiyaku?::mock",
  :composes,
  "keiyaku?::describe",
  "one stub per operation"
)

edge(
  "keiyaku?::frame",
  :composes,
  "keiyaku?::pack",
  "frame carries packed bytes"
)

edge("keiyaku?::bundle", :composes, "keiyaku?::parse", "merges parsed specs")
edge("keiyaku?::mock", :composes, "kyuuji::serve", "served as an app")
edge("keiyaku?::serve", :composes, "kyuuji::serve", "REST binding of a server")

edge(
  "keiyaku?::call",
  :composes,
  "tsuushin::request",
  "REST binding of an operation"
)

edge(
  "keiyaku?::introspect",
  :composes,
  "tsuushin::request",
  "queries the live endpoint"
)

edge(
  "keiyaku?::federate",
  :generalizes,
  "keiyaku?::bundle",
  "bundle with ownership rules"
)

edge(
  "keiyaku?::checksum",
  :guards,
  "keiyaku?::unframe",
  "verify frames before use"
)

edge("keiyaku?::call", :guards, "keiyaku?::validate", "validate before sending")

edge(
  "keiyaku?::conform?",
  :guards,
  "keiyaku?::validate",
  "the predicate under the raising form"
)

edge(
  "keiyaku?::unframe",
  :inverse,
  "keiyaku?::frame",
  "wrap and split messages"
)

edge(
  "keiyaku?::render",
  :inverse,
  "keiyaku?::introspect",
  "fetch a schema, or write it out"
)

edge(
  "keiyaku?::unpack",
  :inverse,
  "keiyaku?::pack",
  "encode and decode a layout"
)

edge("keiyaku?::render", :inverse, "keiyaku?::parse", "spec text both ways")

edge(
  "keiyaku?::introspect",
  :inverse,
  "keiyaku?::render",
  "fetch a schema, or write it out"
)

edge("keiyaku?::parse", :inverse, "keiyaku?::render", "spec text both ways")

edge(
  "keiyaku?::frame",
  :inverse,
  "keiyaku?::unframe",
  "wrap and split messages"
)

edge(
  "keiyaku?::pack",
  :inverse,
  "keiyaku?::unpack",
  "encode and decode a layout"
)

edge("keiyaku?::paginate", :lifts, "keiyaku?::call", "every page of a call")
edge("keiyaku?::stream", :lifts, "keiyaku?::call", "streaming form of call")

edge(
  "keiyaku?::pack",
  :pairs,
  "deeta::encode",
  "binary layouts beside text encodings"
)

edge("keiyaku?::render", :pairs, "deeta::render", "specs are data")

edge(
  "keiyaku?::call",
  :pairs,
  "heikou::retry",
  "operation idempotence sets retry"
)

edge("keiyaku?::client", :pairs, "keiyaku?::call", "bind then invoke")

edge(
  "keiyaku?::serve",
  :pairs,
  "keiyaku?::client",
  "server and client of one spec"
)

edge(
  "keiyaku?::generate",
  :pairs,
  "keiyaku?::diff",
  "generation follows spec changes"
)

edge("keiyaku?::checksum", :pairs, "keiyaku?::frame", "frames carry a check")
edge("keiyaku?::diff", :pairs, "kyuuji::hook", "breaking changes gate releases")

edge(
  "keiyaku?::negotiate",
  :pairs,
  "sokketto?::handshake",
  "agreed during the opening"
)

edge("keiyaku?::paginate", :refines, "tsuushin::list", "operation-level paging")

edge(
  "keiyaku?::call",
  :requires,
  "keiyaku?::client",
  "calls go through a client"
)

edge(
  "keiyaku?::generate",
  :requires,
  "keiyaku?::describe",
  "code per operation"
)

edge("keiyaku?::client", :requires, "keiyaku?::parse", "bind a parsed spec")
edge("keiyaku?::describe", :requires, "keiyaku?::parse", "lists a parsed spec")
edge("keiyaku?::diff", :requires, "keiyaku?::parse", "compares parsed specs")
edge("keiyaku?::lint", :requires, "keiyaku?::parse", "checks a parsed spec")

edge(
  "keiyaku?::serve",
  :requires,
  "keiyaku?::validate",
  "requests checked on entry"
)
