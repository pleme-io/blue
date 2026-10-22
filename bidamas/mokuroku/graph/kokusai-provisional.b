space("kokusai?", {status: :provisional})

verb(
  "kokusai?",
  "catalog",
  {
    kind: :decl,
    shape: "catalog(entries) -> catalog",
    laterals: ["validate"],
    fleet: "pleme-i18n",
    today: "absent",
    meaning: "declare message texts per locale",
    wave: 3,
    origin: "A"
  }
)

verb(
  "kokusai?",
  "collate",
  {
    kind: :pure,
    shape: "collate(locale, a, b) -> int",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "order two texts by a locale's alphabet",
    wave: 3,
    origin: "A"
  }
)

verb(
  "kokusai?",
  "coverage",
  {
    kind: :pure,
    shape: "coverage(catalog, locales) -> record",
    laterals: ["validate"],
    fleet: "namimado",
    today: "absent",
    meaning: "keys each locale lacks",
    wave: 3,
    origin: "A"
  }
)

verb(
  "kokusai?",
  "currency",
  {
    kind: :pure,
    shape: "currency(locale, amount, code) -> text",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "money shown by a locale's conventions",
    wave: 3,
    origin: "A"
  }
)

verb(
  "kokusai?",
  "date",
  {
    kind: :pure,
    shape: "date(locale, value, opts) -> text",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "date or instant shown by a locale's conventions",
    wave: 3,
    origin: "A"
  }
)

verb(
  "kokusai?",
  "direction",
  {
    kind: :pure,
    shape: "direction(locale) -> symbol",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "text direction: left-to-right or right-to-left",
    wave: 3,
    origin: "A"
  }
)

verb(
  "kokusai?",
  "extract",
  {
    kind: :pure,
    shape: "extract(source, opts) -> [key]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "message keys used by a source tree",
    wave: 4,
    origin: "A"
  }
)

verb(
  "kokusai?",
  "locale",
  {
    kind: :pure,
    shape: "locale(tag) -> locale",
    laterals: ["error", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "parse a BCP 47 language tag",
    wave: 3,
    origin: "A"
  }
)

verb(
  "kokusai?",
  "negotiate",
  {
    kind: :pure,
    shape: "negotiate(wanted, available) -> locale",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "best available locale for an Accept-Language list",
    wave: 3,
    origin: "A"
  }
)

verb(
  "kokusai?",
  "number",
  {
    kind: :pure,
    shape: "number(locale, n, opts) -> text",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "number shown by a locale's conventions",
    wave: 3,
    origin: "A"
  }
)

verb(
  "kokusai?",
  "phrase",
  {
    kind: :pure,
    shape: "phrase(locale, items) -> text",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "items joined as \"a, b and c\" in a locale",
    wave: 3,
    origin: "A"
  }
)

verb(
  "kokusai?",
  "plural",
  {
    kind: :pure,
    shape: "plural(locale, n) -> symbol",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "CLDR plural category of a number",
    wave: 3,
    origin: "A"
  }
)

verb(
  "kokusai?",
  "relative",
  {
    kind: :pure,
    shape: "relative(locale, duration) -> text",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "a duration as \"3 days ago\" in a locale",
    wave: 3,
    origin: "A"
  }
)

verb(
  "kokusai?",
  "translate",
  {
    kind: :pure,
    shape: "translate(catalog, key, args, opts) -> text",
    laterals: ["error"],
    fleet: "pleme-i18n",
    today: "absent",
    meaning: "message for a key in a locale, with fallbacks",
    wave: 3,
    origin: "A"
  }
)

edge(
  "kokusai?::extract",
  :composes,
  "bunpou?::find_all",
  "scan source for keys"
)

edge("kokusai?::catalog", :composes, "deeta::read", "catalogs are documents")
edge("kokusai?::relative", :composes, "jikan::total", "largest sensible unit")
edge("kokusai?::coverage", :composes, "kokusai?::catalog", "compare key sets")

edge(
  "kokusai?::negotiate",
  :composes,
  "kokusai?::locale",
  "parses the wanted tags"
)

edge("kokusai?::currency", :composes, "kokusai?::number", "amount then symbol")

edge(
  "kokusai?::translate",
  :composes,
  "kokusai?::plural",
  "choose the plural form"
)

edge(
  "kokusai?::translate",
  :composes,
  "moji::fill",
  "put args into the message"
)

edge("kokusai?::phrase", :composes, "moji::join", "locale-aware conjunction")
edge("kokusai?::currency", :composes, "seimitsu?::decimal", "money is exact")

edge(
  "kokusai?::coverage",
  :guards,
  "kokusai?::translate",
  "finds missing messages first"
)

edge(
  "kokusai?::locale",
  :guards,
  "kokusai?::translate",
  "a catalog lookup needs a locale"
)

edge("kokusai?::relative", :pairs, "jikan::since", "elapsed time to words")
edge("kokusai?::collate", :pairs, "junjo::sort", "locale-aware sort")
edge("kokusai?::number", :pairs, "kokusai?::currency", "plain and monetary")

edge(
  "kokusai?::negotiate",
  :pairs,
  "kokusai?::translate",
  "choose the language, then the text"
)

edge("kokusai?::plural", :pairs, "kokusai?::translate", "message variants")
edge("kokusai?::date", :refines, "jikan::render", "locale-aware rendering")
edge("kokusai?::number", :refines, "kazu::render", "locale-aware rendering")
edge("kokusai?::collate", :refines, "moji::compare", "locale alphabet")
edge("kokusai?::date", :requires, "jikan::in_zone", "local fields need a zone")
edge("kokusai?::catalog", :requires, "kokusai?::locale", "keys are per locale")

edge(
  "kokusai?::direction",
  :requires,
  "kokusai?::locale",
  "script decides direction"
)

edge(
  "kokusai?::number",
  :requires,
  "kokusai?::locale",
  "separators are per locale"
)

edge("kokusai?::plural", :requires, "kokusai?::locale", "rules are per locale")
