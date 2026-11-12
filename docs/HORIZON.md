---
kind: explanation
summary: the long plan for blue, ten horizons from hygiene to a language that proves, replays and explains itself, eight authority horizons that make every host effect a capability granted from one declaration in every placement, an ontology of every concept in khipu that the tests are generated from, and the kernel as both a verified target and the enforcer of access; destination first, each horizon with its first step, its gate and what it unlocks
---

# HORIZON: where blue goes next

This document holds the destination. [`ROADMAP.md`](ROADMAP.md) holds the
work. A horizon becomes a ROADMAP row when its first phase starts. The
[Ledger](#ledger) at the end shows the state of each horizon. Nothing here is
built unless the ledger or a line says so.

**Build order, 2026-11-09 (operator).** The operator set the build order to the
three layers of [`SUBSTRATE.md`](SUBSTRATE.md): blue on engenho first, then
every placement, then high-assurance local systems. H8 (placements) and the
authority work (H11 to H20) are scheduled through SUBSTRATE's phases (§9). This
document keeps each horizon's idea, gate and first step; § Order below is the
order as it stood on 2026-11-06.

## The destination

Blue is the one language a person and a model write together for everything
pleme-io runs, and the language that knows itself. Every word can be found
before it is written again. Every claim a program makes is a gate that can go
red. Every program runs where its placement says, from a kernel probe to a
browser, without a second language. Every bad state is refused at the earliest
stage that can see it, and where two good ideals conflict, a program chooses a
position on the blueshift instead of forking the language.

## Where blue stands (measured 2026-11-06)

| Fact | Value |
|---|---|
| Crates | 24, all with description and license |
| Bidamas | 65, about 180,000 lines of blue |
| Conformance | `spec/rows/`, 37 files, run on five columns (tree-walker, VM, wasm ABI, the `blue` binary, the in-process front end) |
| Safety matrix | 19 rows: 6 sealed, 10 partly, 3 open ([`SAFETY.md`](SAFETY.md)) |
| Gaps | of the 16 gaps the first pass found: 7 closed, 7 partial, 2 not measured again |
| Identity | `def_hash` per definition, docs hashed in (`blue-lang-runtime/src/def_hash.rs`) |
| Concurrency | OTP-style processes in every door (`blue-lang-proc`) |
| Reach | CLI, services as wasm components, kernel BPF (`kaaneru`), word search (`arika`) |

## The ten horizons

Each horizon names its idea, why it compounds, its first step and the gate that
proves that step. "Unlocks" names the horizons that wait on it.

### H0. Hygiene: the base the rest stands on

The 2026-11-06 survey found the drift that hand-kept tables always gather.

- Render the `docs/DIAGNOSTICS.md` codes table from `RULES` in `nix run .#regen`,
  as `docs/REFERENCE.md` already is. Twice in one day a new rule code missed it
  (B0079, B0080); a rendered table makes that unrepresentable.
- Render CATALOG's `needs` column from `Bluefile.lock`, the truth B0019 keeps,
  not from Bluefile text (19 packages wrong today).
- Ship nested levels in the `blue-lang-pkg` crate (`bidamas/**/*.b`); today the
  published crate drops all 47 level files.
- B0058 to 0 (four bidama moduledocs lack an example), then B0056 and B0057
  down by the largest packages first (isshou, toriyose, eigyou, kakehashi).
- A ROADMAP row for every doc with open phases (HTTP2, CLI-TUI, SERVICE-DATA,
  API-EVOLUTION, BUILD-STACK, BUILD-ASSURANCE, DOCUMENTATION, OPERATORS,
  KERNEL, BIDAMA-COHESION).

**Gate:** each table is generated and `-fresh` checked; the census ratchets fall.
**Unlocks:** every horizon, because a plan built on a wrong ledger is wrong.

**Built (2026-11-08, measured at `5399e761` plus this change):**

- The DIAGNOSTICS codes table and CATALOG's `needs` are rendered by `nix run .#regen`.
- Nested levels ship in `blue-lang-pkg`: its `include` takes `bidamas/**/*.b`
  (`2c9568f0`), and `checks.package-fidelity` (`nix/package-fidelity.nix`,
  `03ad83e5`) builds blue from the packaged crates. `cargo package --list -p
  blue-lang-pkg` lists 283 `.b` files under `bidamas/`, 217 of them in a level
  below a package: every `.b` file the checkout holds.
- B0058 is 0, ratchet 0 (was 7): bougyo, keiyu, zenbu, kazoe, chuuzou, kiban
  and the project fixture each open with a `@moduledoc` and a running example.
- B0056 2805 to 2557 and B0057 894 to 782, ratchets lowered to match. The
  largest gains: `isshou/raifusaikuru`, `isshou/nisshi`, `eigyou/tajuu`,
  `eigyou/heddaa`, and chuuzou and kiban's comments lifted into `@doc`.
- ROADMAP has a row for HTTP2, CLI-TUI, SERVICE-DATA, API-EVOLUTION,
  BUILD-STACK, BUILD-ASSURANCE, DOCUMENTATION, OPERATORS, KERNEL and
  BIDAMA-COHESION, each tier read from its own ledger.

Open: B0056 and B0057 to 0, next by size `toriyose` (danpen, outou, kyasshu)
and `kakehashi` (kijun, kirikae, nikkusu).

### H1. Shapes: sums, patterns and refusals that flow

`record` gave blue products. The next forms complete the data model:

- **Unions.** `union shape = circle(r: Float) | rect(w: Float, h: Float)`: each
  arm a record, the union a closed set. `case` over a union is checked for
  exhaustiveness, which seals SAFETY row 3 ("case falls through to nil").
- **Patterns.** `case` destructures: `when rect(w, h)`, `when [x, *rest]`,
  `when {name:}`; a binding destructures: `[a, b] = pair`. Closes gap G13.
- **Refusals that flow.** On top of guard `return`: `s = read(cs)?` returns a
  refusal from the function at once, lowered to a guard, so khipu's `then`
  disappears. With unions, `ok`/`no` become one declared `result` union, and
  ABSENCE's Option is a union too: one mechanism instead of three conventions.

**First step:** `union` as a declaration that lowers like `record`, with a
check-stage rule for a `case` that misses an arm. **Built (2026-11-06):**
`union shape = circle(r: Float) | rect(w: Float, h: Float)`, one line, or one
arm a line with each later arm starting `|`. The parser reads it as
`(blue-union shape shape? (blue-record circle …) (blue-record rect …))`; every
door but the documented one lowers it to the arm records plus
`(blue-union shape shape? circle? rect?)`, so constructors, predicates, field
reads and JSON are the record machinery's, and the formatter raises it back.
`shape?(v)` is true for a value of any arm. B0081 (union-arms) refuses a
`case` whose `when` arms test a union's predicates, miss one and have no
`else`. An arm needs at least one field, as a record does; `union` stays a free
name (shuugou's `union(a, b)` is untouched).
**Gate:** a conformance row per arm shape; the exhaustiveness rule's red run
(drop an arm, the rule fires).
**Patterns, built (2026-11-08):** a `when` that holds a name destructures.
`rect(w, h)` matches a record the program declares and binds its fields by
position, `[x, *rest]` a list of at least one with its head and the rest,
`{name:}` (or `{name: n}`) a map or record holding `:name`. Inside a pattern a
name binds, `_` matches anything and a literal compares with `==`; a pattern
with no name in it compares by value, as before. `crates/blue-lang-syntax/src/pattern.rs`
lowers each such arm at every `parse_program*` door but the documented one,
after the guard rewrite, to the existing machinery: the record's predicate
(`rect?(case-subject)`, which B0081 reads as `when rect?`), `blue-shape-list?`/`blue-shape-key?` tests, and a
`let` of `blue-shape-at`/`blue-shape-from` reads (runtime `shape.rs`). So the
walker, the VM, WASM and the CLI run one lowering, and the formatter raises it
back (`pattern::raise`). B0081 counts `when rect(w, h)` as covering `rect`,
since its test is the predicate alone; `when rect(w, 1)` does not cover it.
A record pattern names a record declared in the same program; one from another
bidama is not yet a pattern and still compares by value. Rows:
`spec/rows/patterns.b`.
**Destructuring bindings, built (2026-11-08):** `[a, b] = pair`,
`[h, *t] = xs` and `{name:, age: n} = person` are statements over the same
patterns. They lower in their statement sequence to `bind-subject = value`, a
test that raises :pattern naming the pattern when the value does not fit, and
one binding per name, so nothing ever binds nil. G13 is closed.
**`?`, built (2026-11-08):** `x = f(y)?`, `[a, b] = f(y)?` and a bare
`f(y)?` statement end a statement of a `def` body. A refusal is kyohi's: a map
whose `:ok` is `false` (`kyohi::refused(r)`, `{ok: false, refusal: r}`); a map
whose `:ok` is `true` is a value and `?` gives its `:value`; anything else
raises :usage, so a `nil` or a khipu `{why:}` map never passes as either.
`crates/blue-lang-syntax/src/try_op.rs` lowers it before the guard rewrite to
`try-subject = f(y)`, `if blue-try-refused?(try-subject) return try-subject
end`, `x = blue-try-value(try-subject)`, so GUARD-RETURN's own lowering turns
it into if/else and every evaluator door runs that. A `?` the rewrite cannot
place (an argument, a lambda, the top level) is a parse error; the formatter
raises it back. Not yet: `?` on an Option (ABSENCE P1 has no `umu`), one
declared `result` union, and khipu still writes its own `{why:}` guards.
**Unlocks:** H2 (types have shapes to name), ABSENCE P1, SAFETY rows 1 and 3.

### H2. Types that grow with the program

Blue's ladder stays: an unannotated program pays nothing. What grows is how
far a type reaches once it is written.

- Local inference inside a typed definition, so one annotation types its body.
- Record and union types in signatures, and parameters over them
  (`List(T)` today, `Map(K, V)` and user records next).
- The checked boundary (gap G8): an untyped caller of a typed function is
  checked at the call where the value is known, not only inside the callee.
- A per-file or per-bidama position on the blueshift (`strict`), so a
  foundation package can demand types and a script cannot be made to.

**First step:** inference of local bindings from typed parameters and literals.
**Gate:** a spec row per inference rule; the corpus check stays clean at the
`dynamic` rung (no program that runs today is refused).

**Built (2026-11-06):** inside a typed definition, a binding `x = e` takes the
type of `e`: a literal, a typed parameter, an operator, a call to a typed
definition, a builtin whose result is declared (`blue_lang_check::builtin_result`,
each row probed against the runtime), or an `if` whose branches agree. A name
assigned in a branch, a loop or a function, or bound twice with two types, stays
`dyn`. A later misuse is B0003, B0004 or B0005, and an inferred kind passed to a
builtin that takes another kind is B0062. Rows: `spec/rows/check.b`
`check.infer.*`. Untyped definitions are still not walked.

**Built (2026-11-09), wave 3:** the rest of H2 except the runtime seam.
Signatures name `Map(K, V)` (and bare `Map`, `List`) and the records and
unions the program declares (`blue_lang_check::Ty::{Map, Record, Union}`). A
list literal infers `List(T)`, a map literal `Map(K, V)`, a record's
constructor that record. Inside a typed definition a record value is read by
its fields: `p.y` has the field's declared type and `p.z` on a record without
`z` is B0079. A union parameter takes any of its records, a `Map` parameter
takes a record, and anything else is B0005; a value typed with a union is read
as `dyn` until a `case` narrows it, which nothing does yet. The checked
boundary (G8, static half): once a program has a typed definition, every
other top-level form, untyped `def` bodies and the file's top level, is walked
for calls to typed definitions (`check_program_with`'s boundary pass, counted
in `Stats::boundary_visited`, so `visited` still measures only typed bodies).
An argument whose type is known at the call (a literal, a local binding of
one, a list, map or record built there, a typed call) is checked as B0005; an
argument not known there, or a parameter typed with a name blue does not know
(`String`), is left alone, and no other rule runs on untyped code. A bare call is checked when one top-level definition has the name and
no local binds it; a qualified `pkg::f(...)` is checked against `pkg`'s typed
`f`. The position: `blueshift(:strict)` at the top level of a file is that
file's demand for the `checked` rung, B0082 (waivable) at every top-level
`def` with no annotation at all (`blue fmt` drops a hand-written `x: dyn`, so
one annotation is the demand; `def show(x) -> dyn` takes any value). The
marker binds the file that declares it only, so a script that `use`s a strict
bidama is not made strict. `scope::is_file_declaration` is now the one
predicate for the declarations that never run (`use`, `legacy_names`,
`namespace()`, `blueshift(:strict)`). Rows: `spec/rows/check.b`
`check.infer.{list,map}_literal`, `check.signature.*`, `check.boundary.*`,
`check.B0082*`; fixture `spec/bidamas/sp_strict`. Not yet: the runtime half
of G8 (`shift.wrong_arg.annotated`: an untyped caller passing an untyped
value, refused at run time), a bidama-wide position in the Bluefile, carrying
a top-level binding across forms, `case` narrowing a union, and record or
union types named across a bidama (`geo::point` in a signature stays opaque).
B0082 is in `gen/consumers.json`'s swept codes (2026-11-10): the sweep at
this blue finds all 23 consumers green.

### H3. Code is content: the definition hash as identity

Blue already hashes every definition. Make that hash the identity everything
keys on:

- **A test cache keyed on hashes.** A test whose target and controls hash the
  same as a passing run does not run again. The cache lives in sui, so a test
  passed on rio is passed on every node. CI time falls with every unchanged
  definition.
- **Incremental check.** The check stage keys its work on `def_hash`; editing
  one definition re-checks its callers only.
- **Semantic diff and release.** `danpen-diff` and API-EVOLUTION read change as
  "these hashes moved", so a release names exactly the definitions it changes
  and a doc-only edit is visibly one.
- **Memo by default for pure definitions** (`BLUE_MEMO` exists): a pure
  definition's result is a function of its hash and its arguments.

**First step:** `blue test` records each passing test's identity
(`test_identities` exists) and skips a test whose identity is recorded.
**Gate:** red run: change a callee, and its tests run again; change an
unrelated definition, and they do not.
**Unlocks:** H7 (memo and caching are performance), H9 (cheap re-verification).

**Content addressing by default, with proofs** (operator, 2026-11-07: compile
time first). Measured the same day: `def_hash` is BLAKE3 over each
definition's resolved tree with every callee replaced by its hash
(`crates/blue-lang-runtime/src/def_hash.rs`), and almost nothing uses it by
default to skip work.

| Stage | Cached today | Key |
|---|---|---|
| parse, resolve | in memory only (mondou; the LSP and `blue check`) | text hash, then `def_hash` |
| check and erase | built, on by default for every check a `blue` command runs: `check`, `test`, `run`, `fmt`, the LSP (`BLUE_CHECK_CACHE=off`, `--no-cache` on `check` and `test`): the name walks, the lowered tree and project rules, per definition; shipped per bidama as its `analysis` output, read through `BLUE_CACHE_SHARED` | `def_hash` + engine identity + the hashes it read |
| `blue test` | built, on by default (`BLUE_TEST_CACHE=off` turns it off), shared through `BLUE_CACHE_SHARED` | the engine's `b3:` + the test's hash + preamble + bounds |
| a pure call | built, off by default (`BLUE_MEMO`; measured slower on the corpus's tests), shared when on | `def_hash` + the arguments' canonical form |
| a nix `bidama-test-*` check | none: one change anywhere reruns every package | the closure the test reaches |
| a generator, arika's word table | none: always rerun and compared | the generator's hash + its inputs' hashes |

`blue check` of kaaneru (10,252 lines with its levels) takes 1.4 s, and of
eigyou 1.1 s (debug build, cid); the flake's 273 checks each check their
closure again from nothing.

The rungs, compile time first:

1. **A check cache per definition, on by default.** Check and erase results
   kept under `def_hash`, engine identity and the hashes each read, beside the
   memo store; an edit re-checks the definitions whose hash moved and nothing
   else.
2. **A bidama ships its analysis.** `mkBidama` emits the parsed, resolved,
   hashed and checked package as a nix output keyed by the engine and the
   package's source hash, so a run, a test and an editor load
   it checked, from sui.
3. **The test cache and memo on by default, shared.** The test cache is on
   by default on one node since 2026-11-09; the memo is not. The build
   identity becomes the binary's `b3:` hash instead of its path and mtime, so
   a key matches on every node and sui serves it.
4. **Narrow test derivations, with a proof.** A nix test check depends on the
   closure its tests reach, not the whole `BLUE_PATH`; the passed keys form a
   tameshi Merkle tree (`compute_leaf_root`, `leaf_inclusion_proof`), so a
   skipped test carries an inclusion proof that it passed for that hash.
5. **Generators skip on equal inputs.** A generated file records the hash of
   its generator and inputs; equal hashes skip the run. arika's word table
   becomes a sparse Merkle tree keyed by shape hash, updated by the shapes
   that moved.

**Built (rung 1, 2026-11-08):** `blue check` keeps its per-definition work in
mondou's `Store` under `$XDG_CACHE_HOME/blue/check`, one file per source file
of the program, the same `Identity` directory and header the memo uses
(`blue_lang_runtime::check_cache`). A key is BLAKE3 in the domain
`blue check v1` over the engine identity, the pass, and what the pass read:

- **resolve** (the name walk `lower` and `resolve()` run): the form's spanned
  tree with spans relative to the form, its namespace and index, and a
  span-free fingerprint of the whole name table;
- **names** (the check stage's name walk): the resolve key, the definition's
  `def_hash` (a form that defines nothing: the hash of its lowered tree), and
  whether its warnings are reported;
- **rule** (each project rule on each entry definition): the `def_hash`, the
  call-explicit form the rule reads, the rule program's erased content, its
  code, severity, step budget and memory bound.

Only a clean result is kept: a form whose walk found a diagnostic, a missing
`use` or a respelling, and a rule that reported a finding, are checked again
every run. A hit restores the walk's references with spans and node addresses
rebuilt in the current tree. An entry under another identity is refused twice:
the store's header names the identity, and the key holds it. Off
(`BLUE_CHECK_CACHE=off` or `blue check --no-cache`) runs exactly the code path
of before. The nix builds keep it off: their `HOME` dies with the build
(`mkBidama`'s app check names it off; the rest have no writable `HOME`).

Measured on cid (macOS, debug build, `blue check`, wall seconds; a
one-definition edit changes one string in one definition's body):

| Package | off | cold | warm | one definition edited |
|---|---|---|---|---|
| kaaneru (1,260 forms, 243 in the entry) | 1.37 | 1.70 | 0.73 | 0.77 |
| eigyou (1,141 forms, 2 in the entry) | 1.07 | 1.06 | 0.54 | 0.55 |

Gates (`crates/blue-lang-mondou/tests/check_cache.rs`): a callee's edit
checks it and its caller again and nothing else; an unrelated edit checks
that definition only; another engine identity checks everything, in memory
and with a store file copied across identity directories; a warm run reports
exactly the diagnostics, lowered tree and call-explicit tree an uncached run
does. The JSON output of `blue check` on kaaneru and eigyou is byte-equal off,
cold and warm.

Not yet: the parse, the docs rules (0.14 s of kaaneru) and the layout check
are not cached; adding or renaming a name anywhere moves the table
fingerprint and makes the next run cold (cold costs up to a quarter more than
off); a bucket that reaches its share of the bound takes no new entries until
it is evicted; the flake's checks gain nothing, because a sandbox has no
store that outlives it (rung 2).

**Built (rungs 2 and 3, 2026-11-10, wave 4):** one store, one identity,
one shared tier.

- **The identity is the engine's bytes.** `Identity::of_this_build` is the
  store format, the version and the BLAKE3 of the running executable
  (`store::executable_hash`), no longer its path and mtime. The hash is kept
  under `$XDG_CACHE_HOME/blue/engine/` by a stamp of the file (path, length,
  inode, device, mtime and ctime), so a build is hashed once. Two nodes, or
  two paths, running the same bytes share every entry; one changed byte
  moves every key. An unreadable executable falls back to the old parts.
- **A shared tier under every rung.** `BLUE_CACHE_SHARED` names read-only
  roots laid out like `$XDG_CACHE_HOME/blue` (`check/`, `memo/`, `test/`).
  `store::open_tier` opens one tier with them; `Store::load` falls through
  to each root on a miss, reads it under its own identity only (another
  identity's file is damage, never served) and copies what it read into the
  local store. The check cache, the memo and the test cache all open
  through it; the test cache now lives in the same `Store` (one bucket per
  build, bounded and checksummed) instead of its own text file.
- **A key is the same in every place.** The check cache's name-table
  fingerprint held every file's absolute path. The paths are read only by
  `inside_distribution` (B0021), so the fingerprint now carries the relation
  it reads (which file sits under which bidama's root) and no path, and a
  bucket is labelled `<bidama>/<file>` for a package's file. A loose script
  keeps its path: its namespace is `File(<path>)`.
- **A bidama ships its analysis** (rung 2). `mkBidama` checks the package
  a second time, from a distribution laid out as an installed one (real
  directories, files linked to their store paths, so every file sits outside
  the root as it does under `BLUE_DIST`), and keeps that check store as a
  second output, `analysis` (`check/v1-<engine>/…`). `mkAnalysis` joins a
  distribution's analyses into one root, and `mkBlueWithBidamas` suffixes it
  onto `BLUE_CACHE_SHARED` (`analysis = false` turns it off). The engine
  identity is the bytes of `${blue}/bin/blue`, which the binary wrapper
  executes, so the build's entries are the wrapper's. Measured: after
  `nix build` of `blue-with-bidamas` (763 buckets), every bucket the
  installed blue wrote checking kaaneru (17), eigyou (24), okite (13) and
  retsu (2) from the distribution was a shipped one. Seconds, release
  build, `blue check <dist>/<pkg>/<pkg>.b`, a fresh cache each (off / cold /
  warm / fed by the analysis, three runs alike): kaaneru 0.28 / 0.29 / 0.19
  / 0.20, eigyou 0.23 / 0.23 / 0.15 / 0.16, okite 0.09 / 0.10 / 0.09 /
  0.09. The first check on a node is now a warm one. Each bidama build
  checks twice.
- **The memo stays off by default**, shared when on. Measured (cid, debug,
  `blue test`, seconds, memo off / process / store):
  okite 3.23 / 3.31 / 3.60, moji 0.27 / 0.33 / 0.39, heni 0.26 / 0.29 / 0.31,
  retsu 0.12 / 0.13 / 0.13; a warm store did not win either (okite 3.52).
  The tests of the corpus repeat few pure calls, so the memo costs more
  than it answers there, and the default is the faster one.

Measured on cid (macOS, debug build, seconds, loaded machine). A second
node (another engine path, another cache, the same bytes) runs
`blue test` with the first node's cache as its shared root:

| Package | before: second node, first run | after: second node, first run | after: second run |
|---|---|---|---|
| okite (23 tests) | 3.41 | 0.25, all 23 cached | 0.15 |
| moji (103 tests) | 0.33 | 0.22, all 103 cached | 0.13 |
| kazu (52 tests) | 0.09 | 0.16, all 52 cached | 0.06 |

Before, the second node's run passed every test again: the identity named
the path. kazu's first run pays the engine hash (68 MB debug binary, about
0.05 s optimized), once per build per node.

Gates (`crates/blue-lang-cli/tests/shared_cache.rs`, the store's own
tests): a test passed on one node is cached on another node running the
same bytes from another path, and a third node with no shared root runs it;
a dependency whose callee changed runs the test again whatever the shared
root holds, and a dependency whose unrelated definition changed keeps it
cached; a package checked from two places keys every check the same; a
dependency that drops a name is reported whatever the shared root holds; a
shared root answers a miss and the entry is copied here; another identity's
file planted in a shared root answers nothing; one executable is one
identity wherever it sits and one byte moves it. Red runs: a test key
without the test's own hash fails the changed-dependency gate; `sharing`
that keeps no root fails the second-node and changed-dependency gates; the
path-and-mtime identity fails the second-node gate; the fingerprint with
the raw paths fails the two-places gate.

Not yet: a consumer's program does not reuse a bidama's analysis, because
a key carries the fingerprint of the whole program's name table, and the
program's own names are in it; that wants a fingerprint per bidama (what
its forms can see). The dropped-name gate cannot be reddened through the
cache: the dependency check (B0011) and the arity check (B0072) run outside
the cached walks, and a caller's `def_hash` already carries its callees'.
Nothing uploads a node's store to sui; a node shares through a root it is
given (a nix output, a copied directory). The test cache does not read the
analysis, and the nix test checks keep no store (`HOME` dies with them).

**One store under every rung, packaged and spread** (operator, same day:
"re-use and generalize the caching across all this", "package all the
goodness up and spread it"). The five rungs are one primitive used five ways,
not five caches. mondou's `Store` (`crates/blue-lang-mondou/src/store.rs`:
`Identity`, `Bucket`, `Store`, already the memo store's and the test cache's
root) becomes it:

- **One key rule.** A key is BLAKE3 with a domain per use
  (`blue check v1`, `blue test v1`, `blue memo v1`, `blue gen v1`), over the
  engine identity and the hashes the result read. A result read under another
  identity or domain is refused, never reused.
- **One tier ladder.** Memory, then the local disk, then sui as the shared
  tier; a miss falls through, a hit is promoted. Each entry carries its
  provenance (who computed it, from which keys).
- **One proof.** Every bucket's entries fold into a tameshi Merkle root, so
  a hit can carry an inclusion proof and a bucket's whole state is one hash.
- **Spread.** The store is a blue-lang crate any pleme-io Rust host links
  (escriba, arnes, kensa, pangea-operator), and a bidama of blue words
  (`get`, `put`, `memo`, `prove`) so a blue program caches by content with
  the same keys, tiers and proofs. A new use is a new domain string, not a
  new cache.

Prerequisite: tameshi gates its Merkle code behind `full`, which brings tokio
and axum; it gets a lean `merkle` feature (blake3 and `rs_merkle` only).
**First step:** rung 1, measured: the flake checks' total check time before
and after on rio. **Gate:** red run: change a callee's body, and the caller
is checked again; change an unrelated definition, and no other definition
is; a cached check result read under a different engine identity is refused.

### H4. Time: async, replay and a debugger that goes backwards

- **Async**, as designed in [`ASYNC.md`](ASYNC.md): `net_wait` in the node
  loop, node-time timers, the virtual clock in `blue test`, structured
  concurrency under the `heikou` space, every scheduler a blueshift position.
- **Replay.** Processes already write receipts. With the virtual clock, a run
  is a function of its inputs and its receipts: `blue replay <receipt>`
  re-runs a production failure on a laptop, bit for bit.
- **A debugger over replay.** A DAP server where stepping backwards is
  re-running to a point, not undoing; breakpoints on a definition's hash.

**First step:** ASYNC A1.
**Gate:** the async conformance set green at `schedulers(1)` and
`schedulers(n)`; a replayed run's receipt equals the original's.

**Built (2026-11-09), wave 3.** `net_wait` is in the node loop: a process
that waits on a socket parks on `Wait::Net`, and the loop polls every waiting
handle through `poll(2)` (rustix on Linux, the one `libc::poll` in the darwin
seam) beside the node-time timers A1 built. On the virtual clock a wait with
nothing ready jumps to the next deadline; a wait with no deadline waits on
the sockets in real time. The handles are the `tcp_*` words of
[`HTTP2.md`](HTTP2.md) §5d (`tcp_listen`, `tcp_port`, `tcp_accept`,
`tcp_connect`, `tcp_read`, `tcp_write`, `tcp_close`), all non-blocking and
held by `Capability::Network`. Replay: `blue run --receipts DIR --record`
runs on the virtual clock with every host call's answer on a tape per
process, writes the run's receipt as `blue-receipt` version 6 (a `replay`
block naming the hashes of the inputs, the output and the tape) and
`<receipt hash>.run.json` beside it; `blue replay <receipt>` runs the program
again from that record, every host call answered from the tape, and passes
only when the replayed run's receipt is the original's. Tests:
`blue-lang-proc/tests/net_wait.rs` (8) and `blue-lang-cli/tests/run_replay.rs`
(7), the receipt form in `receipt.rs` (2). Red runs: no poll in the idle
loop deadlocks `a_process_waiting_on_a_socket_parks_and_never_holds_the_node`;
a child `net_wait` that never parks fails it and
`a_process_wait_times_out_in_virtual_time_among_other_timers`; a replay
answered live instead of from the tape fails
`a_recorded_run_replays_to_a_receipt_equal_to_the_original` and
`a_networked_run_replays_with_no_socket_open`; an inputs hash without the
arguments fails the negative control
`a_changed_input_makes_the_replayed_receipt_differ`. Open: `schedulers(n)`
does not exist (ASYNC A6), so the gate holds at `schedulers(1)` only; a
process's `net_wait` replays its answer but not the node time it came at
(the root's does); the idle lane is not replayable; I/O words other than
`tcp_*` still block the node (A3).

**Built (2026-11-10), wave 4: the debugger over replay.** `blue debug`
speaks the Debug Adapter Protocol on stdin and stdout, framed by
`blue_lang_lsp::frame` (the language server's own `Content-Length` framing,
moved out of its server so both speak it). `launch` names the receipt of a
run recorded with `--record`; the launch replays it once from its tape under
a call observer that numbers every step (a call of a program definition, or
its return) and refuses the run when the replayed receipt is not the
recorded one. Every stop is a fresh replay to the step asked for, held to
the launch's step numbering, so `stepBack` and `reverseContinue` re-run to
an earlier point and never undo. A stop shows the stack of active
definitions, each with its parameters bound to its arguments, the innermost
one's `return` (or `raised`) at a return step, the caller's line at its call,
and each frame's `defHash`. Breakpoints: `setFunctionBreakpoints` by name or
by `def_hash` (`b3:<hex>`), `setBreakpoints` on a line where a definition
starts. `next`, `stepIn`, `stepOut`, `continue` go forward. The program's
own output goes to stderr (`dup2_stdout`, rustix), never into the protocol
stream. Tests: `blue-lang-cli/tests/debug.rs` (7), scripted DAP sessions
over a recorded run. Red runs: a stop that keeps its old stack instead of
replaying fails `a_step_back_replays_to_the_earlier_value`,
`stepping_forward_walks_calls_and_returns_to_the_end` and
`a_breakpoint_on_a_definitions_hash_stops_at_its_calls`; a return step that
drops its value fails the first two; a replay answered live instead of from
the tape fails six of seven at launch (`a_tampered_tape_is_refused_at_launch`
is its negative control); program output left on stdout fails
`the_programs_output_never_enters_the_protocol_stream`. Open: a step is a
call or a return, not a line, so a local bound inside a body shows only once
it is passed to a call; no `evaluate`; one DAP thread, so a spawned
process's calls show on the root's stack only when it runs on the same OS
thread (stacks are kept per thread); each stop costs one whole replay.

### H5. Knowledge: the corpus as a graph you can ask

- **arika Phases 2-5** ([`ARIKA.md`](ARIKA.md)): the snapshot, the MCP service
  (`blue_word_*`), full-text through codesearch.
- **khipu over blue itself** ([`KHIPU.md`](KHIPU.md)): every definition, test,
  doc, rule, receipt and commit (read through `utsushi`) as quads, so a
  question like "which definitions reach the network and have no test?" is one
  query, and so is "what changed in the words kaaneru uses since v0.0.150?".
- **Why-answers.** A diagnostic links to its rule, its law, its witness and the
  commit that introduced it, all from the graph.

**First step:** arika Phase 2, `blue arika emit` and `SNAPSHOT.json`.
**Gate:** arika G1-G9; khipu's W3C suites against Oxigraph.

**Built (2026-11-09, wave 3, on `h5/arika-khipu`):** the facts carry each
definition's `calls`, `reach` and the `tests` that name it (mondou's
`of_entry_linked`). arika Phase 3's verbs answer from them: `find` ranks by
BM25 through the new `bidamas/junni` (the subject of the ratified `sakuin` verb space:
`analyze`, `invert`, `lookup`, `score`), and `get`, `uses`, `groups`,
`changed` and `golden` (G5, 22 questions) read the rows. The MCP door is blue:
`eigyou/kyuuji` speaks JSON-RPC 2.0 and Streamable HTTP (`mcp_answer`,
`mcp_handler`), `arika.b`'s `TOOLS` is the schema, `docs/arika-tools.json` is
rendered from it (G8), and `blue arika serve` offers six `blue_word_*` tools
whose structured content is the CLI's `--json` answer. khipu ingests blue
itself: definitions, tests, doc examples and check rules as quads under
`urn:blue:`, stored for DuckDB through `kueri`, and `blue arika ask
untested-network` is one basic graph pattern with one NOT EXISTS. Gate:
`the_definitions_that_reach_the_network_and_have_no_test_are_one_question`
answers exactly `kumo::fetch` and `kumo::first_line` on its fixture, and a
test naming `fetch` leaves only `first_line`. Open: Parquet, T3, CATALOG.md
from the facts, G7, G9, `blue_word_like`, GraphQL, the release on ryn
(Phases 4 and 5's other repos), and khipu's W3C suites.

**Built (why-answers, 2026-11-10, wave 4, on `h5/why-answers`):** `blue
arika why WORD` and the MCP tool `blue_word_why` answer why a word exists and
is shaped as it is, every line cited: its reasons (the `@doc` prose, now in
the facts as `doc`; the commits whose message names it; the `docs/ROADMAP.md`
and `docs/HORIZON.md` lines that name it), its pins (the tests that name it,
its callers, the oldest commit that wrote its `def`), and each source it
could not read. Absence is its own state: `no recorded reason` when every
source was read and none says why, `blind` when one could not be read, `none`
for no such word. The history is read through gitto 0.1.5 (`list` takes
`grep:`, `pickaxe:` and `path:`; `message`). Gates:
`why_cites_the_doc_the_commits_and_the_plans_and_a_word_with_none_has_no_recorded_reason`
(a git fixture: doc, commit and plan reasons, `no recorded reason`, `none`,
`blind` once `.git` is gone) and
`why_answers_real_words_from_blue_s_own_facts_and_says_when_nothing_records_a_reason`
(`retsu::first` from its doc, `gitto::out_or` from its whole wrapped doc,
`eigyou/kyuuji::mcp_answer` from a HORIZON line, an undocumented gitto
parser that no commit or plan names with no recorded reason, and the MCP call
equal to the CLI), with the blue tests in `arika.b` and gitto's
`list narrows commits ...`. Each was seen red once. Measured 2026-11-10: one
`why` over blue's tree with the facts built in process takes 36 s (a debug
build, on a loaded machine). Open: a
diagnostic's why (its rule, law and witness) is not answered yet; commits
come from git, not from khipu quads through utsushi; a plan reason in wrapped
prose cites the one line that names the word, not its whole sentence.

### H6. Proof: claims that cannot round up

- **Properties from what a definition already says.** A doc example is a
  point; with H2's types, blue generates the neighbourhood around it
  (property tests from signatures and examples), seeded and replayable.
- **Mutation testing as a ratchet everywhere.** `heni` runs per bidama today;
  make its caught ratio a ratchet per package, so a test that cannot say no
  is visible.
- **Laws as theorems for a decidable fragment.** okite's laws and integer
  ranges checked by a solver for linear integer arithmetic and list lengths,
  behind one seam (CONTAIN THE C), the rest staying tested laws. A law the
  solver proves carries that tier; one it cannot stays tested.

**First step:** heni's caught ratio as a ratchet per package
(`bidamas/heni/ratio.baseline`, held by the `heni-mutations` check).
**Gate:** a mutant that survives makes its package's ratio fall, and the
check names the package and its survivors.

**Built (first step, 2026-11-06, `40d73db3`):** `gen/heni-gate.b`, the
`heni-mutations` check, holds every package at the caught ratio recorded in
`bidamas/heni/ratio.baseline`; a package whose ratio falls fails, named with
its survivors, and `blue gen/heni-gate.b record` is the one writer.

**Built (properties, 2026-11-09):** `blue test` draws properties from what a
definition already says. For each `@doc` example call of a typed definition
(`blue_lang_check::properties`), each literal argument whose declared type is
`Int`, `Float`, `Str` or `Bool` moves near its point by `ran`'s generator, and
each drawn call (up to 8 per example call) is one assertion of a test
``@property `f` example k, seed S``: the call returns the declared return type,
judged by `blue-conforms?`, the predicate a typed record field is judged by.
A call that raises passes; a refusal breaks no return type. The seed is
`BLUE_PROPERTY_SEED` (default 1, `off` turns it off), mixed with the
definition's name, and the cases land in the tree as literals, so one seed
replays one failure: `assert conforms?(grade(50), Str)`. No property for an
untyped definition, a return type of `dyn` or a name, an optional or rest
parameter, or an example call with no drawable literal argument. Gate,
`crates/blue-lang-cli/tests/properties.rs`: `grade(52) #=> "pass"` passes with
properties off, and the drawn `grade(50)` returns nil and fails; the same
seed gives the same output; the untyped `grade` runs exactly its doctest. Red
run: with `generated_properties` answering no tests, the fixture passed (1
test) and two of the three tests failed. Corpus cost: `blue test bidamas` ran
the same 4737 tests with properties off (81.2 s, 76.4 s) and on (81.2 s,
72.9 s), release build, the spread being host load; no corpus definition is
typed and documented with a drawable example yet, so none is generated.
Open: record and named return types; drawn values for `List` and `Sym`
arguments.

**Built (solver-checked laws, 2026-11-10):** a law is a typed definition
named `law_…` that returns `Bool`. `blue test` gives each one a `test` block
whose name says which check stands behind it, and prints a tally
(`3 law(s): 1 proved, 1 refuted, 1 tested, 0 unchecked`). Tiers:
**proved** (the solver found no model of the negation; up to 8 drawn calls
still run, so the runtime has to agree), **refuted** (the block asserts the
law at the solver's counterexample and fails: `FAIL @law
`law_take_keeps_n`: refuted (cooper) at xs = [0], n = -1`), **tested-N**
(outside the fragment, or no solver: N drawn calls, the reason in the name),
**unchecked** (no draw is possible, and the name says why). Tested never
reads as proved. `BLUE_LAWS` is `cooper` (default), `tested` (no solver) or
`off`; draws follow `BLUE_PROPERTY_SEED`. An untyped `law_…` (all of okite's
today) gets no block, so no program that runs today changes.

The seam is `blue_lang_check::lia::Backend`, one typed enum: `Cooper`, a
pure-Rust Cooper search over linear integer arithmetic with divisibility,
and `Absent`, the typed absence of a solver (every answer `Unknown`). No C is
linked. Each step picks the variable with the fewest candidates and the
smaller of its lower and upper bound sets, inequalities are divided through
by their gcd, every candidate costs one step of a 200 000-step budget, and a
spent budget answers `Unknown`, so the law is tested. A model is checked
against the formula before it is returned. `blue_lang_check::laws` reads the
law into the fragment: `Int` parameters as integers, `Bool` parameters as
truth values, `List` parameters by their length alone; `+`, `-`, `*` and `%`
by a constant, `abs`, `min`, `max`, comparisons, `==`, `!=`, `and`, `or`,
`not`, `if`, local bindings, and the lengths of lists built by `[…]`, `cons`,
`append`, `reverse`, `map`, `take`, `drop`, `range` and `zip`, read by
`length`, `count` and `empty?` (each length rule measured against the
runtime: `take(-1, xs)` is empty, `drop(5, [1, 2, 3])` is empty,
`range(5, 2)` is empty). A refuted list law gets a list built to the length
the solver chose. A word the file defines is read as the file defines it,
inlined; a word a `use` brings in bare is outside the fragment. Blue
integers raise on overflow, so a law proved over the integers holds at every
call that returns. B0043 never reads `law_` as a hand-made namespace: a
program of three laws was refused, and `blue run` would have stripped the
prefix and with it every law block (`canon.B0043.laws`).

Gates: `crates/blue-lang-cli/tests/laws.rs` runs `blue test` on fixtures:
`law_clamp_in_range` is proved; `law_clamp_is_identity` is refuted and red at
its counterexample; with `BLUE_LAWS=tested` the true law is tested and
passes; `a * b == b * a` is outside the fragment and tested; a list-length
law is proved and a false one is red at a built list; an unchecked law, and a
proved law with draws off, leave the file running (red first: the empty
block's body was the symbol `nil`, and B0001 refused the file). Red runs: with
`Cooper` answering `Unknown` for every formula, the proved fixture's tally
read `0 proved, 0 refuted, 1 tested` and four of the six tests failed; with
`Cooper` answering `Unsat` for every formula, the false laws were named
`proved (cooper)` and only the drawn calls beside the proof failed them.
`lia::tests::cooper_agrees_with_a_search_of_the_box_on_drawn_formulas`
checks 400 drawn three-variable formulas: no `Unsat` has a model in
`[-9, 9]³`, every `Sat` model satisfies its formula, and fewer than 60 answer
`Unknown`; with the far candidates dropped it failed at once. The WIP
translator read a same-file `def abs(x) x end` as the builtin and named
`abs(a) >= 0` proved; `a_word_the_file_rebinds_is_read_as_the_file_defines_it`
was red on it before the fix. Cost, debug build: on 300 drawn formulas with
coefficients up to 2, the WIP search (fixed variable order, lower bounds
only) took 142 s and the per-variable choice 0.07 s; with coefficients up to
3 one formula still took 87 s until each candidate was charged to the
budget; the 400 of the gate take 4.2 s. Open: okite's laws as typed laws
(they take no arguments and test runtime behaviour, not arithmetic); integer
ranges on parameters (H2's refinements); `rest`, `butlast` and `filter`
lengths; a z3 backend behind the same enum; no corpus definition is a typed
law yet. Law blocks are made at every parse of the entry file, as doctests
and properties are, so `blue run` and `blue check` of a file with typed laws
pay the solver (within its budget) for blocks they drop; the parse does not
know whether tests will run.

### H7. Speed with receipts

- The bytecode VM as the default door where the conformance columns agree.
- Ahead-of-time compilation of a hot bidama to wasm, run by the same component
  host services use.
- Performance as a ratchet: `blue bench` results recorded per release, a slower
  release refused unless it carries a typed reason ([`PERFORMANCE.md`](PERFORMANCE.md)).
- Faster than Rust by doing less work ([`PERFORMANCE.md`](PERFORMANCE.md)
  section 3.0): each lever blue's knowledge enables (bake, memo by identity,
  incremental, data-parallel, partial evaluation) is a bench row per
  workload, a ratio against a plain Rust program of the same job, held by
  the same ratchet. Parity through `chuuzou` is the floor, not the target.

**First step:** a bench row set in CI with a recorded baseline.
**Gate:** red run: a deliberately slower build fails the ratchet.
(2026-11-11: shinsuu's old hex words on `BLUE_PATH` turn `hexmsg` red,
PERFORMANCE.md 0.1.)

### H8. Reach: one program, every placement

`fueki` renders one program by placement. Extend the placements:

- **Browser.** Frontends in blue ([`FRONTEND-PLAN.md`](FRONTEND-PLAN.md)), the engine as a
  wasm component in the page.
- **Kernel.** `kaaneru` compiles blue to BPF; more program kinds, and a
  verifier report that names the blue line.
- **Nix.** Blue as the source of nix configuration (`kakehashi`): a node's
  configuration authored in blue, nix a rendering, so no hand-written nix
  remains in a blue project.
- **GPU (aspirational).** A restricted rung of blue lowered to compute shaders
  for data-parallel definitions.

**First step:** the frontend plan's first rendered page served by a blue service.
**Gate:** the same program, run through two placements, gives equal receipts.

### H9. Model-native: a language designed for the pair that writes it

- **A model eval suite as a ratchet.** Golden tasks a model must solve in blue
  (write a bidama word, fix a refusal, port a function), scored each release;
  a release that makes blue harder for models to write is visible.
- **Diagnostics as prompts.** Every rule carries a witness, a law and a fix;
  make each diagnostic's JSON a complete repair instruction, tested by the eval
  suite.
- **Naturalize as a tool.** `blue naturalize <crate|module>` scaffolds a
  bidama with a differential harness against the original, so porting a
  library is filling in rows until the harness agrees.
- **Context packs.** `blue context <word>` returns the word, its laws, its
  callers and its tests in one bounded answer (arika's facts).

**First step:** ten golden tasks and a scored run recorded per release.
**Gate:** the score is a census row; it may not fall without a typed reason.

**Built (2026-11-11, on `h9/model-native`):** all four items, each seen red
once.

- **The eval as a ratchet.** `eval/score.baseline` is the census: one
  `model-eval-passed` row per run, `reference` and each model's latest
  answers under `eval/scores/<version>/<model>/`. `eval/census.b` rescores
  every run with the blue being built, and `checks.model-eval` runs it, so a
  broken recorded answer or a blue change that a recorded answer no longer
  passes is red. A row falls only through `record --reason <task-added |
  task-changed | rule-tightened | answers-replaced> --receipt WHY`. First run:
  `claude-opus-5-5` at 0.0.192, given only each `prompt.md`, the blue CLI and
  blue's docs, 10/10. Red: one recorded answer replaced by a stub, `passes 9,
  below its recorded 10`.
- **Diagnostics as repair prompts.** `blue check --format json` carries each
  rule's `law` and `witness`, and a formatter-fixed rule with no edit gets one
  machine-applicable whole-file edit (`fixes::complete_with_rewrite`).
  `every_rule_outside_the_census_is_repaired_by_its_own_diagnostic` applies
  each rule's first fixes to its own witness and the rule must stop firing;
  `a_diagnostic_s_json_alone_carries_its_law_its_witness_and_a_repair` does it
  through the CLI. The census `fixes::REPAIR_CENSUS` is held exact: 35 of 79
  rules (2026-11-11), mostly the refusals with no single right edit (types,
  waivers, duplicates, data laws, `discarded-value`). Red without the rewrite:
  23 rules.
- **`blue naturalize TARGET DIR`** (`crates/blue-lang-cli/blue/naturalize.b`):
  a Rust module (`FILE.rs[::name]`, rustc) or crate (`CRATE_DIR[::mod::name]`,
  cargo) to a bidama of stubs, the rows the original returned (a panic is a
  `raises` row) and a test per word that is red until the body agrees.
  `tests/naturalize.rs`: red as stubs, red with a wrong body, green ported.
- **`blue context WORD`** (and `blue arika context`, MCP `blue_word_context`):
  the word, its import line, doc, reach, the `law_` definitions that call it,
  its callers, its tests and its callees, each list capped at 8 with its
  total, the whole at most 8192 bytes. Red with the cap removed: 774 callers
  shown.

Open: the 35 rules of the repair census; naturalize drives only scalar, text
and integer-list signatures; model runs are recorded by hand, outside CI.

### H10. Ecosystem: bidamas anyone can trust

- A registry of bidamas with quality signals computed, not claimed: docs
  coverage, tests, heni ratio, reach, conformance, model-eval score.
- Signed releases (`shomei`) and lock-verified loading (gap G10).

**First step:** the quality signals rendered per package in CATALOG.
**Gate:** each signal reproduces from the lock alone.

## Authority and ontology: one capability set, every placement, every concept a class (H11 to H20)

Added 2026-11-07 (blue `9ca7c2cc`, release v0.0.160), from two read-only
surveys of the language and of every placement. Every "built" below cites code.

**The destination.** Authority in blue is a capability, and a capability comes
from one place. A program, a bidama, a process and a service each hold only
what their declaration grants, narrowed from their caller and never widened.
One closed set, `blue_lang_waku::Capability`, names every host effect, and
every other list is a projection of it. One declaration renders the boundary
of every placement: the interpreter frame, the embedder posture, the wasm
imports and grant, the engenho native enclosure, the Kubernetes NetworkPolicy
and securityContext, the systemd sandbox, the image entrypoint and the browser
CSP. One gate proves that the placements agree. A program with no declaration
is pure. Ambient authority is a declaration (`allow(:all)`), visible and
counted, never a default.

World-facts that limit this destination: WASI has no subprocess; a dynamic
language cannot prove higher-order purity without an effect system (H14 builds
one); the kernel verifier and the browser origin are boundaries blue renders
to, not boundaries it replaces.

### Where authority stands (measured 2026-11-07)

| Fact | Value |
|---|---|
| Capability set | 6 pure and 14 host bundles, closed, no `Other` arm (`crates/blue-lang-waku/src/capability.rs:349-426`) |
| Lattice | `Reach` with meet and join; `narrow` is the only run-time move, there is no widen (`crates/blue-lang-waku/src/lib.rs:70-297`) |
| Lock check | `⋁ floors ⊑ allow ∨ provided`, per definition (`crates/blue-lang-pkg/src/capabilities.rs:862-1035`); runs only when the root declares `allow`, a provider or `bounds` (`:1097`) |
| Run-time hold | one frame for the whole interpreter; a breach is fatal, exit 77 (`crates/blue-lang-runtime/src/lib.rs:376-543`) |
| Default | ambient when nothing is declared: `blue run`, `load_hosted`, an embedder with no posture |
| Adoption | 1 of 88 Bluefiles declares `reach` (`bidamas/kaaneru`), 1 declares `allow` (`examples/docking`) |
| Service access | `Access`, with a second, 7-variant `Effect` enum (`crates/blue-lang-pkg/src/deploy/runtime.rs:8`) |
| Placements with a boundary derived from `access` | 1 of 14: the engenho wasm pod (`blue.pleme.io/access`, enforced by engenho's kidou) |
| Placements with no boundary | GitHub Actions `run.b`, the image entrypoint, `mkBlueApp` executables, the systemd and launchd trio |

### H11. One vocabulary

`access.effects` names 7 `Effect`s; the Bluefile's `allow` and `reach` name 14
`Capability`s, spelled differently (`kernel_bpf`, `kernel-bpf`). Nothing ties
a service's code to its `access`.

- `Effect` becomes a projection of `Capability`: a total, tested map, so a
  capability added to waku has a service spelling or the build fails.
- A service's code floor, which `blue lock` already derives, must fit under its
  `access.effects`.
- One spelling, read both ways by the parser, printed one way.

**First step:** `Effect` derived from `Capability` by an exhaustive map, and
`blue lock` refuses a service whose floor exceeds `access.effects`, naming the
definition.
**Gate:** red run: a service whose code calls `exec_into` without `:process`
in `access` fails the lock.
**Unlocks:** H12, H16.
**Built (first step, 2026-11-07):** `Effect::capability` and
`Effect::of_capability`, the second an exhaustive match over every
`Capability` (`crates/blue-lang-pkg/src/deploy/runtime.rs`); `access.effects`
reads either spelling and refuses a host capability with no service spelling
by name; `capabilities::verify_access` holds each service's code to its
`access.effects` at lock (`crates/blue-lang-pkg/src/capabilities.rs`). Gate:
`crates/blue-lang-cli/tests/lattice.rs`,
`a_service_whose_code_reaches_past_its_access_is_refused_at_lock`; red run:
without the check that test fails.

**Typed weaker (2026-11-07):** every service reads its own declaration at
boot: `nix/service.nix` bakes `defaults.yaml` into every service's image and
`settei` reads it through `*_DEFAULTS`. So every service's lock ceiling holds
`filesystem` (`capabilities::DECLARATION_READ`). The lattice has no read/write
split, so this admits any file reach at lock; the layers that hold a service
to its declaration read are SERVICE-ACCESS A2/A3, not built. H15's
path-scoped grants close it. Gates: `a_service_reads_its_own_declaration_and_locks`,
`the_declaration_read_grants_filesystem_and_nothing_else`; red run: with
`DECLARATION_READ` another capability, the first fails. The docs gate found
this: it runs every tutorial block, and the tutorial service was refused.

### H12. Pure by default

Every door with no declaration is ambient today. The flip comes in rings, each
its own land. `allow(:all)` stays a legal declaration, so no behaviour is
deleted; it is configured, and the configuration is visible.

1. A census: every Bluefile and every action `run.b` in pleme-io declares
   `allow`; a check counts the undeclared ones, and the count only falls.
2. The lattice check runs on every lock, not only when the root declares.
3. Embedders: a `Load` with no posture is pure, and ambient is
   `posture(Capability::all())`. A posture refusal is fatal, as `blue run`'s
   breach is, unless the embedder declares it catchable.
4. `blue run` with no declaration grants nothing; `--allow all` and
   `allow(:all)` keep the old behaviour.

**First step:** rings 1 and 2.
**Gate:** red run: a project with no `allow`, whose bidama declares
`reach(%i[clock])` and calls `read_file`, fails `blue lock`.
**Unlocks:** H13.

### H13. Authority per bidama at run time

The run-time hold is one frame for the whole interpreter. A bidama gets every
capability the root grants, and code a dependency gained after locking is held
only by the root.

- Each package runs in its own frame: its declared `reach` met with its
  caller's hold.
- `process` implies every capability, since a subprocess can do anything; a
  grant of it reads as top.
- Program macros run in the macro-phase frame (today they expand under the
  run's hold).
- A spawned process holds its spawner's frame or a narrower one.

**First step:** per-package frames through the scoped-provider path
(`crates/blue-lang-runtime/src/lib.rs:395-431`), and `process` implies all.
**Gate:** red run: under a root `allow(%i[filesystem clock])`, a bidama with
`reach(%i[clock])` that calls `read_file` is refused at run time.
**Unlocks:** H15.

**Memory is part of the frame** (operator, 2026-11-07: "protect memory
spaces … easily define these memory boundaries in bluelang"). Built today:
a live-byte account per evaluation and per blue process, refused with a
typed `memory-exhausted` rather than an abort
(`crates/blue-lang-runtime/src/memory.rs`, `alloc.rs`); a process rlimit
for a host's worker (`bound_memory`, `crates/blue-lang-host/src/world.rs`);
a pod limit from a service's `resources`. Missing: a bound a bidama or a frame
declares, and isolation between frames.

- **Declared with the authority.** A frame carries a memory bound beside its
  capabilities: `reach(%i[clock], memory: "64mb")` in a Bluefile, the same
  in `spawn(f, args, {memory: "16mb"})`. The rule is the capability rule: a
  child's bound fits under what its parent has left, and its account charges
  the parent's too.
- **Isolation by immutability.** Frames share only immutable values. A value
  that crosses a frame is content-addressed (H3's one store, hash-consed), so
  sharing it costs nothing and the receiver cannot write the sender's memory;
  mutable state lives in a process and is reached only by message.
- **One number, every layer** (H16): the interpreter account, the process
  meter, the worker's rlimit, the service's cgroup `memory.max` and the
  kernel map of H20 render from the one declaration.
- **The native gap.** The account is read between steps, so one native call
  that asks for more than the machine holds still aborts (`memory.rs`, "what
  it does not bound"). A native's large request is checked against the
  account before it allocates, the same seam escriba's stoppable native call
  needs.

**Gate:** red run: a bidama declared at `memory: "1mb"` that builds a 2 MB
list is refused with `memory-exhausted` while its caller, under a larger
bound, continues; a value passed into a frame and changed there leaves the
sender's value unchanged.

### H14. The checker sees authority

Refusals come from the lock and the runtime, never from `blue check`, so an
editor sees none of them.

- Effect inference per definition in the check stage, from the free-name walk
  the lock uses, with an effect variable so `map(f, xs)` carries `f`'s
  effects.
- A `capability-escape` B-code at check time, with the path to the host word
  (gap G9's destination).
- ASYNC's `suspends` joins the same effect row.

**First step:** the B-code for first-order escapes, judged against the root
Bluefile's ceiling.
**Gate:** red run: `blue check` on a file that calls `now_ms` under
`allow([])` names the code and the line.

### H15. Capabilities as values

Authority today is "can name X". An object capability is a value: passed in,
narrowed and revoked.

- A grant is a value (`fs = grant(:filesystem, under: "/data")`), and the host
  word takes it.
- Attenuation: `fs.under("logs")`, `net.only("db:5432")` (per-peer egress
  inside the language), `clock.monotonic`.
- Revocation by the grant's maker; a use after revoke is a typed refusal.
- The ambient names stay as sugar over the root grant, configured off per
  project.
- New capabilities: `secret` (SAFETY row 14: opaque, redacted on print,
  refused on send), `stdout`, `gpu`. An embedder extension joins the closed
  set or is refused.

**First step:** the filesystem grant with `under`, and the `secret`
capability.
**Gate:** red run: a function given `fs.under("a")` cannot read `b/x`; a
printed secret shows `<secret>`.

### H16. One declaration, every placement

Only the engenho wasm pod turns `access` into a boundary today.

- haibi also renders `kakoi.pleme.io/access`, so a native-rung service gets
  its enclosure from the same declaration; one annotation read by both doors
  is the destination.
- A wasm component imports only what `access.effects` grants (SERVICE-ACCESS
  S3).
- The chart renders NetworkPolicy egress and ingress, read-only `reads`
  volumes and `automountServiceAccountToken` (A2).
- The trio renders systemd `IPAddressAllow`, `ReadOnlyPaths`,
  `NoNewPrivileges` and `SystemCallFilter` (A3).
- The image entrypoint and `mkBlueApp` executables run with `--allow` derived
  from `access`; a Rust host loads a service program under
  `posture(access.effects)` (A5).
- An action's `run.b` gets a Bluefile with `allow`.
- `frontend(...)` and `workload(...)` gain `access`; a frontend's CSP and
  `connect-src` render from it.
- Default egress: the code renders `[]`; SERVICE-ACCESS.md §3 says the
  declared bindings plus DNS. The doc's default is the destination.

**First step:** haibi renders the kakoi annotation, and the
`-component-serves` check's wasmtime flags derive from `access`.
**Gate:** red run: on engenho, a native pod of a service with `egress: []`
that opens a socket is refused.
**Unlocks:** H17.

**The model is the native way to model** (operator, 2026-11-07). Anything
that has to be modeled is declared once, as a blue model (`chozou/teeburu`'s
`model`, in its own bidama as "A schema is a bidama" below; the Bluefile `model` word this line named until
2026-11-09 is superseded, `SERVICE-ARCHITECTURE.md` §5c), and every artifact that names its shape is a rendering of it, never a second
spelling:

| Rendering | From the model | State (2026-11-07) |
|---|---|---|
| storage and migrations | tables, `keifu`, the additive SQL, shinka's `DatabaseMigration` | built; the CR is string lines, not checked against shinka's CRD |
| API | GraphQL types and Query roots (`toriyose/outou`) | `from_model` built; the bridge from teeburu's shape is being built with rubrica |
| client | typed fragments (`danpen`), the normalized store's keys (`kyasshu`) | built over a generated schema table |
| gates | kenshi `TestGate` and `BuildPipeline` from the Bluefile's checks | design (SERVICE-ARCHITECTURE P7) |
| packaging | the service's chart on pleme-lib, published by version | chart built, publish being built; pleme-lib not pinned; pleme-lib is configured off per chart as typed rendering covers it (`SUBSTRATE.md` §7, 2026-11-09) |
| ontology | a khipu class per entity, a property per field, a shape per constraint (H19) | design |

A shape spelled twice (a GraphQL type written by hand beside its table, a
migration written beside the model) is the bad state; the gate is the H17
matrix with a column per rendering.

**GraphQL compiled to one query, not resolved field by field.** `outou`
resolves each field with a function, which over a database is one query per
field per row (N+1), the problem Hasura and PostGraphile exist to remove. From
the model, an operation compiles to one `kueri` statement (joins, a JSON
aggregate per selection), and the bar is set past theirs:

- every operation is checked against the model at build time (`danpen`), so a
  query naming a missing field is a compile error, not a request-time one;
- production runs persisted operations only, keyed by their hash (H3);
- row access comes from the same declaration as the capability frame, not a
  second metadata layer;
- a result is cached in H3's store under the operation hash and its inputs,
  invalidated by the model's `keifu` changelog, with a Merkle receipt of what
  was served.

**Gate:** one SQL statement per operation for every operation in the
fixture, measured by the statement log; red run: an operation naming a field
the model lacks fails the build.

**No SQL is written by hand** (operator, same day). SQL is a rendering of
`kueri`'s typed AST, from the model or from a typed query, the house's TYPED
EMISSION rule applied to databases. Today haibi writes its DDL and its
migration as text lines (`bidamas/eigyou/haibi/haibi.b`), and they move onto
`kueri` and `teeburu` first.

**One data framework.** The pieces above are one framework, encapsulated as
one entry bidama that composes them the way `zenbu` composes the
distribution: the model (`chozou/teeburu`), its evolution (`keifu`, shinka),
its queries (`kueri`), its API (`toriyose/outou`, compiled to one statement),
its client (`danpen`, `kyasshu`), its stores (`kiibariu`, `sutoriimu`), its
gates (kenshi) and its classes (khipu). A program writes one `use` and one
model; the bidama's name is minted through the naming procedure, which is
pending. The design, the research it rests on and its
rungs D1 to D6: `docs/DATA-FRAMEWORK.md`.

**A schema is a bidama.** A model lives in its own bidama, versioned and
locked like any package and hashed by `teeburu::version_hash`, so one
schema is redistributed to every system that needs it: the services that own
and read it, Postgres and DuckDB through `kueri`, Valkey through `kv_model`,
JetStream subjects through `sutoriimu`. `teeburu::evolve` and `judge` refuse
a breaking change, so a consumer pinned to a version cannot be broken under
it. A `model` macro expands one form into the typed accessors and renderings
(SERVICE-DATA's pending model accessors); it waits on compile-time,
hygienic macros, since blue's `defmacro` expands after the check stage today.

**Gate:** an okite law refuses a database call
whose statement is a string rather than a rendered `kueri` value; red run: a
fixture passing `"SELECT 1"` to it is refused at `blue check`.

### H17. Parity: the placements agree on authority

kakoi, kidou, the chart and the trio each keep their own effect table. Nothing
proves that one `access` allows and refuses the same effects in each.

- A capability conformance matrix, in the shape of `spec/rows`: per
  capability, a probe that succeeds when granted and is refused when withheld,
  on every placement column.
- kakoi and kidou read one effect table generated from waku.

H8 compares what a program computes across placements; H17 compares what it is
allowed to do.

**First step:** the matrix on three columns: `blue run`, the wasm component,
the engenho wasm pod.
**Gate:** red run: one column that allows a withheld capability turns the
matrix red.

### H18. Least privilege as a ratchet

The hold already counts calls per granted name
(`crates/blue-lang-runtime/src/lib.rs:440-475`).

- Each run's receipt records the capabilities it used.
- Declared minus used is a census row per package, and it only falls.
- `blue lock --tighten` writes the narrowest `reach` the code allows.

**First step:** used capabilities in the receipt, and the census row.
**Gate:** a capability declared and never used by the test suite appears in
the census, and the row may not rise.

### H19. Ontology: every concept a class, every law a shape

Operator, 2026-11-07: *"capabilities and everything else in bluelang should
have full ontology and therefore be able to be fully ontologically tested"*.

Blue's concepts live today in typed tables that do not know each other: the
waku capability table, `Effect`, the host installers, `RULES`, the word
shapes, the Bluefile and its lock, arika's facts. A relation between two of
them (this host word belongs to that capability; that capability renders at
this placement) is checked, if at all, by a test written for that pair.

- **One ontology of blue, in khipu.** Classes for each concept (Capability,
  HostWord, Effect, Placement, Boundary, Bidama, Definition, Rule, Shape,
  Process, Service, Access, ...) and properties between them (`implies`,
  `projectsTo`, `belongsTo`, `rendersAt`, `enforcedBy`, `reaches`, `declares`,
  `refusedBy`). Each instance is rendered from the typed table that owns it,
  never hand-kept, as N-Quads in khipu (K1a, built), with the dataset's
  content hash.
- **Axioms are shapes.** Each law is a khipu shape (KHIPU K4, each a `kousei`
  entry judged alone): every host word belongs to exactly one capability;
  every capability projects to an Effect or says it has none; every
  (placement, capability) pair has a rendering or a typed refusal; every rule
  has a witness, a law and a fix; every exported definition has a doc. An
  unbuilt constraint is `blind`, and `blind` is never `conforms`.
- **Ontological testing.** The tests are generated from the ontology: each
  axiom over each instance is a row. H17's matrix is the (placement,
  capability) slice of it. An all-variants gate makes completeness a build
  fact: a new variant of a concept's enum or sum with no ontology rows fails
  the build.
- **One face to ask.** `blue ontology ask` takes a SPARQL query (KHIPU K2), and
  arika's facts (H5) join as the instances of Definition.

**First step:** the capability ontology. Capability, HostWord, Effect and
Placement rendered from the waku table, the `Effect` map and a placement
table into N-Quads, and four shapes judged in blue over the quads until K4
lands.
**Gate:** red runs: a host word with no capability, a capability with no
Effect decision and a placement with no row for a capability each turn the
ontology check red, naming the instance and the axiom.
**Depends on:** khipu K1b to K4 for the store, the query and the shape
engine; H5 for the facts.

### H20. Kernel: admitted by construction, and the kernel as the enforcer

Operator, 2026-11-07: blue as a verifier-guaranteed language, and the kernel
with BPF as a deterministic capability sandbox. Measured against that claim:

- Not yet: "blue requires explicit capability declarations". An undeclared run
  is ambient (H12).
- Partly: "cycle budgets". The interpreter has `bounds`; in BPF the bound is
  the verifier's, and `kaaneru` inlines calls, holds 64 stack slots and lowers
  tail loops only for a `CAP_BPF` loader (`KERNEL.md` §4).
- Not so: "formal contracts (blueshift)". The blueshift is a position between
  two good ideals, not a contract system.
- Not claimed: "unhackable". The verifier is part of the trusted base, and it
  has admitted a program that panicked the kernel: `sdiv` of the lowest value
  by -1 at 6.6.142, measured 2026-11-04 (`KERNEL.md` §4). Admission is a
  property against a named kernel, not a proof of safety.

**Admission by construction.** The bad state is a program that compiles and
the verifier then refuses. `kaaneru` already refuses some shapes at compile
time (`*` on a parameter of a global subprogram, a stack past 512 bytes, a
signed divide below 6.12). Make that the rule for every shape:

- Each verifier refusal the matrix observes becomes a compile-time rule with
  the blue line and the reason, at the floor kernel (6.6) and per kernel
  where they differ.
- A complexity estimate at compile time (instructions, branches, stack) beside
  the verifier's own limits, so a program near a limit is named before load.
- The proof is differential, because the verifier is the oracle: a generator
  over the language the compiler accepts, every program loaded on every
  matrix kernel (6.6.142, 6.12.92, 6.12.93, 7.0.11). One refusal at load is
  red and becomes a new compile rule.

**The kernel as the enforcer of `access`.** For a native placement, the kernel
is where a boundary cannot be skipped by the program. `access` renders to BPF
LSM and cgroup programs attached to the service's cgroup (`file_open`,
`socket_connect`, `bprm_check_security`, device and `sock_create`, each already
attached by blue on plo, `KERNEL.md` §6), beside kakoi's Landlock and seccomp.
The same declaration, one more rendering; H17's matrix gets a kernel column.

**`kernel_bpf` attenuated.** One capability for every program kind is coarse.
A grant names the kinds and attach points it allows (tracing, XDP on one
interface, LSM), as H15 attenuates the filesystem, and the chart's exact Linux
capabilities derive from the kinds.

**Full control of the BPF layer, joined to capabilities** (operator,
2026-11-07, second brief: Linux as the hardware layer, policy in blue's
programs). Measured the same day:

| Part | State | Where |
|---|---|---|
| LSM, XDP, cgroup and `struct_ops` programs compiled and attached by `kaaneru` | built, measured on plo | `bidamas/kaaneru/kaaneru.b` (lsm kind, `attached`, `install_struct_ops`); `KERNEL.md` §6 |
| An enforcer in blue | built, one target task | `kanshi/enforcer/program.b` (a one-slot map holding one tgid) |
| A capability mask per cgroup in a BPF map, filled from the waku hold | absent | the missing primitive below |
| AF_XDP to user space | absent | `xskmap` and `redirect_map` are names only (`bpf/bpf.b`) |
| ibuki's wire header and Tide (LEDBAT) in the datapath | absent; Tide runs in the interpreter | `bidamas/ibuki/ibuki.b` (Tide controller) |
| `sched_ext` | absent; the `struct_ops` loader is proven on TCP congestion control | `KERNEL.md` §6 |
| Crash record and replay | built for the interpreter (blue-trace v3, `blue replay`); no kernel events in the trace | `crates/blue-lang-proc/src/trace.rs`, `crates/blue-lang-cli/src/replay.rs` |
| A Linux guest from macOS | absent: the vm checks write `-absent` on darwin; kasou (Virtualization.framework) is not wired to tests | `nix/vm-check.nix` |
| Kernel config asserted | partial: `lsm=landlock,yama,bpf` and `FPROBE`; `BPF_LSM`, `DEBUG_INFO_BTF`, `XDP_SOCKETS`, `SCHED_CLASS_EXT` are not asserted | `Bluefile` kernel matrix |

Washed claims: Linux keeps hardware, page tables and the verifier, so it
stays in the trusted base (not "zero authority"); a time ("nanoseconds") is
a measurement on a named kernel, not a design property; replay of a kernel
breach replays the recorded event into the interpreter, never the kernel.

The parts, in order:

1. **The capability frame in the kernel.** A BPF map keyed by cgroup id,
   holding the frame's `Reach` as a mask, written when a service starts or an
   actor spawns from the run-time hold (H13), and one generic program set that
   reads it: `file_open`, `socket_connect`, `bprm_check_security`, device and
   `sock_create`. A denied call returns `-EPERM` and writes a ring-buffer
   event that the host records into blue-trace, so `blue replay` reproduces
   the breach in the interpreter. kanshi's enforcer is the template.
2. **A Linux guest from macOS.** One nix command boots a kernel with the
   asserted config (`BPF_LSM`, `DEBUG_INFO_BTF`, `XDP_SOCKETS`,
   `SCHED_CLASS_EXT`) under Virtualization.framework through kasou, shares the
   checkout over virtiofs, and runs the vm checks, so the loop does not need
   plo or a hosted KVM runner. The kernel matrix keeps its kernels; this adds
   a host.
3. **The wire in the datapath.** ibuki's header parsed in XDP, Flash frames
   redirected to an AF_XDP socket, Tide's delay controller lowered from the
   interpreter to tc or XDP with the same tests.
4. **`sched_ext`.** A `sched_ext_ops` struct through the proven `struct_ops`
   loader, with a dispatch queue for background actors that an interactive
   wake preempts.

**First step:** the generator and the load-everything gate on the matrix
kernels, and the first compile rule it produces. **Then** part 1 on plo: a
service whose `access` lacks `network` is denied `connect` by the kernel.
Red run: with the map entry absent, the connect succeeds and the test fails.
**Gate:** red run: a generated program shape the compiler accepts and 6.6
refuses fails the matrix, naming the shape; after the rule lands, the compiler
refuses it with the blue line.
**Depends on:** the kernel matrix (`.github/workflows/kernel-matrix.yml`),
H16 for the rendering, H15 for the attenuated grant, H19 for program kind,
attach point and kernel release as ontology classes.
**Unlocks:** H17 (its matrix is generated), H14 and H18 (their effects and
receipts become instances).

## Order

Since 2026-11-09 the build order is SUBSTRATE's three layers (the note at the
head of this document). H8 lands as SUBSTRATE L2.1 to L2.3; the authority
horizons H11 to H20 land through the layer 1 phases that need them. The table
keeps the 2026-11-06 order inside that frame.

| When | Horizons | Why first |
|---|---|---|
| Now | H0; H1 (unions, patterns, `?`); H3 (the test cache) | H0 makes the ledger true; H1 completes the data model every later horizon names; H3 makes every later change cheaper to verify |
| Next | H2; H4 (async A1); H5 (arika Phase 2); H6 (heni's ratio as a ratchet, built; generated properties, built; solver laws, built) | each builds on H1's shapes or H3's identities |
| Later | H7; H8; H9; H10 | each multiplies what the earlier horizons made true |
| Authority, now | H11; H12 rings 1 and 2; H16's first step; H19's first step | one vocabulary first, so every later horizon names one set; the census measures the flip before it happens; the capability ontology makes every later authority horizon a set of generated rows |
| Authority, next | H12 rings 3 and 4; H13; H17 | per-bidama frames and the parity matrix stand on one vocabulary |
| Kernel, alongside | H20's first step | the matrix and the compiler exist; the generator only needs them |
| Authority, later | H14; H15; H18; the rest of H20 | effect inference and capability values change the language surface; least privilege needs receipts from every placement |

## What this plan refuses

- A feature without a gate. Every first step above names the red run that
  proves it.
- A second language for a placement. A placement blue cannot reach is a rung
  to build, not a reason to write TypeScript, nix or Rust beside it.
- Ambient authority as a default. It stays legal as a declaration.
- A placement that configures its boundary by hand. Each boundary is rendered
  from the one declaration.
- A global switch to settle a conflict between two good ideals. That is a
  blueshift position.

## Ledger

✅ built and tested · ⏳ in progress · ❌ not built

One row per horizon, measured 2026-11-09 on main. A ⏳ row names what is built
and what is not.

| Item | State | What makes it true |
|---|---|---|
| H0. Hygiene | ⏳ in progress | Built: the DIAGNOSTICS codes table and CATALOG's `needs` render in `nix run .#regen`; `checks.package-fidelity` (`nix/package-fidelity.nix`); B0058 at 0. Not built: B0056 and B0057 at 0. |
| H1. Shapes | ⏳ in progress | Built: unions, patterns, destructuring bindings and `?` (`spec/rows/unions.b`, `patterns.b`, `refusals.b`; `crates/blue-lang-runtime/tests/unions.rs`). Not built: one declared `result` union, `?` on an Option, a record pattern from another bidama. |
| H2. Types that grow | ⏳ in progress | Built: local inference in a typed definition (`check.infer` rows in `spec/rows/check.b`). Not built: record and union types in signatures, the checked boundary, a `strict` position per file. |
| H3. Code is content | ⏳ in progress | Built: rung 1, the check cache per definition, on by default (`crates/blue-lang-mondou/tests/check_cache.rs`); the test cache, on by default (`BLUE_TEST_CACHE=off` turns it off); the memo, off by default (`BLUE_MEMO`). Not built: rungs 2 to 5 and the shared store. |
| H4. Time | ⏳ in progress | Built: `net_wait` in the node loop (`crates/blue-lang-proc/tests/net_wait.rs`), node-time timers, record and replay (`crates/blue-lang-cli/tests/run_replay.rs`). Not built: `schedulers(n)`, the debugger over replay. |
| H5. Knowledge | ⏳ in progress | Built: arika Phase 2 for blue's own tree (`crates/blue-lang-cli/tests/arika.rs`), khipu K1a (`bidamas/khipu`). Not built: the MCP service, khipu over blue itself, why-answers. |
| H6. Proof | ⏳ in progress | Built: heni's caught ratio as a ratchet (`bidamas/heni/ratio.baseline`, `checks.heni-mutations`); generated properties (`crates/blue-lang-cli/tests/properties.rs`). Not built: laws over a decidable fragment. |
| H7. Speed with receipts | ⏳ in progress | Built: a bench row set with a recorded baseline (`bench/bench.b`, `bench/cost.baseline`, the `bench-ratchet` check in `flake.nix`); the VM as `blue run`'s default door where the conformance columns agree, with a door receipt and an off switch (`crates/blue-lang-runtime/src/door.rs`, `crates/blue-lang-cli/tests/door.rs`, the conformance door gate); AOT of the hex words to a wasm component run by wasmtime, equal to the interpreter over four seeds (`checks.native-wasm`); a raised bench row needs a typed reason (`receipt_kinds`); lever rows memo, bake, incremental and hexmsg as ratios to a Rust twin (`bench/lever.baseline`, PERFORMANCE.md 1.6) and as CI cost rows. Not built: a bench record written per release tag (the ratchet runs on every land), the data-parallel and partial-evaluation rows, AOT of a bidama a service calls through the component host's imports. |
| H8. Reach | ⏳ in progress | Built: the gate, equal receipts across two placements: `crates/blue-lang-cli/tests/placement.rs` runs `crates/blue-lang-wasm/page/app.b` with `blue run --allow none --receipts` and as the wasm engine in a page that `page/serve.b`, a blue service, serves, driven through the page's own generated loader (burauza's `engine` row) in Node's V8; the section and the receipt are byte-equal and the module imports nothing (2026-11-11). `blue bundle --sources`; `checks.conformance` compares output across placements. Kernel: `kaaneru` compiles blue to BPF, a refusal names the `.b` file and line for xdp, sched_cls, socket_filter, cgroup_skb and cgroup_sysctl (`kernel/object_suite.b`), and cgroup_sysctl is a program kind (`kernel/net_suite.b`). Nix: `kakehashi/nikkusu`'s `render` and `module`; `nix/node-fixture/node.b` renders `configuration.nix`, and `checks.node-from-blue` evaluates it and a hand-written oracle to one NixOS toplevel. Not built: a real headless browser run, hydration (FRONTEND-PLAN F8), a blue project's own flake rendered from blue, the GPU rung. |
| H9. Model-native | ⏳ in progress | Built: the score as a census row that falls only with a typed reason (`eval/census.b`, `eval/score.baseline`, `checks.model-eval`); every diagnostic's JSON carries its law, witness and fix (`fixes::REPAIR_CENSUS`, 35 of 79 rules left); `blue naturalize`; `blue context`. Not built: a repair for the 35 census rules; model runs recorded by CI. |
| H10. Ecosystem | ⏳ in progress | Built: docs, tests and reach per package in CATALOG's "Quality signals". Not built: heni ratio, conformance and model score in that table; signed releases. |
| H11. One vocabulary | ⏳ in progress | Built: `Effect` as a projection of `Capability`, held at lock (`crates/blue-lang-cli/tests/lattice.rs`, `a_service_whose_code_reaches_past_its_access_is_refused_at_lock`). Not built: one spelling read both ways. |
| H12. Pure by default | ❌ not built | The lattice check still runs only when the root declares `allow`, a provider or `bounds` (`crates/blue-lang-pkg/src/capabilities.rs`). No census counts undeclared Bluefiles. |
| H13. Authority per bidama at run time | ⏳ in progress | Built: a live-byte account per evaluation and per process (`crates/blue-lang-runtime/src/memory.rs`). Not built: a frame per package, a memory bound a bidama declares. |
| H14. The checker sees authority | ❌ not built | No `capability-escape` code exists in any crate. |
| H15. Capabilities as values | ❌ not built | No grant value and no `secret` capability exist in `crates/blue-lang-waku/src/capability.rs`. |
| H16. One declaration, every placement | ❌ not built | No bidama or crate renders the native enclosure annotation. Only the engenho wasm pod derives a boundary from `access`. |
| H17. Parity on authority | ❌ not built | No capability conformance matrix exists. |
| H18. Least privilege as a ratchet | ❌ not built | No receipt records the capabilities a run used. No `blue lock --tighten` exists. |
| H19. Ontology | ❌ not built | No crate or generator renders a capability ontology. It waits on khipu K1b to K4. |
| H20. Kernel | ⏳ in progress | Built: LSM, XDP, cgroup and `struct_ops` programs in `bidamas/kaaneru/kaaneru.b`; the kernel matrix (`.github/workflows/kernel-matrix.yml`). Not built: the program generator and its load-everything gate, the capability frame in a BPF map. |
