space("jikan", {status: :ratified})

verb(
  "jikan",
  "add",
  {
    kind: :pure,
    shape: "add(instant, duration) -> instant",
    laterals: ["time"],
    fleet: nil,
    today: "partial:hizuke",
    meaning: "instant moved by a duration; negative goes back",
    wave: 1,
    origin: "A"
  }
)

verb(
  "jikan",
  "after?",
  {
    kind: :pure,
    shape: "after?(a, b) -> Bool",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "whether a is later than b",
    wave: 1,
    origin: "A"
  }
)

verb(
  "jikan",
  "before?",
  {
    kind: :pure,
    shape: "before?(a, b) -> Bool",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "whether a is earlier than b",
    wave: 1,
    origin: "A"
  }
)

verb(
  "jikan",
  "between",
  {
    kind: :pure,
    shape: "between(a, b) -> duration",
    laterals: ["time"],
    fleet: nil,
    today: "partial:hizuke",
    meaning: "duration from a to b",
    wave: 1,
    origin: "A"
  }
)

verb(
  "jikan",
  "compare",
  {
    kind: :pure,
    shape: "compare(a, b) -> int",
    laterals: ["time"],
    fleet: nil,
    today: "partial:hizuke",
    meaning: "order two instants as -1, 0 or 1",
    wave: 1,
    origin: "A"
  }
)

verb(
  "jikan",
  "day",
  {
    kind: :pure,
    shape: "day(instant) -> int",
    laterals: ["time"],
    fleet: nil,
    today: "partial:hizuke",
    meaning: "day of the month",
    wave: 1,
    origin: "A"
  }
)

verb(
  "jikan",
  "days",
  {
    kind: :pure,
    shape: "days(n) -> duration",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "duration of n days of 24 hours",
    wave: 1,
    origin: "A"
  }
)

verb(
  "jikan",
  "due?",
  {
    kind: :pure,
    shape: "due?(schedule, last, now) -> Bool",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "whether an occurrence fell between last and now",
    wave: 2,
    origin: "A"
  }
)

verb(
  "jikan",
  "end_of",
  {
    kind: :pure,
    shape: "end_of(instant, unit) -> instant",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "last moment of the day, week, month or year",
    wave: 2,
    origin: "A"
  }
)

verb(
  "jikan",
  "hour",
  {
    kind: :pure,
    shape: "hour(instant) -> int",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "hour of the day in the instant's zone",
    wave: 1,
    origin: "A"
  }
)

verb(
  "jikan",
  "hours",
  {
    kind: :pure,
    shape: "hours(n) -> duration",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "duration of n hours",
    wave: 1,
    origin: "A"
  }
)

verb(
  "jikan",
  "in_zone",
  {
    kind: :pure,
    shape: "in_zone(instant, name) -> instant",
    laterals: ["error", "time"],
    fleet: nil,
    today: "absent",
    meaning: "same moment shown in another zone",
    wave: 2,
    origin: "A"
  }
)

verb(
  "jikan",
  "instant",
  {
    kind: :pure,
    shape: "instant(unix_seconds, opts) -> instant",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "build an instant from unix seconds",
    wave: 1,
    origin: "A"
  }
)

verb(
  "jikan",
  "measure",
  {
    kind: :effect,
    shape: "measure(f) -> record",
    laterals: ["log", "time", "trace"],
    fleet: nil,
    today: "absent",
    meaning: "run f; return its value and how long it took",
    wave: 1,
    origin: "A"
  }
)

verb(
  "jikan",
  "milliseconds",
  {
    kind: :pure,
    shape: "milliseconds(n) -> duration",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "duration of n milliseconds",
    wave: 1,
    origin: "A"
  }
)

verb(
  "jikan",
  "minute",
  {
    kind: :pure,
    shape: "minute(instant) -> int",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "minute of the hour",
    wave: 1,
    origin: "A"
  }
)

verb(
  "jikan",
  "minutes",
  {
    kind: :pure,
    shape: "minutes(n) -> duration",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "duration of n minutes",
    wave: 1,
    origin: "A"
  }
)

verb(
  "jikan",
  "month",
  {
    kind: :pure,
    shape: "month(instant) -> int",
    laterals: ["time"],
    fleet: nil,
    today: "partial:hizuke",
    meaning: "calendar month, 1 to 12",
    wave: 1,
    origin: "A"
  }
)

verb(
  "jikan",
  "months",
  {
    kind: :pure,
    shape: "months(n) -> span",
    laterals: ["time"],
    fleet: nil,
    today: "partial:hizuke",
    meaning: "calendar span; add respects month lengths",
    wave: 1,
    origin: "A"
  }
)

verb(
  "jikan",
  "next",
  {
    kind: :pure,
    shape: "next(schedule, after) -> instant or nil",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "first occurrence strictly after an instant",
    wave: 2,
    origin: "A"
  }
)

verb(
  "jikan",
  "now",
  {
    kind: :effect,
    shape: "now() -> instant",
    laterals: ["capability", "time"],
    fleet: "tatara-lisp-script",
    today: "rust:blue-lang-runtime",
    meaning: "the current instant",
    wave: 0,
    origin: "A"
  }
)

verb(
  "jikan",
  "occurrences",
  {
    kind: :pure,
    shape: "occurrences(schedule, range) -> [instant]",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "every occurrence inside a range, sorted",
    wave: 2,
    origin: "A"
  }
)

verb(
  "jikan",
  "offset",
  {
    kind: :pure,
    shape: "offset(name, instant) -> seconds",
    laterals: ["error", "time"],
    fleet: nil,
    today: "absent",
    meaning: "zone offset from UTC at that moment",
    wave: 2,
    origin: "A"
  }
)

verb(
  "jikan",
  "parse",
  {
    kind: :pure,
    shape: "parse(text, format, opts) -> instant",
    laterals: ["error", "time"],
    fleet: nil,
    today: "absent",
    meaning: "text to instant: rfc3339, date, human, pattern",
    wave: 1,
    origin: "A"
  }
)

verb(
  "jikan",
  "render",
  {
    kind: :pure,
    shape: "render(value, format, opts) -> text",
    laterals: ["serialize", "time"],
    fleet: nil,
    today: "partial:hizuke",
    meaning: "instant or duration to text",
    wave: 1,
    origin: "A"
  }
)

verb(
  "jikan",
  "round",
  {
    kind: :pure,
    shape: "round(instant, unit) -> instant",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "nearest whole minute, hour or day",
    wave: 2,
    origin: "A"
  }
)

verb(
  "jikan",
  "scale",
  {
    kind: :pure,
    shape: "scale(duration, factor) -> duration",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "duration multiplied by a number",
    wave: 1,
    origin: "A"
  }
)

verb(
  "jikan",
  "schedule",
  {
    kind: :decl,
    shape: "schedule(spec) -> schedule",
    laterals: ["time", "validate"],
    fleet: "lava-cron",
    today: "absent",
    meaning: "declare a cron, RRULE or every-duration schedule",
    wave: 2,
    origin: "A"
  }
)

verb(
  "jikan",
  "second",
  {
    kind: :pure,
    shape: "second(instant) -> int",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "second of the minute",
    wave: 1,
    origin: "A"
  }
)

verb(
  "jikan",
  "seconds",
  {
    kind: :pure,
    shape: "seconds(n) -> duration",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "duration of n seconds",
    wave: 1,
    origin: "A"
  }
)

verb(
  "jikan",
  "since",
  {
    kind: :effect,
    shape: "since(instant) -> duration",
    laterals: ["capability", "time"],
    fleet: "tatara-lisp-script",
    today: "rust:blue-lang-runtime",
    meaning: "duration from an instant to now",
    wave: 0,
    origin: "A"
  }
)

verb(
  "jikan",
  "sleep",
  {
    kind: :effect,
    shape: "sleep(duration) -> nil",
    laterals: ["cancel", "deadline", "time"],
    fleet: "tatara-lisp-script",
    today: "rust:blue-lang-runtime",
    meaning: "pause for a duration",
    wave: 0,
    origin: "A"
  }
)

verb(
  "jikan",
  "start_of",
  {
    kind: :pure,
    shape: "start_of(instant, unit) -> instant",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "first moment of the day, week, month or year",
    wave: 2,
    origin: "A"
  }
)

verb(
  "jikan",
  "today",
  {
    kind: :effect,
    shape: "today(opts) -> date",
    laterals: ["capability", "time"],
    fleet: nil,
    today: "absent",
    meaning: "the current calendar date in a zone",
    wave: 1,
    origin: "A"
  }
)

verb(
  "jikan",
  "total",
  {
    kind: :pure,
    shape: "total(duration, unit) -> number",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "duration expressed in one unit",
    wave: 1,
    origin: "A"
  }
)

verb(
  "jikan",
  "unix_seconds",
  {
    kind: :pure,
    shape: "unix_seconds(instant) -> int",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "seconds since the unix epoch",
    wave: 1,
    origin: "A"
  }
)

verb(
  "jikan",
  "until",
  {
    kind: :effect,
    shape: "until(instant) -> duration",
    laterals: ["capability", "time"],
    fleet: nil,
    today: "absent",
    meaning: "duration from now to an instant",
    wave: 1,
    origin: "A"
  }
)

verb(
  "jikan",
  "weekday",
  {
    kind: :pure,
    shape: "weekday(instant) -> symbol",
    laterals: ["time"],
    fleet: nil,
    today: "partial:hizuke",
    meaning: "day of the week as a name",
    wave: 1,
    origin: "A"
  }
)

verb(
  "jikan",
  "weeks",
  {
    kind: :pure,
    shape: "weeks(n) -> duration",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "duration of n weeks of 7 days",
    wave: 1,
    origin: "A"
  }
)

verb(
  "jikan",
  "year",
  {
    kind: :pure,
    shape: "year(instant) -> int",
    laterals: ["time"],
    fleet: nil,
    today: "partial:hizuke",
    meaning: "calendar year of an instant",
    wave: 1,
    origin: "A"
  }
)

verb(
  "jikan",
  "years",
  {
    kind: :pure,
    shape: "years(n) -> span",
    laterals: ["time"],
    fleet: nil,
    today: "partial:hizuke",
    meaning: "calendar span; add respects leap years",
    wave: 1,
    origin: "A"
  }
)

verb(
  "jikan",
  "zone",
  {
    kind: :pure,
    shape: "zone(instant) -> name",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "name of the zone an instant is shown in",
    wave: 2,
    origin: "A"
  }
)

verb(
  "jikan",
  "zones",
  {
    kind: :pure,
    shape: "zones() -> [name]",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "every zone name the tz database knows",
    wave: 3,
    origin: "A"
  }
)

edge("jikan::day", :composes, "hizuke::day_of", "calendar field of an instant")

edge(
  "jikan::add",
  :composes,
  "hizuke::days_in",
  "calendar part honors month length"
)

edge(
  "jikan::month",
  :composes,
  "hizuke::month_of",
  "calendar field of an instant"
)

edge("jikan::weekday", :composes, "hizuke::weekday_of", "weekday of the date")

edge(
  "jikan::year",
  :composes,
  "hizuke::year_of",
  "calendar field of an instant"
)

edge("jikan::round", :composes, "jikan::between", "distance to each boundary")
edge("jikan::since", :composes, "jikan::between", "between(instant, now)")
edge("jikan::until", :composes, "jikan::between", "between(now, instant)")
edge("jikan::after?", :composes, "jikan::compare", "compare is 1")
edge("jikan::before?", :composes, "jikan::compare", "compare is -1")
edge("jikan::weeks", :composes, "jikan::days", "7 days each")
edge("jikan::days", :composes, "jikan::hours", "24 hours each")
edge("jikan::today", :composes, "jikan::in_zone", "date in the chosen zone")

edge(
  "jikan::seconds",
  :composes,
  "jikan::milliseconds",
  "1000 milliseconds each"
)

edge("jikan::hours", :composes, "jikan::minutes", "60 minutes each")
edge("jikan::due?", :composes, "jikan::next", "next occurrence not after now")

edge(
  "jikan::occurrences",
  :composes,
  "jikan::next",
  "repeat next across the range"
)

edge("jikan::measure", :composes, "jikan::now", "take the start")
edge("jikan::since", :composes, "jikan::now", "now minus an instant")
edge("jikan::today", :composes, "jikan::now", "the date part of now")
edge("jikan::until", :composes, "jikan::now", "an instant minus now")
edge("jikan::in_zone", :composes, "jikan::offset", "shift by the zone offset")

edge(
  "jikan::schedule",
  :composes,
  "jikan::parse",
  "cron text and RRULE text parse"
)

edge("jikan::minutes", :composes, "jikan::seconds", "60 seconds each")
edge("jikan::measure", :composes, "jikan::since", "time the call")

edge(
  "jikan::end_of",
  :composes,
  "jikan::start_of",
  "start of the next unit minus one"
)

edge(
  "jikan::round",
  :composes,
  "jikan::start_of",
  "floor or step to the next unit"
)

edge("jikan::scale", :composes, "jikan::total", "multiply the total")
edge("jikan::minute", :composes, "jikan::unix_seconds", "seconds modulo 3600")
edge("jikan::second", :composes, "jikan::unix_seconds", "seconds modulo 60")
edge("jikan::parse", :composes, "moji::find", "match the fixed layouts")
edge("jikan::render", :composes, "moji::pad", "zero-padded fields")
edge("jikan::compare", :generalizes, "jikan::before?", "three-way order")
edge("jikan::zones", :guards, "jikan::offset", "lists the valid names")
edge("jikan::between", :inverse, "jikan::add", "add(a, between(a, b)) is b")
edge("jikan::add", :inverse, "jikan::between", "add(a, between(a, b)) is b")

edge(
  "jikan::unix_seconds",
  :inverse,
  "jikan::instant",
  "numbers and instants round-trip"
)

edge("jikan::total", :inverse, "jikan::milliseconds", "build versus read back")
edge("jikan::render", :inverse, "jikan::parse", "text and instant round-trip")
edge("jikan::parse", :inverse, "jikan::render", "text and instant round-trip")
edge("jikan::milliseconds", :inverse, "jikan::total", "build versus read back")

edge(
  "jikan::instant",
  :inverse,
  "jikan::unix_seconds",
  "numbers and instants round-trip"
)

edge("jikan::occurrences", :lifts, "jikan::next", "batch form of next")
edge("jikan::sleep", :pairs, "heikou::retry", "backoff waits")
edge("jikan::unix_seconds", :pairs, "jikan::between", "numbers for subtraction")
edge("jikan::month", :pairs, "jikan::day", "calendar fields")
edge("jikan::start_of", :pairs, "jikan::end_of", "the two edges of a unit")
edge("jikan::zone", :pairs, "jikan::in_zone", "read and change the zone")
edge("jikan::hour", :pairs, "jikan::minute", "clock fields")
edge("jikan::year", :pairs, "jikan::month", "calendar fields")
edge("jikan::days", :pairs, "jikan::months", "fixed versus calendar span")
edge("jikan::minute", :pairs, "jikan::second", "clock fields")
edge("jikan::now", :pairs, "jikan::since", "one reads the clock for the other")
edge("jikan::milliseconds", :pairs, "jikan::sleep", "smallest sleep unit")
edge("jikan::now", :pairs, "jikan::today", "instant and date")
edge("jikan::since", :pairs, "jikan::until", "past versus future")
edge("jikan::measure", :pairs, "rogu::info", "report how long it took")
edge("jikan::total", :pairs, "tanni?::convert", "duration in another unit")

edge(
  "jikan::seconds",
  :refines,
  "tanni?::quantity",
  "a duration is a time quantity"
)

edge("jikan::scale", :refines, "tanni?::scale", "same operation on durations")
edge("jikan::months", :requires, "hizuke::days_in", "month lengths vary")
edge("jikan::years", :requires, "hizuke::leap?", "year lengths vary")
edge("jikan::next", :requires, "jikan::schedule", "needs a declared schedule")
edge("jikan::add", :requires, "jikan::seconds", "a duration to add")
edge("jikan::sleep", :requires, "jikan::seconds", "takes a duration")
edge("jikan::day", :requires, "jikan::zone", "field depends on the zone")
edge("jikan::hour", :requires, "jikan::zone", "field depends on the zone")
edge("jikan::month", :requires, "jikan::zone", "field depends on the zone")
edge("jikan::next", :requires, "jikan::zone", "local-time rules")
edge("jikan::render", :requires, "jikan::zone", "text depends on the zone")

edge(
  "jikan::start_of",
  :requires,
  "jikan::zone",
  "day boundaries depend on the zone"
)

edge("jikan::year", :requires, "jikan::zone", "field depends on the zone")

edge(
  "jikan::offset",
  :requires,
  "jikan::zones",
  "name must be in the tz database"
)
