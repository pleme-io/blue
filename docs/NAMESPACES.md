---
kind: explanation
summary: a bidama definition stays in its bidama: the rule as built and its gates
---

# Namespaces: a bidama definition stays in its bidama

The design is `theory/BLUE-NAMESPACES.md` (pleme-io/theory). This page
records one rule of it as built, the receipt that asked for it, and the
gates that hold it.

## The rule

A bare name resolves through four tiers, in this order. The order is part of
the language (operator decision 4, 2026-09-29).

1. Local bindings, innermost first.
2. Definitions of the file's own bidama (a script: its own definitions).
3. Names the file lists, `use("retsu", [:first])`.
4. Builtins and master verbs.

`pkg::name` and `blue::name` skip the tiers and are exact.

A bidama definition that shares a builtin's name is legal. It answers in its
own bidama (tier 2) and in a file that lists it (tier 3). It never answers in
any other file. That file's bare name is the builtin, or the master verb that
dispatches on its subject's space.

The flat runtime bound a bare name program-wide. Some callers depend on that
old meaning. A bidama keeps their B0012 refusal only for names it declares
flat-era:

```ruby
legacy_names("0.1.0", [:first, :rest])
```

The window is `since <= version < next_minor(since)`, as for every
`legacy_names` form. Inside the window, an importer's bare `first` is B0012,
and its fix writes `retsu::first`, the old meaning. Outside the window, or
for a name that is not listed, the bare name is the builtin, and nothing is
refused. A loader that cannot read a Bluefile version (an embedded or
in-memory loader) keeps the window open, so a host never loses a refusal it
had.

Each entry of the list is judged alone (B0022): a name the bidama does not
define, a name that is not a builtin, a master verb, and a repeated name are
each refused, and the valid entries still apply.

Measured flat-era names, 2026-10-24: 19, in kansuu (6), kazu (3), retsu (7)
and shuugou (3). Each existed in its bidama at `0056364`, the commit that
keyed definitions `pkg/name`. The list only shrinks.

## Receipt (2026-10-24)

The `outou` bidama defined `def read(text)`. The pre-push gate
`distribution_definitions_that_replace_builtins_are_pinned` went red with "a
bidama definition that replaces a builtin program-wide was added". The author
renamed it to `outou::parse` (`5f25221`).

Measured on `df13419`: the runtime did not leak. A program that loads outou
with `def read` gets the dispatcher for its bare `read(42)`
("read: no space owns a int subject"), and another bidama's bare `read`
gets the dispatcher too. Definitions are keyed `pkg/name` since `0056364`
(`crates/blue-lang-runtime/src/pipeline.rs:758`, `lower`). The gate's text
was stale.

The real leak was in the check stage. B0012
(`crates/blue-lang-check/src/names.rs`, `Walker::record`, line 1544) refused an
importer's bare call of any builtin that a loaded bidama also defined, and
its machine fix wrote the bidama's name into the importer. So `def trim` in
moji (2026-10-23) made `use("moji")` + `trim(s)` an error whose fix was
`moji::trim(s)`. Master verbs alone were exempt (2026-10-23). Nine
definitions had this effect: `danpen.compose`, `gitto.get`, `gitto.list`,
`jisho.empty?`, `moji.trim`, `moji.truncate`, `raifusaikuru.link`,
`rogu.error`, `tsuushin.join`.

## Gates

- `crates/blue-lang-cli/tests/legacy_names.rs`: a bidama that defines
  `trim`, `first` and `read` leaves the importer's bare calls to the
  builtins and the dispatcher, and its own calls reach its own definitions
  (red before: B0012 on `trim` and `first`). A flat-era name keeps B0012
  inside its window and loses it at the next minor. A bad entry is refused
  alone.
- `crates/blue-lang-runtime/tests/resolution_order.rs`: a loader with no
  versions keeps a flat-era window open, and only that name.
- `crates/blue-lang-cli/tests/check_corpus.rs`,
  `distribution_definitions_that_share_a_builtins_name_stay_in_their_bidama`:
  over the whole distribution (`use("zenbu")`), every bidama definition that
  shares a builtin's name resolves to the builtin from the importer, and the
  flat-era list is pinned.
- `spec/rows/modules.b`, `modules.ns.builtin_not_replaced`: no longer pending.

## Off switch

None for the isolation. A bidama definition that answers outside its
bidama produces no good behaviour, so it is a bad state, and a bad state is
never configured. The refusal that remains is configured per name by the
`legacy_names` list. It goes off when its window closes, and the declaration
stays as the ledger.

## Rejected alternatives

- **Refuse a def that shares a builtin's name.** Rejected: theory decision 4
  makes it legal, and 54 definitions in the distribution use it (retsu's
  total `first`, gitto's master-verb handlers).
- **Refuse a `use` list that names a builtin.** Rejected: the list is the
  importer's explicit choice (tier 3 over tier 4), and theory decision 4
  records it as an override, not an error.
- **Keep B0012 for every builtin collision.** Rejected: it is the leak. A
  bidama's new definition changes the verdict of code outside it.
- **Drop B0012's builtin arm at once.** Rejected: a consumer on the flat
  runtime that wrote bare `first` meant retsu's. Without the window, its
  bump changes the meaning in silence.
- **Mark flat-era names by date in the checker.** Rejected: the checker reads
  source, not history. The declaration is source, and the gate pins it.
