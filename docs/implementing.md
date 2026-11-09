---
kind: reference
summary: "the implementer detail behind the agent guide's \"Changing blue itself\": the check registry, crate map, hard-won rules, CI gates, dependencies and what is not built"
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

**Each bidama is a namespace** ([NAMESPACES.md](NAMESPACES.md)). A file reaches
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
| processes, supervision, mailboxes, isolation; the blue-level words (`node`), crash traces and `blue replay` (`trace`), `defmigrate`; a process's scheduling class and the one darwin priority seam (`scheduling`, `seam`); eviction's `blue-image` and its Tide frames (`image`), carried by the runtime's wire (`wire::CARRIER`) | `blue-lang-proc` |
| interpreter construction, erasure, pipeline; blue values into Rust `TataraDomain` types (`domain`); BLAKE3 + Ed25519, pure and C-free (`crypto`); NATS and HTTP spoken over std TCP (`net`, host-gated as `Capability::Network`) | `blue-lang-runtime` |
| one evaluation session — contexts, live redefinition, pure frame, budget, interrupt, expansion (`session`); its JSON-lines protocol (`session::protocol`, `blue serve`); values as blue text (`literal`) | `blue-lang-runtime` |
| `test`/`assert` runner | `blue-lang-test` |
| the conformance suite: `spec/rows/*.b` on every evaluator, and the missing-row gate (`checks.conformance`; format and pending mechanism in `spec/README.md`) | `blue-lang-test/tests/conformance/` |
| Bluefile (the `WORDS` table) + version solver + `Bluefile.lock` | `blue-lang-pkg` |
| `image` and `workload`: specs and per-entry refusals, the rendered objects, the structural diff (`deploy`); the CLI doors in `blue-lang-cli/src/deploy.rs`; the lowering and the distroless gate in `nix/project.nix`, `nix/image-gate.b` | `blue-lang-pkg` |
| the project engine: a `Bluefile.lock` lowered to packages, checks and apps (`lib.project`; blue's own flake is its first caller) | `nix/project.nix`, over `bidamas/mk-bidama.nix` |
| the WASM surface (zero host imports) | `blue-lang-wasm` |
| the senses: audio out and in through the platform's sound ABI, loaded with dlopen behind one unsafe seam (`seam`); a CPU canvas (`canvas`) and the `garasu-canvas/1` socket client (`display`); the words and their providers live in the runtime (`audio`, `display`) | `blue-lang-senses` |
| the query engine `mondou` (問答): parse, packages, items, scope and resolve, memoized; `def_hash` (a definition's identity, its resolved tree with each callee replaced by its hash); completion, definition, references, rename, symbols, signatures; `host_reach` (each definition's host capabilities, with the chain) and code queries (`query`, `blue query`) | `blue-lang-mondou` |
| LSP: transport-free core + stdio shim, every answer from `mondou` | `blue-lang-lsp` |
| the mark, wordmark, Nord theme | `blue-lang-art` |
| embedding blue in a Rust program: `#[host]` turns an impl block into host functions, `Program` loads `.b` and makes typed calls; the one dependency a Rust host takes | `blue-lang-host`, `blue-lang-host-macros` |
| every subcommand; `BlueConfig` (the five typed bounds) | `blue-lang-cli` |
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

**CI guards `main`; land with `git land`.** `git land [slug] [--watch]` (`gen/land.b`; `nix develop` sets the alias) pushes HEAD to `land/<slug>`. `.github/workflows/land.yml` runs the `ci` suite on that exact commit and, when it is green, fast-forwards `main` to it and deletes the branch; when `main` moved first the fast-forward is refused, unless `main` moved only by release commits and the land writes no `Cargo.toml`, `Cargo.lock` or `Cargo.gen.lock`: then it rebases onto them and fast-forwards without a new suite (`BLUE_LAND_ABSORB_RELEASE=off` turns that off). `--dry` lands on `land/dry-<slug>`, where the fast-forward is only rehearsed. A push straight to `main` stays possible. A land behind `main` rebases itself: the merge driver regenerates a generated file that conflicts, and `blue lock .` and `gen/regen.b` refresh what merged clean but went stale, in a commit of their own (`--no-regen` skips the second); any other conflict stops, names the paths and leaves HEAD alone. A fetch of `main` that meets a ref lock another worktree of the same `.git` holds (`lock_messages` in `gen/land.b`) tries again up to four times, 1, 2 and 4 seconds apart; any other fetch failure ends the land with git's words. `--requeue=N` bounds it (2 by default; `--requeue=0` refuses instead of rebasing).

With `--watch`, a land takes a turn, because only one land reaches `main` and the others' suites are spent. The queue goes by the time a land first queued, kept in a branch `land-queue/<YYYYMMDDHHMMSS>/<slug>` (no workflow runs on it) from the first wait until the land ends, so a land that pushes again keeps its place and never passes one queued before it; a land waiting without a run holds its place too, a run from a client without tickets queues at the time it was created, a waiting land renames a `land-beat/<time>/<slug>` branch each minute, a ticket whose land has not beaten for 10 minutes gives up its place, and a ticket older than 6 hours is ignored. A land waits while another land runs (`--queue-minutes=N`, 240 by default; `--no-queue` lands beside them, and a `gh` that answers no list holds the turn too, up to that limit), rebases, and rechecks before it pushes; of two that took one turn, the one queued later stops and queues again. A run green in CI and refused at the fast-forward rebases and lands again. A land that changes a release file also waits while an auto-release run that can bump is in flight, because it cannot absorb that release. CI holds the same queue on its side, so a land pushed without `--watch`, with `--no-queue` or past a rate limit cannot run beside another: before the suite, `gen/land.b --turn` (in `ci.yml`'s `blue` job, and in `land.yml`'s `prose` job) refuses the run when an older land still runs or `main` gained a commit the land cannot absorb, and waits while a release it would collide with is in flight. A refused run skips its suite, and its fast-forward fails at the step `refuse a land that does not hold the turn`; `--watch` reads that step and lands again whether or not `main` moved; a land again of a HEAD its ref already names deletes the ref first, so the push starts a new run rather than following the one that was cancelled or refused (repository variable `BLUE_LAND_TURN=off` turns the turn off). In CI, `ci.yml`'s `stop-on-red` job cancels a land's run at its first red job, so the next land starts (repository variable `BLUE_LAND_STOP_ON_RED=off` skips it). `--proven` runs the suite first (`gen/proof.b --prove`) and pushes its proof as a note under `refs/notes/blue-suite`; CI skips `cargo test` when the note names the commit's tree and locks (`docs/TESTING.md`, pre-merge and post-merge).

A change only to prose (`land_scope` in `gen/prepush.b`: the root's and the docs' markdown, and the generated files that only render them) lands on `land/prose-<slug>`, whose suite is the gates that read prose (`prose_gates`, from the lock). Evaluated on 2026-11-04, a doc edit changed the derivation of 18 of 276 checks; the 9 of those with a whole-tree source (`conformance`, `network` and so on) read no `docs/`. `land.yml` recomputes the scope and refuses a `prose-` ref over a change that is not; an unknown path, an empty change and `docs/DIAGNOSTICS.md`, which Rust tests read, are `whole`; the push to `main` still runs the whole suite. `--no-prose` runs the whole suite on the land too.

**A generated file never conflicts by hand.** `.gitattributes`, itself generated, marks each with `merge=blue-generated`; `nix develop` and `git land` set the driver, and `gen/merge.b` regenerates the file from the merged tree in a merge, a rebase or a cherry-pick (`BLUE_MERGE_PICK=off` merges a cherry-pick as text). A failed generator or a clone with no driver merges as text.

**Every push runs a fast local gate first.** `nix develop` sets `core.hooksPath` to `.githooks`, whose `pre-push` runs `gen/prepush.b`: the light gates the changed paths select from `gate_table` (formatting, the changed locks, retired words), in seconds; a path in `every_gate_paths` or one no gate names selects every gate. A landing (a push to `main` or a land ref) also runs the land gates its paths select: the census, the reuse ratchet, the bench and `regen`. The heavy gates (the gen pin and tie, the sweep of every consumer in `gen/consumers.json`, tests beside, each member compiled alone, the distribution tests, strict conformance) run in CI, or here with `BLUE_PREPUSH_FULL=1`. A clean tree that passed skips its next push. Off: `BLUE_PREPUSH_OFF=1`. What each gate caught and what it costs: [LESSONS.md](LESSONS.md).

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

This table lists the gaps of the language and its runtime. Do not cite a ❌ row as a feature. Do not build against a ❌ row without saying so.

✅ built and tested · ⏳ in progress · ❌ not built

| Item | State | What makes it true |
|---|---|---|
| A per-process GC heap | ❌ not built | Processes have private environments, and messages are deep-copied. Reclamation is `Arc` refcounting (`crates/blue-lang-proc/src/lib.rs`), so no process has its own collection pause. |
| A registry client | ✅ built | Resolution works over a git directory (`crates/blue-lang-pkg/src/git_registry.rs`). `blue lock` pins a source with `nix flake prefetch` (`crates/blue-lang-cli/src/prefetch.rs`). The nix build fetches each `source(name, url, dir)` over its pin (`nix/project.nix`, `checks.source-fixture`). The CLI adds a pinned source to the load path (test `a_locked_source_on_this_machine_joins_the_project_after_its_packages`). |
| Self-hosting on the implementation axis | ❌ not built | The parser, checker and runtime are Rust. `spec/rows/*.b` is the specification axis only. |
| Comments inside a form | ✅ built | The formatter places each comment by its span. Tests: `comments_inside_a_body_are_placed`, `comments_inside_a_call_and_a_list_are_placed` (`crates/blue-lang-fmt/src/lib.rs`). |
| Entropy | ✅ built | `random_bytes(n)` reads the kernel's non-blocking device under `Capability::Entropy` (`crates/blue-lang-runtime/src/entropy.rs`, test `a_draw_has_the_requested_length_of_byte_integers`). |
| Encryption | ❌ not built | The `crypto` layer hashes, signs and verifies (`crates/blue-lang-runtime/src/crypto.rs`). A keypair comes from a seed the caller supplies. The ciphers in `angou` are classical and insecure by design. |
| TLS | ❌ not built | `net` speaks NATS and HTTP over plain TCP. An `https://` URL and a NATS server that requires TLS are refused by name (`crates/blue-lang-runtime/src/net/http.rs`, `net/nats.rs`). The plan is HTTP2.md P4: rustls with ALPN `h2`. |
| Import emission into a wasm module | ❌ not built | `blue_lang_waku::imports_of` derives the import table from a frame (`crates/blue-lang-waku/src/imports.rs`). Nothing writes that table into a `.wasm`, and no engine border uses it. |
| Editor answers inside a broken buffer | ❌ not built | The parser does no error recovery. The language server answers from the newest revision that parsed (`crates/blue-lang-lsp/src/analysis.rs`). The plan is [CST-PLAN.md](CST-PLAN.md). |
| Project rules in the editor or as wasm | ❌ not built | `blue check` runs project rules in-process under the rule frame (`crates/blue-lang-runtime/src/project_rules.rs`). The language server does not run them. The ABI fits a wasm module, but nothing builds one. |
| A move the send ring cannot carry | ❌ not built | A moved plain process carries its tape, mailbox journal and host-call count (`blue-image` version 5). A moved server carries its journal, count and state root (version 6). An account past the tape bound or the send ring stays behind. That process's journal, count and receipt root start again at the new node (`crates/blue-lang-proc/tests/nomad.rs`, `a_plain_process_whose_tape_the_send_ring_cannot_hold_still_moves_and_its_trace_says_the_tape_stayed`). |
| A link across nodes | ❌ not built | `evict` breaks a link and tells a partner that traps exits. It refuses a partner that does not (`evict_breaks_a_link_with_evicted_for_every_partner_that_traps_exits_and_names_one_that_does_not`). |
| An authenticated image | ❌ not built | An image's BLAKE3 name proves that it arrived whole. It does not prove who sent it. The image runs under the frame of the node that accepts it, never more (`crates/blue-lang-proc/src/image.rs`). |
| `case` and `when` pattern matching | ✅ built | A `when` destructures a union arm, a list and a map. B0081 refuses a `case` that misses an arm (`spec/rows/patterns.b`, `spec/rows/unions.b`). |
| Range syntax `a..b` | ❌ not built | `range(a, b)` and `range(a, b, step)` exist (`spec/rows/lists.b`). The parser refuses `1..3`. The plan is OPERATORS.md O1. |
