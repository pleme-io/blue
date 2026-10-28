---
kind: reference
role: agents
summary: rules for people and agents who write blue programs or change blue itself, with the build commands from the Bluefile
---

# blue — the agent guide

No `pending-shikumi:` — M2 closed 2026-09-29. `BlueConfig`
(`crates/blue-lang-cli/src/config.rs`) implements `shikumi::TieredConfig` with
four bounds, each with a shipped overridable default: `solver_max_steps`,
`max_expr_depth`, and the execution budget as `max_call_depth` and
`max_steps` (depth defaults to tatara-lisp-eval's `DEFAULT_MAX_DEPTH`, steps to
unbounded, since a default step bound would end runs that work today; applied
to every interpreter through `blue_lang_runtime::set_execution_bounds`).
`flake.nix` carries the module trio that deploys them, and `blue config <tier>`
is the operator surface.

The M1 waiver this replaced, and why two of its three knobs are settled against configuration, is in [LESSONS.md](LESSONS.md), "Bounds, never preferences".

pending-tela: not a frontend app; blue hosts the frontend framework that
retargets Tela (`theory/BLUE-FRONTEND.md`, `docs/FRONTEND-PLAN.md`). No `pending-urdume:` — blue is a language
workspace, not a Rust service.

> **★★★ CSE / Knowable Construction.** This repo operates under
> **Constructive Substrate Engineering** — canonical spec at
> [`pleme-io/theory/CONSTRUCTIVE-SUBSTRATE-ENGINEERING.md`](https://github.com/pleme-io/theory/blob/main/CONSTRUCTIVE-SUBSTRATE-ENGINEERING.md).
> **The design is canonical in [`theory/BLUE.md`](https://github.com/pleme-io/theory/blob/main/BLUE.md)
> — read it before non-trivial changes, and do not restate it here.**

A general-purpose language: a Ruby/Elixir surface, a tatara-lisp AST, macros
as term rewriting on that AST, and a Rust runtime. Crates are `blue-lang-*`
(bare `blue` is squatted on crates.io); source extension is `.b`.

This page has two parts. **Writing blue programs** is for anyone who writes
blue. **Changing blue itself** is for implementers of the parser, the runtime
and the nix engine. `AGENTS.md` and `CLAUDE.md` are both rendered from this
page and the `Bluefile`.

## Writing blue programs

blue looks like Ruby and Elixir and parses to a tatara-lisp tree that a Rust
runtime executes. There is one formatting and no configuration, and most
of the vocabulary lives in packages called bidamas.

### Start from an example

Copy the closest program in [`docs/EXAMPLES.md`](EXAMPLES.md) and change
it. Every example there runs as a check, so it works as written. Then look up
names in [`docs/REFERENCE.md`](REFERENCE.md) (built-ins, operators,
syntax) and [`bidamas/CATALOG.md`](../bidamas/CATALOG.md) (every bidama
definition). Both are generated from the implementation and gated fresh.

### A file is a program; a project is one command away

A script needs no structure. `blue new --script tool.b` writes one that opens
with `#!/usr/bin/env blue` and is executable, so both of these run it:

```text
blue tool.b a b        ./tool.b a b
```

It can `use` every standard bidama with no Bluefile and no `BLUE_PATH`: they
are compiled into `blue`. Run this way a script prints only what it writes, and
every argument after the file reaches `argv` as given. A subcommand wins over
a file of the same name; `blue ./test` runs the file.

**Safety first is the default posture.** A script states the host
capabilities it needs in its shebang, `#!/usr/bin/env -S blue --allow
filesystem`, and a name outside them is refused (`none`, `host`, or
`process`, `filesystem`, `environment`, `clock`, `network`, `entropy`). Every
Rust guarantee, the blue gate that matches it and its off switch:
[`docs/SAFETY.md`](SAFETY.md).

When a script outgrows one file, `blue new NAME` starts a project: a Bluefile
with `packages("bidamas")`, its lock, the stub `flake.nix`, the code and tests
in `bidamas/NAME/NAME.b`, and `main.b` calling it. `blue new --bidama NAME`
writes a package alone, inside a distribution's directory.

`use("pkg")` looks in order: the `packages` roots of the project the file
sits in (the nearest Bluefile above it that declares them), then the roots on
`BLUE_PATH` (your override), then `BLUE_DIST` (the installed distribution the
fleet's `blue` wrapper sets), then the distribution compiled into `blue`. The
project always wins; outside it, a copy whose version is outside the range the
file's `Bluefile.lock` records is skipped and named, never chosen.

### Commands

| | |
|---|---|
| `blue file.b a b` | run a program as a script: quiet, every argument after the file to `argv` |
| `blue run file.b` | run a program and print its final value; `--quiet` drops it, `-- a b` passes arguments; `--allow CAP` holds it to those host capabilities; a runtime error prints the blue call stack, and `--format json` prints it as one object; `--timings` prints the wall time of each pipeline stage to stderr |
| `blue new NAME` | a project; `--bidama NAME` a package, `--script NAME.b` an executable script |
| `blue watch [check\|test\|run] PATH…` | rerun the command on every save (`check` by default) |
| `blue test file.b` | check it, then run its `test` blocks; a directory runs every file with tests, in parallel; `--filter NAME` keeps tests whose name contains it; `--coverage` lists each definition's calls and the uncovered ones |
| `blue profile file.b` | run it and list every function called: calls, inclusive and exclusive time, and allocations made in each |
| `blue trace NAME file.b` | run it and print each call of `NAME` with its arguments and value |
| `blue check file.b` | every rule (unbound names with did-you-mean, unused bindings, types, waivers); `--format json` prints one object per diagnostic, `--fix` applies the machine-applicable fixes |
| `blue query '(reaches filesystem) (unannotated)' DIR` | every definition a code query matches: `(match PATTERN)` over the resolved tree with bindings, `(reaches CAP)`, `(calls retsu/first)`, `(package P)`, `(longer-than N)`; `--json`; a Bluefile's `query(name, text)` runs as `blue query NAME` ([`docs/DIAGNOSTICS.md`](DIAGNOSTICS.md)) |
| `blue explain B0001` | what a diagnostic code means; `--list` lists them ([`docs/DIAGNOSTICS.md`](DIAGNOSTICS.md)) |
| `blue doc NAME` | a builtin, `pkg::name` or bare name: signature, doc line, namespace, tier and an example (a builtin's from its spec row, a definition's from its package's tests); `blue doc PKG` lists a package; `--file F` gives each answer's tier as F reaches it; `--json` |
| `blue verbs import\|export\|check\|findings` | the verb graph (`bidamas/mokuroku/graph`, `docs/verbs/H/DESIGN.md`): `import` TSVs into its row files, `export` them back (the only writer of TSV), `check` its gates against the recorded baseline (`--record` writes it), `findings --tsv DIR` of a directory of TSVs |
| `blue fmt file.b` | print the one formatting, zero-parameter calls bare (it resolves the file to know which); `--write` rewrites, `--check` fails on drift |
| `blue reference` | the language reference as JSON |
| `blue eval 'EXPR'` | evaluate once and print the value; `blue eval file.b:LINE:COL` evaluates the top-level form there in that file's context |
| `blue repl` | an evaluation session: multi-line input, `:load`, `:expand`, `:doc`, `:reset`, `:quit`; ctrl-c stops a running evaluation |
| `blue serve` | the same session as JSON lines on stdio, for editors (`theory/BLUE-TOOLING.md` §4) |
| `blue image build [NAME]` | build a Bluefile `image` through nix: the tarball, its size and layers |
| `blue workload render [NAME]` | a Bluefile `workload` as Kubernetes objects; `--write` rewrites the committed files |
| `blue diff --context CTX` | the committed workload files against a cluster, read-only; there is no `blue apply`, GitOps applies |
| `blue registry render [BACKEND]` | a Bluefile `registry` entry (sui first, FlakeHub optional) as its publish workflow; `--write` rewrites the committed files; `blue registry status` says whether sui serves each pin. The lock stays the truth: [`docs/REGISTRY.md`](REGISTRY.md) |

Sessions (`eval`, `repl`, `serve`) are pure: code that reaches the host
(`read_file`, `now_ms`, `exec_capture`, …) is refused as volatile unless the
session was started with `--allow host` (or `--allow filesystem`, and so on);
`--budget STEPS` bounds each evaluation.

A project adds its own check rules, written in blue: `rule("R0001",
"rules/x.b", "def_name")` in its Bluefile names a definition that receives each
top-level form as data and returns findings (`{at: path, message: "…", fix:
tree}`); `blue check` runs it under a pure frame and a step budget, and the
usual `# waive R0001: reason` applies. The shape, the frame and a worked rule:
[`docs/DIAGNOSTICS.md`](DIAGNOSTICS.md), "Project rules"; blue's own are
in [`rules/`](../rules/).

`run`, `test` and `check` rewrite a non-canonical file in place before they
compile it, and say `blue: formatted <file>`. A checkout's bidamas override
the compiled-in ones from `BLUE_PATH`:
`BLUE_PATH=path/to/blue/bidamas blue test file.b`.

`blue test` is hermetic. It drops the inherited `GIT_DIR`, `GIT_WORK_TREE`
and their kin, so a fixture repository a test makes is its own, and it
refuses a write outside the temporary directory (`TMPDIR`). The off switches
are `BLUE_TEST_ENV=inherit` and `BLUE_TEST_WRITES=anywhere`. A test that
writes a `.b` file writes it with `write_program`, which formats it (B0064).

### One way to write each thing

blue reads every older or borrowed spelling and writes one: `a and b`, `not x`,
`if not c`, `f(x, y)`, `x.field`, `f(a, *xs)`, `raise(:kind, "why")`,
`x rescue fallback`, `def main()`. `blue fmt --write` and `blue check --fix`
rewrite a file to it and name each rule; `blue run` formats its entry in
place; `blue test` and `blue check` never write a file, and refuse naming the
command that fixes it. A loaded dependency compiles as written: its form is
its producer's ([`docs/COMPOUNDING.md`](COMPOUNDING.md)). The rules are the table at the end of
[`docs/REFERENCE.md`](REFERENCE.md) (generated from the registry the
check stage runs); why each spelling won is
[`docs/CANONICAL-FORMS.md`](CANONICAL-FORMS.md). Write the canonical
spelling and nothing is rewritten.

The one spelling is the shortest that stays distinct, and each shorthand is
built from a longer form that also works, so writing the long form is never
wrong: the formatter shortens it. The same holds for the library: one verb per
meaning, and one bidama for each cross-cutting concern (errors and refusals in
`kyohi`, entries and switches in `kousei`, configuration in `settei`). Reach
for that bidama before writing the concern by hand. Why: `theory/BLUE.md` §0
and §V.28.1.

Configuration is a record of defaults, grouped by concern, that
`settei::read(app, defaults)` resolves: the defaults, then
`~/.config/<app>/<app>.yaml` (or `<APP>_CONFIG`), then `<APP>_<GROUP>__<KEY>`
in the environment, each value typed by its default. Read it by dotted path,
`config.guard.branch`: a misspelt path raises and names the fields that
exist, where `config["branch"]` returns nil. A program never reads its own
settings with `getenv`. `bidamas/kirikae` is the worked example.

Before you name a function, look for its verb: the graph rows in
`bidamas/mokuroku/graph/` (one file per space) and the contract for each verb in
`docs/verbs/contracts.tsv`. A verb that exists is called as `space::verb` with that
contract. A verb that is only a row is the work to do: build it to its contract. A
meaning with no row gets a row first (TSV, then `blue verbs import`), named in plain
English as `read`, `put`, `need` (raises) or `get` (nil), never a `_or` variant.
The plan and the waves are `docs/VERB-ROADMAP.md`.

### The traps that cost the most

Each one was checked against the runtime.

- **`nil` is not `[]`** (okite D0004). `nil == []` is false, `list?(nil)` is
  true, and `length(nil)` raises. Use retsu's `size`, `first`, `rest`,
  `is_empty`, which accept both. The built-in `first([])` raises; retsu's
  answers nil.
- **`/` never truncates.** `7 / 2` is 3.5, while `6 / 2` stays the Int 3.
  Integer division is `floor(a / b)`. `%` is Euclidean: `-7 % 3` is 2.
- **`==` is structural** (`equal?`): strings, lists and maps compare by
  content, and `4 == 4.0`. `<` takes numbers only; order text with
  `compare(a, b)`.
- **Argument order is Lisp's.** `map(f, xs)`, `filter(f, xs)`,
  `reduce(f, init, xs)`, `nth(i, xs)`, `take(n, xs)`, but `join(xs, sep)` and
  `split(s, sep)`. A pipe `xs |> f(a)` is read as `f(xs, a)` and written
  that way (B0028), so `xs |> map(f)` is `map(xs, f)` and fails.
- **Brevity is the house style.** A lambda that only forwards its parameters to a `def` of the file is that name (`map(describe, vs)`, B0044, machine-fixed); say it in the fewest tokens that parse to the same tree.
- **No blocks, no indexing.** Write `map((x) -> x * 2, xs)` (inline, one expression), or a broken `fn(x) … end` over several lines; `fn … end` is never on one line, and blue compiles only canonical source. Never
  `xs.map { |x| … }` or `do … end`. Write `nth(0, xs)`, never `xs[0]`.
- **Errors are raised and rescued.** `raise(:not_found, "no repo #{name}")`
  raises; `raise(:k, "m", {data: d, cause: e})` attaches data and the error
  it wraps; `raise(e)` raises one again. `json_parse(text) rescue nil` is the
  value or nil. A block catches by kind and binds the error:
  `begin … rescue :timeout, :refused as e … rescue e … ensure … end`, and a
  `def` takes the same clauses directly. The error reads as a record:
  `e.kind`, `e.message`, `e.data`, `e.cause`, `e.trace`. A catch-all that
  ignores the error is written `rescue _` (B0038). Retry a flaky step with
  `saishikou::retrying({times: 3, wait_ms: 500}, fn() fetch(url) end)`.
  Return refusals as data (`kyohi`) where a caller must branch on several.
- **`x.name` reads a field; it is not a call.** It reads a map's key, a
  keyed list (`exec_capture(...)` gives `cap.status`, `cap.stdout`), a
  parsed JSON object (`doc.spec`) or an error's field, and raises naming the
  fields there are when it is absent; `get(m, :k)` reads one that may be
  absent. Nested JSON that may be missing: `deeta::json_at(doc,
  "spec.items.0.name")`, nil when any step is absent. A call with arguments
  is written `f(x, y)`.
- **The entry point is `def main()`.** `blue run FILE` calls it after the
  file's top level; `blue test`, `blue check` and `use` never do, so a file
  is a program and a library at once. No `X_MAIN` variable (B0041).
- **Each bidama is a namespace.** Reach another bidama's definition
  qualified, `kueri::join(a, b)` after `use("kueri")`, or list it,
  `use("retsu", [:first, :size])`, then call `first(xs)` bare. Nothing else
  is visible: a name another bidama defines, reached bare without a list, is
  an error (B0012), and `blue migrate FILE` adds the lists. When that name is
  also a builtin, the builtin answers; B0012 then fires only for the
  flat-era names a bidama lists in `legacy_names` (docs/NAMESPACES.md). A bare name is a
  local, else your bidama's own definition, else a listed one, else a
  builtin; `blue::first` names the builtin past a same-named definition. A
  listed name can replace a builtin for your file only: kazu's `max(a, b)`
  takes two numbers, and shuugou's `remove(xs, v)` reverses the built-in's
  order (REFERENCE.md marks each). **Do not prefix** your names (`kz_count`
  is an error, B0013/B0014): callers write `kazu::count`.
- **Maps cannot be walked.** `get(m, k)` and `assoc(m, k, v)` work, but no
  word lists a map's keys. When you need entries, keep `[key, value]` pairs,
  as shuugou's `group_by` and `frequencies` do. A parsed JSON object is such a
  pair list, not a map: read it with `json_get` or deeta.
- **A function with no parameters is called bare** (B0023, `blue explain
  B0023`): `now_ms`, `argv`, `kueri::count_all`, never `now_ms()`. `blue fmt
  --write` rewrites the old spelling and the check stage refuses it. Pass
  such a function as a value with `fn() now_ms end`. A local or parameter of
  the same name is its value, never a call. Effects run where the name is
  written: the built-in ones are listed in
  [`docs/REFERENCE.md`](REFERENCE.md), "Called where written bare". Find
  a definition's callers through the resolver (`blue ast --resolved --json
  FILE` lists every reference, `"position": "call"` or `"value"`, and the
  language server's references), never by searching for `name(`: a bare
  call has no parentheses.
- **Output is `write_stdout`.** `println` prints strings with their quotes.
- **Logic is words.** `if ready and not failed`; `&&`, `||` and `!` are read
  and written as `and`, `or` and `not` (B0025). `not` binds tightly:
  `not a == b` is `(not a) == b`, and blue writes the parentheses; the
  comparison you meant is `a != b`.
- **A list spread as arguments is a splat**: `max(*xs)`, `exec_capture(cmd,
  *argv)`; `apply(f, xs)` with `f` a name is written that way (B0042).
- **Names with `-` do not exist in blue.** tatara-lisp's kebab-case words are
  unreachable. A keyword may end in `?` or `!` (`[:pair?]`), as a name may.
- **Deep recursion aborts.** Prefer `map`, `filter` and `reduce` over
  hand-written recursion on long lists, and `sort_keyed(key, xs)` for sorting.

The rest of blue's semantics is Ruby's, except where
[`bidamas/okite/RULES.md`](../bidamas/okite/RULES.md) says otherwise.

### Conventions

The formatter settles layout. For the rest, follow the examples: a predicate
you define ends in `?` (okite D0010), names in lower snake_case (B0040),
interpolation over `concat`, `use` forms first and sorted, each listing what
the file reads, and names without a prefix in a bidama (B0013/B0014) or a
program (B0043). Tests go in the same
file, named for the behaviour, with the empty input among the cases.

Tests live beside what they test, and the Bluefile is the pipeline
(`docs/TESTING.md`). A bidama definition no test reaches fails
`checks.test-beside` beyond its package's recorded debt; waive one with
`waive(name, why, until)` in `gen/test-beside.b`, never by deleting the gate.

### More

- [`bidamas/AUTHORING.md`](../bidamas/AUTHORING.md): writing and testing a
  bidama, and the measured traps not yet made rules.
- [`bidamas/NAMES.md`](../bidamas/NAMES.md): how packages are named.
- [`spec/README.md`](../spec/README.md): the conformance suite, one row per
  observable behaviour run on every evaluator; a row's program and expected
  result is the most exact statement of what blue does.
- [`llms.txt`](../llms.txt): these files as an index.

## Changing blue itself

### Grow blue pattern-first

Before any capability is coded, fix its plan in writing: the reuse map (read from source; move,
never copy), the shape (adopt what existing implementations agree on), the idioms, and the
dependency order. **Blue bends to the pattern:** boilerplate in a blue program means blue is
missing a word, so add the form, macro or primitive. The principle is `theory/BLUE.md` §I.1; the
loop (plan, build, test, ancestry, DuckDB analysis, promote) is the `blue-development-cycle` skill.

### One short way, built on the last

The FORM axis (`theory/BLUE.md` §0) is the core of blue: each thing has one spelling, the
shortest that stays distinct from every other meaning. A new form or shorthand lowers to a form
that already exists (`x++` → `x += 1` → `x = x + 1`), and it ships whole or not at all: a
`Spelling` note and formatter arm, a `RULES` row with a witness and autofix, a
`CANONICAL-FORMS.md` row, spec rows, and an okite law per lowering link that the two spellings
agree on every input class. The library follows the same law (§V.28): one verb per meaning, with one argument shape,
return shape and error behaviour in every space that has it (`docs/verbs/contracts.tsv`), larger
verbs built from smaller ones. A capability is done when its verbs are rows in the graph
(`blue verbs check`) and each has a unit test. One battery per cross-cutting concern (§V.28.1),
extended rather than rewritten. A Rust program
runs blue through `blue-lang-host`.

Every break blue's evolution causes (a new rule, a retired word) ships its fixer, and the error
names the one command: a rule row with `fix: Machine` or a row in `evolution::GAPS`, a word with
its `legacy_names` row (a three-string row for a retired word). Form is the producer's: a
dependency compiles as written, a bidama build judges meaning only, and `blue test` and `blue
check` never write. The ledger and the receipts are `docs/COMPOUNDING.md`.

### Compose first: a reusable component is the unit of development

Every capability starts as the smallest reusable component, and a service is a declaration that
composes them. Declare entries with `kousei` (each checked, configured off, tuned or refused
alone); declare service behaviour as `shisei` postures (on by default, a blocking one defaults to
`audit`); take the request defence from `bougyo`. A second copy of a shape is a bug the
distribution refuses: `cargo test -p blue-lang-pkg --test distribution` fails when the count of
identical function shapes rises, so reuse the existing word. The list of service batteries and
what is still missing: `theory/FUEKI.md` section I.

### The pipeline is the architecture

**parse → check → erase → run.** The order is load-bearing and lives in
`blue-lang-runtime::pipeline`, not in each caller, because two of the four
orderings are silently wrong: *erase before check* turns the type checker off,
and *run before check* reports a type error after the side effects. Neither
fails loudly; both produce a green run on a program that should be rejected.

**Ask the pipeline for a result, never assemble the stages yourself.** A
caller that re-implements the order is one reordering away from disabling the
checker.

### Architecture rules are pipeline errors; lint is a view over them

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

### Where to look

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

### Rules this repo has learned the hard way

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

### Every behaviour is a spec row

A new builtin (`docs::NAMES`), form (`FORMS`), keyword, operator (`INFIX`),
rule code (`RULES`) or okite decision is red in `checks.conformance` until a
row in `spec/rows/` covers it. A row states what blue PROMISES; where the
implementation falls short it is `pending("<gap>")`, and it fails the run the
moment the gap closes, until the mark is removed. Evaluators must agree with
the tree-walker on every row. `spec/README.md` has the format.

### Testing discipline

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

### Dependencies

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

### `Cargo.gen.lock` is committed, and that is a trade

The slim delta avoids eval-time IFD; `checks.gen-confirm` and `gen-spec.yml` keep it tied to
`Cargo.lock`. Regenerate it with `gen build .` AFTER any lock work and check the sha tie. Why,
the measured failure and the tier: [`docs/CARGO-GEN-LOCK.md`](CARGO-GEN-LOCK.md).

### What is not built

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
