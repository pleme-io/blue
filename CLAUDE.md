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
| sliding-scale typing; `Seam`; `Stats`; diagnostic spans | `blue-lang-check` |
| REACH/WHEN/WHERE frame lattice; the closed `Capability` set; `imports_of` | `blue-lang-waku` |
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
- **A span is a property of the tree that `to_sexp` throws away, so tree tests
  cannot see it either** — the same lesson, fourth citation, now off the
  formatter. Making the parser build `Spanned` landed two mis-anchored
  productions (`body`'s synthesized `begin`, `case`'s `else`) that every one of
  the 82 parser tests passed over, because both TREES were correct and the
  spans were not compared to anything. The gate that found them walks each node
  asserting it sits inside its parent's span. **A derived artifact needs a test
  that reads the artifact, not the thing it was derived from.**
- **A diagnostic without a span is a diagnostic the editor puts in the wrong
  place.** `Diagnostic` carried only a message, so the LSP attached every type
  error to `Range::default()` — line 0, column 0 — and drew the squiggle on the
  first character of the file. It was not the LSP's bug: the parser had already
  discarded the position, and a span discarded at the parser is unrecoverable.
  **When a layer reports a location it does not have, look upstream for where
  the location was dropped, not downstream for somewhere to invent one.**
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
- **`interpreter_hostless` is not hostless when the `sys` feature is on.** It
  forks a base built by `interpreter(&mut ())`, and `interpreter` installs the
  host layer under `#[cfg(feature = "sys")]` — so in `blue-lang-cli`, and in
  every `cargo test --workspace` run through cargo's feature unification, the
  "hostless" interpreter binds all 37 host primitives including `rm_rf`.
  `bluefile`'s module doc credited the opposite for months: it said a manifest
  was *"safe by absence of a binding"*. It is safe by the `check_reach` frame,
  and by nothing else — which makes the frame load-bearing rather than
  belt-and-braces. **A name that reads like a guarantee is not one; ask an
  interpreter.** Pinned by `blue-lang-cli/tests/capability_surface.rs`.
- **A capability is a bundle of NAMES, not a host effect.** `Reach` governs
  *what may be named*, and blue's real frames grant `+`, `define` and `package`
  — so a closed universe of host effects alone could not express a single frame
  blue mints. `Capability` closes the whole nameable vocabulary; the host-effect
  subset is what `imports_of` lowers. **Adding a variant is `E0004` at four
  sites**, which is what makes the import table derived rather than maintained.
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

`tatara-lisp` and `tatara-lisp-eval` are **crates.io registry deps**, not path
deps and not git deps.

A path dep outside the repo cannot resolve in a Nix sandbox, where the source
is just this repository — which is why `tatara-lisp` was extracted from the
tatara mono-workspace in the first place. A GIT dep does resolve there, and is
still wrong: a git source and a registry source are DISTINCT to cargo even at
an identical version, so a git dep silently doubles the crate in every
consumer's graph, and a crate carrying one **cannot be published at all**.

Co-developing the two means publishing tatara-lisp first and bumping the
version — the trunk-based order anyway. That is a real cost and it is the one
being paid deliberately: the alternative costs publishability.

**And the cost is NOT the release. It is the CONSUMPTION, which nothing
automates.** Measured 2026-08-12: `Cargo.toml` asks for `"0.3"`, a caret
requirement that accepts anything in the line — and `Cargo.lock` pinned
`0.3.27` while tatara-lisp had shipped through **`0.3.44`**. Seventeen
releases, available the whole time, never consumed.

The tempting diagnosis is that publishing is expensive so nobody paid it.
That is false and worth refuting, because it points at the wrong fix:
tatara-lisp's `auto-release.yml` fires reliably — its log alternates
`release: workspace v0.3.43`, `v0.3.44` with the feature commits that earned
them. **Upstream cadence was never the problem. blue's lock was.**

What that cost, concretely: a reclamation leak (~832 B per dead interpreter
incarnation) sat unfixed across those releases; the `&[Value]` calling
convention that makes `Arc::get_mut` unable to ever succeed went un-renegotiated;
`Vm`'s private frames kept a debugger unbuildable. Every one of those reads at
first glance as "an upstream problem we cannot reach" and is really "a version
we did not take."

**So: a stale `Cargo.lock` against a pleme-io-owned crate is the same defect
class as a stale `flake.lock`** — the org's named cardinal sin, and the exact
failure ★★ MAINTENANCE JUGGLING exists to prevent. Treat it as one. Before
concluding that a limitation is upstream's, check what `cargo update` would
take: the fix may already be published.

**The ordering that must not be got wrong when you do update.** `gen build`
rewrites `Cargo.gen.lock` from whatever `Cargo.lock` it finds, so regenerate
the delta AFTER the lock work, never before — generating against a stale lock
ties the delta to bytes about to change, and can quietly revert an in-flight
`Cargo.lock` edit. Verify the tie afterwards by comparing
`shasum -a 256 Cargo.lock` against the delta's `cargo_lock_sha256`.

**Corrected 2026-08-12.** This section said "git deps pinned by rev" and had
said so since before `ffbe667` (*deps: pleme-io dependencies to crates.io,
never git*) made it false. Stale in the worst direction — it instructed the
next author to do the exact thing `Cargo.toml`'s own comment explains would
make this workspace unpublishable.

## `Cargo.gen.lock` is committed, and that is a trade

The rationale is recorded here because the artifact itself landed in `d917383`,
a commit about Japanese naming that says nothing about it — three concurrent
sessions were writing to this repo that night and one swept the other's staged
files into its own commit. A 5880-line generated file appearing with no
explanation is how the next author learns to distrust it.

**Why it exists.** Without a committed delta, substrate takes the IFD path and
says so on every evaluation — ten times in one `nix flake check`:

    trace: mkBuildSpec[IFD]: no committed Cargo.build-spec.json for
    /nix/store/…-source → eval-time `gen build` (network). Commit one for a
    deterministic no-IFD build.

That runs `gen build` inside a `__noChroot` sandbox *during eval* — network,
variable latency, and a derivation whose `.drv` exists only because eval put it
there. When that `.drv` is not valid in the store at build time the check dies
with `path '…-cargo-build-spec-ifd.drv' is not valid`. **That failure is
store-state dependent, not a property of this source** — on a warm store where
the IFD `.drv` is still valid the same tree checks green, which it did here
before the fix. Do not read one green run as evidence the path is sound.

Measured with a control, same eval, one file moved: delta absent → 1 trace,
delta present → 0.

**Why the delta and not `Cargo.build-spec.json`.** substrate's
`reusable-gen-spec.yml` states the doctrine — "the committed artifact is the
slim `Cargo.gen.lock` … a gitignored `Cargo.build-spec.json` intermediate" —
and `lockfile-builder` reads the delta *first*, reconstructing the graph in
pure Nix. 197 KB against 417 KB, and committing both would be two derived
files that can disagree.

**The cost, and what pays it.** A checked-in derived file can go stale: land a
`cargo update` without re-running `gen build` and substrate reconstructs the
build graph from a delta describing a dependency set the lock no longer has.
Two things hold it, neither of which existed before:

- **`checks.gen-confirm`** — already emitted by substrate's tool-release and
  until now passing over nothing. Its `gen confirm . --if-present` *tolerates*
  a repo with no delta; blue had none, so the check was green having verified
  nothing. With the delta committed it recomputes `sha256(Cargo.lock)` offline
  and compares it to the recorded `cargo_lock_sha256`. Red run: that field
  zeroed by hand → `{"status":"stale"}`, exit 1; restored → `{"status":"fresh"}`,
  14 manifests verified, exit 0.
- **`.github/workflows/gen-spec.yml`** — the regen. On main `gen build . --commit`
  is a no-op when fresh; on a PR it regenerates without committing and fails if
  the result differs.

**Honest tier: eval- and CI-caught, not unrepresentable.** Nothing stops a
stale delta being committed locally; it cannot pass `nix flake check`.

**Generate the delta AFTER any lock work, never before.** `gen build` rewrites
`Cargo.gen.lock` from whatever `Cargo.lock` it finds, so generating against a
stale lock ties the delta to bytes about to change — and it can quietly revert
an in-flight `Cargo.lock` edit. Verify the tie afterwards by comparing
`shasum -a 256 Cargo.lock` against the delta's `cargo_lock_sha256`; a tie that
reports fresh against a lock you never checked is the trap.

## What is not built

Stated so nobody cites it as existing: **no per-process GC heap** (processes have
private environments and messages are deep-copied, but reclamation is `Arc`
refcounting — no independent collection pause), **no registry client** (resolution
is real; nothing fetches), **no self-hosting on the implementation axis**
(`spec/*.b` is the specification axis only), **no comment attachment inside a
form**, **no import EMISSION into a wasm module** (`blue_lang_waku::imports_of`
derives the table from a frame — nothing puts an entry into a `.wasm`, and no
engine border is wired: that is `BLUE-EXECUTION.md` M2, blocked on `tatara-wasm`
not being on crates.io), **no completion / go-to-definition** (each needs a
resolved name table),
and no **`case`/`when` pattern matching** or **ranges** — the two remaining
surface gaps a Ruby or Elixir author would reach for. `theory/BLUE.md` §V.26 holds the tier ledger; **do not build against a
DESIGN-tier row without saying so.**
