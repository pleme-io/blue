space("toutatsu?", {status: :provisional})

verb(
  "toutatsu?",
  "certify",
  {
    kind: :effect,
    shape: "certify(key, principal, ttl) -> certificate",
    laterals: %w[capability time],
    fleet: nil,
    today: "absent",
    meaning: "Obtain a short-lived SSH certificate for a key.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "toutatsu?",
  "close",
  {
    kind: :effect,
    shape: "close(session) -> nil",
    laterals: ["resource"],
    fleet: nil,
    today: "absent",
    meaning: "End a session; closing twice is done.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "toutatsu?",
  "connect",
  {
    kind: :effect,
    shape: "connect(host, opts) -> session",
    laterals: %w[capability deadline error resource],
    fleet: "sshproxy",
    today: "absent",
    meaning: "Open an authenticated remote shell session.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "toutatsu?",
  "copy",
  {
    kind: :effect,
    shape: "copy(session, from, to, opts) -> nil",
    laterals: %w[error resource],
    fleet: nil,
    today: "absent",
    meaning: "Move a file to or from a remote host.",
    wave: 2,
    origin: "C",
    contract: "copy(session, from, opts) -> nil"
  }
)

verb(
  "toutatsu?",
  "delete",
  {
    kind: :effect,
    shape: "delete(zone, record) -> nil",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "Remove a DNS record; absent counts as done.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "toutatsu?",
  "deregister",
  {
    kind: :effect,
    shape: "deregister(registration) -> nil",
    laterals: ["resource"],
    fleet: nil,
    today: "absent",
    meaning: "Withdraw an instance; absent counts as done.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "toutatsu?",
  "diff",
  {
    kind: :pure,
    shape: "diff(wanted, actual) -> [change]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "Record changes that turn actual into wanted.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "toutatsu?",
  "down",
  {
    kind: :effect,
    shape: "down(link) -> nil",
    laterals: ["resource"],
    fleet: "blackmatter-vpn",
    today: "absent",
    meaning: "Take a tunnel interface down.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "toutatsu?",
  "find",
  {
    kind: :effect,
    shape: "find(service, opts) -> [instance]",
    laterals: ["cache"],
    fleet: nil,
    today: "absent",
    meaning: "Healthy instances of a service; empty if none.",
    wave: 2,
    origin: "C",
    contract: "find(service, query, opts) -> [instance]"
  }
)

verb(
  "toutatsu?",
  "forward",
  {
    kind: :effect,
    shape: "forward(session, local, remote) -> forwarding",
    laterals: %w[cancel resource],
    fleet: "sshproxy",
    today: "absent",
    meaning: "Carry a local port to a remote one over the session.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "toutatsu?",
  "info",
  {
    kind: :effect,
    shape: "info(link) -> record",
    laterals: [],
    fleet: "blackmatter-vpn",
    today: "absent",
    meaning: "Peers, last handshake and traffic of a tunnel.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "toutatsu?",
  "list",
  {
    kind: :effect,
    shape: "list(zone, opts) -> [record]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "Every record in a zone.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "toutatsu?",
  "peer",
  {
    kind: :decl,
    shape: "peer(key, endpoint, allowed) -> peer",
    laterals: %w[capability config],
    fleet: "blackmatter-vpn",
    today: "absent",
    meaning: "Declare one tunnel peer by key and address ranges.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "toutatsu?",
  "propagated?",
  {
    kind: :effect,
    shape: "propagated?(record, servers) -> Bool",
    laterals: %w[deadline time],
    fleet: nil,
    today: "absent",
    meaning: "Whether every server answers the new value.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "toutatsu?",
  "put",
  {
    kind: :effect,
    shape: "put(zone, record) -> record",
    laterals: %w[error idempotent],
    fleet: nil,
    today: "absent",
    meaning: "Create or replace a DNS record.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "toutatsu?",
  "register",
  {
    kind: :effect,
    shape: "register(service, opts) -> registration",
    laterals: %w[resource time],
    fleet: nil,
    today: "absent",
    meaning: "Announce a service instance under a lease.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "toutatsu?",
  "resolve",
  {
    kind: :effect,
    shape: "resolve(name, type, opts) -> [record]",
    laterals: %w[cache deadline error],
    fleet: nil,
    today: "absent",
    meaning: "Look up DNS records of a type for a name.",
    wave: 1,
    origin: "C"
  }
)

verb(
  "toutatsu?",
  "reverse",
  {
    kind: :effect,
    shape: "reverse(address) -> [name]",
    laterals: %w[deadline error],
    fleet: nil,
    today: "absent",
    meaning: "Names that point at an address.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "toutatsu?",
  "rotate",
  {
    kind: :effect,
    shape: "rotate(link, opts) -> key",
    laterals: %w[capability time],
    fleet: nil,
    today: "absent",
    meaning: "Replace a tunnel's keys without a gap.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "toutatsu?",
  "run",
  {
    kind: :effect,
    shape: "run(session, command, opts) -> result",
    laterals: %w[deadline error process],
    fleet: "sshproxy",
    today: "absent",
    meaning: "Run a command remotely; same result as a local run.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "toutatsu?",
  "up",
  {
    kind: :effect,
    shape: "up(link) -> nil",
    laterals: %w[capability resource],
    fleet: "blackmatter-vpn",
    today: "absent",
    meaning: "Bring a tunnel interface up.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "toutatsu?",
  "watch",
  {
    kind: :stream,
    shape: "watch(service, f) -> nil",
    laterals: ["cancel"],
    fleet: nil,
    today: "absent",
    meaning: "Call f when a service's instances change.",
    wave: 2,
    origin: "C"
  }
)

edge("toutatsu?::forward", :composes, "sokketto?::pipe", "relay bytes")

edge(
  "toutatsu?::propagated?",
  :composes,
  "toutatsu?::resolve",
  "asks each server"
)

edge(
  "toutatsu?::find",
  :generalizes,
  "toutatsu?::resolve",
  "discovery over DNS or registry"
)

edge(
  "toutatsu?::certify",
  :guards,
  "toutatsu?::connect",
  "short-lived cert replaces long keys"
)

edge(
  "toutatsu?::connect",
  :inverse,
  "toutatsu?::close",
  "start and end a session"
)

edge(
  "toutatsu?::close",
  :inverse,
  "toutatsu?::connect",
  "start and end a session"
)

edge(
  "toutatsu?::put",
  :inverse,
  "toutatsu?::delete",
  "create and remove a record"
)

edge(
  "toutatsu?::register",
  :inverse,
  "toutatsu?::deregister",
  "announce and withdraw"
)

edge("toutatsu?::up", :inverse, "toutatsu?::down", "raise and lower a link")

edge(
  "toutatsu?::delete",
  :inverse,
  "toutatsu?::put",
  "create and remove a record"
)

edge(
  "toutatsu?::deregister",
  :inverse,
  "toutatsu?::register",
  "announce and withdraw"
)

edge(
  "toutatsu?::reverse",
  :inverse,
  "toutatsu?::resolve",
  "name to address and back"
)

edge(
  "toutatsu?::resolve",
  :inverse,
  "toutatsu?::reverse",
  "name to address and back"
)

edge("toutatsu?::down", :inverse, "toutatsu?::up", "raise and lower a link")
edge("toutatsu?::watch", :lifts, "toutatsu?::find", "changes in the result")

edge(
  "toutatsu?::find",
  :pairs,
  "chuukai?::upstream",
  "discovery fills upstreams"
)

edge(
  "toutatsu?::register",
  :pairs,
  "goui?::heartbeat",
  "a registration lives by its lease"
)

edge(
  "toutatsu?::watch",
  :pairs,
  "goui?::watch",
  "both stream membership changes"
)

edge(
  "toutatsu?::resolve",
  :pairs,
  "heikou::retry",
  "lookups retried on failure"
)

edge("toutatsu?::run", :pairs, "heikou::timeout", "remote commands are bounded")
edge("toutatsu?::up", :pairs, "sokketto?::connect", "a tunnel carries sockets")

edge(
  "toutatsu?::connect",
  :pairs,
  "sokketto?::secure",
  "a session is an encrypted connection"
)

edge("toutatsu?::list", :pairs, "toutatsu?::diff", "actual state for the diff")

edge(
  "toutatsu?::resolve",
  :pairs,
  "toutatsu?::list",
  "query versus zone listing"
)

edge("toutatsu?::peer", :pairs, "toutatsu?::up", "declare then bring up")
edge("toutatsu?::diff", :refines, "deeta::diff", "records as data")
edge("toutatsu?::copy", :refines, "fairu::copy", "remote form of copy")
edge("toutatsu?::run", :refines, "shisutemu::run", "remote form of run")

edge(
  "toutatsu?::close",
  :requires,
  "toutatsu?::connect",
  "ends what open began"
)

edge("toutatsu?::copy", :requires, "toutatsu?::connect", "needs a session")
edge("toutatsu?::forward", :requires, "toutatsu?::connect", "rides a session")
edge("toutatsu?::run", :requires, "toutatsu?::connect", "needs a session")
edge("toutatsu?::put", :requires, "toutatsu?::diff", "reconcile applies a diff")

edge(
  "toutatsu?::rotate",
  :requires,
  "toutatsu?::info",
  "reads handshake before swapping"
)

edge("toutatsu?::up", :requires, "toutatsu?::peer", "needs declared peers")

edge(
  "toutatsu?::find",
  :requires,
  "toutatsu?::register",
  "returns registered instances"
)

edge("toutatsu?::info", :requires, "toutatsu?::up", "inspects a link")
