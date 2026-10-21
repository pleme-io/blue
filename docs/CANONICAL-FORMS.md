# Canonical forms

blue has one way to write each thing. This is the inventory of every place where
the surface accepts two or more spellings of one meaning, the spelling blue
writes, why, which layer of the compiler holds it, and the rule that names it.

## The principles, in order

1. **Readability first.** The canonical spelling is the one a person reading the
   line cold understands fastest: words over symbols where blue offers both,
   the descriptive name over the terse one, no clever shorthand. This decided
   every row marked *readability* below.
2. **One tree.** Two spellings of one meaning lower to one AST, so every tool
   (the evaluator, the VM, `def_hash`, the checker, the formatter, the LSP)
   sees one shape. Where two spellings built different trees with the same
   meaning, the parser or the resolver now builds the canonical tree.
3. **Corpus frequency** decides only what the first two leave open, measured
   with the parser over the 240 tracked `.b` files of pleme-io on 2026-10-19
   (blue, nix, arnes, substrate, ola-mundo, blackmatter-akeyless, makoto,
   nupastel), aggregated in DuckDB.

## How a rule is held

Every form below still **parses**: an older program, a model or a Ruby habit is
read and means exactly what it says. What it cannot do is stay in a stored
file:

| door | what happens to a non-canonical spelling |
|---|---|
| `blue fmt --write` | writes the canonical spelling |
| `blue run`, `blue test`, `blue check` | rewrite a writable file before compiling it, naming the rules (`blue: formatted x.b (B0025 logical-words ×3; …)`); a read-only file (the nix store) is refused naming the rules |
| `blue fmt --check`, mkBidama's gate | fail naming the file, the rules and the first place |
| `blue check`, the LSP | report each finding with its code; `blue check --fix` applies the fixes |
| a session, `blue eval`, a string | accepted as written: it has no canonical text to hold |

Two doors decide. The **form door** (`pipeline::form_diagnostics`) compares a
file with its canonical rendering; the parser records which accepted spelling
explains each difference (`blue_lang_syntax::spelling`). The **check stage**
holds what only resolution knows (a builtin's other name, a zero-parameter call)
and the refusals. `blue explain CODE` prints each row.

## The inventory

| written | canonical | why | layer | rule | fix |
|---|---|---|---|---|---|
| `a && b`, `a \|\| b`, `!x`, `∧ ∨ ¬` | `a and b`, `a or b`, `not x` | readability: read aloud without a lookup; `!` vanishes beside a name. Corpus: 676 `&&`, 333 `\|\|`, 208 `!` | parser (one tree) | B0025 | autofix |
| `unless c` | `if not c` | readability: one conditional keyword; `unless … else` reads backwards. Corpus: 0 | parser | B0026 | autofix |
| `else` holding only `if … end` | `elsif` | one tree; a flat chain, one `end`. Corpus: 2 | parser, formatter | B0027 | autofix (kept when a comment sits beside the inner `if`) |
| `x.f(y)`, `x \|> f(y)` | `f(x, y)` | one tree; the function named first, a recursive call reads forwards. Corpus: 0, 0 | parser | B0028 | autofix |
| `{:a => 1}` | `{a: 1}` | one tree; reads as a field. Corpus: 0 (244 rockets with other keys stay) | parser | B0029 | autofix |
| `def f`, `fn … end` | `def f()`, `fn() … end` | one tree; the definition says it takes nothing | parser | B0030 | autofix |
| `not(x)`, `and(a, b)`, `mod(a, b)`, `equal?(a, b)`, `list(…)`, `define(x, v)`, `0 - x`, `≠ ≤ ≥ × ÷ − ≡` | `not x`, `a and b`, `a % b`, `a == b`, `[…]`, `x = v`, `-x`, the ASCII operator | one tree; readability: the operator a reader can type | parser | B0031 | autofix |
| `[1, 2,]`, `f(a,)`, `{a: 1,}`, `def f(a,)` | no trailing comma | was a parse error; now read and dropped, because models write it | parser | B0032 | autofix |
| `1000000`, `1_000`, `1e3`, a raw control or invisible character in a string | `1_000_000`, `1000`, `1000.0`, `"\u{1b}"` | readability: six or more digits grouped by threes; a character a reader cannot see is never in source (the formatter used to write a raw ESC byte). Corpus: 153 integers of 6+ digits, 6 raw control characters | formatter | B0033 | autofix |
| `not (a == b)`, `not (a != b)` | `a != b`, `a == b` | readability: one comparison; identical by okite D0002. Corpus: 9 | parser (builds `not=`) | B0034 | autofix |
| `if c … else nil end`, an empty `else` | `if c … end` | an `if` that fails is already nil. Corpus: 85 | parser (drops the branch) | B0035 | autofix (kept when the `else` holds a comment) |
| `car`, `cdr`, `next`, `modulo`, `rem`, `bool?`, `comp`, `foldl`, `nil?(x)`, `some?(x)`, `error_kind(e)`, `error_message(e)` | `first`, `rest`, `rest`, `a % b`, `a % b`, `boolean?`, `compose`, `reduce`, `x == nil`, `x != nil`, `e.kind`, `e.message` | readability: the name a reader without Lisp knows; `some?` reads as "some element". Each pair measured equal on every input class (`blue eval`, 2026-10-19). Corpus: 2 `car`, 12 `cdr`, 34 `modulo`, 13 `foldl`, 2 `bool?`, 7 `nil?` | resolution | B0036 | autofix; writes `blue::first` where a listed import shadows the bare name |
| `throw(error(k, m))`, `throw(x)`, `try(x, catch(e(), h))`, `begin … end` as a whole `def` body | `raise(k, m)`, `raise(x)`, `x rescue h` or `begin … rescue e … end`, the clauses on the `def` | readability: one step to raise, a block that reads like Ruby's, the error a readable record. Corpus: 92 `throw(error(`, 178 `throw(`, 212 `try(` | resolution (`throw`), parser (`try`, `begin`) | B0037 | autofix |
| `apply(f, a, xs)` with `f` a name | `f(a, *xs)` | one tree; the call keeps its shape. Corpus: 41 | parser, formatter | B0042 | autofix |
| `(x) -> f(x)` with `f` a `def` of the file taking exactly those parameters | `f` | one function, the shorter name; `fn … end` on one line is B0024 | check stage | B0044 | autofix |
| `to_s(to_s(x))`, `string(trim(x))`, `to_int(to_int!(x))`, `to_float(sqrt(x))`, `trim(trim(x))`, `to_s("a")`: a conversion whose argument is a builtin call that already returns the kind it leaves alone, or a literal of that kind | the argument itself | the chain does nothing; one table, `blue_lang_check::chains::RULES`, read by the check stage, the formatter and the evaluator, each row carrying an okite law (D0013). `to_int(to_int(x))`, `to_float(to_float(x))` and `upcase(downcase(x))` stay: they change values. A local or definition named like the builtin is never rewritten | check stage, evaluator | B0045 | autofix |
| `if getenv("X_MAIN", "") == "1" … f … end` | `def main()`, called by `blue run` | one entry-point convention; no environment variable. Corpus: 8 | check stage | B0041 | autofix where the guard calls one zero-parameter function used nowhere else; refused otherwise |
| `ro_resolve_argv`, `ro_patch_argv`, `ro_main` in a program | `resolve_argv`, `patch_argv`, `main` | the file is the namespace; a prefix repeats it. Corpus: the nix programs and the `gen/` generators | check stage | B0043 | autofix where no stripped name is already used in the file or reserved; refused otherwise (a bidama's prefix is B0013/B0014) |
| `rescue e` with an empty or `nil` handler | `rescue _` and `nil`, or `x rescue nil` | silence must be visible | check stage | B0038 | refused |
| two tests with one name | distinct names | a failure must say which test | check stage | B0039 | refused |
| `retryCount` | `retry_count` | readability: one case for names. Corpus: 1 | check stage | B0040 | refused (a name is its callers' too) |
| whitespace, indentation, width 80, blank lines, redundant parentheses, a call whose one argument is a literal broken over lines | `blue fmt`'s layout | one layout; a short call stays on its line | formatter | B0024 | autofix |
| `name()` for a zero-parameter function | `name` | (shipped in v0.0.74) | resolution | B0023 | autofix |
| a `use` out of order, twice, or unread | sorted, once, read | (shipped) | check stage | B0015, B0016 | list sort and `use` form order: autofix; unused: refused |
| a bare name reached only through a bidama another `use` loaded; `retsu::first` with no `use("retsu")` | `use("retsu", [:first, :last])` added in package order; `use("retsu")` added | the file says what it reads | check stage | B0012, B0010 | autofix in a script (a bidama's Bluefile `needs` is the author's) |
| `blue::name` where the bare name is the builtin | `name` | (shipped) | resolution | B0018 | autofix |

## New forms these rules write

- **Logic words**: `and`, `or`, `not` are reserved. `not` binds as `!` did
  (tightly), and a negation that is an operand of a comparison or arithmetic is
  written `(not a) == b`.
- **Errors**: `raise(:kind, "message")`, `raise(:kind, "message", {data: d, cause: e})`,
  `raise(e)`. `x rescue fallback` binds loosest of all, below `|>`. A block:
  `begin … rescue :a, :b as e … rescue e … ensure … end`; a `def` takes the same
  clauses directly. An uncaught error prints `kind: message`, every cause, and
  the stack, and exits 1. The error value's fields: `e.kind`, `e.message`,
  `e.data`, `e.cause`, `e.trace` (the raise site, `file:line`); `"#{e}"` is
  `kind: message (at file:line)`.
- **Records**: `x.name` without parentheses reads a field: a map's keyword or
  string key, a keyed list (`exec_capture`'s `[[:status, n], …]`, a parsed JSON
  object), or an error's field. A missing field raises naming the fields there
  are; `get(m, :k)` reads a field that may be absent.
- **Splat**: `f(a, *xs)`, the list last.
- **Entry point**: `def main()`, called by `blue run` and by nothing else.
- **Libraries**: `deeta::json_at(doc, "spec.items.0.name")`, nil when any step
  is absent; `saishikou::retrying({times: 3, wait_ms: 500, on: [:timeout]}, fn() … end)`.

## Considered and not made rules

| forms | decision | why |
|---|---|---|
| `"a" + x` vs interpolation | no second form | `+` is numbers only; `"a#{x}"` is the one spelling |
| `concat(a, b)` vs `"#{a}#{b}"` | both stay | different trees, and `concat` is how a literal `#{` is built (222 calls) |
| `:sym` vs `"sym"` | both stay | different values |
| `x == true` vs `x` | both stay | different meanings under truthiness (2,479 in tests) |
| `eq?` vs `==`, `null?` vs `empty?`, `length` vs `count`, `some` vs `any?` | both stay | different answers on some input (`eq?` is identity; `null?("")`; `length(nil)` raises; `some` answers nil) |
| `count(x) == 0` vs `empty?(x)` | both stay | `count` raises where `empty?` answers; a rewrite would change a failure into a value |
| `if not c a else b end` vs `if c b else a end` | both stay | branch order is the author's emphasis, and swapping it moves comments |
| pipelines | call form | the tree does not remember the spelling; a pipeline rendering for long data-first chains needs a shape detector and is a formatter version bump (§V.13) |
| `def f()` vs `def f` | `def f()` | the definition says it takes nothing; only the call is bare |
| unused locals and parameters | B0002 stays a warning | renaming in flight would rename a parameter the author is about to use |
| `return`, `do`/braces blocks, `;`, `xs[i]` | one form already | refused by the parser with the canonical spelling named |
| a typed `raise :kind, "m"` keyword form | `raise(…)` call | blue has no paren-less calls; one call grammar |
| Result values and a `?` operator | not added | exceptions stay the one error model; `kyohi` holds refusals as data where a caller branches on them |
| retry as syntax (`retry`) | a bidama, `saishikou` | a bounded helper says its bound; a keyword hides a loop |
| a warning for rescuing a kind nothing raises | not built | no analysis can know which kinds a call raises |
