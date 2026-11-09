---
kind: explanation
summary: "a bidama definition stays in its bidama: the rule as built and its gates"
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

`pkg::name`, `a::b::c` and `blue::name` skip the tiers. See "A bidama is a tree".

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

## A bidama is a tree

Operator's instruction, 2026-11-04. This replaces the rule that a name has one
qualifier. One bidama holds levels, as deep as it needs.

| | |
|---|---|
| A level | a directory `sub/` holding `sub/sub.b`, or a file whose first code after `@moduledoc` is `namespace()` |
| Not a level | a sibling file with no `namespace()`, which stays a part of its parent as it always was; a directory with no `<d>/<d>.b` (`fixtures/`, `mokuroku/graph/`) |
| The tree | one symbol, `a/b/c/x`, and its runtime key is the same symbol. `qualified()` reads the name as the last segment |
| Manifest | one Bluefile at the root, so one version and one lock. A level with its own Bluefile is refused. A level's `use` joins the root's `needs`; a `use` inside the tree is not a need |
| Tests | each level's file holds its own, and `checks.bidama-test-<pkg>-<level>` runs them |
| Capabilities | every level's reach joins the root's floor in `Bluefile.lock`, and `definitions` names `tree/room/deep::word` |

### One spelling (operator, 2026-11-05)

A name has one spelling, so a reader needs no imports to read it and `rg`
finds every caller:

| Where | Spelling | Refused otherwise by |
|---|---|---|
| a definition of the file's own level | bare, `x` | B0018 |
| a name the file lists, `use("a/b", [:x])` | bare, `x` | B0018 |
| every other definition | the full path of its level, `a::b::x` | B0076 |
| an import | `use("a/b")` or `use("a/b", [:x])`: a slash string, one level | B0077 |
| a tree | imported once: a `use` of an ancestor brings every level below | B0078 |

`blue check --fix` writes each canonical form. A level reaches below itself
with no `use`, and a `use` of a level loads it and every level below it.

The reader still parses a path written `"a::b"`, `%i[a b]`, `%w[a b]` or as a
spread, a form that imports several children, a second name
(`use({s: "a/b"})`) and a tail of a path (`b::x` after `use("a")`). Each is one
meaning, so each loads and resolves, and each is a check-stage error whose fix
writes the one spelling. Before 2026-11-05 these were accepted as the author's
choice; a search for a caller missed every one.

### Privacy and re-export

Every level is public: blue has no private definition, and a level adds none. A
level sees nothing of its parent or siblings without a `use`. A parent does not
re-export: `use("caixa/sub", [:inner])` inside caixa does not make `caixa::inner`,
so one definition keeps one key and `rg` finds it. A facade, a level that defines
nothing, works as it does for a bidama.

### A bidama moves into a tree

A flat bidama can become a level of another: `bpf` becomes `kaaneru/bpf`. The
root it moves into declares the move in its Bluefile, the package twin of
`legacy_names`:

```ruby
package("kaaneru", "0.1.0")
legacy_packages(
  "0.1.0",
  [%w[bpf kaaneru/bpf], %w[btf kaaneru/btf], %w[erufu kaaneru/erufu]]
)
```

From `since` to the root's next minor version, the bridge is open. A loader
that finds no bidama `bpf` asks the roots on its path whether one moved it
(`Loader::moved`), and loads `use("bpf")`, `use("bpf", [:compile])` and
`use("bpf/asm")` as `kaaneru/bpf` and below. `bpf::compile` reaches
`kaaneru::bpf::compile`. Each such `use`, and each qualifier written through
the old name, is B0074. It is a warning outside kaaneru's distribution while
the bridge is open, an error inside it, and an error once the bridge has
closed. The row stays in the Bluefile as the ledger, so a closed bridge still
names the move and still carries the fix. `blue check --fix` writes
`use("kaaneru/bpf")` and `kaaneru::bpf::compile`. In a bidama that still
`needs("bpf", …)`, it also writes `needs("kaaneru", "^0.2.0")` and relocks.
`blue lock` derives `kaaneru` from a `use` still on the old name.

The Bluefile refuses a row that cannot mean one thing: an old name of more
than one segment or the root's own name, a new path that is not a level of
this root, and a `since` the root has not reached.

### Cycles

A `use` of a level brings every level below it, so a level never imports its
ancestor, and siblings never import each other in a loop. The resolver refuses
either with the path: `cyc -> cyc::kid -> cyc`. A cycle among whole one-level
bidamas still terminates, as it always has.

### One `use` grammar

Every spelling reads to one list of imports (`scope::use_targets`), so the
loader, the check stage, capability floors and `blue lock` see one thing. The
canonical spelling is the first row; every other row is B0077, and its fix
writes one canonical `use` per level.

| Spelling | Means |
|---|---|
| `use("thing/sub")` | the path |
| `use("thing::sub")` | the path, as a reference writes it |
| `use(%i[thing sub])`, `use([:thing, :sub])` | the path as symbols; one tree, the formatter prints `%i` |
| `use(%w[thing sub])`, `use(["thing", "sub"])` | the path as strings; one tree, the formatter prints `%w` |
| `use(*%i[thing sub])` | the path spread as a call's arguments |
| `use(**%i[thing sub])` | the same, destructured. The reader takes `**` on its own in a call only: `**%i[…]` cannot sit before a second argument, so a list goes with `use(%i[thing sub], [:a])` |
| `use(path, [:a, :b])` | names listed for bare use, from that level |
| `use(path, %w[sub other/deep])` | several children, each an import. Strings are paths, symbols are names |
| `use(path, {sub: [:a], other: []})` | several children, with their lists |
| `use({s: "thing/sub", o: %i[thing other]})` | a second name for each level. The first argument is a map |

Rejected, and why:

- `use(thing::sub)`, a bare path. An argument that looks like a reference and is
  never evaluated breaks the rule that arguments are data, and `use(thing)`
  could only be read as a variable.
- `use("thing", "sub")`. It reads as two imports.
- `use(:thing, :sub)`. The same, and a symbol in second place means a name.
- `use("thing/{sub,other}")`. A second grammar inside a string, which neither the
  formatter nor an editor can see.
- `{sub: {deep: [:x]}}`, a nested map. A second path syntax inside the map; write
  two forms.
- A wildcard, `use("thing/*")`. Adding a definition would change what an
  importer's bare name means, which is why blue has no glob.

Every argument is a literal, and a computed one is B0073, at the check stage,
naming why. A level imported twice is B0015, whichever spellings did it.

### Where a root comes from

A name has a second axis: the repository that holds its root. The call site
never states it. `use("thing/sub")` reads the same whether `thing` sits in
the project, in blue's distribution or in another repository.

| Where | What it states |
|---|---|
| `source(name, url, dir)` in the Bluefile | a repository, and the directory in it that holds package roots |
| `Bluefile.lock` | the exact tree: `rev` and `narHash` |
| the build (`nix/project.nix`) and the CLI load path | every package root under `dir` joins the project's roots |

One root holds a name. When two roots of the project hold the same name, the
build refuses it and names both. A source the lock does not pin adds nothing,
and the other sources still build. The flow, the pins and the off switches:
[REGISTRY.md](REGISTRY.md), "Build flow".

### Embedding

`Embedded` is one level. A host compiles a tree in by chaining one
`EmbeddedOver` per level; each answers `children` for the level above it.

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
