# naturalize(tree-sitter) — the destination, before the build

**Status: DESIGN. Nothing here is implemented.** Do not cite any of it as
existing. This is `/naturalize` step 1–3 (essence, recon, name) written down so
the build has a destination to walk toward rather than a next deliverable to
chase.

---

## 1. The essence of tree-sitter — what we want, and what we refuse

tree-sitter owns one problem genuinely well: **incremental, error-tolerant
parsing of a buffer that is being edited.** Its good ideas, worth taking:

| Idea | Why it matters | Take? |
|---|---|---|
| **Incremental reparse** — an edit reparses the changed subtree, not the file | the property that makes editor tooling feel instant on a large file | **take** |
| **Error tolerance** — a syntactically broken buffer still yields a usable tree | an editor's buffer is *always* mid-edit; a parser that returns `Err` gives an editor nothing to highlight | **take** |
| **A concrete syntax tree** — every token, including whitespace and comments | lossless formatting, precise ranges, comment-preserving refactors | **take** |
| **Queries as data** (`.scm` s-expression patterns) | highlighting and folds become declarative, not code | **take — and note it is already a Lisp** |
| **Grammar as an independent artifact** (`grammar.js`) | portability across editors | **REFUSE — see §2** |
| **A generated C parser + C runtime** | speed, embeddability | **refuse the C; keep the goal** |

The refusals are the load-bearing part. Taking tree-sitter's *implementation*
would be a wrap, and a wrap is a guest. We want the capability as substrate.

---

## 2. The one architectural fact that decides everything

**Blue already has a parser.** `blue-lang-syntax::parse_program` is hand-written,
produces `Sexp`, and is the only definition of blue's syntax that exists.

The conventional move — hand-author a `grammar.js`, run `tree-sitter generate`,
ship the artifact — creates a **second, independent definition of blue's
grammar**. Two parsers, two authors, no mechanism keeping them equal. They drift
the first time either changes, and the drift is invisible: the editor highlights
one language while the compiler compiles another.

That is precisely the failure this repo just lived through in miniature. A
reserved word was accepted as a method name by the parser and re-emitted by the
formatter as something the parser rejected — two components disagreeing about
one grammar, silent until a round-trip property looked. That was *one* codebase
with *one* parser. Adding a second parser makes that class structural.

So the destination is not "blue gets a tree-sitter grammar". It is:

> **ONE typed grammar spec. Blue's parser and the tree-sitter grammar are both
> EMITTED from it, so disagreement between them has no representation.**

This is the fleet's ★★ EMITTER SUBSTRATE and "solve once, in one place" applied
to the thing a language most often duplicates. It is also the only version of
this work that compounds: a third consumer of the grammar (an LSP semantic
tokenizer, a syntax-highlighting web widget, a `blue fmt` that is generated
rather than hand-tracked) is then a new renderer, not a new parser.

---

## 3. The shape

```
                  (defgramatica blue …)          <- ONE authored spec, tatara-lisp
                          │
              ┌───────────┼────────────┬─────────────────┐
              ▼           ▼            ▼                 ▼
        Rust parser   grammar.js   highlight .scm    docs / railroad
        (the truth    (editors     (queries are      (generated, so the
         today)        that want    already Lisp —    manual cannot lie
                       upstream)    emit, don't       about the syntax)
                                    hand-write)
```

**The gate that makes it real:** a differential test asserting the emitted
tree-sitter parser and blue's own parser agree on every file in `spec/` and
`bidamas/` — and on every *prefix* of every file, since the totality suites
already established that a prefix models a mid-edit buffer. Grammar drift
becomes a red build rather than a bug report from someone whose editor looked
wrong.

---

## 4. "Optimize it ourselves in Rust" — where the performance work actually is

tree-sitter's runtime is C. The naturalized replacement is a Rust incremental
parsing engine, and this repo has already measured where the wins are:

- **Fork a warm prototype rather than rebuild.** The 48× interpreter win came
  from `LazyLock` + `fork()` of a prepared base instead of constructing a fresh
  environment per run. An incremental parser wants the same shape: a persistent
  parse state that an edit *forks*, not a table rebuilt per keystroke.
- **Content-addressed memoisation.** The fleet already hashes everything
  (BLAKE3). A subtree keyed by the hash of its source span is reusable across
  *files* and across *sessions*, which tree-sitter does not attempt — its reuse
  is within one buffer's edit history. This is the genuinely differentiated
  move, and it is available because the surrounding infrastructure exists.
- **Purgatory (BLUE.md §V.11)** — the generational nursery — is the natural home
  for short-lived parse nodes produced while typing and discarded on the next
  keystroke.

Sequence matters: **do not start here.** Optimising a parser that has no second
consumer is optimising a benchmark. The engine work earns its keep only once the
emitted grammar exists and something depends on the incremental path.

---

## 5. Names — RATIFIED (`/naming`, 2026-08-01)

**The grammar spec is `kiwari` (木割).** The earlier proposal `kōshi` (格子) was
**rejected**, and the reason is worth keeping: 格子 glosses to *lattice*, and
blue already has one — `waku`'s order-theoretic posture lattice, 22 live uses,
already indexed in `blue/CLAUDE.md` as "REACH/WHEN/WHERE frame **lattice**". A
second primitive glossing to the same word does not merely fail to teach, it
routes the reader to the wrong crate. A Japanese speaker separates 格子
(grid-lattice) from 束 (order-lattice); our readers get romaji plus an English
gloss, where they are one word. Law 2 failed independently too — nobody guesses
"the one grammar spec that emits parser, grammar.js, queries and docs" from
"latticework", and the defence offered ("the part of a window that gives shape
to what is otherwise a hole") was a post-hoc simile, which is itself the tell.

**木割** is the proportioning rule-book of Japanese traditional carpentry (the
*kiwari-sho* manuals, e.g. *Shōmei*, 1608): the codified system from which every
member's dimensions derive from one base module, so no two pieces of the
building can disagree. It teaches both halves this primitive needs — the
codified rules of the thing (grammar), and one source with nothing able to drift
(the whole reason it exists). Zero fleet collisions.

Two cautions, recorded rather than discovered later: the naive morpheme read is
"wood-splitting", so the architectural sense must be glossed at first use; and
`kiwari` rhymes with `hikari` (光), the fleet's live syntax-highlight vocabulary,
whose territory M2 touches. Different initial consonant, no shared morpheme — a
caution, not a collision. **This also widens blue's family**: the lineage is the
Japanese wooden house (`genkan`, `kannuki`, `oshiire`, `sumika`, `todojimari`,
`waku`), not the window alone.

**The incremental parse engine is `kizami` (刻み)** — *a notch; an increment or
step* (5分刻み = in five-minute increments; 刻む = to carve, to notch). The
literal meaning states the defining property: it re-cuts only the notch an edit
touched and leaves the rest of the board standing. It joins the Craft/Making
family (匠) with `tatara`, `takumi`, `shikumi`, `forja` — deliberately NOT
blue's house lineage, because the engine is fleet substrate consumed outside
blue. Zero fleet collisions; the kanji 刻 appears nowhere in the fleet.
crates.io availability is unchecked — a publishability question to settle before
M4, not a naming defect.

---

## 6. Honest ordering

| Milestone | Deliverable | Gate |
|---|---|---|
| **M0** | `(defgramatica …)` spec covering blue's *current* surface, hand-checked against `parse.rs` | the spec round-trips every file in `spec/` and `bidamas/` |
| **M1** | Emit `grammar.js` from the spec; ship a real tree-sitter grammar | differential vs blue's parser over every file AND every prefix |
| **M2** | Emit highlight/fold/indent queries; wire into blackmatter-nvim | an operator sees blue highlighted from the generated artifact |
| **M3** | Emit blue's own parser from the spec, retiring the hand-written one | byte-identical `Sexp` on the whole corpus before the old parser is deleted |
| **M4** | `kizami` — Rust incremental engine + content-addressed subtree memo | measured against the C runtime on a real buffer, not a microbenchmark |

**M3 is the one that makes the whole thing true**, and it is the one most
tempting to skip: at M1 you already have a working editor grammar, and the
second parser is exactly the drift this design exists to prevent. Until M3
lands, the differential gate is the *only* thing holding the two in agreement —
so it is not optional scaffolding, it is the load-bearing part of M1 and M2.

---

## 7. Separately: "world-class syntax"

Measured gaps in blue's surface today, none of which block the above:

- **No brace blocks / trailing-block calls.** `xs.map { |x| x * 2 }` does not
  parse. `fn(x) … end` works and the HOFs work, so this is ergonomics, not
  capability — a correction to an earlier claim in
  `docs/COMPETING-LANGUAGES.md` §3.
- **Argument order is lisp-native**, not receiver-first: `map(f, xs)`, and
  `join(list, sep)` while `split(s, sep)`. Defensible, but inconsistent between
  siblings, which is the kind of thing a grammar spec makes visible.
- **Kebab-case and `?`/`!` suffixed names are unreachable** from blue's lexer,
  so a chunk of the underlying tatara-lisp stdlib (`every?`, `sort-by`,
  `string-length`) cannot be called at all. `junjo` reimplements `sort` for
  exactly this reason.
- **`nil` and `[]` are distinguishable** and `length(nil)` errors, which
  `retsu`'s total `size`/`first`/`rest` currently paper over at the library
  layer rather than fixing at the cause.

Each is a candidate for the syntax pass; each should be decided *in the grammar
spec*, so the decision lands in every emitted artifact at once instead of in a
parser and then, months later, in a grammar.
