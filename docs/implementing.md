---
kind: reference
summary: the implementer detail behind the agent guide's "Changing blue itself": the check registry, crate map, hard-won rules, CI gates, dependencies and what is not built
---

# Implementing blue — the detail behind the agent guide

The agent guide (`docs/agents.md`, rendered as AGENTS.md and CLAUDE.md) states each of these in short and links here. Moved out of the guide on 2026-10-29 so the always-loaded page stays inside its context budget; nothing was dropped.

## Architecture rules are pipeline errors; lint is a view over them

**Every rule blue enforces is a row in one registry, `blue_lang_check::RULES`,
and runs in the check stage** — so `blue run`, `blue test`, `blue check`, the
LSP and every bidama build enforce it, and an error-severity violation cannot
run or build. A row is a code (`B0001`), a severity, a one-line law, an
explanation (`blue explain CODE`), a witness program (the kept red run:
`every_rule_fires_on_its_witness_and_only_it` fails unless it produces exactly
that code) and an optional fix. **A new rule is a new row, never a separate
checker**: a future `blue lint` lists and fixes over these rows. Refusal is
scoped: every diagnostic in a file is reported in one pass, naming the
offending definition. The one escape hatch is `# waive CODE: reason` directly
above the offending top-level definition; it is counted and reported, never
silent, and there is no global switch. Names resolve by an explicit tier list
(`names::RESOLUTION_ORDER`: local, own bidama, the names the file's `use`
forms list, builtin; `pkg::name` is exact), and the runtime evaluates the
tree that resolution produced — every definition keyed `pkg/name` — so the
two cannot disagree; `blue-lang-runtime/tests/resolution_order.rs` pins the
agreement. A namespace rule the corpus is still being brought to carries a
`ratchet` and is counted by `blue census` until it reaches zero. Full shape:
`docs/DIAGNOSTICS.md`. **A project's own rules are not rows**: they are blue
definitions its Bluefile names (`rule`), run by `blue check` under a pure
frame with codes outside `B`, and the check stage leaves their waivers to
that door (`docs/DIAGNOSTICS.md`, "Project rules").

**Each bidama is a namespace** (`theory/BLUE-NAMESPACES.md`). A file reaches
another bidama's definition only qualified (`kueri::join`) or listed
(`use("retsu", [:first])`); a name reached because something else loaded it
is B0012. Prefixing a bidama's definitions (`q_join`) is B0013/B0014, with
`blue migrate --strip` as the fix; `blue migrate FILE` makes a file's
references explicit. Both are blue (`crates/blue-lang-cli/blue/migrate.b`),
and both keep a file only when its resolved tree proves unchanged (`blue ast
--resolved --json`) — a text replace cannot see a local that would capture a
renamed call, and the proof did. `mkBidama` runs the check stage, so a
bidama that does not check does not build.

## Where to look

| Intent | Crate |
|---|---|
| lexer + Pratt parser → `Sexp`; the `INFIX` table | `blue-lang-syntax` |
| the one formatting (Wadler/Oppen) | `blue-lang-fmt` |
| sliding-scale typing; `Seam`; `Stats`; diagnostic spans | `blue-lang-check` |
| REACH/WHEN/WHERE frame lattice; the closed `Capability` set; `imports_of` | `blue-lang-waku` |
| package posture floors + resolution | `blue-lang-bidama` |
| processes, supervision, mailboxes, isolation; the blue-level words (`node`), crash traces and `blue replay` (`trace`), `defmigrate` | `blue-lang-proc` |
| interpreter construction, erasure, pipeline; blue values into Rust `TataraDomain` types (`domain`); BLAKE3 + Ed25519, pure and C-free (`crypto`); NATS and HTTP spoken over std TCP (`net`, host-gated as `Capability::Network`) | `blue-lang-runtime` |
| one evaluation session — contexts, live redefinition, pure frame, budget, interrupt, expansion (`session`); its JSON-lines protocol (`session::protocol`, `blue serve`); values as blue text (`literal`) | `blue-lang-runtime` |
| `test`/`assert` runner | `blue-lang-test` |
| the conformance suite: `spec/rows/*.b` on every evaluator, and the missing-row gate (`checks.conformance`; format and pending mechanism in `spec/README.md`) | `blue-lang-test/tests/conformance/` |
| Bluefile (the `WORDS` table) + version solver + `Bluefile.lock` | `blue-lang-pkg` |
| `image` and `workload`: specs and per-entry refusals, the rendered objects, the structural diff (`deploy`); the CLI doors in `blue-lang-cli/src/deploy.rs`; the lowering and the distroless gate in `nix/project.nix`, `nix/image-gate.b` | `blue-lang-pkg` |
| the project engine: a `Bluefile.lock` lowered to packages, checks and apps (`lib.project`; blue's own flake is its first caller) | `nix/project.nix`, over `bidamas/mk-bidama.nix` |
| the WASM surface (zero host imports) | `blue-lang-wasm` |
| the query engine `mondou` (問答): parse, packages, items, scope and resolve, memoized; `def_hash` (a definition's identity, its resolved tree with each callee replaced by its hash); completion, definition, references, rename, symbols, signatures; `host_reach` (each definition's host capabilities, with the chain) and code queries (`query`, `blue query`) | `blue-lang-mondou` |
| LSP: transport-free core + stdio shim, every answer from `mondou` | `blue-lang-lsp` |
| the mark, wordmark, Nord theme | `blue-lang-art` |
| embedding blue in a Rust program: `#[host]` turns an impl block into host functions, `Program` loads `.b` and makes typed calls; the one dependency a Rust host takes | `blue-lang-host`, `blue-lang-host-macros` |
| every subcommand; `BlueConfig` (the two typed bounds) | `blue-lang-cli` |
| project check rules written in blue: the Bluefile's `rule` word, the ABI and frame (`project_rules` in `blue-lang-runtime`), the pass `blue check` runs (`project_rules` in `blue-lang-pkg`), codes and waivers (`blue-lang-check::project`) | `blue-lang-check`, `-runtime`, `-pkg` |
| the verb graph: row files (`space`, `verb`, `edge`, `vocab`, `lateral`) read as data, never run; gates G1, G2, G4, G7, G9 and their hadome baseline (`graph.baseline`); TSV import and export; `blue verbs` (`blue-lang-cli/blue/verbs.b`) and `checks.verb-graph` (`gen/verb-graph.b`) | `mokuroku` (`bidamas/mokuroku/graph/`), `blue-lang-cli` |
| `blue doc`: a blue program (`blue-lang-cli/blue/doc.b`) over mokuroku | `blue-lang-cli` |

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
- **A spawned function is turned back into code, never shared.** Detail: [LESSONS.md](LESSONS.md).
- **A VM closure carries its chunk.** Before tatara-lisp-eval 0.4.x a closure
  compiled by one program and called from another read the caller's constant
  pool: a wrong constant or a panic. `defmigrate` compiles new code into a
  running process's interpreter, so it depends on that fix; so does any REPL
  on the VM.
- **A restart empties the mailbox.** In-flight messages were addressed to the
  incarnation that died. Replaying them is how a poison message kills a
  process forever.
- **Restart intensity is checked on the child that exited**, not on siblings a
  strategy sweeps up. A sibling restarted as collateral has not misbehaved.
- **A passing formatter law is not a right formatter, and a corpus is only as strong as its contents.** When you change rendering, read the output. Add the case with the rule; adding a keyword forces its corpus entry. Detail: [docs/LESSONS.md](LESSONS.md).
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
- **A derived artifact needs a test that reads the artifact, not its source.** Ship the formatter arm WITH the surface form and read the output; a round-trip law measures the tree, never the readability. A span the parser drops is unrecoverable downstream: look upstream, never invent one. Detail: [docs/LESSONS.md](LESSONS.md).
- **Isolation is the SEAL, not the rebuild.** Use `blue_lang_proc::forking` for `spawn`, never a factory that rebuilds; a plain `Clone` is NOT a fork, because `Env::set` writes through the `Arc`. Detail: [docs/LESSONS.md](LESSONS.md).
- **A name has three arbiters, and an environment lookup sees one.** Special
  forms are `match` arms in no environment; a macro rewrites before evaluation
  and beats a same-named binding. `assert` was lost to the second, and the
  replacement gate was still blind to the first while blue lowers to `not`. Ask
  `Interpreter::resolve_head`, which answers *which* arbiter claims the name.
- **One door to the formatter.** Everything that shows a user their own file goes through `format_source_lossless`; `format_source` is for comparing trees. A document built to be measured must give its comments back: measure through `Renderer::probe`, decide on comments before building, and keep the door's output check. Keep `skip_interpolation` reading a nested string whole. Detail: [docs/LESSONS.md](LESSONS.md).
- **A layout change is a change to every `.b` file.** `canonical::admit` refuses
  or rewrites a file that is not what the formatter prints, so a new layout
  lands with the reformatted corpus in the same commit (`tests/corpus.rs`
  reports the drift). `PROPTEST_CASES=20000 cargo test -p blue-lang-fmt` is the
  deep run; a failure it finds is saved beside the test file.
- **A name that reads like a guarantee is not one; ask an interpreter.** `interpreter_hostless` binds the host layer under the `sys` feature, so `check_reach` is load-bearing. A capability is a bundle of NAMES, not a host effect; adding a variant is `E0004` at four sites. Pinned by `blue-lang-cli/tests/capability_surface.rs`. Detail: [docs/LESSONS.md](LESSONS.md).
- **Nix reads blue's evaluation of a Bluefile; it never re-derives it.** Edit a Bluefile or a bidama's `use` forms, run `blue lock <dir>`, and commit both. Detail: [LESSONS.md](LESSONS.md).
- **A generated file is declared once, in the root `Bluefile`, and refreshed by its command.** Edit the program, run `nix run .#regen`, and commit both; a generator reads project files only through `generate`'s `inputs`, and regen refuses an untracked file under them (`BLUE_REGEN_UNTRACKED=allow` renders without it). Detail: [LESSONS.md](LESSONS.md).
- **A description lives beside the table it describes, and a gate makes the omission red.** A new operator, keyword, word or primitive arrives with its doc line. Detail: [LESSONS.md](LESSONS.md).
- **The mark is a COLOUR shift, and its direction is meaning.** Four solid `█` across Nord's Frost band, named by ANSI slot. Never a density ramp or dither glyphs; theme colours are `irodori` lookups, blue carries no hex, and a test enforces it. Quoting a warning and arguing past it is not clearing it. Detail: [docs/LESSONS.md](LESSONS.md).

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

**CI guards `main`; land with `git land`.** `git land [slug] [--watch]` (`gen/land.b`; `nix develop` sets the alias) pushes HEAD to `land/<slug>`. `.github/workflows/land.yml` runs the `ci` suite on that exact commit and, when it is green, fast-forwards `main` to it and deletes the branch; when `main` moved first the fast-forward is refused, and you rebase and land again. `--dry` lands on `land/dry-<slug>`, where the fast-forward is only rehearsed. A push straight to `main` stays possible.

**Every push runs a fast local gate first.** `nix develop` sets `core.hooksPath` to `.githooks`, whose `pre-push` runs `gen/prepush.b`: the light gates the changed paths select from `gate_table` (formatting, the changed locks, retired words), in seconds; a path in `every_gate_paths` or one no gate names selects every gate. The heavy gates (`regen`, the gen pin and tie, the sweep of every consumer in `gen/consumers.json`, tests beside, each member compiled alone, the distribution tests, strict conformance) run in CI, or here with `BLUE_PREPUSH_FULL=1`. A clean tree that passed skips its next push. Off: `BLUE_PREPUSH_OFF=1`. What each gate caught and what it costs: [LESSONS.md](LESSONS.md).

**A new rule lands after its consumers are written in it.** `gen/consumers.json` is the registry of pleme-io repositories with `.b` files and the blue each pins (flake, git cargo source, crates.io or blue-setup); `blue gen/consumers.b derive` rewrites it from the workspace. `blue gen/consumers.b sweep` runs every consumer's files through this blue's `fmt --check` and `check`; prepush and the `consumers` CI job run it, and recorded debt may shrink, never grow (hadome). `blue gen/consumers.b fix REPO` writes one consumer with `fmt --write` in a worktree and commits only when `blue erase` is byte-identical before and after each file; the consumer then moves its pin and runs its tests. `checks.consumers` is red while `blue explain --list` names a code that `sweep --record` has not recorded green. Off: `level(REPO, :audit, why)` or `level("*", :off, why)` in `entries`.

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

The measured cost of a stale lock, and the update order, are in [LESSONS.md](LESSONS.md), "A stale Cargo.lock is a stale flake.lock".

## What is not built

Stated so nobody cites it as existing: **no per-process GC heap** (processes have
private environments and messages are deep-copied, but reclamation is `Arc`
refcounting — no independent collection pause), **no registry client** (resolution
is real; nothing fetches), **no self-hosting on the implementation axis**
(`spec/*.b` is the specification axis only), **no comment attachment inside a
form**, **no entropy primitive and no encryption** (the `crypto` layer hashes,
signs and verifies; a keypair comes from a seed the caller supplies),
**no TLS** (`net` speaks NATS and HTTP over plain TCP: an `https://` url and a
NATS server requiring TLS are refused by name; planned in `docs/HTTP2.md` P4,
rustls with ALPN `h2`),
**no import EMISSION into a wasm module** (`blue_lang_waku::imports_of`
derives the table from a frame — nothing puts an entry into a `.wasm`, and no
engine border is wired: that is `BLUE-EXECUTION.md` M2, blocked on `tatara-wasm`
not being on crates.io), **no editor answer inside a broken buffer** (the
LSP answers from the newest revision that parsed until the parser recovers,
`BLUE-ENGINE.md` E6), **project rules in the editor or as wasm** (`blue check`
runs them in-process under the rule frame; the LSP does not run them, and the
ABI is shaped for a wasm module that nothing builds yet), and no **`case`/`when` pattern matching** or **ranges** — the two remaining
surface gaps a Ruby or Elixir author would reach for. `theory/BLUE.md` §V.26 holds the tier ledger; **do not build against a
DESIGN-tier row without saying so.**
