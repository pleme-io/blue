# Diagnostics

What blue's check stage reports, and the machine-readable shape of it.

Every rule lives in one registry, `blue_lang_check::RULES`
(`crates/blue-lang-check/src/rules.rs`). The check stage runs on every door —
`blue run`, `blue test`, `blue check`, the language server and every bidama
build — so an error-severity rule is a program that does not run or build.
`blue explain CODE` prints a rule's explanation and an example that violates
it; `blue explain --list` lists them.

## Codes

| code | slug | severity | law |
|---|---|---|---|
| B0001 | unbound-name | error | every name a program uses is bound |
| B0002 | unused-binding | warning | a local binding is read at least once, or its name starts with `_` |
| B0003 | return-type-mismatch | error | a typed definition's body produces its declared type |
| B0004 | operand-type-mismatch | error | an operator in a typed definition gets operands of its type |
| B0005 | argument-type-mismatch | error | a call to a typed definition passes the declared types |
| B0006 | syntax-error | error | a file parses |
| B0007 | malformed-waiver | error | a waiver names a known, waivable code and gives a reason |
| B0008 | unused-waiver | error | a waiver suppresses at least one diagnostic |
| B0009 | ambiguous-name | error | no two namespaces in one resolution tier define a name |
| B0010 | qualifier-not-imported | error | a qualified name's package is one the file `use`s |
| B0011 | no-such-definition | error | a qualified name, or a name a `use` lists, is a definition of that package |
| B0012 | implicit-reference | error | a bare name that is another bidama's definition is one the file lists, or is written qualified |
| B0013 | prefixed-definition | error | a bidama's definition does not spell its bidama |
| B0014 | mangled-namespace | error | a bidama does not prefix nine in ten of its definitions with one short `x_` |
| B0015 | non-canonical-import | error | a file's `use` forms come first, one per package, sorted, each list sorted |
| B0016 | unused-import | error | every `use` is reached, and every name it lists is read |
| B0017 | duplicate-definition | error | a namespace defines a function or macro once |
| B0018 | redundant-qualifier | error | a qualifier changes what its name means |
| B0019 | needs-mismatch | error | the bidamas a bidama `use`s are exactly the ones its Bluefile `needs` |
| B0020 | package-as-value | error | a bidama's name is written as a qualifier, never as a value |
| B0021 | legacy-name | error | a renamed or moved definition is called by its new name; the old one is a bridge that closes at the next minor version |
| B0022 | legacy-misuse | error | a `legacy_names` declaration is one of each form per bidama, dated from a version it has reached, names no name twice, and moves a name only to a definition a loaded bidama holds |
| B0023 | bare-nullary-call | error | a call to a function that takes no parameters is written bare: `now_ms`, never `now_ms()` |
| B0024 | layout | error | a file is laid out as `blue fmt` writes it: indentation, line breaks at 80 columns, blank lines and parentheses |
| B0025 | logical-words | error | logic is written in words: `a and b`, `a or b`, `not x`, never `&&`, `\|\|`, `!` |
| B0026 | unless | error | a negated condition is written `if not c`, never `unless c` |
| B0027 | elsif | error | an `else` whose whole body is an `if` is written `elsif` |
| B0028 | call-form | error | a call is written `f(x, y)`: never `x.f(y)` or `x \|> f(y)` |
| B0029 | keyword-key | error | a map key that is a keyword is written `name: value`, never `:name => value` |
| B0030 | parameter-list | error | a definition and a lambda write their parameter list, even an empty one: `def f()`, `fn() … end` |
| B0031 | operator-spelling | error | an operator or literal is written as itself, never as the call it lowers to or a typographic alias |
| B0032 | trailing-comma | error | no comma before a closing bracket |
| B0033 | literal-spelling | error | a literal is written as `blue fmt` writes its value: digits of six or more grouped `1_000_000`, an invisible character escaped `\u{1b}` |
| B0034 | negated-comparison | error | a negated equality is written with the other operator: `a != b`, never `not (a == b)` |
| B0035 | else-nil | error | an `if` has no `else` whose body is empty or `nil` |
| B0036 | builtin-synonym | error | a builtin with two names is called by its readable one: `first` not `car`, `rest` not `cdr` or `next`, `a % b` not `modulo`/`rem`, `boolean?` not `bool?`, `compose` not `comp`, `reduce` not `foldl`, `x != nil` not `some?(x)`, `e.kind`/`e.message` not `error_kind`/`error_message` |
| B0037 | error-spelling | error | an error is raised with `raise` and caught with `rescue`: never `throw(error(…))` or `try(…, catch(…))` |
| B0038 | swallowed-error | error | a `rescue` that catches every error and does nothing names the error `_` |
| B0039 | duplicate-test-name | error | the tests of a file have distinct names |
| B0040 | identifier-case | error | a function, parameter or local is named in lower snake_case (`retry_count`, never `retryCount`); a top-level constant may be UPPER_SNAKE |
| B0041 | main-guard | error | a program's entry point is `def main()`, which `blue run` calls; never a top-level `if getenv("X_MAIN", "") == "1"` guard |
| B0042 | splat | error | a list passed as a call's last arguments is written `f(a, *xs)`, never `apply(f, a, xs)` with `f` a name |
| B0043 | prefixed-program | error | a program does not prefix every definition with one short `x_`: the file is the namespace |
| B0044 | eta-reduction | error | a function that only forwards its parameters to a named function is that name: `map(describe, vs)`, never `map((v) -> describe(v), vs)` |
| B0046 | map-pun | error | a map entry whose value is the variable of the same name is written `{name:}`, never `{name: name}` |
| B0047 | nil-test | error | a nil test is written `x.nil?`, never `nil?(x)`, `x == nil` or `nil == x` |
| B0045 | redundant-conversion | warning | a conversion is not applied to a value it leaves alone: `to_s(to_s(x))` is `to_s(x)`, never the longer chain |

The registry is the source of truth; a test fails if a code is missing here.

## Ratchets: how a rule becomes an error

A rule the corpus does not yet satisfy is registered with `ratchet: Some(n)`:
it is computed on every program and its findings are counted, not enforced.
`blue census [ROOT]` counts them over every `.b` file under ROOT, and
`checks.namespace-census` fails unless each count equals its row's ratchet
exactly, so every change to a count is a reviewed edit of the number. The
commit that brings a count to zero sets the row to `Some(0)`, and from then
on the rule is an error on every door. `blue census --findings` lists each
finding.

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
      {at: first(p), message: "write `x == nil`", fix: quote
        unquote(arg) == nil
      end}
    end,
    hits
  )
end
```

The code and severity are the Bluefile row's. A path, not a byte offset: the
rule sees only data, and `blue check` resolves the path against the form it
gave the rule, so the rule needs no access to the source (and can later run as
a wasm module, `theory/BLUE-EXECUTION.md` §I.2). A fix is rendered by the
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
