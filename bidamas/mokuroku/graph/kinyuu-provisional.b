space("kinyuu?", {status: :provisional})

verb(
  "kinyuu?",
  "allocate",
  {
    kind: :pure,
    shape: "allocate(money, ratios) -> parts",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "split money by ratios; parts sum to the whole",
    wave: 1,
    origin: "G"
  }
)

verb(
  "kinyuu?",
  "amortize",
  {
    kind: :pure,
    shape: "amortize(loan) -> schedule",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "payment schedule: interest, principal, balance",
    wave: 2,
    origin: "G"
  }
)

verb(
  "kinyuu?",
  "balance",
  {
    kind: :pure,
    shape: "balance(ledger, account, at) -> money",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "what an account holds at a time",
    wave: 1,
    origin: "G"
  }
)

verb(
  "kinyuu?",
  "check",
  {
    kind: :pure,
    shape: "check(ledger) -> findings",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "verify chain, balance and period seals",
    wave: 1,
    origin: "G"
  }
)

verb(
  "kinyuu?",
  "convert",
  {
    kind: :pure,
    shape: "convert(money, currency, rate) -> money",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "money in another currency at a rate",
    wave: 1,
    origin: "G"
  }
)

verb(
  "kinyuu?",
  "discount",
  {
    kind: :pure,
    shape: "discount(flows, rate) -> money",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "present value of future cash flows",
    wave: 1,
    origin: "G"
  }
)

verb(
  "kinyuu?",
  "get",
  {
    kind: :effect,
    shape: "get(rates, pair, at) -> rate or nil",
    laterals: ["cache"],
    fleet: nil,
    today: "absent",
    meaning: "an exchange rate at a time; nil if unquoted",
    wave: 2,
    origin: "G",
    contract: "get(rates, pair, opts) -> rate or nil"
  }
)

verb(
  "kinyuu?",
  "interest",
  {
    kind: :pure,
    shape: "interest(principal, rate, term, kind) -> money",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "simple or compound interest",
    wave: 1,
    origin: "G"
  }
)

verb(
  "kinyuu?",
  "invoice",
  {
    kind: :decl,
    shape: "invoice(lines, opts) -> invoice",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "declare an invoice: lines, tax, totals",
    wave: 2,
    origin: "G"
  }
)

verb(
  "kinyuu?",
  "irr",
  {
    kind: :pure,
    shape: "irr(flows) -> rate",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the rate at which flows net to zero",
    wave: 2,
    origin: "G"
  }
)

verb(
  "kinyuu?",
  "ledger",
  {
    kind: :decl,
    shape: "ledger(accounts, rules) -> ledger",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "declare accounts and posting rules",
    wave: 1,
    origin: "G"
  }
)

verb(
  "kinyuu?",
  "list",
  {
    kind: :pure,
    shape: "list(ledger, filter) -> entries",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "entries that match, oldest first",
    wave: 1,
    origin: "G",
    contract: "list(ledger, opts) -> entries"
  }
)

verb(
  "kinyuu?",
  "money",
  {
    kind: :decl,
    shape: "money(amount, currency) -> money",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "exact amount in minor units; float refused",
    wave: 1,
    origin: "G"
  }
)

verb(
  "kinyuu?",
  "parse",
  {
    kind: :pure,
    shape: "parse(text, locale) -> money",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "text such as 1.234,50 EUR to money",
    wave: 1,
    origin: "G"
  }
)

verb(
  "kinyuu?",
  "post",
  {
    kind: :effect,
    shape: "post(ledger, entry) -> entry",
    laterals: %w[idempotent log validate],
    fleet: nil,
    today: "absent",
    meaning: "record a balanced entry once; unbalanced is refused",
    wave: 1,
    origin: "G"
  }
)

verb(
  "kinyuu?",
  "price",
  {
    kind: :pure,
    shape: "price(instrument, market, opts) -> money",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "value a bond, option or swap from market data",
    wave: 3,
    origin: "G"
  }
)

verb(
  "kinyuu?",
  "reconcile",
  {
    kind: :pure,
    shape: "reconcile(ledger, statement) -> mismatches",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "match entries to a bank statement",
    wave: 2,
    origin: "G"
  }
)

verb(
  "kinyuu?",
  "render",
  {
    kind: :pure,
    shape: "render(money, locale) -> text",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "money as a locale writes it",
    wave: 1,
    origin: "G"
  }
)

verb(
  "kinyuu?",
  "reverse",
  {
    kind: :effect,
    shape: "reverse(ledger, entry) -> entry",
    laterals: %w[idempotent log],
    fleet: nil,
    today: "absent",
    meaning: "post the opposite of an entry",
    wave: 1,
    origin: "G",
    contract: "reverse(ledger) -> entry"
  }
)

verb(
  "kinyuu?",
  "round",
  {
    kind: :pure,
    shape: "round(money, mode) -> money",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "money rounded to the currency minor unit",
    wave: 1,
    origin: "G"
  }
)

verb(
  "kinyuu?",
  "seal",
  {
    kind: :effect,
    shape: "seal(ledger, period) -> nil",
    laterals: %w[idempotent log],
    fleet: nil,
    today: "absent",
    meaning: "seal a period; later posts to it are refused",
    wave: 2,
    origin: "G"
  }
)

verb(
  "kinyuu?",
  "tax",
  {
    kind: :pure,
    shape: "tax(amount, rules) -> breakdown",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "tax due per rule, with the rounding shown",
    wave: 2,
    origin: "G"
  }
)

verb(
  "kinyuu?",
  "trade",
  {
    kind: :pure,
    shape: "trade(book, order) -> {fills, book}",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "match an order against a book",
    wave: 3,
    origin: "G"
  }
)

verb(
  "kinyuu?",
  "trial",
  {
    kind: :pure,
    shape: "trial(ledger, at) -> report",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "every balance, with debits equal to credits",
    wave: 1,
    origin: "G"
  }
)

edge("kinyuu?::trial", :composes, "kinyuu?::balance", "every balance")

edge(
  "kinyuu?::irr",
  :composes,
  "kinyuu?::discount",
  "root of net present value"
)

edge(
  "kinyuu?::price",
  :composes,
  "kinyuu?::discount",
  "value is discounted flows"
)

edge("kinyuu?::amortize", :composes, "kinyuu?::interest", "a row per period")
edge("kinyuu?::discount", :composes, "kinyuu?::interest", "inverse of growth")
edge("kinyuu?::ledger", :composes, "kinyuu?::money", "entries hold money")
edge("kinyuu?::trade", :composes, "kinyuu?::post", "a fill is posted")
edge("kinyuu?::invoice", :composes, "kinyuu?::tax", "totals with tax")
edge("kinyuu?::post", :composes, "nisshi::append", "an append-only record")
edge("kinyuu?::seal", :guards, "kinyuu?::post", "no post into a sealed period")
edge("kinyuu?::render", :inverse, "kinyuu?::parse", "money to text")
edge("kinyuu?::reverse", :inverse, "kinyuu?::post", "opposite entry")
edge("kinyuu?::parse", :inverse, "kinyuu?::render", "money to text")
edge("kinyuu?::post", :inverse, "kinyuu?::reverse", "opposite entry")
edge("kinyuu?::render", :refines, "gamen?::localize", "money form of localize")

edge(
  "kinyuu?::invoice",
  :requires,
  "bunsho::fill",
  "an invoice is rendered from a template"
)

edge("kinyuu?::irr", :requires, "kinji::zero", "a root finder")

edge(
  "kinyuu?::tax",
  :requires,
  "kinyuu?::allocate",
  "spread rounding across lines"
)

edge("kinyuu?::reconcile", :requires, "kinyuu?::balance", "compare balances")
edge("kinyuu?::convert", :requires, "kinyuu?::get", "needs a rate")
edge("kinyuu?::list", :requires, "kinyuu?::ledger", "reads a ledger")
edge("kinyuu?::post", :requires, "kinyuu?::ledger", "posts to a ledger")
edge("kinyuu?::balance", :requires, "kinyuu?::list", "sums entries")
edge("kinyuu?::reconcile", :requires, "kinyuu?::list", "match against entries")

edge(
  "kinyuu?::reverse",
  :requires,
  "kinyuu?::list",
  "find the entry to reverse"
)

edge("kinyuu?::allocate", :requires, "kinyuu?::money", "splits a money")
edge("kinyuu?::get", :requires, "kinyuu?::money", "a rate converts money")
edge("kinyuu?::invoice", :requires, "kinyuu?::money", "totals in money")
edge("kinyuu?::round", :requires, "kinyuu?::money", "rounds a money")
edge("kinyuu?::trade", :requires, "kinyuu?::money", "prices in money")
edge("kinyuu?::amortize", :requires, "kinyuu?::round", "each payment rounded")
edge("kinyuu?::convert", :requires, "kinyuu?::round", "round after converting")
edge("kinyuu?::interest", :requires, "kinyuu?::round", "round each period")

edge(
  "kinyuu?::money",
  :requires,
  "kinyuu?::round",
  "amounts sit on minor units"
)

edge("kinyuu?::check", :requires, "kinyuu?::trial", "debits equal credits")

edge(
  "kinyuu?::seal",
  :requires,
  "kinyuu?::trial",
  "trial balance before sealing"
)

edge("kinyuu?::check", :requires, "shomei::hash", "chain verification")
edge("kinyuu?::price", :requires, "toukei::describe", "market data summaries")
