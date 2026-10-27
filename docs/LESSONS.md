---
kind: explanation
summary: the full story behind each rule the agent page states in short
---

# Lessons behind the agent guide's rules

Full text of rules that the agent guide (`docs/agents.md`, rendered as AGENTS.md and CLAUDE.md) states in short. Each shipped as a defect.

- **A formatter law passing is not the formatter being right.** All three laws
  held while every call rendered as a method send — `fact(n - 1)` printed as
  `(n - 1).fact`. A round-trip law measures the tree, never the readability.
  **When you change rendering, read the output.**
- **A corpus is only as strong as what is in it.** The annotated-`def`
  rendering bug survived because the formatter corpus contained no annotated
  defs. Add the case with the rule. `SURFACE_KEYWORDS` now makes the *omission*
  the failure — adding a keyword forces the corpus entry.

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

- **Two doors to the formatter is one door too many.** `fmt --write` learned to
  re-interleave comments; the LSP kept calling `format_forms`, so
  `textDocument/formatting` returned 707 bytes for 1010 and **deleted all six
  comments in the buffer**. Everything that shows a user their own file goes
  through `format_source_lossless`; `format_source` is for comparing trees.
- **A document built to be measured must give its comments back.** The
  formatter claims a comment when a document takes it, and a lambda is built
  as its inline and its block spelling while only one is printed; the rescue
  modifier measures its operands before it picks `begin`. Each dropped its
  comments with `Ok` and a green law, because the claim flag says a document
  took the comment, not that it was printed. Measure through `Renderer::probe`,
  decide on comments before building, and rely on the door's output check
  (`format_tree_lossless` compares the comment texts it prints with the ones it
  was given). A comment inside `#{}` code is invisible to the lexer's comment
  list; `comment_count` counts it and the door refuses it by line.
- **Printing code inside `#{}` can end the interpolation early.** The lexer
  closed `#{` on the first unbalanced brace, strings included, so a printed
  `"}"` cut the code short. It now reads a nested string whole; keep it that
  way when touching `skip_interpolation`.

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

## Bounds, never preferences

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
- **Execution budget** — was open because no default constant existed to
  expose. tatara-lisp-eval 0.3.63 gave both executors one budget and made
  exceeding it a catchable error rather than a stack overflow, which closed M2.

**The admission rule, which is what makes the surface safe to have shipped:** a
knob may live in `BlueConfig` only if it is a **BOUND, never a preference**.
Raising `solver_max_steps` or `max_expr_depth` changes no program's meaning —
only whether a pathological input is refused — so neither can freeze a design
guess as a public interface, which was the M1 objection. A preference would.
Both are also read for real (`blue deps` → `Solver::with_max_steps`, every
parsing subcommand → `parse_with_depth`), each with a red run recorded in the
test that proves it.

## A stale Cargo.lock is a stale flake.lock

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

## Rules from the agent guide, in full

The agent guide (`docs/agents.md`) states each of these in one line.

- **A spawned function is turned back into code, never shared.** `spawn`
  walks the function's free names: functions come along as definitions
  recompiled for the VM in the child, data comes along as deep copies, and a
  host handle is refused by name. Sharing the closure would share its
  environment, which is the coupling isolation exists to remove
  (`blue_lang_proc::code`). Every child's host reads go through a recorder, so
  a crash trace replays without the host; a new host name needs no edit here,
  because the recorder reads `Capability::host_effects()`.
- **Nix reads blue's evaluation of a Bluefile; it never re-derives it.**
  `mk-bidama.nix` used to split each manifest's text on `needs("`, and a
  computed `needs` was invisible to it — a facade closure one package short,
  with nothing red. It now reads the committed `Bluefile.lock` (`blue lock`),
  and `bidama-locks-fresh` + `granularity.rs` fail on a stale one. **Edit a
  Bluefile or a bidama's `use` forms, run `blue lock <dir>`, commit both**: a
  bidama's locked `needs` derive from its `use`s, a hand row only narrows a
  range. A new manifest word is a row
  in `bluefile.rs`'s `WORDS` and a name in `MANIFEST_NAMES`; a gate fails if
  the two disagree. **It is also a row in `nix/project.nix`** (`known` plus its
  lowering): the engine refuses every lock key it does not lower, so a new word
  fails every project's evaluation until it has one, instead of being dropped.
- **A generated file is declared once, in the root `Bluefile`, and refreshed by
  its command.** `generate(name, output, program)` names the committed file and
  the blue program that writes it; the project engine (`nix/project.nix`, the
  same one behind every project's `lib.project`) reads `Bluefile.lock` and derives
  `packages.generated-<name>` and `checks.generated-<name>-fresh`, and
  `nix run .#regen` (`gen/regen.b`, reading the same lock) rewrites every such
  file in place. Edit the program, run regen, commit both; never copy a store
  path over a committed file. First instance: kigou's character tables
  (`crates/blue-lang-syntax/gen/kigou.b`, rendered by the `sabi` bidama).
  A generator runs alone in the store, so it reads project files only through
  `generate`'s fourth argument: `inputs` names the paths, the engine puts
  exactly those under `$GEN_ROOT` (regen: the project root), and the fresh
  check goes red when one changes. `docs/REFERENCE.md` (from `blue
  reference`) and `docs/EXAMPLES.md` (from `examples/`) are the first two.
- **A description lives beside the table it describes, and a gate makes the
  omission red.** `INFIX` rows carry `doc`, `keyword_doc` covers every
  reserved word, `FORMS` rows are parsed by their own gate, `WORDS` rows carry
  `doc`, and `blue_lang_runtime::docs::NAMES` is compared with a live
  interpreter in both directions (a bound name with no row, a row naming
  nothing, a signature disagreeing with the arity). A new operator, keyword,
  word or primitive arrives with its line, and `docs/REFERENCE.md` follows.

## The pre-push gates

**A push to `main` runs the local gates first.** `nix develop` sets
`core.hooksPath` to `.githooks`, whose `pre-push` runs `gen/prepush.b` on the
working tree: `cargo fmt --check`, every `Bluefile.lock` confirmed, `regen` in
every project that generates (each red names the file it rewrote; commit it),
`gen --version` against substrate's one gen pin (red names the nix lock bump),
`gen confirm` (red runs `gen build .` and names the files to commit),
each member's test targets compiled alone (`cargo test -p M --no-run`, since
`--workspace` unifies features and hid a break), and the `registry_graph`,
`check_corpus`, `distribution` and `verb_graph` tests. These caught
four `main` reds on 2026-10-22 that CI found only after the push. About 4.5 min
warm (2026-10-23): regen of the root 71 s, the per-member compile 44 s, the
tests 136 s. A project whose declared
`tool` is not on PATH (`native`: `tatara-rust-emit`) is reported `➖`, never
green. The hook first calls the global `core.hooksPath` hook of the same
name, so the fleet's commit gates still run. Off: `BLUE_PREPUSH_OFF=1`.
