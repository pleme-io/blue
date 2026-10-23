space("moji", {status: :ratified})

verb(
  "moji",
  "bytes",
  {
    kind: :pure,
    shape: "bytes(text, opts) -> bytes",
    laterals: [],
    fleet: "tatara-lisp-script",
    today: "rust:blue-lang-runtime",
    meaning: "the UTF-8 bytes of the text",
    wave: 1,
    origin: "A"
  }
)

verb(
  "moji",
  "case",
  {
    kind: :pure,
    shape: "case(text, style) -> text",
    laterals: [],
    fleet: nil,
    today: "partial:moji",
    meaning: "convert to snake, kebab, camel, pascal or title case",
    wave: 1,
    origin: "A"
  }
)

verb(
  "moji",
  "casefold",
  {
    kind: :pure,
    shape: "casefold(text) -> text",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "caseless-comparison form of the text",
    wave: 2,
    origin: "A"
  }
)

verb(
  "moji",
  "chars",
  {
    kind: :pure,
    shape: "chars(text) -> [char]",
    laterals: [],
    fleet: "tatara-lisp-script",
    today: "rust:blue-lang-runtime",
    meaning: "the code points of the text",
    wave: 0,
    origin: "A"
  }
)

verb(
  "moji",
  "closest",
  {
    kind: :pure,
    shape: "closest(text, candidates, opts) -> text or nil",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "candidate nearest to the text, for did-you-mean",
    wave: 2,
    origin: "A"
  }
)

verb(
  "moji",
  "compare",
  {
    kind: :pure,
    shape: "compare(a, b, opts) -> int",
    laterals: [],
    fleet: nil,
    today: "partial:moji",
    meaning: "order two texts; a locale option sorts by language",
    wave: 1,
    origin: "A"
  }
)

verb(
  "moji",
  "contains?",
  {
    kind: :pure,
    shape: "contains?(text, needle) -> Bool",
    laterals: [],
    fleet: nil,
    today: "exists:moji",
    meaning: "whether a string or pattern occurs in the text",
    wave: 0,
    origin: "A"
  }
)

verb(
  "moji",
  "count",
  {
    kind: :pure,
    shape: "count(text, needle) -> int",
    laterals: [],
    fleet: nil,
    today: "exists:moji",
    meaning: "number of non-overlapping occurrences",
    wave: 0,
    origin: "A"
  }
)

verb(
  "moji",
  "dedent",
  {
    kind: :pure,
    shape: "dedent(text) -> text",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "remove the common leading space of all lines",
    wave: 1,
    origin: "A"
  }
)

verb(
  "moji",
  "distance",
  {
    kind: :pure,
    shape: "distance(a, b, opts) -> number",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "edit distance: levenshtein, damerau, hamming",
    wave: 2,
    origin: "A"
  }
)

verb(
  "moji",
  "ends_with?",
  {
    kind: :pure,
    shape: "ends_with?(text, suffix) -> Bool",
    laterals: [],
    fleet: nil,
    today: "exists:moji",
    meaning: "whether the text ends with the suffix",
    wave: 0,
    origin: "A"
  }
)

verb(
  "moji",
  "escape",
  {
    kind: :pure,
    shape: "escape(text, target) -> text",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "make text safe for regex, shell, html, json or sql",
    wave: 1,
    origin: "A"
  }
)

verb(
  "moji",
  "fill",
  {
    kind: :pure,
    shape: "fill(template, data, opts) -> text",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "put data into the slots of a template",
    wave: 2,
    origin: "A",
    contract: "fill(template, data) -> text"
  }
)

verb(
  "moji",
  "find",
  {
    kind: :pure,
    shape: "find(text, pattern, opts) -> match or nil",
    laterals: [],
    fleet: "tatara-lisp-script",
    today: "rust:blue-lang-runtime",
    meaning: "first match with start and groups, else nil",
    wave: 1,
    origin: "A"
  }
)

verb(
  "moji",
  "find_all",
  {
    kind: :pure,
    shape: "find_all(text, pattern, opts) -> [match]",
    laterals: [],
    fleet: "tatara-lisp-script",
    today: "rust:blue-lang-runtime",
    meaning: "every non-overlapping match",
    wave: 1,
    origin: "A"
  }
)

verb(
  "moji",
  "from_bytes",
  {
    kind: :pure,
    shape: "from_bytes(bytes, opts) -> text",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "UTF-8 bytes to text; invalid bytes raise",
    wave: 1,
    origin: "A"
  }
)

verb(
  "moji",
  "graphemes",
  {
    kind: :pure,
    shape: "graphemes(text) -> [text]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "the user-perceived characters of the text",
    wave: 3,
    origin: "A"
  }
)

verb(
  "moji",
  "indent",
  {
    kind: :pure,
    shape: "indent(text, prefix) -> text",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "prefix every line",
    wave: 1,
    origin: "A"
  }
)

verb(
  "moji",
  "join",
  {
    kind: :pure,
    shape: "join(list, separator) -> text",
    laterals: [],
    fleet: "tatara-lisp-script",
    today: "rust:blue-lang-runtime",
    meaning: "list of text joined with a separator",
    wave: 0,
    origin: "A"
  }
)

verb(
  "moji",
  "lines",
  {
    kind: :pure,
    shape: "lines(text) -> [text]",
    laterals: [],
    fleet: nil,
    today: "exists:moji",
    meaning: "text cut at line ends",
    wave: 0,
    origin: "A"
  }
)

verb(
  "moji",
  "lower",
  {
    kind: :pure,
    shape: "lower(text) -> text",
    laterals: [],
    fleet: nil,
    today: "exists:moji",
    meaning: "every letter in lower case",
    wave: 0,
    origin: "A"
  }
)

verb(
  "moji",
  "matches?",
  {
    kind: :pure,
    shape: "matches?(text, pattern) -> Bool",
    laterals: [],
    fleet: "tatara-lisp-script",
    today: "rust:blue-lang-runtime",
    meaning: "whether the pattern matches the whole text",
    wave: 1,
    origin: "A"
  }
)

verb(
  "moji",
  "normalize",
  {
    kind: :pure,
    shape: "normalize(text, form) -> text",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "Unicode form NFC, NFD, NFKC or NFKD",
    wave: 3,
    origin: "A"
  }
)

verb(
  "moji",
  "pad",
  {
    kind: :pure,
    shape: "pad(text, width, opts) -> text",
    laterals: [],
    fleet: nil,
    today: "exists:moji",
    meaning: "extend text to a width on a chosen side",
    wave: 0,
    origin: "A"
  }
)

verb(
  "moji",
  "pattern",
  {
    kind: :pure,
    shape: "pattern(text, opts) -> pattern",
    laterals: ["error", "validate"],
    fleet: "tatara-lisp-script",
    today: "rust:blue-lang-runtime",
    meaning: "compile a regex into a reusable value",
    wave: 1,
    origin: "A"
  }
)

verb(
  "moji",
  "repeat",
  {
    kind: :pure,
    shape: "repeat(text, n) -> text",
    laterals: [],
    fleet: "tatara-lisp-script",
    today: "exists:moji",
    meaning: "text repeated n times",
    wave: 0,
    origin: "A"
  }
)

verb(
  "moji",
  "replace",
  {
    kind: :pure,
    shape: "replace(text, pattern, with, opts) -> text",
    laterals: [],
    fleet: "tatara-lisp-script",
    today: "rust:blue-lang-runtime",
    meaning: "replace matches by text or by f(match)",
    wave: 1,
    origin: "A"
  }
)

verb(
  "moji",
  "reverse",
  {
    kind: :pure,
    shape: "reverse(text) -> text",
    laterals: [],
    fleet: "tatara-lisp-script",
    today: "absent",
    meaning: "code points in reverse order",
    wave: 1,
    origin: "A"
  }
)

verb(
  "moji",
  "similarity",
  {
    kind: :pure,
    shape: "similarity(a, b, opts) -> number",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "likeness from 0 to 1 by a chosen metric",
    wave: 2,
    origin: "A"
  }
)

verb(
  "moji",
  "size",
  {
    kind: :pure,
    shape: "size(text) -> int",
    laterals: [],
    fleet: nil,
    today: "exists:moji",
    meaning: "number of code points",
    wave: 0,
    origin: "A"
  }
)

verb(
  "moji",
  "slots",
  {
    kind: :pure,
    shape: "slots(template) -> [name]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "slot names a template uses",
    wave: 2,
    origin: "A"
  }
)

verb(
  "moji",
  "slug",
  {
    kind: :pure,
    shape: "slug(text, opts) -> text",
    laterals: [],
    fleet: "tatara-lisp-script",
    today: "rust:blue-lang-runtime",
    meaning: "lowercase ASCII words joined by hyphens",
    wave: 1,
    origin: "A"
  }
)

verb(
  "moji",
  "split",
  {
    kind: :pure,
    shape: "split(text, pattern, opts) -> [text]",
    laterals: [],
    fleet: "tatara-lisp-script",
    today: "rust:blue-lang-runtime",
    meaning: "cut text at each match",
    wave: 1,
    origin: "A"
  }
)

verb(
  "moji",
  "starts_with?",
  {
    kind: :pure,
    shape: "starts_with?(text, prefix) -> Bool",
    laterals: [],
    fleet: nil,
    today: "exists:moji",
    meaning: "whether the text begins with the prefix",
    wave: 0,
    origin: "A"
  }
)

verb(
  "moji",
  "template",
  {
    kind: :pure,
    shape: "template(text, opts) -> template",
    laterals: ["error", "validate"],
    fleet: nil,
    today: "absent",
    meaning: "compile text with named slots into a template",
    wave: 2,
    origin: "A"
  }
)

verb(
  "moji",
  "tokenize",
  {
    kind: :pure,
    shape: "tokenize(text, opts) -> [token]",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "text to words or sentences with offsets",
    wave: 3,
    origin: "A"
  }
)

verb(
  "moji",
  "transliterate",
  {
    kind: :pure,
    shape: "transliterate(text, script) -> text",
    laterals: [],
    fleet: nil,
    today: "absent",
    meaning: "text in another script, or folded to ASCII",
    wave: 3,
    origin: "A"
  }
)

verb(
  "moji",
  "trim",
  {
    kind: :pure,
    shape: "trim(text, opts) -> text",
    laterals: [],
    fleet: nil,
    today: "partial:moji",
    meaning: "drop space from both ends",
    wave: 0,
    origin: "A"
  }
)

verb(
  "moji",
  "truncate",
  {
    kind: :pure,
    shape: "truncate(text, width, opts) -> text",
    laterals: [],
    fleet: nil,
    today: "exists:moji",
    meaning: "cut text to a width with an ellipsis",
    wave: 0,
    origin: "A"
  }
)

verb(
  "moji",
  "unescape",
  {
    kind: :pure,
    shape: "unescape(text, target) -> text",
    laterals: ["error"],
    fleet: nil,
    today: "absent",
    meaning: "undo escape for the same target",
    wave: 1,
    origin: "A"
  }
)

verb(
  "moji",
  "upper",
  {
    kind: :pure,
    shape: "upper(text) -> text",
    laterals: [],
    fleet: "tatara-lisp-script",
    today: "rust:blue-lang-runtime",
    meaning: "every letter in upper case",
    wave: 0,
    origin: "A"
  }
)

verb(
  "moji",
  "width",
  {
    kind: :pure,
    shape: "width(text) -> int",
    laterals: [],
    fleet: "caixa-unicode-width",
    today: "absent",
    meaning: "terminal columns the text takes",
    wave: 3,
    origin: "A"
  }
)

verb(
  "moji",
  "words",
  {
    kind: :pure,
    shape: "words(text) -> [text]",
    laterals: [],
    fleet: nil,
    today: "exists:moji",
    meaning: "text cut at runs of space",
    wave: 0,
    origin: "A"
  }
)

verb(
  "moji",
  "wrap",
  {
    kind: :pure,
    shape: "wrap(text, width) -> [text]",
    laterals: [],
    fleet: nil,
    today: "exists:moji",
    meaning: "break text into lines of at most a width",
    wave: 0,
    origin: "A"
  }
)

edge("moji::slug", :composes, "moji::case", "kebab form of the words")
edge("moji::size", :composes, "moji::chars", "count of code points")
edge("moji::similarity", :composes, "moji::distance", "scaled by length")
edge("moji::count", :composes, "moji::find_all", "length of the match list")
edge("moji::replace", :composes, "moji::find_all", "rewrite each match")
edge("moji::split", :composes, "moji::find_all", "cut between matches")

edge(
  "moji::reverse",
  :composes,
  "moji::graphemes",
  "reverse clusters, not code points"
)

edge("moji::width", :composes, "moji::graphemes", "sum of cluster widths")
edge("moji::case", :composes, "moji::join", "rejoin in the target style")
edge("moji::repeat", :composes, "moji::join", "n copies joined")
edge("moji::indent", :composes, "moji::lines", "prefix each line")

edge(
  "moji::escape",
  :composes,
  "moji::replace",
  "rewrite the unsafe characters"
)

edge("moji::fill", :composes, "moji::replace", "substitute each slot")
edge("moji::trim", :composes, "moji::replace", "drop edge space")
edge("moji::unescape", :composes, "moji::replace", "rewrite the escapes")

edge(
  "moji::closest",
  :composes,
  "moji::similarity",
  "highest-scoring candidate"
)

edge("moji::slug", :composes, "moji::transliterate", "fold to ASCII first")
edge("moji::pad", :composes, "moji::width", "fill to a column count")
edge("moji::truncate", :composes, "moji::width", "cut to a column count")
edge("moji::wrap", :composes, "moji::width", "lines stay within a width")
edge("moji::case", :composes, "moji::words", "split into words first")
edge("moji::wrap", :composes, "moji::words", "break between words")
edge("moji::graphemes", :generalizes, "moji::chars", "clusters of code points")

edge(
  "moji::find",
  :generalizes,
  "moji::contains?",
  "match record instead of Bool"
)

edge("moji::tokenize", :generalizes, "moji::words", "offsets and sentences too")
edge("moji::normalize", :guards, "moji::compare", "compare after normalizing")
edge("moji::template", :guards, "moji::fill", "compile before filling")
edge("moji::pattern", :guards, "moji::find", "compile before searching")
edge("moji::from_bytes", :inverse, "moji::bytes", "text and UTF-8 round-trip")
edge("moji::indent", :inverse, "moji::dedent", "removes the shared prefix")
edge("moji::unescape", :inverse, "moji::escape", "target-specific round-trip")
edge("moji::bytes", :inverse, "moji::from_bytes", "text and UTF-8 round-trip")
edge("moji::dedent", :inverse, "moji::indent", "removes the shared prefix")
edge("moji::split", :inverse, "moji::join", "list and text round-trip")
edge("moji::join", :inverse, "moji::split", "list and text round-trip")
edge("moji::escape", :inverse, "moji::unescape", "target-specific round-trip")
edge("moji::find_all", :lifts, "moji::find", "every match, not the first")
edge("moji::distance", :pairs, "chigai?::lcs", "edit distance and LCS agree")
edge("moji::from_bytes", :pairs, "deeta::decode", "text encoding then text")
edge("moji::bytes", :pairs, "deeta::encode", "bytes then a text encoding")
edge("moji::compare", :pairs, "junjo::sort", "sort uses compare")
edge("moji::lower", :pairs, "moji::casefold", "casefold is the strong form")
edge("moji::find_all", :pairs, "moji::count", "matches and how many")
edge("moji::upper", :pairs, "moji::lower", "case pair")
edge("moji::trim", :pairs, "moji::pad", "remove versus add space")
edge("moji::width", :pairs, "moji::size", "columns versus code points")
edge("moji::fill", :pairs, "moji::template", "compile once, fill many")
edge("moji::indent", :pairs, "moji::wrap", "layout verbs on lines")
edge("moji::contains?", :pairs, "retsu::contains?", "text versus list")

edge(
  "moji::pattern",
  :refines,
  "bunpou?::grammar",
  "a regex is a small grammar"
)

edge("moji::tokenize", :refines, "bunpou?::lex", "natural-language lexing")
edge("moji::lower", :refines, "moji::case", "a fixed style")
edge("moji::upper", :refines, "moji::case", "a fixed style")
edge("moji::contains?", :refines, "moji::find", "Bool answer only")
edge("moji::matches?", :refines, "moji::find", "match covers the whole text")
edge("moji::casefold", :refines, "moji::lower", "full Unicode folding")
edge("moji::ends_with?", :refines, "moji::matches?", "anchored at the end")
edge("moji::starts_with?", :refines, "moji::matches?", "anchored at the start")
edge("moji::chars", :refines, "moji::split", "cut at every code point")
edge("moji::lines", :refines, "moji::split", "cut at line ends")
edge("moji::words", :refines, "moji::split", "cut at runs of space")
edge("moji::reverse", :refines, "retsu::reverse", "list of clusters")
edge("moji::size", :refines, "retsu::size", "count of code points")
edge("moji::distance", :requires, "moji::chars", "compares code points")

edge(
  "moji::compare",
  :requires,
  "moji::normalize",
  "equal text must compare equal"
)

edge(
  "moji::transliterate",
  :requires,
  "moji::normalize",
  "decompose accents first"
)

edge("moji::fill", :requires, "moji::template", "needs a compiled template")
edge("moji::slots", :requires, "moji::template", "read the compiled form")
