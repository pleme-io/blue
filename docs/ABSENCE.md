---
kind: explanation
summary: no undeclared nil: how blue makes absence a declared, checked state
---

# ABSENCE — no undeclared nil

Parent: [`SAFETY.md`](SAFETY.md), the matrix that maps each Rust safety
guarantee to blue. This document is its row 1, no null (`Option<T>`).

Operator intent (2026-10-24): *"we should have common patterns like Option or
Result, in bluelang."* Rust has no null; it has `Option`. blue should carry no
absence that nothing declares.

## 1. Destination

At the end, blue has no bare nil at runtime. A value that can be missing is an
option, `umu::some(v)` or `umu::none`, and its type says so. A builtin that
today answers nil answers an option. A program that reads a possibly-missing
value without testing it does not check. nil survives only as the inside of
`none`, never as a value a program passes around.

Three things make that real:

1. **The value**: `umu`, blue's Option, beside `kyohi`, blue's Result.
2. **The rule**: the check stage refuses an undeclared absence (B0054, B0055).
3. **The builtins**: each nil-answering builtin gets an option-answering form,
   and the nil form retires through `legacy_names` with a fixer.

This change ships 1 and 2. Section 7 is the ledger for 3.

## 2. Decisions

One answer per question. The rejected alternatives are listed so they are not
proposed again.

| Question | Answer | Rejected, and why |
|---|---|---|
| Where Option lives | A bidama, `umu` (有無, presence or absence), pure blue | A runtime type in Rust: blue grows down the ladder only for what blue cannot express, and an option is two maps. A word inside `kyohi`: kyohi is refusals; an absence is not a refusal, and Rust keeps `Option` and `Result` apart for the same reason |
| Runtime form of `some(v)` | `{some: true, value: v}` | `[v]` / `[]`: a user list `[x]` reads as `some(x)`, and `retsu::is_empty(nil)` is true, so nil would pass for none. A keyword `:none`: a program may hold `:none` as data |
| Runtime form of `none` | `{some: false}`, made by the nullary `umu::none` | nil itself: that is the thing being removed |
| Why a map, and this map | It is kyohi's shape (`{ok: true, value: v}`), so the two read the same way and `ok_or`/`to_option` are a key swap. A map is a value every evaluator (walker, VM, WASM) already has, so umu needs no runtime change | A tagged record type in the runtime: no evaluator change is needed to get the semantics, and the check stage, not the runtime, is where undeclared absence is caught |
| `some(nil)` | Refused (`:usage`) | Allowed, as Rust allows `Some(())`: in blue nil *is* absence, so `some(nil)` would be a some of nothing, the exact ambiguity Option exists to end |
| `map(o, f)` when `f` answers nil | Refused (`:usage`), through `some` | Silently none: that hides an undeclared nil inside an option. A function that may answer nil is written `and_then(o, (v) -> from_nil(f(v)))` |
| A non-option passed to umu | Refused (`:usage`) by `fold`, umu's one eliminator | Read as none: a bare nil would slip through as a valid absence |
| The surface | `some`, `none`, `some?`, `none?`, `fold`, `value_or`, `expect`, `map`, `and_then`, `or_else`, `filter`, `zip`, `from_nil`, `to_nil`, `ok_or`, `to_option` | `unwrap`: `expect(o, why)` says why. `take`, `replace`, `get_or_insert`: they mutate, and blue values do not. `flatten`, `xor`, `unzip`, `is_some_and`, `inspect`: no caller in the fleet yet |
| Argument order | The option first: `map(o, f)` | Lisp order `map(f, o)`: kyohi's `and_then(result, f)` puts the subject first, and a pipe `o \|> umu::map(f)` reads left to right |
| The seam with nil code | `from_nil(v)` in, `to_nil(o)` out; umu itself writes no `nil` (none carries no `:value`, so `to_nil` reads its absent key) | A coercing `some?` that accepts nil: it would make every bare nil a valid none and end the rule's point |
| Rule shape | Two codes: B0054 (a read of a value that can be nil, untested), B0055 (a written `nil` in a function) | One code: the two have different counts and different fixes, and a refusal is scoped to its fault |
| Analysis scope | One function, forward only. Sources of nil: a declared optional parameter `x?`, a builtin in `NIL_RESULTS`, a written `nil`, `x rescue nil`. Guards: `x.nil?` (else branch), `x != nil`, `if x`, `and`, `or`, `some?`/`ok?`/`none?`/`error?`, a branch that raises, `x = x or d` | Following calls to learn what they return: the typing ladder's rule is never to infer backward across an undeclared boundary (`crates/blue-lang-check/src/lib.rs`) |
| Where B0055 is judged | Inside `def` bodies of the entry file; the comparand of `x != nil` is admitted | Tests and top-level forms: they exercise code that still answers nil, and judging them would block the migration's own tests |
| Default posture | `audit`: both codes are reported as warnings, counted by `blue census`, and do not block (section 5) | `enforce` now: 77 B0054 and 559 B0055 findings, none machine-fixable, would turn every distribution build red |
| Off switch | `BLUE_ABSENCE=off\|audit\|enforce`, read by every door like `BLUE_FORM` and `BLUE_LAYOUT` (`absence::Posture`); a value outside the set is refused | A Bluefile knob: the `BlueConfig` admission rule takes bounds, never preferences. `# waive` per definition stays available, as for every rule |

## 3. Option and Result compose

`umu` needs `kyohi`; `kyohi` does not know `umu`.

| From | To | Word |
|---|---|---|
| option | result | `umu::ok_or(o, kyohi::refusal(:not_found, "why"))`: `ok(v)` or `refused(r)` |
| result | option | `umu::to_option(r)`: `some(v)` for `ok(v)`, `none` for a refusal, and `none` for `ok(nil)` |
| option | raise | `umu::expect(o, "why")` raises `:not_found`, a kyohi ledger kind |
| nil | option | `umu::from_nil(v)` |
| option | nil | `umu::to_nil(o)`, only for code that still reads nil |

Round trips: `to_option(ok_or(o, r)) == o` for every option, and
`ok_or(to_option(ok(v)), r) == ok(v)` for every non-nil `v` (both in umu's
tests).

## 4. The checker rule

**B0054 unguarded-absence.** A value that can be nil is tested before
`.field`, `get(v, k)` or `v(...)` reads it. `get(nil, k)` raises, so every
B0054 finding is a crash on the path where the value is missing.

**B0055 undeclared-nil.** A function does not write a bare `nil`. The fix is
`umu::none`, with its callers reading the option, or `umu::from_nil(v)` at the
seam with older code.

Neither has a machine fix. Wrapping a value with `from_nil` changes its type,
so every reader downstream changes with it; `blue check` names the fix in its
help line and leaves the edit to the author. That is the honest limit: a
`maybe-incorrect` rewrite is not applied unattended.

Implementation: `crates/blue-lang-check/src/absence.rs`, run by the check stage
for every door; its unit tests hold the red cases and the guard cases. The
witnesses are `B0054`/`B0055` rows in `RULES`, and `spec/rows/check.b` covers
both codes.

## 5. Count, and the path to enforce

Measured 2026-10-24 on `6f1bb37` with `BLUE_ABSENCE=audit blue census` over the whole repository (every `.b`
file):

| Code | Findings | Where most are |
|---|---|---|
| B0054 | 77 | all are `get` reads (ukai 18, empresa 9, kinko 8, gamen 8, kijun 6) |
| B0055 | 559 | danpen 66, nisshi 40, mokuroku 37, outou 28, raifusaikuru 24 |

Neither count clears by autofix, so the rule lands at `audit`, as the brief and
the coordinator's condition say: enforce unless the count turns the gate red
and autofix cannot clear it. Run `BLUE_ABSENCE=enforce blue check FILE` to see
one file as the enforce posture will.

The flip to `enforce` is phase P2: drive B0054 to 0 first (each is one test or
one `from_nil`), then make `enforce` the default for B0054 alone while B0055
stays at `audit` until the builtins of section 7 answer options.

## 6. Seal tier

**checked-at-expansion**, not unrepresentable. B0054 and B0055 are reported
diagnostics over a tree. A program that sets `BLUE_ABSENCE=off`, waives the
rule, or reaches a nil through a call the analysis does not follow still runs.
`some(nil)` is refused at runtime, so an option never holds nil: that part is
`checked-at-runtime`. Unrepresentability comes only when the runtime stops
producing nil (section 7) and a declared return type can say `Option`.

## 7. Builtins that answer nil

Each row is a ledger entry. Today every row is reachable as an option through
`umu::from_nil(...)` at the call site; the replacement column is the
destination.

| Builtin | Answers nil when | Option path | Status |
|---|---|---|---|
| `get(m, k)` | the key is absent | the verb contract (`docs/verbs/contracts.tsv`, `get`: "value or nil") becomes "option"; `need` stays the raising form | ledger: a contracts change across every space that has `get` |
| `nth(i, xs)` | past either end | an option-answering `nth` | ledger |
| `dig(tree, keys...)` | a step is absent | option | ledger |
| `find(xs, f)` | no element is accepted | option | ledger |
| `json_get(obj, k)` | the field is absent | option, or `deeta`'s readers | ledger |
| `getenv(name)` | the variable is unset | option (the two-argument form keeps its default) | ledger |
| `to_int(x)` | text is not an integer | option; `to_int!` keeps raising | ledger |
| `bytes_text(bytes)` | not UTF-8 | option | ledger |
| `path_extension(path)` | no extension | option | ledger |
| `self_exe` | outside the CLI | option | ledger |
| `space_of(value)` | no space | option | ledger |
| `nats_next_message`, `http_next_request` | nothing came in time | option | ledger |
| `some(f, xs)` | nothing accepted (nil, not false) | `any?`, a Bool | ledger |
| `when(c, ...)`, an `if` with no `else` | the test is false | B0055 does not see these (no `nil` is written); a later rule | ledger |
| `json_parse`, `json_read` | JSON `null` | data, not absence: a parsed document keeps nil until `deeta` reads it as an option | ledger |

Migrated this session: none. A builtin's answer is a runtime change (Rust, its
`docs::NAMES` line, its spec rows, its verb contract), and doing it for one
builtin without the `legacy_names` fixer for every caller would break the
distribution. The first migration is P3.

## 8. Phases

| Phase | What | Gate |
|---|---|---|
| P0 | This document | — |
| P1 | `umu`, wired into zenbu, with heni mutations; B0054 and B0055 at `audit` with the `BLUE_ABSENCE` switch | `blue test bidamas/umu`, heni 9 of 9 caught, rule witnesses, spec rows, census counts |
| P2 | B0054 to 0 across the repository; `enforce` the default for B0054 | `the_check_stage_reports_no_error_on_the_corpus` under enforce |
| P3 | The section 7 builtins answer options, each with its `legacy_names` row and fixer; `get`'s verb contract first | `blue check --fix` migrates a caller; spec rows per builtin |
| P4 | B0055 to 0; `enforce` for B0055; a declared return type can say `Option` | the corpus gate under enforce for both codes |
