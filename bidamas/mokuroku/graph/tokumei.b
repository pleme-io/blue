space("tokumei", {status: :ratified})

verb(
  "tokumei",
  "budget",
  {
    kind: :decl,
    shape: "budget(epsilon, opts) -> budget",
    laterals: ["config"],
    fleet: nil,
    today: "absent",
    meaning: "total privacy a dataset may spend",
    wave: 2,
    origin: "D"
  }
)

verb(
  "tokumei",
  "classify",
  {
    kind: :pure,
    shape: "classify(value, rules) -> [label]",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "label fields or text as kinds of personal data",
    wave: 1,
    origin: "D"
  }
)

verb(
  "tokumei",
  "consent",
  {
    kind: :decl,
    shape: "consent(subject, purpose, until) -> consent",
    laterals: ["config", "time"],
    fleet: nil,
    today: "absent",
    meaning: "a person's permission for one purpose",
    wave: 3,
    origin: "D"
  }
)

verb(
  "tokumei",
  "count",
  {
    kind: :pure,
    shape: "count(xs, epsilon, seed) -> number",
    laterals: [],
    fleet: nil,
    today: "partial:tokumei",
    meaning: "a count with noise that hides one person",
    wave: 0,
    origin: "G",
    contract: "count(xs, epsilon, opts) -> number"
  }
)

verb(
  "tokumei",
  "detokenize",
  {
    kind: :effect,
    shape: "detokenize(token, vault) -> value",
    laterals: ["error", "log", "resource"],
    fleet: nil,
    today: "absent",
    meaning: "recover the value a token stands for",
    wave: 3,
    origin: "D"
  }
)

verb(
  "tokumei",
  "epsilon",
  {
    kind: :pure,
    shape: "epsilon(p) -> number",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:tokumei",
    wave: 0,
    origin: "D"
  }
)

verb(
  "tokumei",
  "erase",
  {
    kind: :effect,
    shape: "erase(subject, opts) -> receipt",
    laterals: ["idempotent", "log", "resource"],
    fleet: nil,
    today: "absent",
    meaning: "delete a person's data from every store, with receipt",
    wave: 3,
    origin: "D"
  }
)

verb(
  "tokumei",
  "estimate",
  {
    kind: :pure,
    shape: "estimate(yes_share, p) -> number",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:tokumei",
    wave: 0,
    origin: "D"
  }
)

verb(
  "tokumei",
  "exposure",
  {
    kind: :pure,
    shape: "exposure(prevalence, p) -> number",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:tokumei",
    wave: 0,
    origin: "D"
  }
)

verb(
  "tokumei",
  "gather",
  {
    kind: :effect,
    shape: "gather(subject, stores) -> bundle",
    laterals: ["log", "resource"],
    fleet: nil,
    today: "absent",
    meaning: "collect everything held about a person",
    wave: 3,
    origin: "D"
  }
)

verb(
  "tokumei",
  "generalize",
  {
    kind: :pure,
    shape: "generalize(value, level) -> value",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "coarsen a value: exact age to ten-year band",
    wave: 2,
    origin: "D"
  }
)

verb(
  "tokumei",
  "k_anonymous?",
  {
    kind: :pure,
    shape: "k_anonymous?(rows, columns, k) -> Bool",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "every combination of columns appears at least k times",
    wave: 2,
    origin: "D"
  }
)

verb(
  "tokumei",
  "laplace",
  {
    kind: :pure,
    shape: "laplace(scale, seed) -> number",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:tokumei",
    wave: 0,
    origin: "D"
  }
)

verb(
  "tokumei",
  "lapsed",
  {
    kind: :pure,
    shape: "lapsed(records, retention, now) -> [record]",
    laterals: ["time"],
    fleet: nil,
    today: "absent",
    meaning: "records kept past their retention",
    wave: 2,
    origin: "D"
  }
)

verb(
  "tokumei",
  "locate",
  {
    kind: :effect,
    shape: "locate(stores, kinds) -> [place]",
    laterals: ["resource"],
    fleet: nil,
    today: "absent",
    meaning: "where in the stores personal data lives",
    wave: 3,
    origin: "D"
  }
)

verb(
  "tokumei",
  "mark",
  {
    kind: :pure,
    shape: "mark(value, kind) -> value",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "tag a value personal so it prints as a mark",
    wave: 2,
    origin: "D"
  }
)

verb(
  "tokumei",
  "mask",
  {
    kind: :pure,
    shape: "mask(text, keep) -> text",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "hide all but a few characters, such as the last four",
    wave: 1,
    origin: "D"
  }
)

verb(
  "tokumei",
  "permitted?",
  {
    kind: :pure,
    shape: "permitted?(subject, purpose, consents, now) -> Bool",
    laterals: ["time", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "a consent covers this use right now",
    wave: 3,
    origin: "D"
  }
)

verb(
  "tokumei",
  "perturb",
  {
    kind: :pure,
    shape: "perturb(value, epsilon, seed) -> number",
    laterals: [],
    fleet: nil,
    today: "partial:tokumei",
    meaning: "add Laplace noise to a value",
    wave: 0,
    origin: "G"
  }
)

verb(
  "tokumei",
  "private_count",
  {
    kind: :pure,
    shape: "private_count(count, epsilon, seed) -> number",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:tokumei",
    wave: 0,
    origin: "D"
  }
)

verb(
  "tokumei",
  "private_mean",
  {
    kind: :pure,
    shape: "private_mean(values, bounds, epsilon, seed) -> number",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "a mean published with differential privacy",
    wave: 2,
    origin: "D"
  }
)

verb(
  "tokumei",
  "private_share",
  {
    kind: :pure,
    shape: "private_share(count, n, epsilon, seed) -> number",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:tokumei",
    wave: 0,
    origin: "D"
  }
)

verb(
  "tokumei",
  "pseudonym",
  {
    kind: :pure,
    shape: "pseudonym(value, key) -> text",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "stable keyed stand-in; same input gives same output",
    wave: 2,
    origin: "D"
  }
)

verb(
  "tokumei",
  "randomize",
  {
    kind: :pure,
    shape: "randomize(truth, p, seed) -> Bool",
    laterals: ["validate"],
    fleet: nil,
    today: "partial:tokumei",
    meaning: "forced-response answer: truth or a fair coin",
    wave: 0,
    origin: "D"
  }
)

verb(
  "tokumei",
  "redact",
  {
    kind: :pure,
    shape: "redact(value, kinds, opts) -> value",
    laterals: ["log", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "replace personal data with fixed marks",
    wave: 1,
    origin: "D",
    contract: "redact(value, kinds) -> value"
  }
)

verb(
  "tokumei",
  "retention",
  {
    kind: :decl,
    shape: "retention(kind, keep, basis) -> retention",
    laterals: ["config", "time"],
    fleet: nil,
    today: "absent",
    meaning: "how long a kind of data is kept, and why",
    wave: 2,
    origin: "D"
  }
)

verb(
  "tokumei",
  "spend",
  {
    kind: :effect,
    shape: "spend(budget, epsilon) -> budget",
    laterals: ["error", "log"],
    fleet: nil,
    today: "absent",
    meaning: "use part of a budget; raises :exhausted at zero",
    wave: 2,
    origin: "D"
  }
)

verb(
  "tokumei",
  "spot",
  {
    kind: :pure,
    shape: "spot(text, kinds) -> [match]",
    laterals: ["validate"],
    fleet: nil,
    today: "absent",
    meaning: "locate personal data inside free text",
    wave: 1,
    origin: "D"
  }
)

verb(
  "tokumei",
  "suppress",
  {
    kind: :pure,
    shape: "suppress(count, k) -> number or nil",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:tokumei",
    wave: 0,
    origin: "D"
  }
)

verb(
  "tokumei",
  "tokenize",
  {
    kind: :effect,
    shape: "tokenize(value, vault) -> token",
    laterals: ["idempotent", "resource"],
    fleet: nil,
    today: "absent",
    meaning: "swap a value for a random token kept in a vault",
    wave: 3,
    origin: "D"
  }
)

verb(
  "tokumei",
  "unique_share",
  {
    kind: :pure,
    shape: "unique_share(group_size, cells) -> number",
    laterals: ["validate"],
    fleet: nil,
    today: "exists:tokumei",
    wave: 0,
    origin: "D"
  }
)

edge(
  "tokumei::erase",
  :composes,
  "fuuin?::destroy",
  "crypto-shred when data is sealed per person"
)

edge("tokumei::tokenize", :composes, "fuuin?::random", "random token")
edge("tokumei::erase", :composes, "nisshi::audit", "a receipt in the audit log")
edge("tokumei::gather", :composes, "nisshi::audit", "each access is logged")

edge(
  "tokumei::pseudonym",
  :composes,
  "shomei::mac",
  "keyed hash is the stand-in"
)

edge(
  "tokumei::private_count",
  :composes,
  "tokumei::laplace",
  "count plus noise"
)

edge(
  "tokumei::private_mean",
  :composes,
  "tokumei::laplace",
  "clipped mean plus noise"
)

edge("tokumei::erase", :composes, "tokumei::locate", "find then delete")
edge("tokumei::gather", :composes, "tokumei::locate", "find then collect")

edge(
  "tokumei::private_share",
  :composes,
  "tokumei::private_count",
  "count over n"
)

edge(
  "tokumei::permitted?",
  :guards,
  "kengen?::permit",
  "purpose check beside access check"
)

edge("tokumei::consent", :guards, "nisshi::audit", "consents are recorded")
edge("tokumei::detokenize", :guards, "nisshi::audit", "each reversal is logged")
edge("tokumei::redact", :guards, "rogu::info", "scrub before logging")
edge("tokumei::suppress", :guards, "tokumei::count", "no small groups")

edge(
  "tokumei::generalize",
  :guards,
  "tokumei::k_anonymous?",
  "raises group sizes"
)

edge(
  "tokumei::unique_share",
  :guards,
  "tokumei::k_anonymous?",
  "estimate before checking"
)

edge(
  "tokumei::spend",
  :guards,
  "tokumei::private_count",
  "each release costs epsilon"
)

edge(
  "tokumei::suppress",
  :guards,
  "tokumei::private_count",
  "small counts are not published"
)

edge(
  "tokumei::tokenize",
  :inverse,
  "tokumei::detokenize",
  "returns the original value"
)

edge(
  "tokumei::randomize",
  :inverse,
  "tokumei::estimate",
  "undoes the randomising in aggregate"
)

edge(
  "tokumei::estimate",
  :inverse,
  "tokumei::randomize",
  "undoes the randomising in aggregate"
)

edge(
  "tokumei::detokenize",
  :inverse,
  "tokumei::tokenize",
  "returns the original value"
)

edge(
  "tokumei::randomize",
  :pairs,
  "tokumei::estimate",
  "answer then recover the share"
)

edge("tokumei::retention", :pairs, "tokumei::lapsed", "declared then applied")
edge("tokumei::consent", :pairs, "tokumei::permitted?", "recorded then checked")
edge("tokumei::budget", :pairs, "tokumei::spend", "declared then spent")
edge("tokumei::classify", :pairs, "tokumei::spot", "labels fields, spots text")

edge(
  "tokumei::mark",
  :refines,
  "himitsu::secret",
  "same printing rule for personal data"
)

edge(
  "tokumei::spot",
  :refines,
  "tokumei::classify",
  "classify inside free text"
)

edge(
  "tokumei::private_mean",
  :refines,
  "tokumei::private_count",
  "a different query, same privacy cost"
)

edge("tokumei::mask", :refines, "tokumei::redact", "keeps the last characters")
edge("tokumei::perturb", :requires, "ran::draw", "seeded noise")
edge("tokumei::laplace", :requires, "ran::stream_seed", "seeded noise stream")
edge("tokumei::spend", :requires, "tokumei::budget", "spends from a budget")

edge(
  "tokumei::locate",
  :requires,
  "tokumei::classify",
  "find stores by labelled kinds"
)

edge(
  "tokumei::mark",
  :requires,
  "tokumei::classify",
  "kind comes from classification"
)

edge(
  "tokumei::permitted?",
  :requires,
  "tokumei::consent",
  "reads the recorded consents"
)

edge("tokumei::exposure", :requires, "tokumei::epsilon", "observer certainty")

edge(
  "tokumei::k_anonymous?",
  :requires,
  "tokumei::generalize",
  "coarsen until it holds"
)

edge(
  "tokumei::erase",
  :requires,
  "tokumei::lapsed",
  "erasure is how retention is enforced"
)

edge("tokumei::count", :requires, "tokumei::perturb", "noise on a count")

edge(
  "tokumei::tokenize",
  :requires,
  "tokumei::pseudonym",
  "stand-in may be random instead"
)

edge("tokumei::epsilon", :requires, "tokumei::randomize", "cost of one answer")

edge(
  "tokumei::lapsed",
  :requires,
  "tokumei::retention",
  "compares age to retention"
)

edge("tokumei::redact", :requires, "tokumei::spot", "replace what was spotted")
edge("tokumei::suppress", :requires, "toukei::describe", "group sizes")
