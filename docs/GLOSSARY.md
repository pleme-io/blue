---
kind: reference
summary: every blue term mapped to the compiler, language or distributed-systems concept it names, in both directions, and how the parts meet in a compile, a test run and a deploy
---

# Glossary: blue's terms and the concepts they name

blue names many of its parts in Japanese or in its own words. This page maps
each name to the standard concept you already know. Each table row gives the
concept in bold, one sentence on what blue does, and the page that owns the
term. A name from Japanese carries its kanji and its literal gloss. A row
marked **design** describes something that is not built.

Every entry is read from the code and the docs on 2026-10-30. When an entry
and its owning page disagree, the owning page is right: fix this page.

## The language and its files

| blue term | standard concept |
|---|---|
| blue | **A general-purpose, gradually typed language.** Its surface reads like Ruby and Elixir, it parses to a tatara-lisp tree, and a Rust runtime runs that tree. [introduction.md](introduction.md) |
| `.b` | **The source-file extension.** Every blue program, script and bidama file ends in `.b`. [agents.md](agents.md) |
| `blue-lang-*` | **The crate prefix.** blue's Rust crates carry it because the bare name `blue` is taken on crates.io. [agents.md](agents.md) |
| tatara-lisp | **The intermediate representation, an s-expression tree.** The parser lowers every blue program to a tatara-lisp tree, and the `tatara-lisp-eval` crate evaluates it. [implementing.md](implementing.md) |
| the pipeline (parse → check → erase → run) | **The compiler driver's fixed phase order.** `blue_lang_runtime::pipeline` owns the order, because erase before check and run before check both turn the checker off without an error. [pipeline.rs](../crates/blue-lang-runtime/src/pipeline.rs) |
| parse | **Lexing and parsing to an AST.** `blue-lang-syntax` lexes the surface and lowers it to a spanned tatara-lisp tree. [blue-lang-syntax](../crates/blue-lang-syntax/Cargo.toml) |
| check | **Static analysis: name resolution, lints and type checks in one stage.** The check stage runs every `RULES` row on every door, so an error-severity rule stops a program before it runs. [DIAGNOSTICS.md](DIAGNOSTICS.md) |
| erase | **Type erasure.** The erase stage deletes each annotation after the check stage reads it, so an annotated and an unannotated definition run as the same tree. [erase.rs](../crates/blue-lang-runtime/src/erase.rs) |
| run | **Evaluation by a tree-walking interpreter.** `tatara-lisp-eval` walks the erased tree; a bytecode VM exists, but `blue run` does not use it. [COMPILE-TIME.md](COMPILE-TIME.md) |
| lowering | **Desugaring.** A shorthand is defined by the longer form it rewrites to: `x++` lowers to `x += 1`, which lowers to `x = x + 1`. [CANONICAL-FORMS.md](CANONICAL-FORMS.md) |
| door | **A front end, or an entry point into the compiler.** A door is one way into the pipeline: `blue run`, `blue test`, `blue check`, the language server or a bidama build. [DIAGNOSTICS.md](DIAGNOSTICS.md) |
| script | **A single-file program.** A `.b` file that opens with `#!/usr/bin/env blue` runs with every standard bidama and no Bluefile. [agents.md](agents.md) |
| project | **A package root with a manifest.** `blue new NAME` writes a Bluefile, its lock, a stub `flake.nix`, a bidama and a `main.b`. [agents.md](agents.md) |
| `def main()` | **The program entry point.** `blue run` calls `main` after the top level; `blue test`, `blue check` and `use` never call it. [agents.md](agents.md) |
| session (`eval`, `repl`, `serve`) | **A sandboxed REPL.** A session refuses code that reaches the host unless it starts with `--allow`, and `--budget STEPS` bounds each evaluation. [agents.md](agents.md) |
| distribution | **The standard library that ships inside the binary.** The distribution is the set of bidamas compiled into `blue`, so a script can `use` them with no install. [agents.md](agents.md) |
| `BLUE_PATH`, `BLUE_DIST` | **The module search path.** `use` looks in the project's `packages` roots, then `BLUE_PATH`, then `BLUE_DIST`, then the compiled-in distribution. [agents.md](agents.md) |
| zenbu (全部, *all of it*) | **A facade, or meta-package.** zenbu depends on every bidama in the distribution, as one dependency. [NAMES.md](../bidamas/NAMES.md) |
| macro (`defmacro`) | **A non-hygienic Lisp macro.** A program's own macro expands while the program runs, after the check stage; hygiene by construction is **design**. [COMPILE-TIME.md](COMPILE-TIME.md) |

## Packages, manifests and builds

| blue term | standard concept |
|---|---|
| bidama (ビー玉, *glass marble*) | **A package.** A bidama is a directory of `.b` files with a Bluefile, a version and its own namespace; the word replaces "package" in blue's surface and tools. [blue-lang-bidama](../crates/blue-lang-bidama/src/lib.rs) |
| Bluefile | **A package manifest that is also a build file (`Cargo.toml` and `build.rs` in one).** A Bluefile is a blue program; its words record facts, and it runs in a frame that binds only those words. [bluefile.rs](../crates/blue-lang-pkg/src/bluefile.rs) |
| Bluefile word | **A manifest key.** Each word (`package`, `needs`, `generate`, `service`, `allow`, …) is one row of `WORDS` in `blue-lang-pkg`, with its signature and what it records. [REFERENCE.md](REFERENCE.md) |
| Bluefile.lock | **A lockfile that holds the evaluated manifest.** It is blue's evaluation of the Bluefile as JSON, so nix reads it and never runs blue. [lock.rs](../crates/blue-lang-pkg/src/lock.rs) |
| `blue lock` | **Lockfile generation plus a permission check.** It evaluates the Bluefile, derives `needs` from the `use` forms, pins each `source` with `nix flake prefetch`, checks the capability lattice, and writes no lock when the check fails. [SAFETY.md](SAFETY.md) |
| `needs` | **A dependency with a version range.** `blue lock` derives a bidama's needs from its `use` forms; a Bluefile `needs` row only narrows a range (B0019). [DIAGNOSTICS.md](DIAGNOSTICS.md) |
| version solver | **A dependency resolver.** `blue-lang-pkg` searches by backtracking with conflict attribution, not PubGrub, and stops at a step bound. [solve.rs](../crates/blue-lang-pkg/src/solve.rs) |
| `use("pkg")` | **An import.** `use("retsu")` makes `retsu::name` reachable; `use("retsu", [:first])` also binds `first` bare in this file. [NAMESPACES.md](NAMESPACES.md) |
| namespace | **A module namespace.** Each bidama is a namespace: a file reaches another bidama's definition qualified or listed in `use`, never bare (B0012). [NAMESPACES.md](NAMESPACES.md) |
| `pkg::name`, `blue::name` | **A qualified name.** A qualified name skips the resolution tiers; `blue::first` names the builtin even past a definition of the same name. [NAMESPACES.md](NAMESPACES.md) |
| resolution tiers | **Scope-resolution order.** A bare name is a local, else the file's own bidama's definition, else a listed name, else a builtin or master verb; `blue explain-name` shows each tier. [NAMESPACES.md](NAMESPACES.md) |
| `legacy_names` | **A deprecated alias with a sunset.** A renamed definition keeps its old name as a bridge until the next minor version, and `blue migrate` rewrites the callers. [NAMESPACES.md](NAMESPACES.md) |
| `generate` and `nix run .#regen` | **A code-generation target with a freshness check.** `generate(name, output, program)` names a committed file that a blue program writes; `checks.generated-<name>-fresh` fails on a stale copy, and `nix run .#regen` rewrites it. [Bluefile](../Bluefile) |
| `checks.<name>` | **A CI test target.** A Bluefile `check(name, file)` becomes a nix flake check that runs `blue test` on the file. [agents.md](agents.md) |
| registry (sui, FlakeHub) | **A package registry.** A Bluefile `registry` entry renders the publish workflow for sui (first) or FlakeHub (optional); the lock stays the source of truth. [REGISTRY.md](REGISTRY.md) |
| `Cargo.gen.lock` | **A committed Nix build spec for Cargo, in the crate2nix family.** It is a delta of `Cargo.lock` that lets substrate build with no import-from-derivation; `gen build .` regenerates it. [CARGO-GEN-LOCK.md](CARGO-GEN-LOCK.md) |
| consumer | **A downstream dependent.** A consumer is a pleme-io repository with `.b` files; `blue gen/consumers.b sweep` runs this blue's `fmt --check` and `check` over each one. [implementing.md](implementing.md) |
| `git land` | **A merge queue.** `git land` pushes HEAD to `land/<slug>`; CI runs on that commit, and a green run fast-forwards `main`. [implementing.md](implementing.md) |
| pre-push gate | **A pre-push hook.** `gen/prepush.b` runs the fast gates that the changed paths select; `BLUE_PREPUSH_OFF=1` turns it off. [implementing.md](implementing.md) |

## Rigor: the blueshift and the typing ladder

| blue term | standard concept |
|---|---|
| blueshift | **Gradual typing as a continuum.** The blueshift is a program's position between loose (the tatara-lisp end) and locked (the Rust end); each declaration moves it toward Rust, and `blue shift` reports it. [climb-the-blueshift.md](howto/climb-the-blueshift.md) |
| rung | **A strictness level.** A rung is a named position on the blueshift: dynamic (0), annotated (1), checked (2) or restricted (3); a file stands on the lowest rung its declarations justify. [shift.rs](../crates/blue-lang-lsp/src/shift.rs) |
| restricted (rung 3) | **Hermetic build-time evaluation.** A restricted file is checked, and its macro phase reads only declared, content-addressed build inputs. [shift.rs](../crates/blue-lang-lsp/src/shift.rs) |
| typing ladder | **Pay-as-you-go type checking.** The checker visits no node of an unannotated program and checks only the structure that is declared. [blue-lang-check](../crates/blue-lang-check/src/lib.rs) |
| `Dyn` | **The dynamic type (`any`).** `Dyn` is the top type and the default, so unannotated code is less analysed, never less correct. [blue-lang-check](../crates/blue-lang-check/src/lib.rs) |
| seam | **A runtime cast at a typed/untyped boundary, as gradual typing inserts.** When typed code receives an argument of unknown type, the checker records a seam (a runtime check at that call), and `blue check` lists it. [blue-lang-check](../crates/blue-lang-check/src/lib.rs) |
| unsafe seam | **An FFI boundary that holds Rust `unsafe`.** blue allows `unsafe` only at one audited seam per foreign ABI; `blue-lang-kiwari` enforces this today, and a workspace-wide deny is **design**. [SAFETY.md](SAFETY.md) |
| FORM axis | **One canonical syntax, as gofmt gives, extended to spelling.** Each thing has one spelling, the shortest that stays distinct, and every tool writes it. [CANONICAL-FORMS.md](CANONICAL-FORMS.md) |
| RIGOR axis | **Opt-in static analysis.** Types, memory and capability limits slide per declaration: declare nothing and get no analysis. [theory/BLUE.md](https://github.com/pleme-io/theory/blob/main/BLUE.md) |
| canonical spelling | **The formatter's one chosen syntax.** blue reads older or borrowed spellings (`&&`, `unless`, `x.f(y)`) and writes one; `blue fmt --write` and `blue check --fix` rewrite a file to it. [CANONICAL-FORMS.md](CANONICAL-FORMS.md) |
| the mark (blueshift ramp) | **The logo.** The mark is four solid cells across Nord's Frost band, `nord7` to `nord10`: a shift in colour, not in density. [blue-lang-art](../crates/blue-lang-art/src/lib.rs) |
| irodori | **The fleet's colour-palette library (Nord).** `blue-lang-art` reads every colour from the `irodori` crate, and blue carries no hex of its own. [blue-lang-art](../crates/blue-lang-art/src/lib.rs) |

## Frames, capabilities and postures

| blue term | standard concept |
|---|---|
| waku (枠, *frame*) | **An execution context that holds a capability set.** A waku says what a computation may depend on, in three parts (REACH, WHEN, WHERE); its only operation is `narrow`, and narrow cannot widen. [blue-lang-waku](../crates/blue-lang-waku/src/lib.rs) |
| REACH | **The set of bound capabilities.** REACH is what a computation may name; a name outside it is an absent binding, not a call-time check. [blue-lang-waku](../crates/blue-lang-waku/src/lib.rs) |
| WHEN | **The evaluation phase (staging).** WHEN says what has already run: `sealed` (nothing; no resident evaluator), `preceding` (earlier forms only, the macro phase) or `anytime` (`eval` allowed). [blue-lang-waku](../crates/blue-lang-waku/src/lib.rs) |
| WHERE | **The memory region.** WHERE is the heap a computation uses: an arena freed at scope exit, its process's own heap, or shared frozen data. [blue-lang-waku](../crates/blue-lang-waku/src/lib.rs) |
| `narrow` | **A monotonic privilege drop (a lattice meet).** `narrow` returns the meet of a frame and a bound, and no method returns a frame above its receiver. [blue-lang-waku](../crates/blue-lang-waku/src/lib.rs) |
| capability | **An object capability, kept as a closed enum.** A capability is a named bundle of identifiers that a frame may grant; the six host capabilities are `process`, `filesystem`, `environment`, `clock`, `network` and `entropy`. [capability.rs](../crates/blue-lang-waku/src/capability.rs) |
| floor (`reach`) | **The permissions a dependency requires.** A bidama's floor is the set of host capabilities its code names, or its declared `reach(%i[…])`, which must cover them. [SAFETY.md](SAFETY.md) |
| ceiling (`allow`) | **The permissions an application grants.** Only the root declares a ceiling, with `allow(%i[…])`; a bidama never declares one. [SAFETY.md](SAFETY.md) |
| the lattice check | **Permission resolution over the dependency closure.** `blue lock` joins every floor in the closure, checks `⋁ floors ⊑ allow ∨ provided`, and names the path to each package that breaks it. [capabilities.rs](../crates/blue-lang-pkg/src/capabilities.rs) |
| `--allow CAP` | **A sandbox flag, like Deno's `--allow-*`.** `blue run --allow` or a shebang `--allow` holds a run to `none`, `host` or the named capabilities, and it only narrows a project's `allow`. [SAFETY.md](SAFETY.md) |
| ambient | **Ambient authority.** A run with no `--allow`, outside a project that declares `allow` or `virtualize`, reaches every host capability; this is still the default of `blue run`. [SAFETY.md](SAFETY.md) |
| hold | **A runtime permission policy.** The hold binds each withheld host name to a breach and each virtualized name to its provider, for the run and every process it spawns. [SAFETY.md](SAFETY.md) |
| breach | **A fatal permission violation.** A breach raises an error that no `rescue` or `ensure` sees, and `blue run` exits 77 (`EX_NOPERM`). [SAFETY.md](SAFETY.md) |
| `virtualize` | **A test double for a system resource, injected by the manifest.** `virtualize(cap, {using: …})` binds a host capability to a pure provider, for the whole program or `for:` the named packages. [SAFETY.md](SAFETY.md) |
| provider | **A deterministic stand-in implementation.** The providers are `deterministic_stepped` (clock), `seeded_prng` (entropy), and `in_memory_overlay` or `null_sink` (filesystem); process, network and environment have none. [provision.rs](../crates/blue-lang-waku/src/provision.rs) |
| posture (frame) | **A point in the permission and staging lattice.** A posture is a waku position; the Bluefile word `posture(when)` declares a package's WHEN floor, `"sealed"`, `"preceding"` or `"anytime"`. [bluefile.rs](../crates/blue-lang-pkg/src/bluefile.rs) |
| engine posture | **The permission set of an embedded interpreter.** `Load::posture(allowed)` in `blue-lang-host` binds every host effect it does not allow as a refusal. [SERVICE-ACCESS.md](SERVICE-ACCESS.md) |
| morphology (`blue morph`) | **A feature matrix of language modes.** It maps each posture to the qualities it grants and forfeits, and lists the pairs that truly exclude each other. [theory/BLUE.md](https://github.com/pleme-io/theory/blob/main/BLUE.md) |
| appliance (`blue bundle`) | **A sealed single-file executable.** `blue bundle FILE --runner blue-appliance` seals the compiled program and its lock's capability record onto a runner, which checks the BLAKE3 digest and runs held to that record. [SAFETY.md](SAFETY.md) |
| pure, volatile | **Purity (effect) analysis.** mondou marks a definition pure only when its answer depends on its arguments alone; a host call, another effect, nondeterminism or an outer mutation makes it volatile. [reach.rs](../crates/blue-lang-mondou/src/reach.rs) |

## Diagnostics, rules and ratchets

| blue term | standard concept |
|---|---|
| B-code (`B0001` …) | **A compiler error code, like rustc's `E0382`.** Each B-code is a `RULES` row with a slug, a severity, a law, a witness and a fix kind; `blue explain CODE` prints it. [DIAGNOSTICS.md](DIAGNOSTICS.md) |
| `RULES` | **The lint registry.** Every rule blue enforces is a row in one table in `blue-lang-check`, and the check stage runs it, so no door skips it. [DIAGNOSTICS.md](DIAGNOSTICS.md) |
| witness | **A failing fixture.** A rule's witness is a short program that breaks the rule, and the rule must flag it. [rules.rs](../crates/blue-lang-check/src/rules.rs) |
| waiver (`# waive CODE: reason`) | **A lint suppression with a required reason, like `#[allow]`.** A waiver above a definition silences one code; a waiver with no reason (B0007) or one that silences nothing (B0008) is an error. [DIAGNOSTICS.md](DIAGNOSTICS.md) |
| project rule (`R0001` …) | **A custom lint, written in the project's own language.** `rule(code, file, def)` names a blue definition that gets each top-level form as data and returns findings; `blue check` runs it in a pure frame under a step budget. [DIAGNOSTICS.md](DIAGNOSTICS.md) |
| okite (掟, *the rules one lives by*) | **Architecture decision records with executable properties.** okite keeps each decision as a record (id, date, rule, why) with the laws that enforce it; the build fails when a decision has no law or a law fails. [RULES.md](../bidamas/okite/RULES.md) |
| D-code (`D0004` …) | **A decision ID.** A D-code names one okite decision; D0004 says that `nil` and `[]` are different values. [RULES.md](../bidamas/okite/RULES.md) |
| law | **A property-based test.** A law is a blue function that returns true when a rule holds; the generative laws run over hundreds of seeded values. [okite.b](../bidamas/okite/okite.b) |
| ratchet | **A baseline that may only shrink (a "no new violations" gate).** A rule with `ratchet: Some(n)` counts its findings without failing; the commit that reaches zero makes it an error on every door. [DIAGNOSTICS.md](DIAGNOSTICS.md) |
| census (`blue census`) | **A violation counter for a staged lint rollout.** `blue census ROOT` counts each finding of every rule still ratcheting in, and `checks.namespace-census` fails unless each count equals its row's ratchet exactly. [DIAGNOSTICS.md](DIAGNOSTICS.md) |
| hadome (歯止め, *ratchet pawl*) | **A baseline file with a ratchet judge.** hadome reads a `<kind>: <key> <size>` baseline and judges each measurement unrecorded, held or grew, so recorded debt shrinks or holds and never grows. [NAMES.md](../bidamas/NAMES.md) |
| `blue check --fix` | **An autofix, like `cargo fix` or `eslint --fix`.** It applies every machine-applicable fix the rules carry. [agents.md](agents.md) |
| `blue migrate` | **A codemod.** It makes each implicit reference to another bidama explicit, and it keeps a file only when its resolved tree is unchanged. [NAMESPACES.md](NAMESPACES.md) |
| form is the producer's | **Per-package editions, as Rust judges each crate by its own edition.** A dependency compiles as written and is judged on meaning only, so a consumer never fails because a dependency is written for another blue. [COMPOUNDING.md](COMPOUNDING.md) |
| seal tier | **The strength of a guarantee.** blue grades each prevented bad state, from truly unrepresentable through parse-time-rejected and CI-caught to only mitigated, and names the ceiling of each weak grade. [VOCABULARIFY-SURFACE.md](VOCABULARIFY-SURFACE.md) |
| DESIGN tier | **A "proposed" status.** A DESIGN row is stated and not built; work that builds against one says so. [agents.md](agents.md) |
| blind | **An inconclusive result.** A probe that cannot observe reports blind, which counts apart and never as a pass. [spec/README.md](../spec/README.md) |

## Tools and the engine

| blue term | standard concept |
|---|---|
| mondou (問答, *question and answer*) | **A memoized query engine on the salsa and rust-analyzer model.** Every tool asks mondou the same queries, and it computes each answer once: a parse per text, an analysis per document revision, a bidama per session; it is hand-written (no salsa crate), and salsa-style early cutoff is **design**. [blue-lang-mondou](../crates/blue-lang-mondou/src/lib.rs) |
| language server (`blue lsp`) | **An LSP server.** `blue-lang-lsp` is a transport-free analysis core over mondou plus a JSON-RPC stdio shim; it adds a `blue/shift` request for the blueshift. [blue-lang-lsp](../crates/blue-lang-lsp/src/lib.rs) |
| `blue serve` | **An editor protocol for live evaluation, like nREPL.** It serves one evaluation session as JSON lines on stdin and stdout. [agents.md](agents.md) |
| `blue query` | **A code query language, like CodeQL or Semgrep.** It lists every definition a query matches over the resolved tree, with forms such as `(match PATTERN)` and `(reaches CAP)`. [DIAGNOSTICS.md](DIAGNOSTICS.md) |
| `def_hash` | **A content hash of a resolved definition, as Unison uses.** mondou hashes each definition's resolved tree, and the call memo keys pure calls by it. [blue-lang-mondou](../crates/blue-lang-mondou/src/lib.rs) |
| recall | **Automatic memoization of pure functions.** mondou answers a call it proves pure from the `def_hash` and the arguments; it is off unless a door turns it on. [recall.rs](../crates/blue-lang-mondou/src/recall.rs) |
| `blue fmt` | **A formatter with no options, like gofmt.** `blue-lang-fmt` gives one output per program, and no configuration surface exists. [CANONICAL-FORMS.md](CANONICAL-FORMS.md) |
| kiwari (木割, *the carpenter's proportioning rule-book*) | **A single-source grammar specification.** kiwari holds blue's one grammar as data and renders tree-sitter's `grammar.js` and queries from it; `blue-lang-kiwari` holds that grammar equal to blue's own parser. [NATURALIZE-TREESITTER.md](NATURALIZE-TREESITTER.md) |
| kigou (記号, *symbol*) | **A Unicode character-class and operator-alias table.** kigou decides what each non-ASCII character means: an alias of an operator blue has (`≠` is `!=`), part of a name (`λ`), or a lex error. [VOCABULARIFY-SURFACE.md](VOCABULARIFY-SURFACE.md) |
| yakugo (訳語, *equivalent term*) | **Localized keywords, a non-English surface syntax.** A yakugo pack rewrites identifier tokens before the parser, so `définir … fin` gives the same tree as `def … end`. [VOCABULARIFY-SURFACE.md](VOCABULARIFY-SURFACE.md) |
| surface | **A concrete-syntax skin over one AST.** A surface is the human language a program is written in, and kigou and yakugo are its vocabulary; `BLUE_LANG` selects it, and an unknown tag is an error. [VOCABULARIFY-SURFACE.md](VOCABULARIFY-SURFACE.md) |
| sabi (錆, *rust*) | **A Rust code generator.** sabi renders Rust source from blue data; it writes kigou's tables into `blue-lang-syntax`. [NAMES.md](../bidamas/NAMES.md) |
| `blue-lang-host` | **An embedding API, like the Lua C API or mlua.** A Rust program adds one dependency and a `#[host]` impl block, and calls blue definitions with typed values. [blue-lang-host](../crates/blue-lang-host/Cargo.toml) |
| `blue-lang-wasm` | **A WebAssembly target with no imports.** It compiles blue to a module with no host imports and no WASI. [blue-lang-wasm](../crates/blue-lang-wasm/Cargo.toml) |
| `blue-lang-component` | **A WASI preview 2 component.** It is the blue engine as one WASI command component that runs one blue service program. [BUILD-STACK.md](BUILD-STACK.md) |

## Testing

| blue term | standard concept |
|---|---|
| `test` block | **An inline unit test, like Rust's `#[test]` in the same file.** A `test "name" … end` block sits beside its code; `blue run` drops it, and `blue test` runs each block in its own forked interpreter. [test-and-doctest.md](howto/test-and-doctest.md) |
| doctest | **An executable doc example, as in Rust and Elixir.** An indented `expr #=> value` line in a `@doc` is a test, and `blue test` runs it beside the `test` blocks. [test-and-doctest.md](howto/test-and-doctest.md) |
| `@doc`, `@moduledoc` | **Doc comments as typed values, as in Elixir.** `@moduledoc` opens a bidama with its purpose and an example, and `@doc` documents one definition; B0056–B0060 refuse a missing, empty or restated one. [DIAGNOSTICS.md](DIAGNOSTICS.md) |
| hermetic `blue test` | **Test isolation from the host.** `blue test` drops the inherited `GIT_DIR` family and refuses a write outside `TMPDIR`; `BLUE_TEST_ENV=inherit` and `BLUE_TEST_WRITES=anywhere` turn each off. [agents.md](agents.md) |
| tesuto (テスト, *test*) | **Assertion helpers and snapshot tests.** tesuto checks that a function raises a given error kind, and compares a value with its stored snapshot. [NAMES.md](../bidamas/NAMES.md) |
| test-beside | **A coverage gate per definition.** `checks.test-beside` fails when a package has more definitions that no test reaches than its recorded hadome debt; `waive(name, why, until)` excuses one. [TESTING.md](TESTING.md) |
| heni (変異, *mutation*) | **Mutation testing, like cargo-mutants.** heni changes one literal in a fresh copy of a package and runs its tests, which must fail; each mutation ends caught, survived, refused or blind. [TESTING.md](TESTING.md) |
| conformance row | **A conformance test, like test262.** A row in `spec/rows/` states one observable behaviour, and every evaluator must agree with stage 0 on it. [spec/README.md](../spec/README.md) |
| evaluator column | **Differential testing across implementations.** The suite runs each row on `walker`, `vm`, `wasm`, `cli` and `static`, and a column that disagrees with stage 0 fails. [spec/README.md](../spec/README.md) |
| `pending("<gap>")` | **A strict expected failure (strict xfail).** A pending row names its gap and fails the run when the gap closes, until the mark is removed. [agents.md](agents.md) |
| second implementation (`*-diff` crates) | **An oracle for differential testing.** `blue-lang-yaml-diff` and `blue-lang-danpen-diff` run yaml-rust2 and apollo-compiler on the same corpus and compare the results with blue's. [blue-lang-yaml-diff](../crates/blue-lang-yaml-diff/Cargo.toml) |

## Batteries and the verb graph

| blue term | standard concept |
|---|---|
| battery (lateral) | **A batteries-included module for one cross-cutting concern.** Each concern that every program carries (errors, retries, configuration, logs) is one bidama or primitive with one verb set; the full lateral map is **design**. [theory/BLUE.md](https://github.com/pleme-io/theory/blob/main/BLUE.md) |
| kyohi (拒否, *refusal*) | **Errors as values: a list of validation results.** A refusal is `[kind, why]`; `check` returns every refusal a subject has, and `enforce` raises them as one error. [NAMES.md](../bidamas/NAMES.md) |
| kousei (構成, *composition*) | **Declarative configuration with per-entry validation.** A declaration is a list of entries, each checked, configured `off`, tuned or refused alone; `judge` sorts them into accepted, off and refused, so one bad entry never fails its siblings. [kousei.b](../bidamas/kousei/kousei.b) |
| settei (設定, *settings*) | **Layered configuration, twelve-factor style.** `settei::read(app, defaults)` resolves the defaults, then `~/.config/<app>/<app>.yaml`, then `<APP>_<GROUP>__<KEY>` variables, each typed by its default. [settei.b](../bidamas/settei/settei.b) |
| shisei (姿勢, *posture*) | **A middleware stack with secure defaults.** A service posture is a kousei entry whose layer wraps a handler; each one runs by default, and one that can refuse a request has an audit-or-enforce mode. [shisei.b](../bidamas/shisei/shisei.b) |
| bougyo (防御, *defence*) | **Request-defence middleware, like Helmet plus request limits.** bougyo adds security headers and a request id and limits method, path, headers and body; `limits` defaults to `audit`. [bougyo.b](../bidamas/bougyo/bougyo.b) |
| saishikou (再試行, *retrying*) | **Retry with exponential backoff.** `saishikou::retrying(policy, step)` calls `step` again after a doubling pause, up to `times` calls, for the error kinds in `on`; it holds no supervisor restart policy. [saishikou.b](../bidamas/saishikou/saishikou.b) |
| mokuroku (目録, *catalogue*) | **A package index with API docs.** mokuroku reads every bidama on a `BLUE_PATH` (manifest, gloss, tests, each `def` with its `@doc`), and it holds the verb-graph rows. [mokuroku.b](../bidamas/mokuroku/mokuroku.b) |
| hon (本, *book*) | **A documentation generator, rustdoc and mdBook in one.** hon reads the Diátaxis pages, the `@doc` attributes and the Bluefile, and renders the reference, the book, `README.md`, `AGENTS.md`, `CLAUDE.md` and the llms files; the static site is **design**. [DOCUMENTATION.md](DOCUMENTATION.md) |
| Diátaxis kind | **The document type.** Each page under `docs/` declares `kind: tutorial`, `howto`, `reference` or `explanation`, and `checks.docs` refuses a page with none. [DOCUMENTATION.md](DOCUMENTATION.md) |
| verb graph | **A registry of the library's operations, a typed API vocabulary.** Each verb is a row in `bidamas/mokuroku/graph/`, one file per space, and `blue verbs check` gates the graph against a recorded baseline; the roadmap that fills it is **design**. [DESIGN.md](verbs/H/DESIGN.md) |
| space | **A module, or protocol namespace, for verbs.** A space groups the verbs of one subject, called as `space::verb`; a provisional space ends in `?`. [VERB-ROADMAP.md](VERB-ROADMAP.md) |
| verb contract | **An interface signature shared by every module that has the verb.** `contracts.tsv` gives each verb one argument shape, one return shape and one error behaviour across spaces. [contracts.tsv](verbs/contracts.tsv) |
| `need`, `get` | **The raising and the nil-returning accessor.** `need` raises when the value is absent and `get` returns `nil`; blue never names a `_or` variant. [agents.md](agents.md) |
| master verb | **A generic function with dynamic dispatch, like a protocol.** A master verb such as `has?`, `delete` or `diff` dispatches on its subject's space, and `verb_for` registers a space's handler. [REFERENCE.md](REFERENCE.md) |
| retsu (列, *row*) | **List utilities made total.** `size`, `first`, `rest` and `is_empty` accept `nil` and `[]` alike. [NAMES.md](../bidamas/NAMES.md) |
| deeta (データ, *data*) | **A JSON and YAML library.** deeta parses JSON and YAML 1.2, reads nested values safely and writes JSON or YAML. [NAMES.md](../bidamas/NAMES.md) |
| kueri (クエリ, *query*) | **A query builder that renders SQL.** kueri holds analysis as a query IR in blue and renders SQL for DuckDB. [NAMES.md](../bidamas/NAMES.md) |
| kazu, shuugou, kansuu, jisho | **Numbers, sets, function combinators and maps.** These are the small core bidamas the agent guide names in its traps (数, 集合, 関数, 辞書). [NAMES.md](../bidamas/NAMES.md) |
| kirikae (切り替え, *switching over*) | **A NixOS switch planner.** kirikae decides whether a system switch must run, may be skipped or must wait, and it is settei's worked example. [NAMES.md](../bidamas/NAMES.md) |

## Services and deployment

| blue term | standard concept |
|---|---|
| `service(...)` | **A service declaration, like a Compose service.** One Bluefile word states the program, port, probes, config, access, runtime and bindings, and every deploy file is a rendering of it. [BUILD-STACK.md](BUILD-STACK.md) |
| `access` | **A least-privilege manifest: a pod security context plus a NetworkPolicy.** `access` lists a service's effects, egress peers, read and write paths, listen ports and programs it runs; the engine posture is built, and most other renderings are **design**. [SERVICE-ACCESS.md](SERVICE-ACCESS.md) |
| runtime rung (wasm, native) | **The deployment target.** A service runs as a WASI preview 2 component by default, and `runtime: :native, because: :<gap>` picks a native process for a named WASI gap (`process`, `host_program`, `device`). [BUILD-STACK.md](BUILD-STACK.md) |
| haibi (配備, *deployment*) | **A Helm chart generator.** haibi renders a `service` into a chart with a closed, generated `values.schema.json`, its config defaults and, for a declared schema, the SQL migration. [NAMES.md](../bidamas/NAMES.md) |
| `blue workload render` | **Committed Kubernetes manifests for GitOps.** It renders a Bluefile `workload` into Kubernetes objects in committed, freshness-gated files. [agents.md](agents.md) |
| `blue image build` | **A container image build.** It builds a Bluefile `image` through nix and reports the tarball, its size and its layers. [agents.md](agents.md) |
| `blue diff --context` | **A read-only `kubectl diff`.** It compares the committed workload files with a cluster; no `blue apply` exists, because a GitOps reconciler applies the commit. [agents.md](agents.md) |
| placement | **A deployment-target binding, like a Kustomize overlay.** `placement(name, {node:})` or `{cluster:, namespace:}` says where a service runs, with per-place values; Flux objects per placement are **design**. [BUILD-STACK.md](BUILD-STACK.md) |
| `blue-lang-proc` | **Erlang/OTP processes and supervisors.** Each process owns its VM and interpreter, a message is deep-copied, and a supervisor restarts children one-for-one, one-for-all, rest-for-one or simple-one-for-one; supervision as a service default is **design**. [blue-lang-proc](../crates/blue-lang-proc/src/lib.rs) |
| kyuuji (給仕, *serving*) | **An HTTP/1.1 server loop.** kyuuji runs handlers as functions from a request to a response record, with a built-in health path, and answers a raise with 500. [NAMES.md](../bidamas/NAMES.md) |
| koutei (工程, *one production step*) | **A CI step toolkit, like `@actions/core`.** koutei reads `INPUT_*` inputs and writes outputs, step summaries and annotations; it is the `run.b` side of every blue action. [NAMES.md](../bidamas/NAMES.md) |
| fueki (不易, *the unchanging*) | **Write once, deploy anywhere by placement.** An application is declared once, and each runtime (WASI, Nix, OCI, engenho, Helm) is a renderer that a placement datum selects. [theory/FUEKI.md](https://github.com/pleme-io/theory/blob/main/FUEKI.md) |

## Fleet terms the docs use

These are pleme-io names outside blue. blue's docs and agent guide use them.

| fleet term | standard concept |
|---|---|
| shikumi | **A typed configuration library.** It is the fleet's config library; `settei` is blue's form of it, and `BlueConfig` implements `shikumi::TieredConfig`. [agents.md](agents.md) |
| substrate | **A Nix build-pattern library.** It builds blue's crates and holds the reusable `blue-project.yml` workflow. [BUILD-STACK.md](BUILD-STACK.md) |
| sui | **A Nix build scheduler and binary cache.** It builds each change once on the build node, and every other machine substitutes. [BUILD-STACK.md](BUILD-STACK.md) |
| engenho | **A Kubernetes runtime written in Rust.** It runs a service's chart on any node, and its wasm backend runs the component. [BUILD-STACK.md](BUILD-STACK.md) |
| Flux | **A GitOps reconciler (FluxCD).** It applies the committed objects to a cluster. [BUILD-STACK.md](BUILD-STACK.md) |
| Tela | **The fleet's frontend standard.** blue hosts a frontend framework that retargets Tela, and that framework is **design**. [theory/BLUE-FRONTEND.md](https://github.com/pleme-io/theory/blob/main/BLUE-FRONTEND.md) |

## Implementer terms

| blue term | standard concept |
|---|---|
| `INFIX` | **The operator-precedence table.** It is one table, and the parser and the formatter both read it, so a new operator is one new row. [implementing.md](implementing.md) |
| lowered name: OWNED or DELEGATED | **A reserved internal name, or a runtime intrinsic.** An OWNED name (`blue-assert`) must not be bound by the runtime; a DELEGATED name (`hash-map`) must be. [implementing.md](implementing.md) |
| the three arbiters | **Head resolution in a Lisp.** A special form, a macro or an environment binding can claim a name, and `Interpreter::resolve_head` says which one does. [implementing.md](implementing.md) |
| `blue_lang_runtime::interpreter` | **The runtime initializer (the prelude).** It installs both runtime layers; a hand-rolled `Interpreter::new()` omits the Lisp standard library. [implementing.md](implementing.md) |
| fork (`blue_lang_proc::forking`) | **A copy-on-write snapshot of an interpreter.** A fork shares the evaluated globals and isolates each child by its seal; a plain `Clone` is not a fork. [implementing.md](implementing.md) |
| parking primitive | **A blocking call that suspends a process.** `receive` parks until a message is ready, and it must not take the message before it parks. [implementing.md](implementing.md) |
| `format_source_lossless` | **A comment-preserving pretty-printer.** Every tool that shows a user their own file formats through it. [implementing.md](implementing.md) |

## Reverse index: from the concept you know to the blue term

| standard concept | blue term |
|---|---|
| ambient authority | ambient run |
| architecture decision record | okite decision (D-code) |
| AST, intermediate representation | tatara-lisp tree |
| autofix | `blue check --fix` |
| baseline, "no new violations" gate | ratchet, census, hadome |
| blocking receive | parking primitive |
| capability-based security | capability, waku REACH |
| CI step toolkit | koutei |
| code generation target | `generate`, `nix run .#regen` |
| code query language | `blue query` |
| codemod | `blue migrate` |
| compiler error code | B-code |
| compiler phases | the pipeline: parse, check, erase, run |
| configuration, layered | settei |
| configuration, per-entry validated | kousei |
| conformance suite | conformance rows (`spec/rows/`) |
| content-addressed definition | `def_hash` |
| coverage gate | test-beside |
| custom lint | project rule (R-code) |
| dependency resolver | version solver (`blue-lang-pkg`) |
| deployment target | runtime rung (wasm or native), placement |
| deprecated alias | `legacy_names` |
| desugaring | lowering |
| differential testing | evaluator columns, `*-diff` crates |
| doctest | doctest (`#=>` line in `@doc`) |
| documentation generator | hon |
| effect analysis, purity | pure and volatile (mondou reach) |
| embedding API | `blue-lang-host` |
| entry point | `def main()`; a door, for the compiler |
| errors as values | kyohi refusal |
| execution context, sandbox frame | waku |
| expected failure (strict xfail) | `pending("<gap>")` |
| facade, meta-package | zenbu |
| FFI boundary | unsafe seam |
| formatter | `blue fmt` |
| generic function, protocol dispatch | master verb |
| gradual typing | blueshift, typing ladder |
| gradual-typing cast | seam |
| grammar specification | kiwari |
| Helm chart generator | haibi |
| HTTP server loop | kyuuji |
| import | `use` |
| language server | `blue lsp` (`blue-lang-lsp`) |
| lint registry | `RULES` |
| lint suppression | `# waive CODE: reason` |
| localized keywords | yakugo |
| lockfile | Bluefile.lock |
| macro | `defmacro` |
| manifest | Bluefile |
| memoization | recall |
| merge queue | `git land` |
| middleware stack | shisei |
| module namespace | bidama namespace |
| module search path | `BLUE_PATH`, `BLUE_DIST` |
| mutation testing | heni |
| operator aliases, character classes | kigou |
| operator-precedence table | `INFIX` |
| OTP supervision | `blue-lang-proc` |
| package | bidama |
| package index | mokuroku |
| package registry | registry (sui, FlakeHub) |
| permission manifest (application) | ceiling, `allow` |
| permission manifest (dependency) | floor, `reach` |
| permission violation | breach |
| pre-push hook | `gen/prepush.b` |
| privilege drop | `narrow` |
| property-based test | okite law |
| query engine (salsa-like) | mondou |
| REPL | session (`blue repl`, `blue eval`, `blue serve`) |
| retry with backoff | saishikou |
| sandbox flag | `--allow` |
| security-header middleware | bougyo |
| single-file executable | appliance (`blue bundle`) |
| snapshot test | tesuto |
| standard library | distribution |
| static analysis stage | check |
| strictness level | rung |
| test double for clock, RNG or files | `virtualize` and its providers |
| type erasure | erase |
| unit test in the same file | `test` block |
| WASI component | `blue-lang-component` |
| write once, run anywhere | fueki |

## How the parts meet

### A compile: `blue run app.b`

1. The CLI finds the nearest project Bluefile above `app.b`. When that project declares `allow` or `virtualize`, `capabilities::hold_for` builds the hold. A project Bluefile that does not read refuses the run.
2. When `app.b` is not in canonical form, `blue run` rewrites it in place and prints `blue: formatted app.b`.
3. Parse. The lexer asks kigou what each non-ASCII character means. When `BLUE_LANG` names a surface, its yakugo pack rewrites the identifier tokens. The parser then lowers the surface to a spanned tatara-lisp tree.
4. Resolve. For each `use`, the loader searches the project's `packages` roots, then `BLUE_PATH`, then `BLUE_DIST`, then the compiled-in distribution. It splices in the bidama's forms. The run drops every `test` block.
5. Check. The check stage resolves each name by tier and runs every `RULES` row. The typing ladder checks only annotated definitions, and it records a seam where typed code meets `Dyn`. An error-severity finding stops the run with `file:line:col: error[CODE]`.
6. Erase. The pipeline lowers each name to its qualified form and deletes the type annotations. The spans stay.
7. Hold. When a frame applies, a withheld host name in the entry file refuses the program before anything runs. Every other withheld name is bound to a breach.
8. Run. tatara-lisp-eval's tree-walker evaluates the top level, then calls `main`. The program's own macros expand here. A withheld host call breaches and exits 77. A raise prints the blue call stack.
9. An editor takes the same path through mondou. The language server asks mondou; mondou parses once per revision and calls the same check stage. So the editor shows what `blue check` reports.

### A test run: `blue test lib.b`, then `nix flake check`

1. `blue test` drops the inherited `GIT_DIR` family. It refuses each write outside `TMPDIR`.
2. It reads `lib.b` and never writes it. A file that is not canonical is refused, and the message names the command that fixes it.
3. It checks the file as `blue check` does, with the test blocks kept. It erases the types.
4. It evaluates the top level once. It never calls `main`.
5. Each `test` block runs in its own forked interpreter. A `set!` on an inherited binding is refused, so test order cannot matter. Each `#=>` doctest line runs beside the blocks.
6. A failed `assert` prints the expression in canonical blue, through the formatter. The run ends with `N test(s): P passed, F failed`.
7. In CI, nix reads `Bluefile.lock` and never runs blue to evaluate it. It runs `bidama-test-<pkg>` for each package and `checks.<name>` for each `check(name, file)`. A `-fresh` check guards each generated file and each lock.
8. The gates around the tests then run: `checks.test-beside` (coverage against the hadome debt), `checks.heni-mutations` (each mutation must be caught), `checks.okite-laws` (each decision's laws), `checks.conformance` (each row on each evaluator) and `checks.namespace-census` (each ratchet count exact).

### A deploy: a blue service from Bluefile to a node

1. The author writes `service("name", {…, access: {…}})` and a `placement(…)` in the Bluefile.
2. `blue lock .` evaluates the Bluefile in its frame, checks the capability lattice and writes `Bluefile.lock`. blue calls nix to pin the sources; nix never calls blue.
3. nix (`blue.lib.project`) reads the lock and lowers each word to packages, checks and apps. `nix run .#regen` rewrites every generated file, and the `-fresh` checks fail until the diff is committed.
4. The runtime judge (`blue_lang_pkg::deploy::runtime`) reads `access` and `host`. It picks a WASI preview 2 component by default. A named gap (`process`, `host_program`, `device`) picks native.
5. haibi renders the Helm chart and its closed values schema into `deploy/<service>/`. `blue workload render --write` renders the Kubernetes objects. `blue image build` builds an image through nix for the native rung.
6. GitHub Actions runs substrate's `blue-project.yml`. sui builds once on the build node and caches the result. Every other machine substitutes. koutei writes each step summary.
7. Flux applies a HelmRelease and a Kustomization for each placement. This step is **design**. `blue diff --context CTX` compares the committed files with a cluster, read-only.
8. engenho runs the chart. On the wasm rung, engenho's `kidou` preopens the program bundle read-only at `/app` and derives the grants from `access`. The chart is built, but no release sets its component closure yet, and no deployed pod has run it.
9. Inside the service, `shisei::stack` composes the declared postures, bougyo's among them, around each handler. kyuuji answers a raise with 500. OTP supervision through `blue-lang-proc` is built, but no service uses it yet: that wiring is **design**.
