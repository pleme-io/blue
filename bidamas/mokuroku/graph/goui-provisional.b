space("goui?", {status: :provisional})

verb(
  "goui?",
  "acquire",
  {
    kind: :effect,
    shape: "acquire(name, opts) -> lease",
    laterals: %w[deadline resource time],
    fleet: nil,
    today: "absent",
    meaning: "Take a lease on a name for a duration.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "goui?",
  "append",
  {
    kind: :effect,
    shape: "append(log, entry, opts) -> index",
    laterals: %w[error idempotent],
    fleet: nil,
    today: "absent",
    meaning: "Add an entry to a replicated log; return where.",
    wave: 4,
    origin: "C"
  }
)

verb(
  "goui?",
  "barrier",
  {
    kind: :effect,
    shape: "barrier(name, count, opts) -> nil",
    laterals: ["deadline"],
    fleet: nil,
    today: "absent",
    meaning: "Block until count members have arrived.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "goui?",
  "compare",
  {
    kind: :pure,
    shape: "compare(a, b) -> order",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "Order two clocks: before, after or concurrent.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "goui?",
  "elect",
  {
    kind: :effect,
    shape: "elect(group, opts) -> leadership",
    laterals: %w[cancel deadline error resource],
    fleet: nil,
    today: "absent",
    meaning: "Campaign until this member leads; hold while valid.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "goui?",
  "enter",
  {
    kind: :effect,
    shape: "enter(group, member) -> view",
    laterals: ["process"],
    fleet: nil,
    today: "absent",
    meaning: "Add a member to a group; return the new view.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "goui?",
  "fence",
  {
    kind: :pure,
    shape: "fence(lease) -> integer",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "The lease's increasing token, checked by the resource.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "goui?",
  "gossip",
  {
    kind: :stream,
    shape: "gossip(peers, state, opts) -> nil",
    laterals: %w[cancel time],
    fleet: nil,
    today: "absent",
    meaning: "Exchange state with random peers until stable.",
    wave: 4,
    origin: "C"
  }
)

verb(
  "goui?",
  "heartbeat",
  {
    kind: :stream,
    shape: "heartbeat(member, interval) -> nil",
    laterals: %w[cancel time],
    fleet: nil,
    today: "absent",
    meaning: "Announce liveness every interval.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "goui?",
  "held?",
  {
    kind: :effect,
    shape: "held?(lease) -> Bool",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "Whether the lease is still valid now.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "goui?",
  "leader",
  {
    kind: :effect,
    shape: "leader(group) -> member or nil",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "Who leads now, or nil if no one.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "goui?",
  "leave",
  {
    kind: :effect,
    shape: "leave(group, member) -> view",
    laterals: ["process"],
    fleet: nil,
    today: "absent",
    meaning: "Remove a member from a group.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "goui?",
  "members",
  {
    kind: :effect,
    shape: "members(group) -> [member]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "Who is in the group now, with their state.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "goui?",
  "merge",
  {
    kind: :pure,
    shape: "merge(a, b) -> value",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "Join two replicas of a mergeable value (CRDT).",
    wave: 4,
    origin: "C"
  }
)

verb(
  "goui?",
  "propose",
  {
    kind: :effect,
    shape: "propose(group, value, opts) -> result",
    laterals: %w[deadline error idempotent],
    fleet: nil,
    today: "absent",
    meaning: "Ask the group to agree on a value.",
    wave: 4,
    origin: "C"
  }
)

verb(
  "goui?",
  "quorum",
  {
    kind: :pure,
    shape: "quorum(size) -> integer",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "The votes that make a majority of a group.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "goui?",
  "release",
  {
    kind: :effect,
    shape: "release(lease) -> nil",
    laterals: ["resource"],
    fleet: nil,
    today: "absent",
    meaning: "Give a lease back; releasing twice is done.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "goui?",
  "renew",
  {
    kind: :effect,
    shape: "renew(lease) -> lease",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "Extend a lease before it lapses.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "goui?",
  "replicate",
  {
    kind: :effect,
    shape: "replicate(log, to, opts) -> info",
    laterals: %w[deadline retry],
    fleet: nil,
    today: "absent",
    meaning: "Bring a follower up to date.",
    wave: 4,
    origin: "C"
  }
)

verb(
  "goui?",
  "resign",
  {
    kind: :effect,
    shape: "resign(leadership) -> nil",
    laterals: ["resource"],
    fleet: nil,
    today: "absent",
    meaning: "Give up leading.",
    wave: 2,
    origin: "C"
  }
)

verb(
  "goui?",
  "snapshot",
  {
    kind: :effect,
    shape: "snapshot(log, opts) -> snapshot",
    laterals: ["resource"],
    fleet: nil,
    today: "absent",
    meaning: "Capture log state so older entries can go.",
    wave: 4,
    origin: "C"
  }
)

verb(
  "goui?",
  "suspect?",
  {
    kind: :pure,
    shape: "suspect?(history, now) -> Bool",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "Whether a member's silence marks it failed.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "goui?",
  "tick",
  {
    kind: :pure,
    shape: "tick(clock, event) -> clock",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "Advance a logical or hybrid clock.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "goui?",
  "watch",
  {
    kind: :stream,
    shape: "watch(group, f) -> nil",
    laterals: ["cancel"],
    fleet: nil,
    today: "absent",
    meaning: "Call f when membership or leader changes.",
    wave: 3,
    origin: "C"
  }
)

verb(
  "goui?",
  "with_lock",
  {
    kind: :effect,
    shape: "with_lock(name, f, opts) -> value",
    laterals: %w[cancel deadline resource],
    fleet: nil,
    today: "absent",
    meaning: "Run f while holding a named lease, then release.",
    wave: 2,
    origin: "C"
  }
)

edge(
  "goui?::elect",
  :composes,
  "goui?::acquire",
  "leadership is a lease on a group"
)

edge("goui?::with_lock", :composes, "goui?::acquire", "acquire around f")

edge(
  "goui?::propose",
  :composes,
  "goui?::append",
  "a proposal appends to the log"
)

edge("goui?::gossip", :composes, "goui?::merge", "exchange then merge")
edge("goui?::with_lock", :composes, "goui?::release", "release after f")

edge(
  "goui?::append",
  :composes,
  "goui?::replicate",
  "entry copied to followers"
)

edge(
  "goui?::gossip",
  :composes,
  "messeeji?::publish",
  "peers are reached by messages"
)

edge(
  "goui?::merge",
  :generalizes,
  "jisho::merge",
  "merge with a convergence law"
)

edge("goui?::quorum", :guards, "goui?::propose", "size checked before voting")
edge("goui?::held?", :guards, "goui?::renew", "a lapsed lease cannot renew")

edge(
  "goui?::fence",
  :guards,
  "goui?::with_lock",
  "the resource checks the token"
)

edge("goui?::release", :inverse, "goui?::acquire", "take and give back")
edge("goui?::resign", :inverse, "goui?::elect", "give up what elect takes")
edge("goui?::leave", :inverse, "goui?::enter", "enter and leave a group")
edge("goui?::enter", :inverse, "goui?::leave", "enter and leave a group")
edge("goui?::acquire", :inverse, "goui?::release", "take and give back")
edge("goui?::elect", :inverse, "goui?::resign", "give up what elect takes")
edge("goui?::watch", :lifts, "goui?::leader", "leader changes as events")
edge("goui?::watch", :lifts, "goui?::members", "membership changes as events")
edge("goui?::propose", :pairs, "akutaa?::call", "agreement over messages")
edge("goui?::snapshot", :pairs, "goui?::append", "snapshot lets the log shrink")
edge("goui?::tick", :pairs, "goui?::compare", "advance and order clocks")
edge("goui?::merge", :pairs, "goui?::gossip", "gossip spreads, merge joins")
edge("goui?::with_lock", :pairs, "goui?::renew", "long work renews")
edge("goui?::elect", :pairs, "goui?::resign", "take and give up")
edge("goui?::heartbeat", :pairs, "goui?::suspect?", "signals and their absence")

edge(
  "goui?::heartbeat",
  :pairs,
  "heikou::deadline",
  "silence past a deadline fails"
)

edge(
  "goui?::with_lock",
  :pairs,
  "kyoujin?::once",
  "lock or key for exactly-once"
)

edge(
  "goui?::replicate",
  :pairs,
  "messeeji?::replay",
  "followers replay the log"
)

edge("goui?::elect", :pairs, "shigoto::every", "one leader runs the schedule")
edge("goui?::members", :pairs, "toutatsu?::find", "both answer who is there")
edge("goui?::acquire", :pairs, "toutatsu?::register", "registration is a lease")
edge("goui?::fence", :requires, "goui?::acquire", "token comes from the lease")
edge("goui?::held?", :requires, "goui?::acquire", "asks about a held lease")
edge("goui?::renew", :requires, "goui?::acquire", "extends a held lease")
edge("goui?::append", :requires, "goui?::elect", "only the leader appends")

edge(
  "goui?::leader",
  :requires,
  "goui?::elect",
  "reads the holder of leadership"
)

edge("goui?::members", :requires, "goui?::enter", "the group joined")

edge(
  "goui?::suspect?",
  :requires,
  "goui?::heartbeat",
  "judges the heartbeat history"
)

edge("goui?::barrier", :requires, "goui?::members", "counts arrived members")
edge("goui?::propose", :requires, "goui?::quorum", "agreement needs a majority")

edge(
  "goui?::replicate",
  :requires,
  "goui?::quorum",
  "commit when a majority has it"
)

edge("goui?::compare", :requires, "goui?::tick", "orders ticked clocks")
