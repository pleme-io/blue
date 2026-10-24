space("nisshi", {status: :ratified})

verb(
  "nisshi",
  "append",
  {
    kind: :effect,
    shape: "append(log, event, opts) -> record",
    laterals: ["error", "idempotent", "log", "serialize", "time"],
    fleet: nil,
    today: "exists:nisshi",
    meaning: "add one event; refuses a bad event with a typed kind",
    wave: 0,
    origin: "F"
  }
)

verb(
  "nisshi",
  "append_all",
  {
    kind: :effect,
    shape: "append_all(log, events, opts) -> [record]",
    laterals: ["error", "idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "add many events atomically or none",
    wave: 2,
    origin: "B"
  }
)

verb(
  "nisshi",
  "at",
  {
    kind: :pure,
    shape: "at(log, entity, seq) -> state",
    laterals: ["validate"],
    fleet: nil,
    today: "partial:nisshi",
    meaning: "an entity's state after a given record",
    wave: 0,
    origin: "D",
    contract: "at(log, entity) -> state"
  }
)

verb(
  "nisshi",
  "audit",
  {
    kind: :effect,
    shape: "audit(actor, action, target, outcome, opts) -> record",
    laterals: ["idempotent", "log", "time"],
    fleet: "tameshi",
    today: "absent",
    meaning: "append who did what to what, with the result",
    wave: 1,
    origin: "D"
  }
)

verb(
  "nisshi",
  "canon",
  {
    kind: :pure,
    shape: "canon(value) -> text",
    laterals: ["serialize"],
    fleet: nil,
    today: "exists:nisshi",
    wave: 0,
    origin: "B"
  }
)

verb(
  "nisshi",
  "capture",
  {
    kind: :stream,
    shape: "capture(source, f, opts) -> nil",
    laterals: ["cancel", "deadline", "retry"],
    fleet: nil,
    today: "absent",
    meaning: "turn a store changes into events, as change data capture",
    wave: 3,
    origin: "B"
  }
)

verb(
  "nisshi",
  "checkpoint",
  {
    kind: :effect,
    shape: "checkpoint(log, consumer, seq) -> nil",
    laterals: ["capability", "idempotent", "log"],
    fleet: nil,
    today: "absent",
    meaning: "record how far a named consumer has read",
    wave: 1,
    origin: "B"
  }
)

verb(
  "nisshi",
  "close",
  {
    kind: :effect,
    shape: "close(log) -> nil",
    laterals: ["resource"],
    fleet: nil,
    today: "absent",
    meaning: "release the log and its writer",
    wave: 1,
    origin: "B"
  }
)

verb(
  "nisshi",
  "compact",
  {
    kind: :effect,
    shape: "compact(log, keyer) -> count",
    laterals: ["error", "idempotent", "resource"],
    fleet: nil,
    today: "absent",
    meaning: "keep only the latest record per key",
    wave: 2,
    origin: "B"
  }
)

verb(
  "nisshi",
  "correlate",
  {
    kind: :effect,
    shape: "correlate(log, id) -> [record]",
    laterals: ["trace"],
    fleet: nil,
    today: "absent",
    meaning: "every record linked to a correlation or cause id",
    wave: 2,
    origin: "B"
  }
)

verb(
  "nisshi",
  "diff",
  {
    kind: :pure,
    shape: "diff(a, b) -> break or nil",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the first sequence where two logs disagree",
    wave: 3,
    origin: "B"
  }
)

verb(
  "nisshi",
  "entry",
  {
    kind: :pure,
    shape: "entry(fields) -> record",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:nisshi",
    wave: 0,
    origin: "B"
  }
)

verb(
  "nisshi",
  "export",
  {
    kind: :effect,
    shape: "export(log, target, opts) -> nil",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "write a sealed bundle of a log for another party",
    wave: 2,
    origin: "F"
  }
)

verb(
  "nisshi",
  "first_break",
  {
    kind: :effect,
    shape: "first_break(log) -> break or nil",
    laterals: ["validate"],
    fleet: nil,
    today: "partial:nisshi",
    meaning: "the first line where the chain fails, with why",
    wave: 0,
    origin: "B"
  }
)

verb(
  "nisshi",
  "fold",
  {
    kind: :effect,
    shape: "fold(log, projection, opts) -> view",
    laterals: ["cancel", "error"],
    fleet: nil,
    today: "absent",
    meaning: "keep a read model current from the log, from a checkpoint",
    wave: 2,
    origin: "B"
  }
)

verb(
  "nisshi",
  "forget",
  {
    kind: :effect,
    shape: "forget(log, subject) -> count",
    laterals: ["error", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "make one subject payloads unreadable while the chain holds",
    wave: 4,
    origin: "B"
  }
)

verb(
  "nisshi",
  "genesis",
  {
    kind: :pure,
    shape: "genesis(label) -> hash",
    laterals: ["serialize"],
    fleet: nil,
    today: "exists:nisshi",
    wave: 0,
    origin: "B"
  }
)

verb(
  "nisshi",
  "get",
  {
    kind: :effect,
    shape: "get(log, seq) -> record or nil",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "one record by sequence number, or nil",
    wave: 1,
    origin: "B"
  }
)

verb(
  "nisshi",
  "head",
  {
    kind: :pure,
    shape: "head(log) -> hex",
    laterals: ["error", "validate"],
    fleet: nil,
    today: "exists:nisshi",
    wave: 0,
    origin: "D"
  }
)

verb(
  "nisshi",
  "history",
  {
    kind: :pure,
    shape: "history(log, entity) -> [record]",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:nisshi",
    wave: 0,
    origin: "D"
  }
)

verb(
  "nisshi",
  "intact?",
  {
    kind: :pure,
    shape: "intact?(log) -> Bool",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:nisshi",
    wave: 0,
    origin: "D"
  }
)

verb(
  "nisshi",
  "interleave",
  {
    kind: :pure,
    shape: "interleave(logs) -> [record]",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "interleave several logs by time into one ordered list",
    wave: 3,
    origin: "B"
  }
)

verb(
  "nisshi",
  "lag",
  {
    kind: :effect,
    shape: "lag(log, consumer) -> number",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "how many records a consumer is behind the head",
    wave: 2,
    origin: "B"
  }
)

verb(
  "nisshi",
  "offset",
  {
    kind: :effect,
    shape: "offset(log, consumer) -> seq or nil",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "where a named consumer last stopped",
    wave: 2,
    origin: "B"
  }
)

verb(
  "nisshi",
  "open",
  {
    kind: :effect,
    shape: "open(path, opts) -> log",
    laterals: ["capability", "config", "idempotent", "resource"],
    fleet: nil,
    today: "exists:nisshi",
    wave: 0,
    origin: "F"
  }
)

verb(
  "nisshi",
  "prove",
  {
    kind: :pure,
    shape: "prove(log, seq) -> proof",
    laterals: ["validate"],
    fleet: "tameshi",
    today: "absent",
    meaning: "proof that a record is in the log up to a head",
    wave: 2,
    origin: "D"
  }
)

verb(
  "nisshi",
  "publish",
  {
    kind: :effect,
    shape: "publish(bus, topic, event, opts) -> nil",
    laterals: ["error", "retry", "serialize", "trace"],
    fleet: "pleme-redis",
    today: "absent",
    meaning: "send an event to the live readers of a topic",
    wave: 2,
    origin: "B",
    contract: "publish(bus, topic, opts) -> nil"
  }
)

verb(
  "nisshi",
  "query",
  {
    kind: :effect,
    shape: "query(log, question, params) -> [record]",
    laterals: ["resource", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "ask a log a question in SQL via kueri",
    wave: 2,
    origin: "D"
  }
)

verb(
  "nisshi",
  "read",
  {
    kind: :effect,
    shape: "read(stream, opts) -> [event]",
    laterals: ["deadline", "error", "resource", "serialize"],
    fleet: "blue",
    today: "exists:nisshi",
    wave: 0,
    origin: "C"
  }
)

verb(
  "nisshi",
  "replay",
  {
    kind: :pure,
    shape: "replay(log, definition) -> states",
    laterals: ["deadline", "error", "migrate", "validate"],
    fleet: nil,
    today: "partial:nisshi",
    meaning: "fold records into the states they imply",
    wave: 0,
    origin: "D"
  }
)

verb(
  "nisshi",
  "roll",
  {
    kind: :effect,
    shape: "roll(log, opts) -> nil",
    laterals: ["idempotent", "resource"],
    fleet: nil,
    today: "absent",
    meaning: "start a new segment linked to the old head",
    wave: 2,
    origin: "D"
  }
)

verb(
  "nisshi",
  "rotate",
  {
    kind: :effect,
    shape: "rotate(log) -> segment",
    laterals: ["resource"],
    fleet: nil,
    today: "absent",
    meaning: "close the current segment and start a new one",
    wave: 3,
    origin: "B"
  }
)

verb(
  "nisshi",
  "seal",
  {
    kind: :effect,
    shape: "seal(log, segment) -> hash",
    laterals: ["idempotent", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "freeze a segment against further writes and hash it",
    wave: 3,
    origin: "B"
  }
)

verb(
  "nisshi",
  "snapshot",
  {
    kind: :effect,
    shape: "snapshot(log, state, opts) -> nil",
    laterals: ["idempotent", "serialize"],
    fleet: nil,
    today: "absent",
    meaning: "save folded state at a sequence so replay can start there",
    wave: 2,
    origin: "B",
    contract: "snapshot(log, opts) -> nil"
  }
)

verb(
  "nisshi",
  "state_at",
  {
    kind: :pure,
    shape: "state_at(log, entity, at) -> state",
    laterals: ["time"],
    fleet: nil,
    today: "exists:nisshi",
    wave: 0,
    origin: "F"
  }
)

verb(
  "nisshi",
  "stream",
  {
    kind: :stream,
    shape: "stream(log, f, opts) -> nil",
    laterals: ["cancel", "deadline", "error"],
    fleet: nil,
    today: "absent",
    meaning: "call f per record from a sequence onward, then return",
    wave: 2,
    origin: "B"
  }
)

verb(
  "nisshi",
  "subscribe",
  {
    kind: :stream,
    shape: "subscribe(log, consumer, f, opts) -> nil",
    laterals: ["cancel", "deadline", "retry"],
    fleet: "pleme-redis",
    today: "absent",
    meaning: "durable delivery to f from the consumer offset, at least once",
    wave: 2,
    origin: "B"
  }
)

verb(
  "nisshi",
  "truncate",
  {
    kind: :effect,
    shape: "truncate(log, before) -> count",
    laterals: ["error", "idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "drop records older than a sequence under a retention rule",
    wave: 3,
    origin: "B"
  }
)

verb(
  "nisshi",
  "upcast",
  {
    kind: :pure,
    shape: "upcast(record, version) -> record",
    laterals: ["migrate", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "raise an old record to the current event shape",
    wave: 3,
    origin: "B"
  }
)

verb(
  "nisshi",
  "verify",
  {
    kind: :pure,
    shape: "verify(log) -> report",
    laterals: ["error", "validate"],
    fleet: nil,
    today: "exists:nisshi",
    wave: 0,
    origin: "D"
  }
)

verb(
  "nisshi",
  "verify?",
  {
    kind: :effect,
    shape: "verify?(log) -> Bool",
    laterals: ["error", "serialize", "validate"],
    fleet: nil,
    today: "partial:nisshi",
    meaning: "whether every hash link and signature holds",
    wave: 0,
    origin: "B"
  }
)

verb(
  "nisshi",
  "watch",
  {
    kind: :stream,
    shape: "watch(log, f, opts) -> nil",
    laterals: ["cancel", "deadline", "resource", "time"],
    fleet: nil,
    today: "absent",
    meaning: "call f per new record as it lands until f says stop",
    wave: 1,
    origin: "B"
  }
)

verb(
  "nisshi",
  "witness",
  {
    kind: :effect,
    shape: "witness(log, ledger) -> receipt",
    laterals: ["idempotent", "resource"],
    fleet: "cartorio",
    today: "absent",
    meaning: "publish the head to an outside ledger",
    wave: 3,
    origin: "D"
  }
)

edge("nisshi::append", :composes, "fairu::append", "JSON Lines backing file")
edge("nisshi::rotate", :composes, "fairu::move", "closed segment moves aside")
edge("nisshi::snapshot", :composes, "fairu::write", "persists the state")

edge(
  "nisshi::forget",
  :composes,
  "himitsu::delete",
  "per-subject key destroyed"
)

edge(
  "nisshi::publish",
  :composes,
  "messeeji?::publish",
  "each event goes to the bus"
)

edge(
  "nisshi::audit",
  :composes,
  "nisshi::append",
  "a record of fixed audit shape"
)

edge("nisshi::append", :composes, "nisshi::canon", "canonical body text")
edge("nisshi::entry", :composes, "nisshi::canon", "body text of the record")

edge(
  "nisshi::fold",
  :composes,
  "nisshi::checkpoint",
  "resumes where it stopped"
)

edge(
  "nisshi::subscribe",
  :composes,
  "nisshi::checkpoint",
  "moves the offset forward"
)

edge(
  "nisshi::witness",
  :composes,
  "nisshi::checkpoint",
  "publish the signed head"
)

edge("nisshi::verify?", :composes, "nisshi::first_break", "true when no break")
edge("nisshi::open", :composes, "nisshi::genesis", "label fixes the first hash")
edge("nisshi::lag", :composes, "nisshi::head", "head position")
edge("nisshi::lag", :composes, "nisshi::offset", "consumer position")
edge("nisshi::export", :composes, "nisshi::read", "bundle is the records read")
edge("nisshi::interleave", :composes, "nisshi::read", "inputs are record lists")
edge("nisshi::query", :composes, "nisshi::read", "SQL over read records")
edge("nisshi::replay", :composes, "nisshi::read", "fold records into states")
edge("nisshi::subscribe", :composes, "nisshi::stream", "delivers records")
edge("nisshi::publish", :composes, "nisshi::watch", "driven by the appends")

edge(
  "nisshi::replay",
  :composes,
  "raifusaikuru::replay",
  "folds them into a state"
)

edge("nisshi::append", :composes, "shomei::chain", "chain the new record")

edge(
  "nisshi::first_break",
  :composes,
  "shomei::first_break",
  "chain check per payload"
)

edge("nisshi::verify", :composes, "shomei::first_break", "find the first break")
edge("nisshi::genesis", :composes, "shomei::genesis", "label to first hash")
edge("nisshi::seal", :composes, "shomei::hash", "hash of the frozen segment")
edge("nisshi::head", :composes, "shomei::head", "chain head of the log")

edge(
  "nisshi::prove",
  :composes,
  "shomei::prove",
  "inclusion proof for a record"
)

edge("nisshi::checkpoint", :composes, "shomei::sign", "sign the head")
edge("nisshi::capture", :composes, "teeburu::listen", "database change notices")
edge("nisshi::append", :guards, "kengen?::permit", "writers are authorised")
edge("nisshi::audit", :guards, "kengen?::permit", "every decision is recorded")
edge("nisshi::seal", :guards, "nisshi::append", "sealed segments refuse writes")

edge(
  "nisshi::upcast",
  :guards,
  "nisshi::replay",
  "old shapes raised before folding"
)

edge("nisshi::verify", :guards, "nisshi::replay", "replay only a valid chain")

edge(
  "nisshi::verify?",
  :guards,
  "nisshi::replay",
  "replay only a chain that verifies"
)

edge(
  "nisshi::snapshot",
  :guards,
  "nisshi::truncate",
  "keep state before dropping records"
)

edge("nisshi::read", :inverse, "nisshi::append", "returns what append wrote")
edge("nisshi::open", :inverse, "nisshi::close", "releases the log")

edge(
  "nisshi::replay",
  :inverse,
  "nisshi::compact",
  "checkpoint replaces records"
)

edge("nisshi::close", :inverse, "nisshi::open", "releases the log")
edge("nisshi::append", :inverse, "nisshi::read", "returns what append wrote")

edge(
  "nisshi::compact",
  :inverse,
  "nisshi::replay",
  "checkpoint replaces records"
)

edge("nisshi::append_all", :lifts, "nisshi::append", "many events as one unit")

edge(
  "nisshi::capture",
  :lifts,
  "nisshi::append",
  "each change becomes an event"
)

edge("nisshi::read", :lifts, "nisshi::append", "all appended events")
edge("nisshi::watch", :lifts, "nisshi::append", "appends as events")
edge("nisshi::watch", :lifts, "nisshi::get", "each new record")
edge("nisshi::stream", :lifts, "nisshi::read", "per-record form")
edge("nisshi::watch", :lifts, "nisshi::read", "follows appended records")

edge(
  "nisshi::fold",
  :lifts,
  "nisshi::replay",
  "incremental form with a checkpoint"
)

edge(
  "nisshi::append",
  :pairs,
  "keiyaku?::checksum",
  "hash chain beside frame checks"
)

edge("nisshi::read", :pairs, "nisshi::append", "read back what was added")
edge("nisshi::watch", :pairs, "nisshi::append", "appenders feed watchers")
edge("nisshi::replay", :pairs, "nisshi::at", "whole fold and one point")
edge("nisshi::open", :pairs, "nisshi::close", "handle and its release")
edge("nisshi::truncate", :pairs, "nisshi::compact", "two ways to bound size")
edge("nisshi::interleave", :pairs, "nisshi::diff", "combine or compare logs")
edge("nisshi::canon", :pairs, "nisshi::genesis", "both fix the byte form")
edge("nisshi::get", :pairs, "nisshi::head", "any record beside the newest")

edge(
  "nisshi::checkpoint",
  :pairs,
  "nisshi::offset",
  "write and read of progress"
)

edge("nisshi::append", :pairs, "nisshi::read", "written then read")

edge(
  "nisshi::snapshot",
  :pairs,
  "nisshi::replay",
  "replay starts from the snapshot"
)

edge(
  "nisshi::rotate",
  :pairs,
  "nisshi::seal",
  "new segment after the old is frozen"
)

edge("nisshi::verify?", :pairs, "nisshi::seal", "proof of a frozen segment")
edge("nisshi::fold", :pairs, "nisshi::snapshot", "view and its starting state")
edge("nisshi::publish", :pairs, "nisshi::subscribe", "sender and receiver")
edge("nisshi::append", :pairs, "nisshi::verify?", "write and prove")

edge(
  "nisshi::export",
  :pairs,
  "nisshi::verify?",
  "a bundle is sealed and checked"
)

edge(
  "nisshi::forget",
  :pairs,
  "nisshi::verify?",
  "the chain still holds afterwards"
)

edge("nisshi::open", :pairs, "nisshi::verify?", "open, then verify the chain")
edge("nisshi::watch", :pairs, "puran?::checkin", "progress events follow")

edge(
  "nisshi::append",
  :pairs,
  "rogu::error",
  "audit lines keep the error record"
)

edge("nisshi::read", :pairs, "rogu::read", "audit versus operator lines")

edge(
  "nisshi::diff",
  :refines,
  "nisshi::first_break",
  "first disagreement of two logs"
)

edge("nisshi::head", :refines, "nisshi::get", "the newest record")
edge("nisshi::correlate", :refines, "nisshi::read", "filtered by link id")
edge("nisshi::get", :refines, "nisshi::read", "one record by sequence")
edge("nisshi::history", :refines, "nisshi::read", "records of one entity")
edge("nisshi::at", :refines, "nisshi::replay", "replay up to a record")

edge(
  "nisshi::state_at",
  :refines,
  "nisshi::replay",
  "replay stopped at an instant"
)

edge("nisshi::watch", :refines, "nisshi::stream", "keeps going after the end")
edge("nisshi::compact", :refines, "nisshi::truncate", "drops by key not by age")
edge("nisshi::intact?", :refines, "nisshi::verify", "true when no break")
edge("nisshi::subscribe", :refines, "nisshi::watch", "durable and resumable")

edge(
  "nisshi::open",
  :requires,
  "nisshi::append",
  "a log must be open to append"
)

edge(
  "nisshi::roll",
  :requires,
  "nisshi::checkpoint",
  "seal a segment before rolling"
)

edge(
  "nisshi::append",
  :requires,
  "nisshi::head",
  "expected sequence for conflict check"
)

edge("nisshi::checkpoint", :requires, "nisshi::head", "signs the current head")
edge("nisshi::state_at", :requires, "nisshi::read", "reads the prefix")

edge(
  "nisshi::append",
  :requires,
  "nisshi::verify?",
  "append to an intact chain"
)

edge(
  "nisshi::compact",
  :requires,
  "nisshi::verify?",
  "only compact an intact chain"
)
