space("shougai?", {status: :provisional})

verb(
  "shougai?",
  "acknowledge",
  {
    kind: :effect,
    shape: "acknowledge(alert, who) -> nil",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "say that a person has taken an alert",
    wave: 2,
    origin: "F"
  }
)

verb(
  "shougai?",
  "announce",
  {
    kind: :effect,
    shape: "announce(audience, message) -> nil",
    laterals: ["log"],
    fleet: nil,
    today: "absent",
    meaning: "publish a status message to an audience",
    wave: 3,
    origin: "F"
  }
)

verb(
  "shougai?",
  "assign",
  {
    kind: :effect,
    shape: "assign(incident, who) -> nil",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "name the person who leads an incident",
    wave: 2,
    origin: "F"
  }
)

verb(
  "shougai?",
  "classify",
  {
    kind: :pure,
    shape: "classify(impact) -> severity",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "map impact to a severity level by a stated rule",
    wave: 3,
    origin: "F"
  }
)

verb(
  "shougai?",
  "declare",
  {
    kind: :effect,
    shape: "declare(summary, opts) -> incident",
    laterals: ["idempotent", "log"],
    fleet: nil,
    today: "absent",
    meaning: "open an incident with a severity and a timeline",
    wave: 2,
    origin: "F"
  }
)

verb(
  "shougai?",
  "drill",
  {
    kind: :effect,
    shape: "drill(scenario, opts) -> report",
    laterals: ["test", "time"],
    fleet: nil,
    today: "absent",
    meaning: "rehearse an incident and measure the response",
    wave: 3,
    origin: "F"
  }
)

verb(
  "shougai?",
  "escalate",
  {
    kind: :effect,
    shape: "escalate(incident, level) -> nil",
    laterals: ["deadline"],
    fleet: nil,
    today: "absent",
    meaning: "move an incident to the next level or person",
    wave: 2,
    origin: "F"
  }
)

verb(
  "shougai?",
  "get",
  {
    kind: :effect,
    shape: "get(source, id) -> record or nil",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "one alert or incident or nil",
    wave: 2,
    origin: "F"
  }
)

verb(
  "shougai?",
  "list",
  {
    kind: :effect,
    shape: "list(source, kind, opts) -> [record]",
    laterals: ["deadline"],
    fleet: nil,
    today: "absent",
    meaning: "alerts, incidents or silences, all pages",
    wave: 2,
    origin: "F",
    contract: "list(source, opts) -> [record]"
  }
)

verb(
  "shougai?",
  "mitigate",
  {
    kind: :effect,
    shape: "mitigate(incident, action) -> nil",
    laterals: ["log"],
    fleet: nil,
    today: "absent",
    meaning: "record and run a step that limits the harm",
    wave: 2,
    origin: "F"
  }
)

verb(
  "shougai?",
  "note",
  {
    kind: :effect,
    shape: "note(incident, text) -> nil",
    laterals: ["log"],
    fleet: nil,
    today: "absent",
    meaning: "add a timestamped entry to the incident timeline",
    wave: 2,
    origin: "F"
  }
)

verb(
  "shougai?",
  "oncall",
  {
    kind: :effect,
    shape: "oncall(schedule, opts) -> [person]",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "who is on call now or at an instant",
    wave: 2,
    origin: "F"
  }
)

verb(
  "shougai?",
  "page",
  {
    kind: :effect,
    shape: "page(target, alert, opts) -> ack",
    laterals: ["deadline", "retry"],
    fleet: "pangea-pagerduty",
    today: "absent",
    meaning: "notify an on-call person or team",
    wave: 2,
    origin: "F"
  }
)

verb(
  "shougai?",
  "postmortem",
  {
    kind: :pure,
    shape: "postmortem(incident, opts) -> doc",
    laterals: ["serialize"],
    fleet: nil,
    today: "absent",
    meaning: "draft a blameless review from the timeline",
    wave: 3,
    origin: "F"
  }
)

verb(
  "shougai?",
  "resolve",
  {
    kind: :effect,
    shape: "resolve(incident, opts) -> nil",
    laterals: ["idempotent"],
    fleet: nil,
    today: "absent",
    meaning: "close an incident with a cause and a time",
    wave: 2,
    origin: "F"
  }
)

verb(
  "shougai?",
  "route",
  {
    kind: :pure,
    shape: "route(alert, rules) -> [target]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "decide whom an alert goes to",
    wave: 2,
    origin: "F"
  }
)

verb(
  "shougai?",
  "silence",
  {
    kind: :effect,
    shape: "silence(matcher, opts) -> silence",
    laterals: ["switch", "time"],
    fleet: nil,
    today: "absent",
    meaning: "mute matching alerts for a period",
    wave: 2,
    origin: "F"
  }
)

verb(
  "shougai?",
  "timeline",
  {
    kind: :pure,
    shape: "timeline(incident) -> [event]",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "the ordered events of an incident",
    wave: 2,
    origin: "F"
  }
)

edge(
  "shougai?::declare",
  :composes,
  "nisshi::append",
  "timeline is an event log"
)

edge("shougai?::note", :composes, "nisshi::append", "one timeline entry")
edge("shougai?::timeline", :composes, "nisshi::read", "ordered events")
edge("shougai?::drill", :composes, "shougai?::declare", "a rehearsed incident")
edge("shougai?::mitigate", :composes, "shougai?::note", "every action is noted")

edge(
  "shougai?::postmortem",
  :composes,
  "shougai?::timeline",
  "draft from the timeline"
)

edge(
  "shougai?::escalate",
  :guards,
  "shougai?::acknowledge",
  "fires when none arrives"
)

edge(
  "shougai?::classify",
  :guards,
  "shougai?::declare",
  "severity at declaration"
)

edge("shougai?::route", :guards, "shougai?::page", "chooses the target")
edge("shougai?::silence", :guards, "shougai?::page", "muted alerts do not page")

edge(
  "shougai?::resolve",
  :inverse,
  "shougai?::declare",
  "closes what declare opened"
)

edge(
  "shougai?::declare",
  :inverse,
  "shougai?::resolve",
  "closes what declare opened"
)

edge("shougai?::silence", :inverse, "shougai?::route", "mute versus deliver")
edge("shougai?::route", :inverse, "shougai?::silence", "mute versus deliver")
edge("shougai?::drill", :pairs, "chishiki?::run", "drills run runbooks")

edge(
  "shougai?::drill",
  :pairs,
  "fuka?::experiment",
  "drills use injected faults"
)

edge(
  "shougai?::postmortem",
  :pairs,
  "kadai?::create",
  "action items become issues"
)

edge(
  "shougai?::mitigate",
  :pairs,
  "rirezu?::rollback",
  "rollback is a mitigation"
)

edge("shougai?::classify", :pairs, "shihyou::burn", "burn suggests severity")

edge(
  "shougai?::declare",
  :pairs,
  "shougai?::classify",
  "severity is chosen at declaration"
)

edge(
  "shougai?::acknowledge",
  :pairs,
  "shougai?::escalate",
  "ack stops the escalation"
)

edge(
  "shougai?::announce",
  :pairs,
  "shougai?::note",
  "public and internal entries"
)

edge(
  "shougai?::declare",
  :pairs,
  "shougai?::page",
  "declared incidents page someone"
)

edge(
  "shougai?::resolve",
  :pairs,
  "shougai?::postmortem",
  "resolved incidents get a review"
)

edge("shougai?::oncall", :pairs, "shougai?::route", "schedule feeds routing")
edge("shougai?::get", :pairs, "shougai?::timeline", "record and its events")
edge("shougai?::timeline", :pairs, "tsuiseki?::correlate", "events plus traces")

edge(
  "shougai?::assign",
  :refines,
  "kadai?::assign",
  "same meaning for incidents"
)

edge("shougai?::get", :refines, "shougai?::list", "one record, or nil")
edge("shougai?::list", :requires, "shihyou::alerts", "alerts come from rules")

edge(
  "shougai?::announce",
  :requires,
  "shougai?::declare",
  "status for a declared incident"
)

edge("shougai?::oncall", :requires, "shougai?::list", "reads the schedule")

edge(
  "shougai?::resolve",
  :requires,
  "shougai?::mitigate",
  "closing follows mitigation"
)

edge("shougai?::escalate", :requires, "shougai?::oncall", "next person")
edge("shougai?::page", :requires, "shougai?::oncall", "who to page")
edge("shougai?::acknowledge", :requires, "shougai?::page", "answers a page")
edge("shougai?::page", :requires, "shougai?::route", "where the alert goes")
