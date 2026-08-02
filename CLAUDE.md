# blue — Claude Orientation

pending-shikumi: M2 — execution budget has no default constant; will type when
one lands. Everything else is closed: `BlueConfig`
(`crates/blue-lang-cli/src/config.rs`) implements `shikumi::TieredConfig` with
the two bounds that *do* have shipped overridable defaults, `flake.nix` carries
the module trio that deploys them, and `blue config <tier>` is the operator
surface.

The M1 waiver this replaces claimed three knobs were "blocked on an unsettled
design". Measured 2026-08-01, two of the three were not blocked — they were
**settled against being configurable**, which is a stronger statement and was
worth correcting rather than carrying:

- **Formatter width** — settled AGAINST. `blue-lang-fmt`'s module docs already
  said so: "There is no configuration type in this crate, and that is the
  feature… there is nowhere to put a knob." Typing it would forfeit §0 (one way
  to write a thing) and the content-addressed identity §V.16.1 rests on. It is
  a regression, not pending work.
- **Posture ceiling** — settled elsewhere. §V.24 moved ceilings to the ROOT as
  a Bluefile input; `blue_lang_waku::Waku` deliberately carries none and
  `blue_lang_bidama::resolve(bidama, ceiling)` takes it as an argument. A
  daemon knob would rebuild the anti-pattern §V.24 removed.
- **Execution budget** — genuinely open, for a concrete reason rather than a
  philosophical one: **no default constant exists in blue to expose**. `Budget`
  matches zero lines in `blue-lang-runtime`, `-test` and `-cli`. This is the
  whole of M2.

**The admission rule, which is what makes the surface safe to have shipped:** a
knob may live in `BlueConfig` only if it is a **BOUND, never a preference**.
Raising `solver_max_steps` or `max_expr_depth` changes no program's meaning —
only whether a pathological input is refused — so neither can freeze a design
guess as a public interface, which was the M1 objection. A preference would.
Both are also read for real (`blue deps` → `Solver::with_max_steps`, every
parsing subcommand → `parse_with_depth`), each with a red run recorded in the
test that proves it.

pending-tela: not a frontend. No `pending-urdume:` — blue is a language
workspace, not a Rust service.

> **★★★ CSE / Knowable Construction.** This repo operates under
> **Constructive Substrate Engineering** — canonical spec at
> [`pleme-io/theory/CONSTRUCTIVE-SUBSTRATE-ENGINEERING.md`](https://github.com/pleme-io/theory/blob/main/CONSTRUCTIVE-SUBSTRATE-ENGINEERING.md).
> **The design is canonical in [`theory/BLUE.md`](https://github.com/pleme-io/theory/blob/main/BLUE.md)
> — read it before non-trivial changes, and do not restate it here.**

A general-purpose language: a Ruby/Elixir surface, a tatara-lisp AST, macros
as term rewriting on that AST, and a Rust runtime. Crates are `blue-lang-*`
(bare `blue` is squatted on crates.io); source extension is `.b`.

## The pipeline is the architecture

**parse → check → erase → run.** The order is load-bearing and lives in
`blue-lang-runtime::pipeline`, not in each caller, because two of the four
orderings are silently wrong: *erase before check* turns the type checker off,
and *run before check* reports a type error after the side effects. Neither
fails loudly; both produce a green run on a program that should be rejected.

**Ask the pipeline for a result, never assemble the stages yourself.** A
caller that re-implements the order is one reordering away from disabling the
checker.

## Where to look

| Intent | Crate |
|---|---|
| lexer + Pratt parser → `Sexp`; the `INFIX` table | `blue-lang-syntax` |
| the one formatting (Wadler/Oppen) | `blue-lang-fmt` |
| sliding-scale typing; `Seam`; `Stats` | `blue-lang-check` |
| REACH/WHEN/WHERE frame lattice | `blue-lang-waku` |
| package posture floors + resolution | `blue-lang-bidama` |
| processes, supervision, mailboxes, isolation | `blue-lang-proc` |
| interpreter construction, erasure, pipeline | `blue-lang-runtime` |
| `test`/`assert` runner | `blue-lang-test` |
| Bluefile + version solver | `blue-lang-pkg` |
| the WASM surface (zero host imports) | `blue-lang-wasm` |
| LSP: transport-free core + stdio shim | `blue-lang-lsp` |
| the mark, wordmark, Nord theme | `blue-lang-art` |
| every subcommand; `BlueConfig` (the two typed bounds) | `blue-lang-cli` |

## Rules this repo has learned the hard way

Each of these is a defect that shipped, not a style preference.

- **`INFIX` is one table, and both directions read it.** Precedence and
  lowering used to live apart, so `==`, `!=`, `&&`, `||` and `%` had a
  precedence and no callee: `a == b` lowered to `(== a b)`, a symbol nothing
  binds, and died at runtime. The formatter kept a third copy labelled "must
  agree with the parser's table", and it did not. **Adding an operator means
  adding one row.**
- **The runtime has two layers and both are required.** `install_primitives`
  is not enough — the Lisp stdlib holds `mod`, `first`, `inc`, and more.
  Three crates each hand-rolled `Interpreter::new()` and all three omitted
  it. **Use `blue_lang_runtime::interpreter`.**
- **A parking primitive must not consume.** `receive` is registered through
  `register_awaitable_fn`, whose readiness phase holds `&System` — so
  take-then-park does not typecheck. Do not move it back to a one-phase
  primitive to "simplify" it; the compile error is the feature.
- **A restart empties the mailbox.** In-flight messages were addressed to the
  incarnation that died. Replaying them is how a poison message kills a
  process forever.
- **Restart intensity is checked on the child that exited**, not on siblings a
  strategy sweeps up. A sibling restarted as collateral has not misbehaved.
- **A formatter law passing is not the formatter being right.** All three laws
  held while every call rendered as a method send — `fact(n - 1)` printed as
  `(n - 1).fact`. A round-trip law measures the tree, never the readability.
  **When you change rendering, read the output.**
- **A corpus is only as strong as what is in it.** The annotated-`def`
  rendering bug survived because the formatter corpus contained no annotated
  defs. Add the case with the rule. `SURFACE_KEYWORDS` now makes the *omission*
  the failure — adding a keyword forces the corpus entry.
- **A name blue lowers to must not be one tatara already binds.** `assert e`
  lowered to `(assert 'e e)`; the stdlib binds `assert` as a macro, a macro beats
  a primitive, and **every assertion in every test silently passed**. Lowered
  names live in the parser (`LOWERED_ASSERT`) and
  `no_lowered_name_is_shadowed_by_the_runtime` gates the class.
- **Comments are not in the tree, and must not be lost.** They carry no meaning,
  so putting them in the `Sexp` would break canonicality. `fmt --write` deleted
  every one until the formatter learned to re-interleave them by position against
  each form's recorded span. A comment *inside* a form is refused, not moved.
- **Call the COMPOSED substrate installer, never the layers by name.** blue
  called `install_primitives` + `install_lisp_stdlib_with` and got neither
  `install_hof` nor `install_map` — so `map`, `filter`, `fold` and every `{...}`
  literal were unbound. Use `install_full_stdlib_with`. This is the same defect
  as the stdlib gap that created `blue-lang-runtime`; naming layers one at a
  time *is* the bug.
- **A lowered name is either OWNED or DELEGATED, and the two invariants are
  opposite.** `blue-assert` must NOT be bound by the runtime; `hash-map` must
  BE bound. One gate conflated them and flagged a correct delegation as a bug.
  Neither gate catches a wrong-but-*bound* name — `map` was bound, to the HOF
  instead of the constructor — so a delegated name also needs an end-to-end test.
- **`==` is `equal?`, not `=`.** tatara's `=` is numeric-only, so lowering `==`
  to it made every string/list/nil comparison a type error. The
  operator-coverage gate could not see it: it resolves callees with numeric
  operands, proving the callee is bound and nothing about the other classes.
- **A round-trip law measures the tree, never the readability** — now with a
  third citation. `x = 5` rendered as `define(x, 5)` and interpolation as
  `concat(concat("a", x), "")`; both re-parse to the same tree, so all three
  laws passed while `fmt --write` silently rewrote real files. **Ship the
  formatter arm WITH the surface form, and read the output.**
- **Isolation is the SEAL, not the rebuild.** The test runner and the process
  supervisor both threw an interpreter away per child to get isolation, at
  ~945µs each — essentially the entire cost of running a test, spent
  re-evaluating the stdlib to reach an identical state. `Interpreter::fork`
  shares the evaluated globals and seals them: a child's `define`s land in a
  private frame, and a `set!` reaching an inherited binding raises `SetSealed`.
  Same guarantee, 29µs. **Use `blue_lang_proc::forking` for `spawn`**, never a
  factory that rebuilds. A plain `Clone` is NOT a fork — `Env::set` writes
  through the `Arc`.
- **A name has three arbiters, and an environment lookup sees one.** Special
  forms are `match` arms in no environment; a macro rewrites before evaluation
  and beats a same-named binding. `assert` was lost to the second, and the
  replacement gate was still blind to the first while blue lowers to `not`. Ask
  `Interpreter::resolve_head`, which answers *which* arbiter claims the name.
- **Two doors to the formatter is one door too many.** `fmt --write` learned to
  re-interleave comments; the LSP kept calling `format_forms`, so
  `textDocument/formatting` returned 707 bytes for 1010 and **deleted all six
  comments in the buffer**. Everything that shows a user their own file goes
  through `format_source_lossless`; `format_source` is for comparing trees.
- **The mark is a COLOUR shift, and its direction is meaning.** Four solid `█`
  across Nord's Frost band (`BrightCyan → Cyan → BrightBlue → Blue`), named by
  ANSI slot so it tracks the reader's theme. The first version was `░▒▓█` — a
  *density* ramp in one flat colour — which shipped and read as a blue box. It
  was wrong twice: a shift with nothing shifting, and dither glyphs katsuji's own
  docs warn "read as fuzz at cell size". **Quoting a warning and arguing past it
  is not clearing it.** Theme colours are `irodori` lookups; blue carries no hex,
  and a test enforces it.

## Testing discipline

Every gate here has a **red run**: the test was shown to fail on a
deliberately broken input before being trusted. Two specific traps this repo
hit:

- **A gate derived from the thing it checks is a tautology.** Compare against
  independent evidence — emitted bytecode, a real interpreter resolving a
  symbol, a counted call — not against the predicate under test.
- **A break attempt that is semantically equivalent proves nothing.** One
  "proof" here stayed green because the mutation could not actually violate
  the property. If the red run does not go red, the mutation is wrong or the
  gate is vacuous; find out which.

## Dependencies

`tatara-lisp` and `tatara-lisp-eval` are **git deps pinned by rev**, not path
deps. A path dep outside the repo cannot resolve in a Nix sandbox, where the
source is just this repository. Co-developing the two means pushing
tatara-lisp first and bumping the rev — which is the trunk-based order anyway.

## What is not built

Stated so nobody cites it as existing: **no per-process GC heap** (processes have
private environments and messages are deep-copied, but reclamation is `Arc`
refcounting — no independent collection pause), **no registry client** (resolution
is real; nothing fetches), **no self-hosting on the implementation axis**
(`spec/*.b` is the specification axis only), **no comment attachment inside a
form**, **no completion / go-to-definition** (each needs a resolved name table),
and no **`case`/`when` pattern matching** or **ranges** — the two remaining
surface gaps a Ruby or Elixir author would reach for. `theory/BLUE.md` §V.26 holds the tier ledger; **do not build against a
DESIGN-tier row without saying so.**
