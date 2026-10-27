# Writing blue

This file is for people and agents writing blue programs. If you are changing
blue itself (the parser, the runtime, the nix engine), read `CLAUDE.md`.

blue looks like Ruby and Elixir and parses to a tatara-lisp tree that a Rust
runtime executes. There is one formatting and no configuration, and most
of the vocabulary lives in packages called bidamas.

## Start from an example

Copy the closest program in [`docs/EXAMPLES.md`](docs/EXAMPLES.md) and change
it. Every example there runs as a check, so it works as written. Then look up
names in [`docs/REFERENCE.md`](docs/REFERENCE.md) (built-ins, operators,
syntax) and [`bidamas/CATALOG.md`](bidamas/CATALOG.md) (every bidama
definition). Both are generated from the implementation and gated fresh.

## A file is a program; a project is one command away

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
[`docs/SAFETY.md`](docs/SAFETY.md).

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

## Commands

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
| `blue explain B0001` | what a diagnostic code means; `--list` lists them ([`docs/DIAGNOSTICS.md`](docs/DIAGNOSTICS.md)) |
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
| `blue registry render [BACKEND]` | a Bluefile `registry` entry (sui first, FlakeHub optional) as its publish workflow; `--write` rewrites the committed files; `blue registry status` says whether sui serves each pin. The lock stays the truth: [`docs/REGISTRY.md`](docs/REGISTRY.md) |

Sessions (`eval`, `repl`, `serve`) are pure: code that reaches the host
(`read_file`, `now_ms`, `exec_capture`, …) is refused as volatile unless the
session was started with `--allow host` (or `--allow filesystem`, and so on);
`--budget STEPS` bounds each evaluation.

A project adds its own check rules, written in blue: `rule("R0001",
"rules/x.b", "def_name")` in its Bluefile names a definition that receives each
top-level form as data and returns findings (`{at: path, message: "…", fix:
tree}`); `blue check` runs it under a pure frame and a step budget, and the
usual `# waive R0001: reason` applies. The shape, the frame and a worked rule:
[`docs/DIAGNOSTICS.md`](docs/DIAGNOSTICS.md), "Project rules"; blue's own are
in [`rules/`](rules/).

`run`, `test` and `check` rewrite a non-canonical file in place before they
compile it, and say `blue: formatted <file>`. A checkout's bidamas override
the compiled-in ones from `BLUE_PATH`:
`BLUE_PATH=path/to/blue/bidamas blue test file.b`.

`blue test` is hermetic. It drops the inherited `GIT_DIR`, `GIT_WORK_TREE`
and their kin, so a fixture repository a test makes is its own, and it
refuses a write outside the temporary directory (`TMPDIR`). The off switches
are `BLUE_TEST_ENV=inherit` and `BLUE_TEST_WRITES=anywhere`. A test that
writes a `.b` file writes it with `write_program`, which formats it (B0064).

## One way to write each thing

blue reads every older or borrowed spelling and writes one: `a and b`, `not x`,
`if not c`, `f(x, y)`, `x.field`, `f(a, *xs)`, `raise(:kind, "why")`,
`x rescue fallback`, `def main()`. `blue fmt --write` and `blue check --fix`
rewrite a file to it and name each rule; `blue run` formats its entry in
place; `blue test` and `blue check` never write a file, and refuse naming the
command that fixes it. A loaded dependency compiles as written: its form is
its producer's ([`docs/COMPOUNDING.md`](docs/COMPOUNDING.md)). The rules are the table at the end of
[`docs/REFERENCE.md`](docs/REFERENCE.md) (generated from the registry the
check stage runs); why each spelling won is
[`docs/CANONICAL-FORMS.md`](docs/CANONICAL-FORMS.md). Write the canonical
spelling and nothing is rewritten.

The one spelling is the shortest that stays distinct, and each shorthand is
built from a longer form that also works, so writing the long form is never
wrong: the formatter shortens it. The same holds for the library: one verb per
meaning, and one bidama for each cross-cutting concern (errors and refusals in
`kyohi`, entries and switches in `kousei`, configuration in `settei`). Reach
for that bidama before writing the concern by hand. Why: `theory/BLUE.md` §0
and §V.28.1.

Before you name a function, look for its verb: the graph rows in
`bidamas/mokuroku/graph/` (one file per space) and the contract for each verb in
`docs/verbs/contracts.tsv`. A verb that exists is called as `space::verb` with that
contract. A verb that is only a row is the work to do: build it to its contract. A
meaning with no row gets a row first (TSV, then `blue verbs import`), named in plain
English as `read`, `put`, `need` (raises) or `get` (nil), never a `_or` variant.
The plan and the waves are `docs/VERB-ROADMAP.md`.

## The traps that cost the most

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
  [`docs/REFERENCE.md`](docs/REFERENCE.md), "Called where written bare". Find
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
[`bidamas/okite/RULES.md`](bidamas/okite/RULES.md) says otherwise.

## Conventions

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

## More

- [`bidamas/AUTHORING.md`](bidamas/AUTHORING.md): writing and testing a
  bidama, and the measured traps not yet made rules.
- [`bidamas/NAMES.md`](bidamas/NAMES.md): how packages are named.
- [`spec/README.md`](spec/README.md): the conformance suite, one row per
  observable behaviour run on every evaluator; a row's program and expected
  result is the most exact statement of what blue does.
- [`llms.txt`](llms.txt): these files as an index.
