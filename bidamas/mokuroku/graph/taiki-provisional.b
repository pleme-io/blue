space("taiki?", {status: :provisional})

verb(
  "taiki?",
  "ack",
  {
    kind: :effect,
    shape: "ack(queue, message) -> nil",
    laterals: ["idempotent"],
    fleet: "pleme-redis",
    today: "absent",
    meaning: "finish a leased message and remove it",
    wave: 2,
    origin: "B"
  }
)

verb(
  "taiki?",
  "cancel",
  {
    kind: :effect,
    shape: "cancel(queue, id) -> nil",
    laterals: %w[cancel idempotent],
    fleet: nil,
    today: "absent",
    meaning: "remove a waiting message before anyone leases it",
    wave: 2,
    origin: "B"
  }
)

verb(
  "taiki?",
  "close",
  {
    kind: :effect,
    shape: "close(queue) -> nil",
    laterals: ["resource"],
    fleet: nil,
    today: "absent",
    meaning: "release the queue handle",
    wave: 2,
    origin: "B"
  }
)

verb(
  "taiki?",
  "dead",
  {
    kind: :effect,
    shape: "dead(queue, opts) -> [message]",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "messages that ran out of retries, with the last error",
    wave: 2,
    origin: "B"
  }
)

verb(
  "taiki?",
  "drain",
  {
    kind: :effect,
    shape: "drain(queue, opts) -> nil",
    laterals: %w[cancel deadline],
    fleet: nil,
    today: "absent",
    meaning: "wait until the queue is empty and nothing is leased",
    wave: 3,
    origin: "B"
  }
)

verb(
  "taiki?",
  "get",
  {
    kind: :effect,
    shape: "get(queue, id) -> message or nil",
    laterals: [],
    fleet: "pleme-redis",
    today: "absent",
    meaning: "one message and its state by id, or nil",
    wave: 2,
    origin: "B"
  }
)

verb(
  "taiki?",
  "info",
  {
    kind: :effect,
    shape: "info(queue) -> {waiting, leased, dead, oldest}",
    laterals: ["time"],
    fleet: "pleme-redis",
    today: "absent",
    meaning: "depth and age counters of the queue as a record",
    wave: 2,
    origin: "B"
  }
)

verb(
  "taiki?",
  "nack",
  {
    kind: :effect,
    shape: "nack(queue, message, opts) -> nil",
    laterals: %w[idempotent retry],
    fleet: "pleme-redis",
    today: "absent",
    meaning: "give a leased message back, optionally after a delay",
    wave: 2,
    origin: "B"
  }
)

verb(
  "taiki?",
  "open",
  {
    kind: :effect,
    shape: "open(spec) -> queue",
    laterals: %w[config resource],
    fleet: "pleme-redis",
    today: "absent",
    meaning: "connect to a durable queue by name",
    wave: 2,
    origin: "B"
  }
)

verb(
  "taiki?",
  "pause",
  {
    kind: :effect,
    shape: "pause(queue) -> nil",
    laterals: %w[idempotent switch],
    fleet: nil,
    today: "absent",
    meaning: "stop handing out messages while still accepting them",
    wave: 3,
    origin: "B"
  }
)

verb(
  "taiki?",
  "peek",
  {
    kind: :effect,
    shape: "peek(queue, n) -> [message]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "look at waiting messages without leasing them",
    wave: 2,
    origin: "B"
  }
)

verb(
  "taiki?",
  "purge",
  {
    kind: :effect,
    shape: "purge(queue) -> count",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "delete every waiting message",
    wave: 3,
    origin: "B"
  }
)

verb(
  "taiki?",
  "receive",
  {
    kind: :effect,
    shape: "receive(queue, opts) -> [message]",
    laterals: %w[deadline error resource],
    fleet: "pleme-redis",
    today: "absent",
    meaning: "lease messages for a visibility time without removing them",
    wave: 2,
    origin: "B"
  }
)

verb(
  "taiki?",
  "redrive",
  {
    kind: :effect,
    shape: "redrive(queue, opts) -> count",
    laterals: %w[error idempotent],
    fleet: nil,
    today: "absent",
    meaning: "move dead messages back to the live queue",
    wave: 3,
    origin: "B"
  }
)

verb(
  "taiki?",
  "renew",
  {
    kind: :effect,
    shape: "renew(queue, message, by) -> nil",
    laterals: %w[deadline time],
    fleet: nil,
    today: "absent",
    meaning: "lengthen the lease on a message being worked",
    wave: 2,
    origin: "B",
    contract: "renew(queue, message, opts) -> nil"
  }
)

verb(
  "taiki?",
  "resume",
  {
    kind: :effect,
    shape: "resume(queue) -> nil",
    laterals: %w[idempotent switch],
    fleet: nil,
    today: "absent",
    meaning: "hand out messages again after a pause",
    wave: 3,
    origin: "B"
  }
)

verb(
  "taiki?",
  "schedule",
  {
    kind: :decl,
    shape: "schedule(queue, spec, message) -> decl",
    laterals: %w[config time],
    fleet: nil,
    today: "absent",
    meaning: "declare a message sent on a repeating time rule",
    wave: 3,
    origin: "B",
    contract: "schedule(queue, spec, opts) -> decl"
  }
)

verb(
  "taiki?",
  "send",
  {
    kind: :effect,
    shape: "send(queue, message, opts) -> id",
    laterals: %w[error idempotent ratelimit serialize],
    fleet: "pleme-redis",
    today: "absent",
    meaning: "add a message, optionally delayed, keyed or prioritized",
    wave: 2,
    origin: "B"
  }
)

verb(
  "taiki?",
  "send_all",
  {
    kind: :effect,
    shape: "send_all(queue, messages, opts) -> [id]",
    laterals: %w[error idempotent],
    fleet: nil,
    today: "absent",
    meaning: "add many messages in one round trip",
    wave: 2,
    origin: "B"
  }
)

verb(
  "taiki?",
  "work",
  {
    kind: :effect,
    shape: "work(queue, f, opts) -> nil",
    laterals: %w[cancel deadline log ratelimit resource retry],
    fleet: "pleme-redis",
    today: "absent",
    meaning: "run f per message with leases, retries and a concurrency limit",
    wave: 2,
    origin: "B"
  }
)

edge("taiki?::work", :composes, "heikou::map", "bounded concurrency")
edge("taiki?::open", :composes, "himitsu::read", "credentials for the broker")

edge(
  "taiki?::work",
  :composes,
  "saishikou::retrying",
  "retry policy per message"
)

edge("taiki?::send", :composes, "shomei::hash", "dedupe key from the message")
edge("taiki?::work", :composes, "taiki?::ack", "finishes on success")
edge("taiki?::drain", :composes, "taiki?::info", "polls until empty")
edge("taiki?::dead", :composes, "taiki?::nack", "messages out of retries")
edge("taiki?::work", :composes, "taiki?::nack", "returns on raise")
edge("taiki?::work", :composes, "taiki?::receive", "takes leases")
edge("taiki?::work", :composes, "taiki?::renew", "keeps long jobs leased")
edge("taiki?::redrive", :composes, "taiki?::send", "re-enqueues each")
edge("taiki?::schedule", :composes, "taiki?::send", "sends on the rule")
edge("taiki?::pause", :guards, "taiki?::drain", "drain waits on a paused queue")
edge("taiki?::send", :inverse, "taiki?::cancel", "withdraws a waiting message")
edge("taiki?::open", :inverse, "taiki?::close", "releases the handle")
edge("taiki?::receive", :inverse, "taiki?::nack", "returns the lease")
edge("taiki?::close", :inverse, "taiki?::open", "releases the handle")
edge("taiki?::resume", :inverse, "taiki?::pause", "starts hand-out")
edge("taiki?::nack", :inverse, "taiki?::receive", "returns the lease")
edge("taiki?::pause", :inverse, "taiki?::resume", "starts hand-out")
edge("taiki?::cancel", :inverse, "taiki?::send", "withdraws a waiting message")
edge("taiki?::purge", :lifts, "taiki?::cancel", "every waiting message")
edge("taiki?::send_all", :lifts, "taiki?::send", "many messages per call")
edge("taiki?::receive", :pairs, "taiki?::ack", "lease then finish")
edge("taiki?::open", :pairs, "taiki?::close", "handle and its release")
edge("taiki?::redrive", :pairs, "taiki?::dead", "moves them back")
edge("taiki?::dead", :pairs, "taiki?::info", "dead count among counters")
edge("taiki?::info", :pairs, "taiki?::peek", "counters beside contents")
edge("taiki?::get", :pairs, "taiki?::send", "look up what was sent")
edge("taiki?::get", :refines, "taiki?::peek", "one message by id")
edge("taiki?::peek", :refines, "taiki?::receive", "looks without leasing")
edge("taiki?::drain", :requires, "taiki?::pause", "no new work meanwhile")
edge("taiki?::ack", :requires, "taiki?::receive", "only a leased message")
edge("taiki?::renew", :requires, "taiki?::receive", "lease must be held")
