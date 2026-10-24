# CST plan: a lossless tree, resilient parsing, surface blame

**Status (2026-10-24): DESIGN.** Nothing here is built. Source read at
`origin/main` `c2843e0`. Each `file:line` below was read at that commit.
Re-measure before you build on a count.

This plan is the bridge between two designs that already exist. It does not
restate them:

- `theory/BLUE-ENGINE.md` §5.1 and milestone E6: parser recovery, holes,
  `Parsed<Complete>` and `Parsed<WithHoles>`.
- `docs/NATURALIZE-TREESITTER.md` §6, M3: blue's own parser is emitted from
  the `kiwari` spec, and the hand-written one retires.

Both refuse a second parser. This plan obeys that. The CST comes from the one
parser, and its shape comes from the one spec.

---

## 1. Destination

The parser always returns a tree. The tree is lossless: its text is the
source, byte for byte, with every space, newline and comment as a token. Each
node kind is a rule of the `kiwari` spec, so the CST, the tree-sitter grammar
and the editor queries share one set of kinds. A broken region is an `ERROR`
node, and the parser resumes at the next statement, closer or `end`. The
`Spanned` tree that the check stage and the evaluator read is a LOWERING of
the CST by the spec's templates. That lowering is the only lowering. A
broken region lowers to a hole, `(blue-hole …)`. The check stage refuses each
hole as B0006, scoped to that hole, and checks every sibling. The compile door
does not accept a tree with holes. Each lowered node records the CST node it
came from, so a runtime error names the operator the author wrote (`%`, `==`)
at the operator's position, not the callee it lowered to (`mod`, `equal?`).
`Sexp`, `def_hash` and canonical text do not change.

**What becomes unrepresentable, by tier** (tiers per
`theory/UNREPRESENTABILITY.md`):

| bad state | after this plan | tier |
|---|---|---|
| a parse that returns no tree, so the editor has no answer (E6) | `parse_cst` returns `Parse`, never `Result` | type |
| a program with a hole reaches `run` | `Parsed<WithHoles>` has no conversion into pipeline input | type (compile-fail test) |
| a parse that loses a byte | `Parse` has one constructor; it checks `text == src`; the corpus and prefix gate proves it | constructor-checked, CI-caught |
| a formatter that drops a comment | a comment is a token in the input CST; the formatter refuses an output CST with fewer comment tokens, in order | door-refused, CI-caught |
| a runtime error that names a lowered callee, or points at the wrong byte | `describe` reads the blame table; a matrix test has one row per lowering link | CI-caught (all-variants matrix) |
| a node kind with no row in the grammar card | the kinds are generated from `kiwari`; a gate fails when a kind has no `FORMS`, `INFIX` or keyword row | CI-caught |

The trivia stays out of `Sexp`. `theory/BLUE-ENGINE.md` §2 (the Roslyn row)
refused trivia in the tree that `def_hash` and canonicality read, and this
plan keeps that refusal. Trivia lives one layer below, in the CST, and the
lowering drops it.

---

## 2. Reuse map

Move, never copy. Each row says what exists, where, and where it goes.

| what | where today | where it goes |
|---|---|---|
| the 47 named node kinds and their lowering templates | `crates/blue-lang-kiwari/blue.kiwari.json` (`lower` map), authored in `bidamas/kiwari/kiwari.b` | the source of `SyntaxKind` (generated, P1) and of the one lowering (P3) |
| the `Cst` trait (kind, range, fields) and the template evaluator `Lowerer` | `crates/blue-lang-kiwari/src/lower.rs:21`, `:66` | moves into `blue-lang-syntax::cst::lower`; `blue-lang-kiwari` keeps the tree-sitter `impl Cst` only (P3) |
| `Template` and the spec reader | `crates/blue-lang-kiwari/src/spec.rs:74`, `:145` | moves with `Lowerer`; gains a span ANCHOR per synthesized atom (P3) |
| the infix table, twice: `INFIX` and `infix_rows` | `crates/blue-lang-syntax/src/parse.rs:387`; `bidamas/kiwari/kiwari.b:666` | one table in `kiwari`; `INFIX` becomes a generated rendering; each `doc` line moves into its `kiwari` row (P1, open decision 2) |
| the keyword lists, twice | `parse.rs:552` (`SURFACE_KEYWORDS`), `:578` (`BLOCK_KEYWORDS`); `kiwari.b:973` (`reserved`) | as `INFIX` (P1) |
| the table-equality test that holds the copies equal | `crates/blue-lang-kiwari/tests/spec.rs` | stays; after P1 it is a tautology, and the generated-fresh check is the real gate |
| `FORMS` (grammar card rows) | `crates/blue-lang-syntax/src/forms.rs:27` | each row names its CST kind; a gate covers every kind (P1) |
| trivia tokens (`Comment`, `Newline`, `is_trivia`) | `crates/blue-lang-syntax/src/lex.rs:107-108`, `:163` | the CST's trivia; whitespace gaps become `Whitespace` tokens (P0) |
| `lex` (returns `Err` on the first bad byte) | `lex.rs:190` | becomes a projection of a total `lex_lossless` (P0) |
| the parser drops comments before it parses | `Parser::over`, `parse.rs:762` | the builder attaches each comment as a token (P2) |
| 161 inline lowering sites (`list_at`, `sym_at`, `atom_at`) | `parse.rs`, for example `infix_node` `:1184`, `nil_test` `:1159`, `rescue_node` `:1125`, `negation` `:1555`, `statement_inner` `:1061` | each moves into its `kiwari` template; the production keeps only the CST shape (P3) |
| 22 spelling notes (`Parser::note`) | `parse.rs:783`; `spelling_notes` `:204` | a CST pass that reads the written token (P3); the `Spelling` set `spelling.rs` stays |
| statement boundary (a statement ends at its line) | `end_of_statement`, `parse.rs:961` | the primary recovery point (P4) |
| `ParseError` with span, line, column | `parse.rs:65` | the payload of each `ERROR` node (P4) |
| the per-thread parse cache and counter | `RECENT`, `parse.rs:196-200`; `parses_on_this_thread` `:118` | keyed the same way; caches `Parse` (P2) |
| prefix totality and span nesting gates | `crates/blue-lang-syntax/tests/totality.rs:241`, `:457` | extended to the CST (P2, P4) |
| the prefix agreement rules, including "tolerance" | `crates/blue-lang-kiwari/src/agree.rs:14`, `:66` | the definition P4's recovery must meet, now on blue's own parser |
| comment placement by span, unplaceable-comment refusal | `crates/blue-lang-fmt/src/lib.rs:172`, `:184`, `:275-365`, `:134` | the renderer reads comments off CST tokens; the refusal stays (P6) |
| hidden comments inside `#{}` | `fmt/src/lib.rs:228` | real tokens under an `interpolation` node (P2) |
| B0006 `syntax-error` row, witness `def f(\n` | `crates/blue-lang-check/src/rules.rs:280` | the code every hole reports (P5) |
| syntax error as a B0006 diagnostic | `crates/blue-lang-runtime/src/pipeline.rs:1371` | one per `ERROR` node, not one per file (P5) |
| lowered-name ownership and its gate | `LOWERED_HEADS` `parse.rs:546`; `no_lowered_name_is_shadowed_by_the_runtime` `crates/blue-lang-test/src/lib.rs:890` | `blue-hole` joins the list; the gate covers it (P5) |
| the LSP early return on a parse error | `crates/blue-lang-lsp/src/analysis.rs:297-315` | goes; diagnostics come from holes (P6) |
| the LSP token painter re-lexes | `crates/blue-lang-lsp/src/tokens.rs:182` | reads CST tokens (P6) |
| mondou's parse query and `last_good` fallback | `crates/blue-lang-mondou/src/lib.rs:54`, `:204`, `:259` | the query returns `Parse`; `last_good` narrows to one definition (P6) |
| runtime message rewrite by call span | `crates/blue-lang-runtime/src/messages.rs:18` (`describe`), `call_at` | reads the blame table (P7) |
| `Fault` (message, place, stack) | `crates/blue-lang-runtime/src/observe.rs:381` | its place becomes the surface anchor (P7) |
| rowan 0.16.1, already locked | `Cargo.toml:45`; `crates/blue-lang-runtime/Cargo.toml:39`; used in `crates/blue-lang-runtime/src/nix.rs:4` through rnix | the green/red tree under `blue-lang-syntax::cst` (P1) |

**Fleet recon (2026-10-24, `rg --no-ignore` over `pleme-io`).** rowan is a
dependency of blue (above), of `sui` (`sui/Cargo.toml:348`, for `sui-lsp` and
`sui-fmt`), and of rnix. `sui-fmt` is the near-miss precedent: a canonical
formatter over a lossless rowan CST, with the same no-knob rule
(`sui/sui-fmt/src/lib.rs:1-27`). tree-sitter's C runtime is a test seam in
`blue-lang-kiwari/src/ts.rs` and is never a production parser here
(NATURALIZE §1 refuses the C). No crate in the fleet has a blue CST. `kiwari`
is the right source of the CST shape: it already names every node kind, it
already lowers a CST to blue's tree, and its differential already proves its
shape matches blue's parser on 1,247,315 prefixes (NATURALIZE §6, measured
2026-10-10).

---

## 3. Shape

### 3.1 Green/red tree: rowan, behind a blue-owned surface

**Decided: rowan, not in-house.** Reasons:

1. It is already in `Cargo.lock` (0.16.1) and already compiled into
   `blue-lang-runtime`. It adds no crate.
2. It is pure Rust. CONTAIN THE C does not apply.
3. Green nodes are immutable, shared and `Hash + Eq`. That is the
   content-addressed subtree key that NATURALIZE §4 and M4 (`kizami`) ask
   for.
4. An in-house green tree rebuilds a near-miss that the house already uses
   twice (Operating Principle 1).

**The surface is blue's.** `blue_lang_syntax::cst` exports `SyntaxKind`,
`Node`, `Token`, `Parse`, `NodeId`. No public signature names a rowan type.
A gate reads `cargo metadata` and fails when a crate other than
`blue-lang-syntax` (and rnix's own users) depends on rowan. So `kizami` can
replace rowan later, and no consumer changes.

### 3.2 Node kinds: one table

`SyntaxKind` is a generated file:
`generate("cst-kinds", "crates/blue-lang-syntax/src/cst/kinds.rs", "gen/kiwari/kinds.b")`
in the root `Bluefile`, with `checks.generated-cst-kinds-fresh`. It reads
`kiwari::blue()`:

| group | from | count today |
|---|---|---|
| named nodes | the spec's rules with a lowering template | 47 |
| operator tokens | `infix_rows` (one kind per row; an alias such as `≠` is the same kind, and the token text keeps the alias) | 13 |
| prefix operator tokens | `unary_rows` | 2 |
| keyword tokens | `reserved.surface` + `reserved.block` | 21 |
| punctuation tokens | `punctuation` | 18 |
| literal and name tokens | `identifier`, `integer`, `float`, `string`, `symbol`, `label` rules | 6 |
| trivia | `Whitespace`, `Newline`, `Comment` | 3 |
| recovery | `ERROR` (node), `MISSING` (zero-width token) | 2 |

**Gates (P1).** Every key of the spec's `lower` map has a kind, and every
named kind has a key. Every `INFIX` row has an operator kind. Every named kind
is covered by at least one `FORMS` row, `INFIX` row or keyword, and each
`FORMS` example parses to a statement of the kind its row names. A missing row
is red, as `every_form_lowers_as_its_row_says` (`forms.rs:185`) is red today.

**Measured gap.** `kiwari` has no rule for `@doc` and `@moduledoc`
(`grep` finds none in `tree-sitter-blue/grammar.js`; `crates/blue-lang-syntax/src/doc.rs`
lowers them). P1 adds a `documentation` rule to `kiwari` first, with its
template. Verify how the differential handles these files before P1.

### 3.3 Tokens and trivia

`lex_lossless(src) -> Vec<Token>` is total. A gap between two tokens is a
`Whitespace` token. A bad byte is an `ERROR` token, and the lexer resumes on
the next line. An unterminated string or heredoc ends at the end of its line,
as an `ERROR` token. The concatenated token text is `src`. `lex` becomes
`lex_lossless` without whitespace, with the first `ERROR` token as its `Err`.
So `lex` has one implementation.

Trivia attaches to the token that follows it (rowan's convention). A trailing
comment on a code line attaches to the `Newline` that ends that line. That is
the `own_line` distinction `Comment` already records (`parse.rs:329`), now a
fact of the tree.

Interpolation: the lexer today stores `#{…}` code as separate strings
(`InterpolatedStr { exprs }`). In the CST, an `interpolation` node holds the
real tokens of that code, rebased to file offsets. So a comment inside `#{}`
is a real token, and `hidden_comments` (`fmt/src/lib.rs:228`) is a CST query.

Yakugo (`yakugo.rs`) maps words between lexing and parsing. The CST keeps the
written text in the token and the canonical meaning in the kind.

### 3.4 Recovery points and `ERROR` nodes

One parser. The recovery is in the hand-written productions now, and in the
emitted ones after M3. The recovery sets come from the spec:

| context | recover at | why |
|---|---|---|
| top level | the next `Newline` whose next token starts a statement at column 0 | a statement ends at its line (`parse.rs:961`, commit `9b3d847`) |
| a body | `end`, and the block keywords that continue it (`else`, `elsif`, `when`, `rescue`, `ensure`) | the `closers` and block keywords in `kiwari` |
| an argument list, list, map | `,` and the matching closer | the punctuation rows |

Two rules make recovery predictable:

1. **Skip, do not guess.** The tokens from the failure to the recovery point
   go into one `ERROR` node. It carries the `ParseError` that the
   production raised.
2. **Close with `MISSING`.** When a closer (`)`, `]`, `}`, `end`) is absent, the
   parser inserts a zero-width `MISSING` token, and the open node closes.
   This is tree-sitter's model. The agreement test already speaks it
   (`agree.rs`).

The depth bound stays. `MAX_EXPR_DEPTH` (`parse.rs:742`) still refuses deep
input. The refusal is now an `ERROR` node, not an abort.

### 3.5 How a broken tree lowers

An `ERROR` node lowers to `(blue-hole "B0006" "<message>")` at the node's
span. `blue-hole` is a lowered name owned by the parser, in `LOWERED_HEADS`.
No source can spell it: a hyphen cannot occur in a blue identifier. No
runtime binds it, and `no_lowered_name_is_shadowed_by_the_runtime` proves
that. This is BLUE-ENGINE §5.1's spelling.

`parse_cst(src).lower()` returns `Parsed<WithHoles>` or `Parsed<Complete>`.
Only `Parsed<Complete>` converts into what `pipeline` accepts. The editor
path takes either. The check stage reports B0006 once per hole, at its span.
It checks every top-level form without a hole. In a form with a hole, it
drops each diagnostic whose span overlaps the hole or whose cause is a name
the hole would bind. The explicit surface hole for agents (BLUE-ENGINE §8,
decision 2) is out of scope. A recovery hole needs no spelling.

### 3.6 Blame: how the lowering carries the CST node into the tree

`Spanned` is tatara-lisp's type (`span`, `form`), and `Span` is `{start, end}`.
`Sexp` carries no position. This plan changes neither (open decision 1).

The lowering records a side table, `Blame`, beside the tree it emits. For each
emitted node it records `(span, shape) -> Origin { node: NodeId, anchor: Span }`.
`NodeId` is the CST node's kind and text range, which is stable within one
revision. `shape` is atom or list, so a list and its head atom never collide.
The span in `Spanned` stays exactly what the parser emits today: the callee of
`a + b` takes the operator's span (`parse.rs:1249-1258`), and `define` in
`x = 5` takes the name's span.

A consumer that holds an evaluator span asks `Blame` for the origin, then asks
the CST for the surface token. `describe` (`messages.rs:18`) already finds the
call by its span; it gains the origin. So
`x = "a" % 2` stops reporting `m.b:1:5: type mismatch: expected integer, got
string` (measured 2026-10-24, `blue` 0.0.111 on PATH: the position is the
operand, and `%` is not named) and reports the operator at `1:9`, by name.

**Injectivity gate.** Over the corpus, no two emissions share
`(span, shape)` with different origins. If one does, the gate names the
template, and the template anchors differently. If no anchor can separate
them, open decision 1 reopens with a measured case.

---

## 4. Phases

Each phase lands on `main` alone. No phase changes `Sexp`, a span in
`Spanned`, a `def_hash` or a formatted byte, except P5 and P6, which change
only inputs that do not parse today. Each gate reads the artifact, not the
thing it came from.

**Standing gates, green after every phase:** `blue-lang-syntax/tests/totality.rs`
(incl. `depth_beyond_the_limit_is_an_err_not_an_abort`,
`every_node_sits_inside_its_parents_span`), `tests/property.rs`,
`tests/runs_on_tatara.rs`, `forms.rs` `every_form_lowers_as_its_row_says`;
`blue-lang-fmt` `corpus.rs`, `laws.rs`, `every_form.rs`, `comment_sweep.rs`,
`regressions.rs`, `totality.rs`; `blue-lang-kiwari` `differential.rs` and
`spec.rs`; `blue-lang-runtime/tests/rules.rs`
`every_rule_fires_on_its_witness_and_only_it`; `blue-lang-test`
`no_lowered_name_is_shadowed_by_the_runtime`; `blue-lang-lsp/tests/engine_session.rs`
`one_parse_per_revision`; `checks.conformance`; `blue-lang-pkg` `distribution`
ratchets; the pre-push hook (`gen/prepush.b`).

**Identity snapshot, taken before P2.** A generated file,
`generate("def-hash-snapshot", "spec/identity/def-hashes.tsv", "gen/def-hash-snapshot.b")`,
lists every corpus definition's key and `def_hash`, plus the BLAKE3 of each
file's `blue ast --json`. P2, P3 and P4 must leave it byte-identical. It is
the one gate that says the CST did not move identity.

| # | phase | delivers | gate (red run first) | depends on |
|---|---|---|---|---|
| **P0** | lossless lexing | `lex_lossless` (total); `lex` as its projection | concat of token text == `src` on every corpus file, every prefix and 20,000 proptest strings. Red run: drop one whitespace gap; the gate fails | none |
| **P1** | kinds from `kiwari` | `cst/kinds.rs` generated; rowan `Language` impl and the blue-owned surface; `documentation` rule in `kiwari`; `INFIX` and keyword lists rendered from `kiwari` (open decision 2) | the §3.2 gates; generated-fresh check; the rowan-confinement gate. Red runs: delete a `FORMS` row; add a `kiwari` rule without a template | P0 |
| **P2** | CST beside the tree | the parser drives a `GreenNodeBuilder` with checkpoints (Pratt wrap) while it still builds `Spanned` as today; `parse_cst` for inputs that parse; `Parse` caches in `RECENT` | (a) `cst.text() == src`, byte-exact, corpus and every parsing prefix; (b) each child range inside its parent and children tile the parent; (c) blue's CST and tree-sitter's CST agree kind for kind (a new `Disagreement::Shape` in `agree.rs`); (d) `Lowerer` over blue's CST equals `parse_program_tree` as `Sexp`; (e) corpus parse time at most 1.3x today, measured. Red runs: skip one comment token; nest one kind wrong | P1 |
| **P3** | one lowering | `Spanned` is `lower(cst)`; each inline lowering moves into its `kiwari` template with a span anchor; spelling notes become a CST pass; `Blame` is recorded | `Spanned` identical, every span included, on the corpus, every `FORMS` example and the `every_form` generated programs; the identity snapshot unchanged; `spelling_notes` identical on the corpus. Red run: move one anchor (`define` to the value's span); the gate names the file and node | P2 |
| **P4** | recovery | `parse_cst` is total; `ERROR` and `MISSING`; the §3.4 recovery sets; `parse_program*` keep their `Result` (the first `ERROR` is the `Err`, same message, same span) | never panics, never fails, text round-trips: every prefix and proptest garbage; the agreement "tolerance" property now on blue's own parser: every statement closed before the cut is an error-free node meaning blue's form; the E6 fixture (one broken statement between two good `def`s yields both). Red run: disable the top-level recovery; the E6 fixture fails | P2 |
| **P5** | holes and the typed door | `ERROR` lowers to `blue-hole`; `Parsed<Complete>` and `Parsed<WithHoles>`; one B0006 per hole; diagnostics around a hole suppressed by span | a `compile_fail` doctest: `pipeline::run` with `Parsed<WithHoles>`; B0006's witness still fires exactly B0006; `blue-hole` is in `LOWERED_HEADS` and the shadow gate; a `spec/rows` row for "a hole is refused by name, its siblings are checked". Red run: bind `blue-hole` in a test interpreter; the shadow gate fails | P3, P4 |
| **P6** | consumers on the CST | the formatter reads comments off CST tokens; the LSP reports diagnostics from holes and paints from CST tokens; mondou's parse query returns `Parse`; `last_good` narrows to a definition | every formatter test unchanged; a new law: the output CST's comment texts, in order, equal the input's, on the corpus; the E6 milestone gate (completion works inside the second `def`); `one_parse_per_revision` still 1. Red run: drop one comment in the renderer; the law fails | P5 (LSP part); P2 (formatter part) |
| **P7** | surface blame | `describe` and `Fault` read `Blame`; B0004 (operand type) names the surface operator; `blue run --format json` gains the surface anchor | a matrix test with one row per lowering link (each `INFIX` row, each unary row, `\|>`, nil test, interpolation, map literal, `assert`, `rescue`): a program that raises inside the lowered callee reports the surface spelling at a position inside the surface node; the matrix fails when a template lands without a row; the injectivity gate. Red run: blank one row's anchor; its row fails | P3 |

P2's dual output is the bridge to M3. After P3 the hand-written productions
only shape the CST. M3 then replaces them with productions emitted from
`kiwari`, and nothing downstream changes, because the CST type, the kinds and
the lowering are already the spec's.

---

## 5. Risks, and what canonical identity needs

**Canonical identity (`theory/BLUE.md` §V.16.1; `crates/blue-lang-mondou/src/def_hash.rs:1-20`).**
`def_hash` hashes the resolved lowered tree. It ignores spans, comments and
layout. Four rules keep it stable:

1. The CST is never an identity. It holds trivia, so two programs that differ
   in one comment have different CSTs and the same identity. A green-node
   hash may key a CACHE (`kizami`, the mondou memo). It never keys an
   identity.
2. The lowering is a pure function of the CST's non-trivia tokens. A gate
   proves it: strip every trivia token from a corpus CST, lower, compare.
3. A definition with a hole has no `def_hash`. `HashedDef` is built from
   `Parsed<Complete>` only. A hole is not content.
4. The identity snapshot (§4) is byte-identical across P2 to P4.

**Other risks:**

| risk | what it costs | mitigation |
|---|---|---|
| the builder adds stack per parser frame | the boxed-error depth margin (overflow measured at 300-310 levels, `parse.rs:744-757`) shrinks | rerun `depth_beyond_the_limit_is_an_err_not_an_abort` on a 2 MiB debug thread in P2; keep the builder off the recursion's stack frames (it lives in `Parser`) |
| P2 slows every door | three parses per keystroke were the LSP's cost before E2 | gate (e): 1.3x on the corpus; `RECENT` caches `Parse` |
| recovery cascades into the check stage | the reason the LSP suppressed everything (`analysis.rs:278-292`) | §3.5: suppression by hole span; the E6 fixture counts diagnostics |
| two parsers until M3 | drift between parse.rs and tree-sitter | gate (c) in P2 compares CST shape, a stronger check than the tree compare |
| the differential skips without the tree-sitter runtime (`differential.rs:46`: `let Some(rt) = runtime() else { return }`) | a green step that did nothing | run gate (c) in the nix check, where the runtime is present; assert the file count, as `differential.rs:49` does |
| `@doc` has no `kiwari` rule | P1 kinds miss a node | P1 adds the rule first |
| rnix bumps rowan | a version split | the confinement gate; one module changes |
| `kizami` replaces rowan later | churn | the blue-owned surface; no rowan type is public |

---

## 6. Open decisions for the operator

1. **The blame carrier.** (a) A side table keyed by `(span, shape)`, with no
   upstream change; or (b) an `origin` field on tatara-lisp's `Spanned`, a
   minor release of tatara-lisp and a bump in blue.
   **Recommendation: (a).** The parser already gives each synthesized node a
   distinct anchor (`parse.rs:1249-1258`). The injectivity gate measures
   whether that holds. Take (b) only if the gate finds a collision that no
   anchor can separate.
2. **Where the operator and keyword tables live.** (a) In `kiwari`, with
   `INFIX` and the keyword lists rendered from it in P1 (each `doc` line moves
   into its `kiwari` row); or (b) both copies stay, held equal by
   `blue-lang-kiwari/tests/spec.rs`, until M3.
   **Recommendation: (a).** NATURALIZE §2 names `kiwari` the one spec, and the
   CST kinds come from it. (b) keeps two tables that a test holds equal, which
   is the drift class this plan removes.
3. **Formatting a buffer with holes.** (a) The formatter refuses it, and the
   LSP returns no edit; or (b) it formats every complete top-level form and
   leaves each `ERROR` region as written.
   **Recommendation: (a).** FORM (`theory/BLUE.md` §0) gives a program one
   rendering. A half-formatted file has no canonical form, and canonical
   admission (`crates/blue-lang-pkg/src/canonical.rs:100`) already refuses a
   file that does not parse. (b) can come later as a configured-off
   behaviour, if editors ask for it.
