space("messeeji?", {status: :provisional})

verb(
  "messeeji?",
  "ack",
  {
    kind: :effect,
    shape: "ack(message) -> nil",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "Confirm the message is done; it is not redelivered.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "messeeji?",
  "batch",
  {
    kind: :effect,
    shape: "batch(bus, subject, messages, opts) -> [receipt]",
    laterals: ["retry"],
    fleet: "samba",
    today: "absent",
    meaning: "Publish many messages and return every receipt.",
    wave: 2,
    origin: "C",
    contract: "batch(bus, subject, opts) -> [receipt]"
  }
)

verb(
  "messeeji?",
  "close",
  {
    kind: :effect,
    shape: "close(bus) -> nil",
    laterals: ["resource"],
    fleet: "blue-lang-runtime",
    today: "rust:blue-lang-runtime",
    meaning: "Close it after flushing.",
    wave: 0,
    origin: "C"
  }
)

verb(
  "messeeji?",
  "commit",
  {
    kind: :effect,
    shape: "commit(consumer, position) -> nil",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "Record how far a consumer group has read.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "messeeji?",
  "compact",
  {
    kind: :effect,
    shape: "compact(bus, name) -> info",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "Keep only the newest message per key.",
    wave: 4,
    origin: "C"
  }
)

verb(
  "messeeji?",
  "connect",
  {
    kind: :effect,
    shape: "connect(url, opts) -> bus",
    laterals: %w[capability deadline error resource],
    fleet: "blue-lang-runtime",
    today: "rust:blue-lang-runtime",
    meaning: "Open a connection to a broker.",
    wave: 0,
    origin: "C"
  }
)

verb(
  "messeeji?",
  "create",
  {
    kind: :effect,
    shape: "create(bus, name, config) -> info",
    laterals: ["config"],
    fleet: nil,
    today: "absent",
    meaning: "Make a stream, queue or consumer; refuses overwrite.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "messeeji?",
  "dedupe",
  {
    kind: :pure,
    shape: "dedupe(window, id) -> Bool",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "Whether a message id was seen within a window.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "messeeji?",
  "delete",
  {
    kind: :effect,
    shape: "delete(bus, name) -> nil",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "Remove a stream, queue or consumer.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "messeeji?",
  "enter",
  {
    kind: :effect,
    shape: "enter(bus, group, f) -> member",
    laterals: %w[process resource],
    fleet: nil,
    today: "absent",
    meaning: "Share a subject's load across a consumer group.",
    wave: 2,
    origin: "C",
    contract: "enter(bus, group) -> member"
  }
)

verb(
  "messeeji?",
  "extend",
  {
    kind: :effect,
    shape: "extend(message, duration) -> nil",
    laterals: ["deadline"],
    fleet: nil,
    today: "absent",
    meaning: "Lengthen the time to ack before redelivery.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "messeeji?",
  "info",
  {
    kind: :effect,
    shape: "info(bus, name) -> record",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "Depth, bytes, consumers and retention of one.",
    wave: 1,
    origin: "C",
    contract: "info(bus, opts) -> record"
  }
)

verb(
  "messeeji?",
  "lag",
  {
    kind: :effect,
    shape: "lag(consumer) -> integer",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "How many messages a consumer is behind.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "messeeji?",
  "list",
  {
    kind: :effect,
    shape: "list(bus, opts) -> [record]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "Every stream, queue or consumer.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "messeeji?",
  "nack",
  {
    kind: :effect,
    shape: "nack(message, opts) -> nil",
    laterals: ["retry"],
    fleet: nil,
    today: "absent",
    meaning: "Refuse the message; redeliver after a delay.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "messeeji?",
  "park",
  {
    kind: :effect,
    shape: "park(message, reason) -> nil",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "Move a message to the dead-letter subject.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "messeeji?",
  "publish",
  {
    kind: :effect,
    shape: "publish(bus, subject, message, opts) -> receipt",
    laterals: %w[error idempotent retry],
    fleet: "blue-lang-runtime",
    today: "rust:blue-lang-runtime",
    meaning: "Put a message on a subject, queue or log.",
    wave: 0,
    origin: "C",
    contract: "publish(bus, subject, opts) -> receipt"
  }
)

verb(
  "messeeji?",
  "purge",
  {
    kind: :effect,
    shape: "purge(bus, name, opts) -> count",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "Drop messages from a stream or queue.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "messeeji?",
  "receive",
  {
    kind: :effect,
    shape: "receive(bus, subject, opts) -> message or nil",
    laterals: ["deadline"],
    fleet: "blue-lang-runtime",
    today: "rust:blue-lang-runtime",
    meaning: "Pull the next message, or nil on timeout.",
    wave: 0,
    origin: "C"
  }
)

verb(
  "messeeji?",
  "redrive",
  {
    kind: :effect,
    shape: "redrive(bus, dead, opts) -> count",
    laterals: ["retry"],
    fleet: nil,
    today: "absent",
    meaning: "Send parked messages back for another try.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "messeeji?",
  "replay",
  {
    kind: :stream,
    shape: "replay(bus, name, range, f) -> nil",
    laterals: ["cancel"],
    fleet: nil,
    today: "absent",
    meaning: "Re-read a log range through f.",
    wave: 2,
    origin: "C",
    contract: "replay(bus, name, opts) -> nil"
  }
)

verb(
  "messeeji?",
  "reply",
  {
    kind: :effect,
    shape: "reply(message, answer) -> nil",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "Answer a request message.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "messeeji?",
  "request",
  {
    kind: :effect,
    shape: "request(bus, subject, message, opts) -> reply",
    laterals: %w[deadline error retry],
    fleet: "blue-lang-runtime",
    today: "rust:blue-lang-runtime",
    meaning: "Publish and wait for one reply.",
    wave: 0,
    origin: "C",
    contract: "request(bus, subject, opts) -> reply"
  }
)

verb(
  "messeeji?",
  "retain",
  {
    kind: :decl,
    shape: "retain(policy) -> config",
    laterals: ["config"],
    fleet: nil,
    today: "absent",
    meaning: "Declare how long or how much a log keeps.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "messeeji?",
  "seek",
  {
    kind: :effect,
    shape: "seek(consumer, position) -> nil",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "Move a log reader to an offset, time or start.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "messeeji?",
  "subscribe",
  {
    kind: :stream,
    shape: "subscribe(bus, subject, f, opts) -> subscription",
    laterals: %w[cancel error],
    fleet: "blue-lang-runtime",
    today: "rust:blue-lang-runtime",
    meaning: "Call f per message on a subject or group.",
    wave: 0,
    origin: "C"
  }
)

verb(
  "messeeji?",
  "unsubscribe",
  {
    kind: :effect,
    shape: "unsubscribe(subscription) -> nil",
    laterals: ["resource"],
    fleet: "blue-lang-runtime",
    today: "rust:blue-lang-runtime",
    meaning: "End a subscription.",
    wave: 0,
    origin: "C"
  }
)

edge("messeeji?::dedupe", :composes, "kyoujin?::seen?", "same seen-key idea")

edge(
  "messeeji?::lag",
  :composes,
  "messeeji?::info",
  "stream end minus consumer position"
)

edge(
  "messeeji?::park",
  :composes,
  "messeeji?::publish",
  "publish to the dead subject"
)

edge(
  "messeeji?::redrive",
  :composes,
  "messeeji?::publish",
  "re-publish parked messages"
)

edge(
  "messeeji?::reply",
  :composes,
  "messeeji?::publish",
  "publish to the reply subject"
)

edge(
  "messeeji?::request",
  :composes,
  "messeeji?::publish",
  "publish with a reply subject"
)

edge("messeeji?::request", :composes, "messeeji?::receive", "then one reply")

edge(
  "messeeji?::replay",
  :composes,
  "messeeji?::seek",
  "seek then read forward"
)

edge(
  "messeeji?::retain",
  :guards,
  "messeeji?::create",
  "policy given at creation"
)

edge("messeeji?::nack", :inverse, "messeeji?::ack", "refuse versus confirm")

edge(
  "messeeji?::connect",
  :inverse,
  "messeeji?::close",
  "open and release a bus"
)

edge(
  "messeeji?::close",
  :inverse,
  "messeeji?::connect",
  "open and release a bus"
)

edge("messeeji?::delete", :inverse, "messeeji?::create", "make and remove")
edge("messeeji?::create", :inverse, "messeeji?::delete", "make and remove")
edge("messeeji?::ack", :inverse, "messeeji?::nack", "refuse versus confirm")

edge(
  "messeeji?::redrive",
  :inverse,
  "messeeji?::park",
  "parked messages go back"
)

edge("messeeji?::receive", :inverse, "messeeji?::publish", "put in, take out")
edge("messeeji?::publish", :inverse, "messeeji?::receive", "put in, take out")

edge(
  "messeeji?::park",
  :inverse,
  "messeeji?::redrive",
  "parked messages go back"
)

edge(
  "messeeji?::unsubscribe",
  :inverse,
  "messeeji?::subscribe",
  "end a subscription"
)

edge(
  "messeeji?::subscribe",
  :inverse,
  "messeeji?::unsubscribe",
  "end a subscription"
)

edge("messeeji?::list", :lifts, "messeeji?::info", "all, rather than one")

edge(
  "messeeji?::batch",
  :lifts,
  "messeeji?::publish",
  "many publishes, many receipts"
)

edge(
  "messeeji?::replay",
  :lifts,
  "messeeji?::receive",
  "a range of past messages"
)

edge(
  "messeeji?::subscribe",
  :lifts,
  "messeeji?::receive",
  "push form of receive"
)

edge(
  "messeeji?::subscribe",
  :pairs,
  "akutaa?::send",
  "subscription feeds a mailbox"
)

edge("messeeji?::enter", :pairs, "goui?::members", "group of consumers")
edge("messeeji?::request", :pairs, "heikou::deadline", "replies are bounded")

edge(
  "messeeji?::publish",
  :pairs,
  "heikou::retry",
  "publish retried with the same id"
)

edge("messeeji?::receive", :pairs, "heikou::timeout", "pull with a bound")

edge(
  "messeeji?::subscribe",
  :pairs,
  "heikou::token",
  "subscription ends on cancel"
)

edge(
  "messeeji?::publish",
  :pairs,
  "kyoujin?::once",
  "publisher id makes it idempotent"
)

edge("messeeji?::info", :pairs, "kyoujin?::pressure", "depth feeds pressure")
edge("messeeji?::lag", :pairs, "kyoujin?::pressure", "lag is a pressure signal")
edge("messeeji?::nack", :pairs, "messeeji?::ack", "opposite verdicts")

edge(
  "messeeji?::dedupe",
  :pairs,
  "messeeji?::publish",
  "publisher ids drop duplicates"
)

edge(
  "messeeji?::ack",
  :pairs,
  "messeeji?::receive",
  "every received message gets a verdict"
)

edge("messeeji?::request", :pairs, "messeeji?::reply", "asker and answerer")

edge(
  "messeeji?::create",
  :pairs,
  "messeeji?::retain",
  "retention set at creation"
)

edge(
  "messeeji?::commit",
  :pairs,
  "messeeji?::seek",
  "save then resume position"
)

edge("messeeji?::replay", :pairs, "nisshi::read", "log replays on both")
edge("messeeji?::connect", :pairs, "sokketto?::connect", "brokers ride sockets")

edge(
  "messeeji?::commit",
  :refines,
  "messeeji?::ack",
  "ack for a whole position"
)

edge(
  "messeeji?::purge",
  :refines,
  "messeeji?::delete",
  "delete messages, keep the stream"
)

edge(
  "messeeji?::compact",
  :refines,
  "messeeji?::purge",
  "purge by key supersession"
)

edge(
  "messeeji?::enter",
  :refines,
  "messeeji?::subscribe",
  "subscribe sharing load"
)

edge("messeeji?::publish", :requires, "messeeji?::connect", "needs an open bus")

edge(
  "messeeji?::info",
  :requires,
  "messeeji?::create",
  "needs an existing stream"
)

edge(
  "messeeji?::seek",
  :requires,
  "messeeji?::create",
  "positions a log consumer"
)

edge(
  "messeeji?::park",
  :requires,
  "messeeji?::nack",
  "parked after tries run out"
)

edge(
  "messeeji?::extend",
  :requires,
  "messeeji?::receive",
  "a held message only"
)
