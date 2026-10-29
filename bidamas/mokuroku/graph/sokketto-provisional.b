space("sokketto?", {status: :provisional})

verb(
  "sokketto?",
  "accept",
  {
    kind: :effect,
    shape: "accept(listener, opts) -> conn",
    laterals: %w[cancel deadline],
    fleet: "blue-lang-runtime",
    today: "rust:blue-lang-runtime",
    meaning: "Take the next incoming connection.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "sokketto?",
  "bind",
  {
    kind: :effect,
    shape: "bind(addr, opts) -> conn",
    laterals: %w[capability error],
    fleet: nil,
    today: "absent",
    meaning: "Bind a datagram socket to receive on.",
    wave: 2,
    origin: "C",
    contract: "bind(addr, role, scope, opts) -> conn"
  }
)

verb(
  "sokketto?",
  "certificate",
  {
    kind: :effect,
    shape: "certificate(host, opts) -> record",
    laterals: %w[error time],
    fleet: nil,
    today: "absent",
    meaning: "The peer certificate chain, expiry and names.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "sokketto?",
  "close",
  {
    kind: :effect,
    shape: "close(conn_or_listener) -> nil",
    laterals: ["resource"],
    fleet: "blue-lang-runtime",
    today: "rust:blue-lang-runtime",
    meaning: "Release it; closing twice is done.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "sokketto?",
  "connect",
  {
    kind: :effect,
    shape: "connect(addr, opts) -> conn",
    laterals: %w[capability deadline error resource],
    fleet: nil,
    today: "absent",
    meaning: "Open a TCP, UDP, Unix or TLS connection.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "sokketto?",
  "enter",
  {
    kind: :effect,
    shape: "enter(conn, group) -> nil",
    laterals: ["capability"],
    fleet: nil,
    today: "absent",
    meaning: "Join a multicast group on a socket.",
    wave: 4,
    origin: "C"
  }
)

verb(
  "sokketto?",
  "exists?",
  {
    kind: :effect,
    shape: "exists?(addr, opts) -> Bool",
    laterals: ["deadline"],
    fleet: nil,
    today: "absent",
    meaning: "Whether a port accepts a connection.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "sokketto?",
  "handshake",
  {
    kind: :effect,
    shape: "handshake(conn, opts) -> record",
    laterals: %w[deadline error],
    fleet: nil,
    today: "absent",
    meaning: "Run a protocol opening (TLS, WebSocket, PROXY) and return its outcome.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "sokketto?",
  "info",
  {
    kind: :effect,
    shape: "info(conn) -> record",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "Local and peer address, protocol and options.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "sokketto?",
  "listen",
  {
    kind: :effect,
    shape: "listen(addr, opts) -> listener",
    laterals: %w[capability error resource],
    fleet: "blue-lang-runtime",
    today: "rust:blue-lang-runtime",
    meaning: "Bind and listen; port 0 picks a free one.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "sokketto?",
  "pipe",
  {
    kind: :effect,
    shape: "pipe(a, b, opts) -> info",
    laterals: %w[cancel resource],
    fleet: nil,
    today: "absent",
    meaning: "Copy bytes both ways until one side closes.",
    wave: 2,
    origin: "C",
    contract: "pipe(a, opts) -> info"
  }
)

verb(
  "sokketto?",
  "read",
  {
    kind: :effect,
    shape: "read(conn, opts) -> bytes",
    laterals: %w[deadline error],
    fleet: nil,
    today: "absent",
    meaning: "Read what has arrived, up to a size.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "sokketto?",
  "receive",
  {
    kind: :effect,
    shape: "receive(conn, opts) -> message",
    laterals: %w[cancel deadline],
    fleet: nil,
    today: "absent",
    meaning: "Take the next datagram or WebSocket message.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "sokketto?",
  "reuse",
  {
    kind: :decl,
    shape: "reuse(opts) -> pool",
    laterals: ["resource"],
    fleet: nil,
    today: "absent",
    meaning: "Declare a pool that keeps connections alive for reuse.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "sokketto?",
  "secure",
  {
    kind: :effect,
    shape: "secure(conn, tls opts) -> conn",
    laterals: %w[capability error],
    fleet: nil,
    today: "absent",
    meaning: "Upgrade a connection to TLS with a verified peer.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "sokketto?",
  "send",
  {
    kind: :effect,
    shape: "send(conn, bytes, to) -> nil",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "Send one datagram or WebSocket message.",
    wave: 1,
    origin: "C",
    contract: "send(conn, bytes, opts) -> nil"
  }
)

verb(
  "sokketto?",
  "stream",
  {
    kind: :stream,
    shape: "stream(conn, f, opts) -> nil",
    laterals: %w[cancel deadline],
    fleet: nil,
    today: "absent",
    meaning: "Call f per message until the peer closes.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "sokketto?",
  "wait",
  {
    kind: :effect,
    shape: "wait(conns, opts) -> [ready conn]",
    laterals: ["deadline"],
    fleet: nil,
    today: "absent",
    meaning: "Block until some connection is ready.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "sokketto?",
  "write",
  {
    kind: :effect,
    shape: "write(conn, bytes, opts) -> nil",
    laterals: %w[deadline error],
    fleet: nil,
    today: "absent",
    meaning: "Write all bytes or raise.",
    wave: 1,
    origin: "C"
  }
)

edge(
  "sokketto?::exists?",
  :composes,
  "sokketto?::connect",
  "connect then close"
)

edge(
  "sokketto?::secure",
  :composes,
  "sokketto?::handshake",
  "TLS opening on a connection"
)

edge("sokketto?::pipe", :composes, "sokketto?::read", "copy loop")

edge(
  "sokketto?::certificate",
  :composes,
  "sokketto?::secure",
  "reads the chain it negotiated"
)

edge("sokketto?::pipe", :composes, "sokketto?::write", "copy loop")

edge(
  "sokketto?::reuse",
  :guards,
  "sokketto?::connect",
  "pool decides open or reuse"
)

edge("sokketto?::connect", :inverse, "sokketto?::close", "open and release")
edge("sokketto?::listen", :inverse, "sokketto?::close", "bind and release")
edge("sokketto?::close", :inverse, "sokketto?::connect", "open and release")
edge("sokketto?::close", :inverse, "sokketto?::listen", "bind and release")
edge("sokketto?::write", :inverse, "sokketto?::read", "bytes in, bytes out")

edge(
  "sokketto?::send",
  :inverse,
  "sokketto?::receive",
  "message out, message in"
)

edge(
  "sokketto?::receive",
  :inverse,
  "sokketto?::send",
  "message out, message in"
)

edge("sokketto?::read", :inverse, "sokketto?::write", "bytes in, bytes out")

edge(
  "sokketto?::wait",
  :lifts,
  "sokketto?::read",
  "ready set instead of one read"
)

edge("sokketto?::stream", :lifts, "sokketto?::receive", "messages until close")

edge(
  "sokketto?::accept",
  :pairs,
  "akutaa?::spawn",
  "one process per connection"
)

edge("sokketto?::connect", :pairs, "heikou::timeout", "connecting is bounded")
edge("sokketto?::stream", :pairs, "heikou::token", "ends on cancellation")
edge("sokketto?::write", :pairs, "keiyaku?::frame", "frames are written whole")

edge(
  "sokketto?::read",
  :pairs,
  "keiyaku?::unframe",
  "bytes are split into frames"
)

edge(
  "sokketto?::certificate",
  :pairs,
  "kyoujin?::probe",
  "expiry is a health signal"
)

edge("sokketto?::listen", :pairs, "sokketto?::accept", "bind then take")
edge("sokketto?::info", :pairs, "sokketto?::certificate", "peer details")

edge(
  "sokketto?::info",
  :pairs,
  "sokketto?::connect",
  "inspect what connect opened"
)

edge(
  "sokketto?::close",
  :pairs,
  "sokketto?::reuse",
  "closed or returned to the pool"
)

edge("sokketto?::bind", :refines, "sokketto?::listen", "datagram counterpart")
edge("sokketto?::receive", :refines, "sokketto?::read", "message-oriented read")
edge("sokketto?::send", :refines, "sokketto?::write", "message-oriented write")

edge(
  "sokketto?::enter",
  :requires,
  "sokketto?::bind",
  "multicast needs a bound socket"
)

edge(
  "sokketto?::handshake",
  :requires,
  "sokketto?::connect",
  "runs on an open connection"
)

edge(
  "sokketto?::read",
  :requires,
  "sokketto?::connect",
  "needs an open connection"
)

edge(
  "sokketto?::secure",
  :requires,
  "sokketto?::connect",
  "upgrades an open connection"
)

edge(
  "sokketto?::write",
  :requires,
  "sokketto?::connect",
  "needs an open connection"
)

edge(
  "sokketto?::accept",
  :requires,
  "sokketto?::listen",
  "accept needs a listener"
)
