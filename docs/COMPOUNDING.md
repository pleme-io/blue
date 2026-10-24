---
kind: explanation
summary: every break blue's evolution causes ships its own fixer
---

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
| R5 | 2026-10-24 | B0062 (argument-kind, blue/hard-blocks) refused `find(f, xs)` and `flat_map(f, xs)` in arnes `wariate`, nix `node-facts`, blackmatter-kubernetes `nerai` and kensa on their next blue bump; each was fixed by hand | a rule shipped with no fixer for its commonest case: a function literal before the collection | B0062 carries a machine fix for that subclass: a builtin whose signature takes a list or map first and a function second (read from `docs::NAMES`: `find`, `flat_map`, `group_by`), or a definition whose inferred parameter kinds are the same (`retsu::flat_map`), called with a function literal first and a value that cannot be a function second, is swapped by `blue check --fix`; every other B0062 stays a suggestion. A rule row's `fixes` witness is checked by `every_carried_machine_fix_repairs_its_witness`, and the conformance suite's `fixes(...)` expectation states what `--fix` writes |
| R6 | 2026-10-24 | ctrl-c did not stop the pre-push hook; the operator killed `blue run gen/prepush.b` and its `regen` child by hand | frost ignores SIGINT for itself (`libc::signal(SIGINT, SIG_IGN)`), and `execve` keeps an ignore, so every command started from frost ignored ctrl-c | `blue run` ends with `blue: stopped (ctrl-c)` and exit 130, and an inherited ignore stays ignored (`src/sigint.rs`, shared with the repl; `tests/stop.rs` finds no child alive a second later). The frost side (`frost_exec::sys::ignore_sigint_in_shell`, a child gets the default SIGINT again) is on frost branch `frost/sigint-default`, not on frost main (2026-10-28) |

Found while closing R3: `blue new`'s scaffold wrote `who == nil`, which B0047
refuses; the in-place rewrite had hidden it. The scaffold now writes
`who.nil?`.
