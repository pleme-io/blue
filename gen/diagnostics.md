---
kind: reference
summary: what the check stage reports, every rule code, and the machine-readable shape of a diagnostic
---

# Diagnostics

What blue's check stage reports, and the machine-readable shape of it.

Every rule lives in one registry, `blue_lang_check::RULES`
(`crates/blue-lang-check/src/rules.rs`). The check stage runs on every door —
`blue run`, `blue test`, `blue check`, the language server and every bidama
build — so an error-severity rule is a program that does not run or build.
`blue explain CODE` prints a rule's explanation and an example that violates
it; `blue explain --list` lists them.

## Codes

```hon
rules
```

The registry is the source of truth: `gen/diagnostics.b` renders this table
from `blue reference`, which reads `RULES`, into this page, whose prose lives
in `gen/diagnostics.md`. Edit that source and run `nix run .#regen`;
`generated-diagnostics-fresh` fails when this page is stale, and a test fails
when a row differs from the registry.

## Ratchets: how a rule becomes an error

A rule the corpus does not yet satisfy is registered with `ratchet: Some(n)`:
it is computed on every program and its findings are counted, not enforced.
`blue census [ROOT]` counts them over every `.b` file under ROOT, and
`checks.namespace-census` fails unless each count equals its row's ratchet
exactly, so every change to a count is a reviewed edit of the number. The
commit that brings a count to zero sets the row to `Some(0)`, and from then
on the rule is an error on every door. `blue census --findings` lists each
finding.

## The reuse ratchet

`blue census --reuse [ROOT]` counts copies per package, against the hadome
baseline `ROOT/reuse.baseline` (`--baseline FILE` to name another). The tool
is `crates/blue-lang-cli/blue/reuse.b`, compiled into the binary.

A copy is a definition of 12 or more nodes (`Near::DEFAULT.min_size`) whose
`shape_hash` is another package's or file's. A row is `reuse-copy: SCOPE N`:
SCOPE is the package, or `%root:FILE` for a script.

| state | exit | what it does |
|---|---|---|
| no baseline | 0 | enforces nothing; prints the measure and the command that adopts it |
| a row held | 0 | |
| a row shrank | 0 | reported; `--record` banks it |
| a row is gone | 0 | advisory; `--record` drops it |
| a row grew, or a scope has no row | 1 | names the row and the copies inside it; every other row, and `run`, `test` and every build, go on |
| a file does not load | 0 | `blind: FILE: why`; counted as blind, never as zero |

`--record` writes the measured rows. It banks a fall with no argument; a raised
or new row is refused without `--receipt "<why>"`, which stays beside the rows
as a `# receipt:` line a reviewer reads. `--json` prints one document with the
rows that broke and each copy's home. `--facts` prints each measured definition
and exits 0. `checks.reuse-ratchet` (`lib.project`) runs the check on every
project, and `pleme-io/actions/blue-reuse` runs it in CI. A project adopts it
with one command, and the file it writes is the only thing that turns it on:

    blue census --reuse . --record --receipt "first measure"

`blue check --reuse FILE` prints each B0070 in one file, with the word to use
and its import line, and always exits 0. `blue check --reuse --hook` reads Claude
Code's PostToolUse JSON from stdin, takes `tool_input.file_path`, stays silent
unless it ends in `.b` and exists, and exits 0 on every failure of its own.

## The data laws (B0048–B0052)

The frontend's data laws are rows like every
other. A fragment declared with `danpen::fragment(:user_card, {on: "User",
fields: […]})` is the type `UserCard`; a parameter annotated with it holds a
fragment ref, and the typing ladder checks every read of it (B0048) and every
ref passed on to a component (B0049, whose fix adds the spread). The schema
enters through the project's Bluefile: `frontend(name, {views:, schema:})`
names the SDL, and the `generate(...)` whose inputs hold that SDL writes the
table the check reads (`danpen::render(sdl, :table)`), so
`checks.generated-<name>-fresh` keeps it current. A file under a frontend's
`views` is a view (B0052 applies); any other file of the project is checked
against the same table (B0050, B0051). A file with no frontend around it has
no table, and B0050–B0052 do not run for it. In nix a check program runs
alone in the store, so only `blue check`, the language server, `blue census`
and the corpus test read the table there.

`blue_lang_check::data_laws::Fragments` is the fragment and composition table
as data (each fragment's type, fields and spreads), for checks that build on
it.

## Name resolution order

A bare name resolves by tier, first match wins, deterministically
(`blue_lang_check::names::RESOLUTION_ORDER`): locals innermost first, then
the referencing file's own bidama (or, for a script, the file), then the
names the file lists in its `use` forms (`use("retsu", [:first])`), then
builtins (harness names, special forms, macros, values). A `use("x")` with no
list makes `x::name` reachable and no bare name; a bidama the file does not
`use` is not visible. Two namespaces in the tier that holds the name is B0009
(two lists naming it). A qualified name — `retsu::first`, or `blue::first`
for the builtin — bypasses the tiers and is exact.

The words the parser lowers its own syntax to (`blue_lang_syntax::LOWERED_HEADS`:
`list` for `[…]`, `concat` for interpolation, `not`, `and`, `or`, `mod`,
`equal?`, `not=`, `apply`) skip the own and listed tiers: a bare one is always
the builtin, so a bidama may define `list` and its literals still build lists.
Its own definition is reached qualified (`gitto::list`), and `B0018` does not
call that qualifier redundant. `get` is not among them: field access lowers to
`blue-field`, so a bidama may define `get` and use `x.name` freely.

The runtime evaluates the tree resolution produced: every definition keyed
`pkg/name` (`%root/name` for a script), every reference to it as that key, a
builtin bare. So the runtime binds exactly what the check resolved.

## Overrides, and `blue explain-name`

When a bare name is bound in one tier while a lower tier also holds it — a
bidama's own `count` over the builtin, a listed `first` over the builtin — the
higher tier wins; that is the order, not an error, since each tier is
something the author wrote. `blue check --format json` records each one in
the entry file as a line after the diagnostics:

| field | meaning |
|---|---|
| `kind` | `override` |
| `name` | the name as written |
| location fields | where the reference is |
| `tier` | the tier that won: `own` or `imported` |
| `namespace` | the winning namespace: a bidama's name, or `this file` |
| `shadowed` | each lower-tier candidate, as `{tier, namespace}` |

`blue explain-name NAME FILE:LINE` prints the whole path for one name at one
place: each tier, what it holds, and which wins.

## Waivers

The one escape hatch is a comment directly above a top-level definition:

```
# waive B0002: the callback shape is fixed
def on_event(event, ctx)
  event
end
```

It suppresses that code inside that definition and nowhere else. There is no
file-wide or global waiver. A waived diagnostic is still reported: `blue check`
counts it, and `--format json` lists it with its `waiver` set.

## `blue check --format json`

JSON Lines on stdout: one object per diagnostic per line, reported ones first,
then waived ones. The exit status is 1 when any error-severity diagnostic is
reported. The field names below are stable; `crates/blue-lang-cli/tests/check_json.rs`
pins the exact output and fails if a field here is undocumented.

| field | type | meaning |
|---|---|---|
| `code` | string | the rule, `B0001` |
| `slug` | string | the rule's kebab-case name, `unbound-name` |
| `severity` | string | `error` or `warning` |
| `message` | string | what is wrong, one line |
| `file` | string or null | the file the primary span is in (an imported bidama's own path when the fault is there) |
| `line`, `column` | number or null | start, 1-based; columns count characters, not bytes |
| `end_line`, `end_column` | number or null | end (exclusive), same units |
| `byte_start`, `byte_end` | number or null | the half-open byte range in `file` |
| `help` | string or null | one line on what to do |
| `related` | array | other places: each has the location fields above and a `message` |
| `fixes` | array | suggested repairs, best first |
| `waiver` | object or null | set when a waiver suppressed this diagnostic: `reason`, and the waiver's `line` |

Each entry of `fixes`:

| field | meaning |
|---|---|
| `message` | what the fix does, `replace with \`length\` (builtin)` |
| `applicability` | `machine-applicable` (preserves meaning; `--fix` applies it) or `maybe-incorrect` (a guess; never applied automatically) |
| `edits` | byte-range replacements applied together: the location fields, `original` (what the range must still contain, or the edit is refused) and `replacement` |

A location is `null` throughout when it cannot be placed honestly (for
example, a span that is not a range in the named file).

## `blue run --format json`

A runtime error as one JSON object on stdout, the same error `blue run` prints
as text: `stage` (`eval`), `severity`, `message` (names as the author writes
them), `file`, `line`, `column` (each `null` when it cannot be justified), and
`stack`, the blue call stack innermost first, each frame `function`, `file`,
`line`, `column`, or `builtin: true` for a builtin the runtime defines in
tatara-lisp. The last frame is `<top level>` when the whole stack was
recorded; `stack_depth` counts every frame unwound, recorded or not (a trace
keeps 256). Any other stage's error is `stage` (`parse`, `check`, `import`)
and `message`. `crates/blue-lang-cli/tests/observe.rs` pins the shape.

## `blue check --fix`

Applies every machine-applicable fix whose edits land in the named file and
still match their `original`, skips overlapping ones, then re-formats and
re-checks the file and reports what remains. Suggestions marked
`maybe-incorrect` are never applied.

`blue check --fix --only CODE FILE` (repeatable) applies only those codes'
fixes, to the file as written: no re-format, no project-rule fix, no Bluefile
edit. A project pinned to an older blue takes one rule's fix from a newer blue
this way, then formats with its own (`blue fmt --write`).

## Project rules

A project adds its own check rules, written in blue, by naming them in its
Bluefile:

```
rule("R0001", "rules/conventions.b", "nil_predicate")
rule("R0002", "rules/conventions.b", "loud_call", "warning")
```

`rule(code, file, def[, severity])` names a definition in a blue file (relative
to the Bluefile). `blue check FILE` gathers the rules of every Bluefile in
FILE's directory and its ancestors, up to the directory holding `.git`, and
calls each one on every top-level form of FILE, beside the registry. A code
declared by two Bluefiles is refused.

**Codes.** A project code is one to four capital letters, never `B` alone,
then four digits (`R0001`, `KZ0003`). `B` + four digits is blue's registry, so
the two never meet. Severity is `error` (the default) or `warning`.

**The ABI.** The definition takes one argument, a top-level form as data (the
tree the parser wrote, as a macro sees its arguments: symbols, lists, `quote`
as `(quote x)`), and returns a list of findings. A finding is a map:

| key | | meaning |
|---|---|---|
| `at` | required | the path to the node, one child index per level; `[]` is the form itself |
| `message` | required | a string |
| `help` | optional | a string |
| `fix` | optional | a tree that replaces the node at `at`, usually built with `quote … unquote(x) … end` |

```
def nil_predicate(form)
  hits = filter(fn(p) call?(last(p), "nil?", 1) end, nodes(form, []))
  map(
    fn(p)
      arg = nth(1, last(p))
      {at: first(p), message: "write `x.nil?`", fix: quote
        unquote(arg).nil?
      end}
    end,
    hits
  )
end
```

The code and severity are the Bluefile row's. A path, not a byte offset: the
rule sees only data, and `blue check` resolves the path against the form it
gave the rule, so the rule needs no access to the source (and can later run as
a wasm module). A fix is rendered by the
formatter and proved before `--fix` will apply it: the edited file is parsed
and must hold exactly the rule's tree at that path (the rendering is retried in
parentheses when an operator binds differently in place); otherwise it is
offered as `maybe-incorrect`.

**The frame.** A rule program, imported bidamas included, may name every
builtin except the host effects (process, filesystem, environment, clock,
network), printing, and `eval`, `require` and `provide`. A rule that names one
is refused before it runs. Each call runs under a step budget
(`blue_lang_runtime::project_rules::RULE_STEPS`).

**Failures.** A rule that does not load, reaches outside its frame, raises,
runs past its budget, or returns anything but a list of findings is reported
once, as an error under its code with the slug `rule-failure`, and is not run
on the file's remaining forms. The other rules still report.

**Waivers** use the one grammar: `# waive R0001: reason` above the definition.
The check stage that `blue run`, `blue test` and every build run does not run
project rules, so it leaves a project-code waiver alone; `blue check` reports
one that names no declared rule (B0007) or suppresses nothing (B0008).

**Output.** Findings are diagnostics in every format above: `file:line:col:
error[R0001]: message`, the same JSON object (the slug is the definition's
name, kebab-cased), the same `fixes`. `blue check` prints `project rules: N`
when any apply.

**In nix**, a project whose Bluefile declares rules gets
`checks.project-rules-hold`: `blue check` on every `.b` file of its packages and
every run, check and app program.

## `blue ast --resolved --json`

How every name in a file resolves, under both rules: today's **flat** rule
(one global environment; the definition evaluated last wins, a builtin only
when no program form defines the name) and **per-bidama namespaces** (locals,
then the file's own package, then its explicit imports, then builtins; a
qualified name exactly). One JSON object on stdout.
`crates/blue-lang-cli/tests/ast_resolved.rs` pins the exact output and fails
if a field here is undocumented. A migration is proven on it: a program whose
`flat` and `ns` trees are equal means the same thing under either rule.

| field | meaning |
|---|---|
| `namespace` | the entry file's bidama (from the Bluefile beside it), or `null` for the root namespace |
| `flat` | the entry file's top-level forms, resolved under the flat rule: each definition renamed to its runtime key (`retsu/first`; `%root/f` for a script) and each reference to what the rule binds it to (a builtin stays bare) |
| `ns` | the same forms under per-bidama namespaces |
| `references` | every non-local reference in the entry file |
| `imports` | the entry file's `use` declarations: the location fields, `package`, and `names` (the list, empty for a whole-package `use`) |
| `first_line` | the first line of the entry file's first top-level form, or `null` |
| `definitions` | the entry file's top-level definitions: the location fields and `name` |
| `builtins` | every name the interpreter binds, sorted |
| `reserved` | the reserved words, which no definition can be named |

Each entry of `references` carries the location fields of `blue check` and:

| field | meaning |
|---|---|
| `top_level` | the index of the top-level form it is in |
| `written` | the symbol as the tree has it: `first`, or `retsu/first` for `retsu::first` |
| `opaque` | inside a macro call's arguments |
| `flat`, `ns` | what each rule binds it to |
| `locals` | the locals in scope where it is written, innermost first |
| `position` | `call` (the head of a call), `value` (anywhere else in code), `place` (the name `set!` rebinds) or `syntax` (a macro head, a template symbol) |
| `argc` | for a `call`, how many arguments it passes; `null` otherwise |
| `nullary` | what `ns` binds it to takes exactly zero parameters: a bare `value` reference is CALLED, and a `call` with `argc` 0 is B0023 |

This list is how a definition's callers are found: bare calls have no
parentheses, so searching the text for `name(` misses every one.

A binding (`flat`, `ns`) has:

| field | meaning |
|---|---|
| `kind` | `def` (a program definition), `builtin`, `local`, `ambiguous` (two imports list it) or `unbound` |
| `namespace` | the defining bidama for a `def`; `null` otherwise, and for the root namespace |
| `name` | the definition's or builtin's name |
| `key` | the symbol the resolved tree writes, or `null` when it keeps the written one |

## `blue query`

`blue query QUERY [PATH…]` lists every definition under the paths (files, or
directories of `.b` files; `.` when none) that satisfies a query: one line per
hit, `file:line:col: definition`, then what the pattern bound, then the chain
through which the definition reaches each capability a `reaches` clause names.
The engine answers it (`blue_lang_mondou::Engine::query`), each file loaded as
`blue check FILE` and the language server load it, so an editor or agent door
gets the same hits. A file whose imports do not load has no
resolved tree; it is named on stderr and the exit is 1.

A query is tatara-lisp data. Several clauses are their conjunction:

| clause | holds for a definition when |
|---|---|
| `(match PATTERN)` | a form of its resolved tree matches `PATTERN`; each matching form is a hit, with what the pattern bound |
| `(reaches CAP)` | it names a primitive of host capability `CAP` (`process`, `filesystem`, `environment`, `clock`, `network`; `host` for any), directly or through the definitions it references |
| `(annotated)`, `(unannotated)` | it is, or is not, a typed definition |
| `(calls NAME)` | a reference in it resolves to `NAME`: `retsu/first` or `retsu::first` for a bidama's definition, `%root/f` for a script's own, `first` for the builtin |
| `(package NAME)` | it is defined in bidama `NAME` |
| `(longer-than N)` | its tree has more than `N` forms |
| `(kind K)` | it is a `function`, `macro` or `value` |
| `(and C …)`, `(or C …)`, `(not C)` | the connectives |

A pattern is tatara's `match` pattern, compiled by tatara's own matcher. A
quasipattern reads as the code it matches: `` `(retsu/first ,xs) `` is a call
to retsu's `first` with one argument, bound to `xs`; outside an unquote a
symbol matches itself, `,_` matches anything, a final `,@rest` matches the
remaining elements, and `,(? string? s)` runs a predicate (under a pure frame
and a step budget; a predicate naming a host primitive or `eval` is refused).
Patterns see the resolved tree, the `ns` tree of `blue ast --resolved --json`:
every reference is written as what it resolved to, so a call written `first`
after `use("retsu", [:first])` and one written `retsu::first` are both
`retsu/first`, and a local named `first` is neither. A function definition's
own `(name params…)` is not a call and is not searched.

`--json` prints one object per hit per line:

| field | meaning |
|---|---|
| `file`, `line`, `column` | where the matching form starts, or the definition when no pattern placed the hit |
| `definition` | the definition's name as written |
| `key` | its runtime key: `retsu/first`, `%root/f` |
| `kind` | `function`, `macro` or `value` |
| `bindings` | each name the pattern bound, and its value as tatara-lisp text |
| `reach` | each host capability the definition reaches, and one chain to it: the definitions it goes through, then the primitive |

A Bluefile names a query with `query(name, text)`, and `blue query NAME` runs
it from the project's directory or below:

```text
query("host_unannotated", "(reaches host) (unannotated)")
```

Over blue's own standard bidamas (2026-10-28, 255 files):

```text
$ blue query '(reaches filesystem)' bidamas
bidamas/isshou/anaritikusu/anaritikusu.b:2131:1: write_history  filesystem via write_file
bidamas/isshou/anaritikusu/anaritikusu.b:2488:1: example_append  filesystem via nisshi/el_append -> nisshi/write -> append_file
…
146 hit(s) in 255 file(s)

$ blue query '(match `(retsu/first ,xs))' bidamas/zumen
bidamas/koubou/zumen/zumen.b:147:14: layer_names  xs = l
1 hit(s) in 1 file(s)
```

`(annotated)` over the same corpus finds nothing: no bidama definition is
typed yet.
