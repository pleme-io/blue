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
| B0007 | malformed-waiver | error | a waiver names a known code and gives a reason |
| B0008 | unused-waiver | warning | a waiver suppresses at least one diagnostic |
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

A name resolves by tier, first match wins
(`blue_lang_check::names::RESOLUTION_ORDER`): locals innermost first, then the
referencing file's or bidama's own definitions, then every other imported
definition, then builtins (harness names, special forms, macros, values). Two
namespaces in the tier that holds the name is B0009. For the head of a call the
evaluator's own order applies first: a special form, then a macro, beats any
definition.

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

## `blue check --fix`

Applies every machine-applicable fix whose edits land in the named file and
still match their `original`, skips overlapping ones, then re-formats and
re-checks the file and reports what remains. Suggestions marked
`maybe-incorrect` are never applied.

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

Each entry of `references` carries the location fields of `blue check` and:

| field | meaning |
|---|---|
| `top_level` | the index of the top-level form it is in |
| `written` | the symbol as the tree has it: `first`, or `retsu/first` for `retsu::first` |
| `opaque` | inside a macro call's arguments |
| `flat`, `ns` | what each rule binds it to |

A binding (`flat`, `ns`) has:

| field | meaning |
|---|---|
| `kind` | `def` (a program definition), `builtin`, `local`, `ambiguous` (two imports list it) or `unbound` |
| `namespace` | the defining bidama for a `def`; `null` otherwise, and for the root namespace |
| `name` | the definition's or builtin's name |
| `key` | the symbol the resolved tree writes, or `null` when it keeps the written one |
