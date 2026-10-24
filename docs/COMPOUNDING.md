# Compounding: every evolution break fixes itself

The operator, 2026-10-23: *"the more we write blue, the easier it should be to
write blue; if not, question why and integrate how we make it so."*

blue evolves at full speed. A new rule or a retired word may break working
code, because a pin means nobody has to upgrade. The price of that speed is
one law:

> **Every break caused by blue's own evolution ships its fixer, and the error
> names the one command that applies it. A break without a fixer is a gap in
> blue, fixed in blue, never in the consumer.**

Two corollaries make "nobody has to upgrade" true:

1. **Form is the producer's.** A rule whose fix is machine-applicable
   preserves meaning (its registry row says so), so a violation is a fact about
   how a file is written. Two such rules are meaning all the same: B0012 (the
   runtime does not bind an implicitly reached name) and B0019 (a needs list
   is what a closure delivers). A file's form is judged by the blue its producer
   pins; a consumer judges a dependency only on meaning. A consumer never fails
   because a dependency is written for another blue.
2. **A test never writes.** `blue test` and `blue check` read; only an
   explicit write (`blue fmt --write`, `blue check --fix`) changes a file.

## The switches

Each is on by default and has a typed off value
(`crates/blue-lang-check/src/evolution.rs`). A value outside its set is
refused before any door runs.

| variable | values | default | off value restores |
|---|---|---|---|
| `BLUE_FORM` | `own`, `none`, `all` | `own`: the entry's form only | `all`: the importer judges every dependency's layout and form rules, as before 2026-10-23 |
| `BLUE_LAYOUT` | `judge`, `rewrite` | `judge` for `test` and `check`; `rewrite` for `run`, `profile`, `trace` | `rewrite`: a door formats its writable entry in place before compiling it |

The loader compiles a dependency as written under `own` and `none`; no compile
door writes a dependency under any value. In nix, a bidama's BUILD judges
meaning only (`BLUE_FORM=none`, `bidamas/mk-bidama.nix`), and its form is the
producer's check: `passthru.formCheck`, which `lib.project` exposes as
`checks.bidama-form-<pkg>` (`blue fmt --check` and `BLUE_FORM=own blue
check`, under the blue the producer's own lock pins). A consumer that makes
the producer follow its blue builds `packages`, never the producer's `checks`.

## The ledger

Three places hold what blue knows about its own evolution. Each is gated.

| what evolves | where its fixer is declared | the gate |
|---|---|---|
| a new rule | its registry row (`crates/blue-lang-check/src/rules.rs`): `fix: Machine` and `ratchet: 0` | `every_evolution_error_ships_its_fixer_or_is_a_named_gap`: every ratcheted error rule ships a machine fix or has a row in `evolution::GAPS` |
| a renamed or moved word | the producer's `legacy_names(since, prefix)` or `legacy_names(since, [[old, "home::new"]])` | B0021 / B0022 and `tests/legacy_names.rs` |
| a retired word whose replacement takes more arguments | a three-string row: `legacy_names(since, [[old, "home::new", "args"]])` | `a_retired_word_is_refused_and_fixed_with_its_new_arguments` |

A retired word never resolves, so the break comes with the upgrade. Its
caller's error (B0001 for a bare call, B0011 for `pkg::old` or a listed
`:old`) says what the word is now, and `blue check --fix` writes
`new(<the caller's arguments>, <args>)` and corrects the import list. Every
diagnostic whose rule or carried fix is machine-applicable prints a
`fix:` line: `blue fmt --write FILE` for layout (B0024–B0035), `blue check
--fix FILE` for the rest.

The gaps (`evolution::GAPS`), each a primitive still to build:

| code | rule | why there is no `check --fix` yet |
|---|---|---|
| B0013 | prefixed-definition | its fixer is `blue migrate --strip`, a rename across files |
| B0014 | mangled-namespace | the same: `blue migrate --strip` |
| B0016 | unused-import | a `use` nothing reaches carries its removal as a fix; a listed name never read carries none yet |
| B0017 | duplicate-definition | one of two definitions must be renamed, which a person chooses |
| B0020 | package-as-value | a bidama written as a value has no single call it stands for |
| B0022 | legacy-misuse | the producer's own declaration, fixed where it is declared |

## The reuse ratchets

Two counts over every distribution definition may only fall
(`crates/blue-lang-pkg/tests/distribution.rs`). A move of a twin to one home
lowers a count. A new copy raises it, and the test fails with the listing.

| gate | what it counts | pin (2026-10-24) | off switch |
|---|---|---|---|
| `exact_duplicate_shapes_only_fall` | groups of definitions with the same tree, parameters numbered | 18 | none |
| `near_duplicate_shapes_only_fall` | definitions in a group whose anti-unifier keeps at least 80% of the nodes with at most 2 holes (`blue_lang_check::shape::Near::DEFAULT`) | 257 in 105 groups | `NEAR.enabled = false` |

The near gate prints each group's shared shape, with `%hN` for each hole.
That shape is the candidate word, and its holes are the word's parameters.
It is the mechanical form of a bidama's "words blue is missing" list.
Theory: `theory/BLUE-SUPERCOMPILATION.md`.

## Receipts

Each row is a break blue's evolution caused, measured on the day, and what
blue now does about it.

| # | date | break | the class | blue now |
|---|---|---|---|---|
| R1 | 2026-10-23 | three ryn system builds failed in one afternoon: arnes `sanshou` and `wariate` (canonical under their pinned blue 5a6149c) and makoto `bunseki` failed B0024 under the nix repo's blue | the consumer's formatter judged the producer's layout: mkBidama ran `blue fmt --check` and the full check stage with the consumer's blue, and the loader refused a non-canonical store dependency | the build judges meaning only; layout and form rules are `checks.bidama-form-<pkg>` under the producer's pin; the loader compiles a dependency as written; a dependency's form diagnostics are not reported to its importer (`BLUE_FORM=own`) |
| R2 | 2026-10-23 | `kyohi::refuse` retired (blue 5e0dd4a) and its callers broke at build time; B0012 and B0015 became errors over previously-green bidamas | a retirement and new rules with no fixer named in the error | `refuse` has its retirement row in `kyohi.b`, and `blue check --fix` writes `enforce(found, [(fs) -> fs], {kind: :first})`; B0012, B0015 and B0047 carry machine fixes and every such error prints its `fix:` command; a dependency's B0015 or B0047 no longer fails its importer. B0012 still does, because the runtime cannot run the violating program: it is meaning, and the producer's `blue check --fix` is its fixer |
| R3 | 2026-10-23 | `blue test` / `blue check` with `BLUE_PATH` at a checkout rewrote dependency bidamas (`retsu.b`, `moji.b`) in place; two agents saw it | the loader's door (`canonical::admit`, called from `load_path::read_sources`) formatted every writable package file in place, and the entry's door did the same | `admit_dependency` never writes; `blue test` and `blue check` refuse a messy entry naming `blue fmt --write`; the old behaviour is `BLUE_LAYOUT=rewrite` (and `BLUE_FORM=all` for dependencies) |
| R4 | 2026-10-23 | the installed blue 0.0.86 rejected `x.nil?`, which the newer formatter (B0047) writes | an older blue cannot read a newer spelling | **open gap.** Judging no longer reaches dependencies, but parsing still must. Run the project's pinned blue (`nix run .#blue`, or the producer's flake pin) rather than an installed one |

Found while closing R3: `blue new`'s scaffold wrote `who == nil`, which B0047
refuses; the in-place rewrite had hidden it. The scaffold now writes
`who.nil?`.

## Toolchain friction

These rows are breaks in the tools around blue, not in the language. The rule
is the same: fix the class in blue, once.

| # | date | break | the class | blue now |
|---|---|---|---|---|
| R5 | 2026-10-24 | a rebase conflicted on `bidamas/CATALOG.md`; the fix was `nix run .#regen` by hand | a generated file merged as text, line by line, by git | `merge=blue-generated` on every generated file (`.gitattributes`, itself generated by `gen/gitattributes.b`); the driver `gen/merge.b` regenerates the file from the merged tree; `bidamas/NAMES.md` is `merge=union`. Proof: PROOF_LINE |
| R6 | 2026-10-24 | `regen .` spent 43 s in `shuugou::unique` over the catalogue's 4,103 definitions | a fold that copies its result once per element is quadratic | `unique` is the builtin `distinct`; `mokuroku::name_collisions` groups once with `group_by` instead of one filter per name. REGEN_LINE |
| R7 | 2026-10-24 | the pre-push gate took 4 to 6 min for every push, a docs-only push too | every gate ran on every push, one after the other | a gate runs only when the hash of its inputs and its tool was not green before, in this clone or in sui; the gates that run go in three parallel lanes (`exec_all`). GATE_LINE |
| R8 | 2026-10-24 | the gate "gen is substrate's pin" failed: PATH had gen 0.1.51, the pin was 0.1.52 | a gate judged with the tool on PATH, not the tool the lock pins | the gate builds the tool from `flake.lock` (`nix build --inputs-from .`), rooted in `.git/blue-prepush/tools/` and named by the lock blob: gen for `gen confirm`, the rust toolchain for `cargo fmt`. The old gate also compared against substrate's `main`, not this repo's lock: the lock pins gen 0.1.45, which is what CI's `gen-confirm` uses. R1 (B0024 in arnes and makoto) is the same class: the judge's version was not the producer's pin. R1 closed it for nix builds; R8 closes it for the hook. R4 stays open: an interactive `blue` on PATH can still be older than the spelling it reads |
| R9 | 2026-10-24 | the disk reached 126 MB free with nine agents building blue, each clone with its own 3.4 GB `target/`; a shared `CARGO_TARGET_DIR` then gave this branch another clone's `blue` (B0001 on `exec_all`, which this tree defines), because cargo names a path member's artifacts without its path and reports them fresh | every clone builds what another clone already built | the gates key on inputs and read sui, so an unchanged input builds nothing. **Open gap:** a shared target dir is not safe across clones of one workspace. The destination is each gate as a nix check that sui substitutes, so a clone builds only what no node has built |

The numbers behind R7, measured on ryn with other agents building at the same
time (so the absolute times are high; the ratios are the point):

| push | before | after |
|---|---|---|
TIMING_ROWS

Why the cache is a green mark in sui and not a nix check yet: `cargo-ci.yml`
says it, `checks.tests` does not exist in the fleet (substrate's
`test-check.nix` returns `ok = false` in lockfile mode), so there is no
derivation to substitute for `cargo test`. The mark is a store path whose
content is the gate's key (`nix store add-file`), so it has the same hash on
every node, and sui answers `<hash>.narinfo` for it. Only a holder of an upload
key writes one (`BLUE_PREPUSH_SUI_KEY`; `lib/sui-cache.nix` names plo); ryn
reads.
