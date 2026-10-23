space("hizuke", {status: :ratified})

verb(
  "hizuke",
  "add_business_days",
  {
    kind: :pure,
    shape: "add_business_days(date, n, calendar) -> date",
    laterals: [],
    fleet: nil,
    today: "partial:hizuke",
    meaning: "date moved by n working days",
    wave: 1,
    origin: "A"
  }
)

verb(
  "hizuke",
  "business_day?",
  {
    kind: :pure,
    shape: "business_day?(date, calendar) -> Bool",
    laterals: [],
    fleet: nil,
    today: "partial:hizuke",
    meaning: "whether work happens on the date",
    wave: 0,
    origin: "A"
  }
)

verb(
  "hizuke",
  "business_days_between",
  {
    kind: :pure,
    shape: "business_days_between(a, b, calendar) -> int",
    laterals: [],
    fleet: nil,
    today: "exists:hizuke",
    meaning: "working days from a to b",
    wave: 0,
    origin: "A"
  }
)

verb(
  "hizuke",
  "day_of",
  {
    kind: :pure,
    shape: "day_of(date) -> int",
    laterals: [],
    fleet: nil,
    today: "exists:hizuke",
    meaning: "day of the month of a date",
    wave: 0,
    origin: "A"
  }
)

verb(
  "hizuke",
  "days_in",
  {
    kind: :pure,
    shape: "days_in(year, month) -> int",
    laterals: [],
    fleet: nil,
    today: "exists:hizuke",
    meaning: "days in a month",
    wave: 0,
    origin: "A"
  }
)

verb(
  "hizuke",
  "easter",
  {
    kind: :pure,
    shape: "easter(year) -> date",
    laterals: [],
    fleet: nil,
    today: "exists:hizuke",
    meaning: "date of Western Easter",
    wave: 0,
    origin: "A"
  }
)

verb(
  "hizuke",
  "fiscal_year",
  {
    kind: :pure,
    shape: "fiscal_year(date, start_month) -> int",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "fiscal year a date belongs to",
    wave: 2,
    origin: "A"
  }
)

verb(
  "hizuke",
  "holiday?",
  {
    kind: :pure,
    shape: "holiday?(date, calendar) -> Bool",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "whether the date is a public holiday",
    wave: 3,
    origin: "A"
  }
)

verb(
  "hizuke",
  "holidays",
  {
    kind: :pure,
    shape: "holidays(calendar, year) -> [date]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "public holidays of a calendar for a year",
    wave: 3,
    origin: "A"
  }
)

verb(
  "hizuke",
  "iso_week",
  {
    kind: :pure,
    shape: "iso_week(date) -> record",
    laterals: [],
    fleet: nil,
    today: "exists:hizuke",
    meaning: "ISO week number and week year",
    wave: 0,
    origin: "A"
  }
)

verb(
  "hizuke",
  "leap?",
  {
    kind: :pure,
    shape: "leap?(year) -> Bool",
    laterals: [],
    fleet: nil,
    today: "exists:hizuke",
    meaning: "whether the year has 366 days",
    wave: 0,
    origin: "A"
  }
)

verb(
  "hizuke",
  "month_of",
  {
    kind: :pure,
    shape: "month_of(date) -> int",
    laterals: [],
    fleet: nil,
    today: "exists:hizuke",
    meaning: "calendar month of a date",
    wave: 0,
    origin: "A"
  }
)

verb(
  "hizuke",
  "nth_weekday",
  {
    kind: :pure,
    shape: "nth_weekday(year, month, weekday, n) -> date",
    laterals: [],
    fleet: nil,
    today: "exists:hizuke",
    meaning: "the n-th given weekday of a month",
    wave: 0,
    origin: "A"
  }
)

verb(
  "hizuke",
  "quarter",
  {
    kind: :pure,
    shape: "quarter(date) -> int",
    laterals: [],
    fleet: nil,
    today: "exists:hizuke",
    meaning: "calendar quarter, 1 to 4",
    wave: 0,
    origin: "A"
  }
)

verb(
  "hizuke",
  "weekday_of",
  {
    kind: :pure,
    shape: "weekday_of(date) -> symbol",
    laterals: [],
    fleet: nil,
    today: "partial:hizuke",
    meaning: "day of the week of a date",
    wave: 0,
    origin: "A"
  }
)

verb(
  "hizuke",
  "weekend?",
  {
    kind: :pure,
    shape: "weekend?(date) -> Bool",
    laterals: [],
    fleet: nil,
    today: "partial:hizuke",
    meaning: "whether the date is Saturday or Sunday",
    wave: 0,
    origin: "A"
  }
)

verb(
  "hizuke",
  "year_of",
  {
    kind: :pure,
    shape: "year_of(date) -> int",
    laterals: [],
    fleet: nil,
    today: "exists:hizuke",
    meaning: "calendar year of a date",
    wave: 0,
    origin: "A"
  }
)

edge(
  "hizuke::add_business_days",
  :composes,
  "hizuke::business_day?",
  "skip non-working days"
)

edge(
  "hizuke::business_days_between",
  :composes,
  "hizuke::business_day?",
  "count working days"
)

edge(
  "hizuke::holidays",
  :composes,
  "hizuke::easter",
  "moveable holidays follow Easter"
)

edge("hizuke::business_day?", :composes, "hizuke::holiday?", "not a holiday")

edge(
  "hizuke::holiday?",
  :composes,
  "hizuke::holidays",
  "membership in the list"
)

edge(
  "hizuke::holidays",
  :composes,
  "hizuke::nth_weekday",
  "rule-based holidays"
)

edge(
  "hizuke::nth_weekday",
  :composes,
  "hizuke::weekday_of",
  "find the first, then step"
)

edge("hizuke::weekend?", :composes, "hizuke::weekday_of", "saturday or sunday")
edge("hizuke::business_day?", :composes, "hizuke::weekend?", "not a weekend")
edge("hizuke::quarter", :composes, "jikan::month", "month divided by three")

edge(
  "hizuke::fiscal_year",
  :composes,
  "jikan::year",
  "calendar year shifted by start month"
)

edge("hizuke::leap?", :guards, "hizuke::days_in", "february length")

edge(
  "hizuke::business_days_between",
  :inverse,
  "hizuke::add_business_days",
  "count versus step"
)

edge(
  "hizuke::add_business_days",
  :inverse,
  "hizuke::business_days_between",
  "count versus step"
)

edge("hizuke::weekend?", :pairs, "hizuke::business_day?", "rest and work")
edge("hizuke::holidays", :pairs, "hizuke::holiday?", "list and membership")
edge("hizuke::easter", :pairs, "hizuke::holidays", "moveable feasts")
edge("hizuke::quarter", :pairs, "hizuke::iso_week", "two ways to group a year")

edge(
  "hizuke::easter",
  :pairs,
  "hizuke::nth_weekday",
  "moveable and rule-based dates"
)

edge(
  "hizuke::fiscal_year",
  :pairs,
  "hizuke::quarter",
  "fiscal and calendar groupings"
)

edge("hizuke::iso_week", :pairs, "hizuke::weekday_of", "week and day")
edge("hizuke::day_of", :pairs, "jikan::day", "date form and instant form")
edge("hizuke::month_of", :pairs, "jikan::month", "date form and instant form")

edge(
  "hizuke::weekday_of",
  :pairs,
  "jikan::weekday",
  "date form and instant form"
)

edge("hizuke::year_of", :pairs, "jikan::year", "date form and instant form")

edge(
  "hizuke::days_in",
  :requires,
  "hizuke::leap?",
  "february depends on leap years"
)

edge(
  "hizuke::iso_week",
  :requires,
  "hizuke::weekday_of",
  "weeks start on Monday"
)
