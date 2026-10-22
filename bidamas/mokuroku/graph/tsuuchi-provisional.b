space("tsuuchi?", {status: :provisional})

verb(
  "tsuuchi?",
  "channel",
  {
    kind: :decl,
    shape: "channel(kind, config) -> channel",
    laterals: ["capability", "config"],
    fleet: nil,
    today: "absent",
    meaning: "Declare how one delivery kind is reached.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "tsuuchi?",
  "compose",
  {
    kind: :pure,
    shape: "compose(parts) -> message",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "Build a MIME or payload message from parts.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "tsuuchi?",
  "parse",
  {
    kind: :pure,
    shape: "parse(text, :email) -> message",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "Read a raw email into headers, body and parts.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "tsuuchi?",
  "register",
  {
    kind: :effect,
    shape: "register(device or address, opts) -> record",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "Enrol a device token or address for delivery.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "tsuuchi?",
  "render",
  {
    kind: :pure,
    shape: "render(template, data) -> message",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "Fill a template; a missing hole is refused.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "tsuuchi?",
  "send",
  {
    kind: :effect,
    shape: "send(message, opts) -> receipt",
    laterals: ["error", "idempotent", "ratelimit", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "Deliver to a person by email, SMS, push or webhook.",
    wave: 1,
    origin: "C",
    contract: "send(message, message, opts) -> receipt"
  }
)

verb(
  "tsuuchi?",
  "sign",
  {
    kind: :pure,
    shape: "sign(payload, secret) -> signature",
    laterals: ["capability"],
    fleet: nil,
    today: "absent",
    meaning: "Sign an outgoing webhook payload.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "tsuuchi?",
  "status",
  {
    kind: :effect,
    shape: "status(receipt) -> record",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "Delivery state: queued, sent, delivered, bounced.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "tsuuchi?",
  "subscribe",
  {
    kind: :effect,
    shape: "subscribe(topic, address) -> nil",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "Put an address on a topic's list.",
    wave: 3,
    origin: "C",
    contract: "subscribe(topic, address, f, opts) -> nil"
  }
)

verb(
  "tsuuchi?",
  "suppress",
  {
    kind: :effect,
    shape: "suppress(address, reason) -> nil",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "Stop sending to an address.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "tsuuchi?",
  "suppressed?",
  {
    kind: :effect,
    shape: "suppressed?(address) -> Bool",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "Whether an address is on the stop list.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "tsuuchi?",
  "template",
  {
    kind: :decl,
    shape: "template(name, body) -> template",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "Declare a message body with named holes.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "tsuuchi?",
  "validate",
  {
    kind: :pure,
    shape: "validate(address, kind) -> address",
    laterals: ["error", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "Check an email or phone number's form.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "tsuuchi?",
  "verify?",
  {
    kind: :pure,
    shape: "verify?(request, secret) -> Bool",
    laterals: ["capability", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "Whether a webhook signature and timestamp are good.",
    wave: 1,
    origin: "C"
  }
)

edge("tsuuchi?::send", :composes, "tsuuchi?::render", "render then deliver")

edge(
  "tsuuchi?::validate",
  :guards,
  "tsuuchi?::send",
  "bad addresses refused early"
)

edge(
  "tsuuchi?::parse",
  :inverse,
  "tsuuchi?::compose",
  "build and read a message"
)

edge(
  "tsuuchi?::compose",
  :inverse,
  "tsuuchi?::parse",
  "build and read a message"
)

edge("tsuuchi?::render", :inverse, "tsuuchi?::parse", "text out versus text in")
edge("tsuuchi?::suppress", :inverse, "tsuuchi?::register", "enrol versus stop")
edge("tsuuchi?::parse", :inverse, "tsuuchi?::render", "text out versus text in")

edge(
  "tsuuchi?::verify?",
  :inverse,
  "tsuuchi?::sign",
  "check and make a signature"
)

edge("tsuuchi?::register", :inverse, "tsuuchi?::suppress", "enrol versus stop")

edge(
  "tsuuchi?::sign",
  :inverse,
  "tsuuchi?::verify?",
  "check and make a signature"
)

edge("tsuuchi?::parse", :pairs, "deeta::parse", "a message is data")
edge("tsuuchi?::send", :pairs, "kyoujin?::bucket", "senders are rate limited")

edge(
  "tsuuchi?::send",
  :pairs,
  "kyoujin?::once",
  "a key makes a send safe to retry"
)

edge("tsuuchi?::send", :pairs, "messeeji?::publish", "delivery can be queued")
edge("tsuuchi?::status", :pairs, "nisshi::append", "receipts are logged")
edge("tsuuchi?::channel", :pairs, "tsuuchi?::send", "declaration and use")

edge(
  "tsuuchi?::suppress",
  :pairs,
  "tsuuchi?::suppressed?",
  "write and read of the stop list"
)

edge(
  "tsuuchi?::send",
  :pairs,
  "tsuushin::request",
  "webhook delivery is a request"
)

edge(
  "tsuuchi?::subscribe",
  :refines,
  "messeeji?::subscribe",
  "topic list for humans"
)

edge("tsuuchi?::sign", :refines, "shomei::sign", "webhook form of sign")
edge("tsuuchi?::verify?", :refines, "shomei::verify?", "webhook form of verify")

edge(
  "tsuuchi?::send",
  :requires,
  "tsuuchi?::channel",
  "delivery needs a channel"
)

edge("tsuuchi?::status", :requires, "tsuuchi?::send", "status of a receipt")

edge(
  "tsuuchi?::send",
  :requires,
  "tsuuchi?::suppressed?",
  "stop-list checked first"
)

edge(
  "tsuuchi?::render",
  :requires,
  "tsuuchi?::template",
  "fills a declared template"
)
