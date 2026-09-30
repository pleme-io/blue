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

## Commands

| | |
|---|---|
| `blue run file.b` | run a program; `--quiet` drops the final value, `-- a b` passes arguments |
| `blue test file.b` | check it, then run its `test` blocks |
| `blue check file.b` | every rule (unbound names with did-you-mean, unused bindings, types, waivers); `--format json` prints one object per diagnostic, `--fix` applies the machine-applicable fixes |
| `blue explain B0001` | what a diagnostic code means; `--list` lists them ([`docs/DIAGNOSTICS.md`](docs/DIAGNOSTICS.md)) |
| `blue fmt file.b` | print the one formatting; `--write` rewrites, `--check` fails on drift |
| `blue reference` | the language reference as JSON |

`run`, `test` and `check` rewrite a non-canonical file in place before they
compile it, and say `blue: formatted <file>`. Bidamas are found on `BLUE_PATH`:
`BLUE_PATH=path/to/blue/bidamas blue test file.b`.

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
  `split(s, sep)`. The pipe `xs |> f(a)` puts `xs` FIRST, so
  `xs |> map(f)` is `map(xs, f)` and fails.
- **No blocks, no indexing.** Write `map(fn(x) x * 2 end, xs)`, never
  `xs.map { |x| … }` or `do … end`. Write `nth(0, xs)`, never `xs[0]`.
- **`error(:kind, "why")` raises nothing.** It builds a value. Raise with
  `throw(error(:kind, "why"))`. A caught error's kind and message cannot be
  read, so return refusals as data (`[[kind, why], …]`) and throw only at the
  boundary. See the errors example.
- **Each bidama is a namespace.** Reach another bidama's definition
  qualified, `kueri::join(a, b)` after `use("kueri")`, or list it,
  `use("retsu", [:first, :size])`, then call `first(xs)` bare. Nothing else
  is visible: a name another bidama defines, reached bare without a list, is
  an error (B0012), and `blue migrate FILE` adds the lists. A bare name is a
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
- **Output is `write_stdout`.** `println` prints strings with their quotes.
- **Names with `-` do not exist in blue.** tatara-lisp's kebab-case words are
  unreachable. A keyword may end in `?` or `!` (`[:pair?]`), as a name may.
- **Deep recursion aborts.** Prefer `map`, `filter` and `reduce` over
  hand-written recursion on long lists, and `sort_keyed(key, xs)` for sorting.

The rest of blue's semantics is Ruby's, except where
[`bidamas/okite/RULES.md`](bidamas/okite/RULES.md) says otherwise.

## Conventions

The formatter settles layout. For the rest, follow the examples: a predicate
you define ends in `?` (okite D0010), `x == nil` over `nil?(x)`, interpolation
over `concat`, `use` forms first and sorted, each listing what the file
reads, and names without a package prefix. Tests go in the same
file, named for the behaviour, with the empty input among the cases.

## More

- [`bidamas/AUTHORING.md`](bidamas/AUTHORING.md): writing and testing a
  bidama, and the measured traps not yet made rules.
- [`bidamas/NAMES.md`](bidamas/NAMES.md): how packages are named.
- [`spec/README.md`](spec/README.md): the conformance suite, one row per
  observable behaviour run on every evaluator; a row's program and expected
  result is the most exact statement of what blue does.
- [`llms.txt`](llms.txt): these files as an index.
