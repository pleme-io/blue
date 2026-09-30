# Writing a bidama — the verified idiom

**Everything here was measured against the runtime, not inferred from the
grammar.** Each surprise below cost a debugging cycle when the first seventeen
packages were written; the list exists so the next author pays once, in reading,
instead of once per package.

Run anything you doubt: `BLUE_PATH=$PWD blue run file.b`.

Writing a program rather than a package? Start at [`../AGENTS.md`](../AGENTS.md)
and [`../docs/EXAMPLES.md`](../docs/EXAMPLES.md).

**Read [`okite/RULES.md`](./okite/RULES.md) first.** It is the whole of blue's
behaviour beyond "values act like Ruby's", one line per rule, and every line is
enforced by laws in okite, so it cannot go stale. This file is what is left:
traps not yet decided. Each one fixed becomes a rule there and leaves here.

---

## The one that breaks structural recursion

**`length(nil)` ERRORS, and `nil` is not `[]`.** The list operations never
hand you that `nil` any more (okite D0011: `cdr([1])` is `[]`, measured
2026-09-29), but a function that receives `nil` — an absent map key, a
`find_first` that found nothing — still reaches it:

```
cdr([1])            => []
nil == []           => false      # two DIFFERENT empties (D0004)
length(nil)         => runtime error: expected a string, got nil
```

So a recursion guarded by `length` dies on the first `nil` it is given:

```blue
# WRONG — dies when xs is nil
def walk(xs)
  if length(xs) < 1
    0
  else
    1 + walk(cdr(xs))
  end
end
```

Use `retsu`'s total replacements, which are true of both empties:

```blue
use("retsu", [:is_empty, :rest])

# RIGHT
def walk(xs)
  if is_empty(xs)
    0
  else
    1 + walk(rest(xs))
  end
end
```

| instead of | use | from |
|---|---|---|
| `length(xs)` | `size(xs)` | retsu |
| `car(xs)` | `first(xs)` | retsu |
| `cdr(xs)` | `rest(xs)` | retsu |
| `length(xs) < 1` | `is_empty(xs)` | retsu |

`map`, `filter`, `reduce`, `append` and `cons` all handle `nil` correctly — it
is only `length` that is partial.

---

## Argument order is lisp-native, and inconsistent between siblings

Function-first for higher-order; **check the order for anything else**, because
`join` and `split` disagree:

```
map(fn(x) x * 2 end, [1,2,3])            => [2, 4, 6]
filter(fn(x) x > 2 end, [1,2,3,4])       => [3, 4]
reduce(fn(a, b) a + b end, 0, [1,2,3,4]) => 10
nth(0, [7,8,9])                          => 7        # INDEX first
take(2, [1,2,3])                         => [1, 2]   # COUNT first
join(["a","b"], "-")                     => "a-b"    # LIST first
split("a-b", "-")                        => ["a","b"] # STRING first
```

---

## Numbers

**`/` is float division (okite D0008), and numbers compare by value (D0001).**

```
7 / 2               => 3.5
sqrt(25) == 5       => true       # 5.0 == 5 (until 2026-09-27: false)
4 == 4.0            => true
```

Use `floor(n / 2)` where you want integer division, and `kazu`'s `near(a, b)`
only where rounding error is real (0.1 + 0.2), not to compare an Int with a Float.

**`%` and `modulo` are EUCLIDEAN, not truncating** — the result is never
negative, which is the opposite of C, Rust, JS and Ruby:

```
-7 % 3        => 2        # NOT -1
7 % -3        => 1
5 % 0         => runtime error ("division by zero"), not a typed one
```

Any modulo idiom ported from another language will silently compute something
else. `kazu.mod_positive` names the guarantee so a caller need not know.

**`<` and `<=` are a TYPE ERROR on strings** ("expected number, got string").
The reachable `compare(a, b)` builtin is total and returns -1/0/1 — that is why
`junjo.sort` is phrased on `compare` and can order words as well as numbers.

---

## Lambdas exist; Ruby's brace block does not

```blue
fn(x) x * 2 end                    # works
map(fn(x) x * 2 end, xs)           # works
[1,2,3].map { |x| x * 2 }          # PARSE ERROR — "blue has no brace blocks"
```

Assignment works (`x = 5`); there is no `let`. Nested lambdas and closures work.

---

## Names you cannot call at all

Blue's lexer treats `-` as an operator, so every KEBAB-CASE name in the
underlying tatara-lisp stdlib is **unreachable**: `sort-by`, `string-length`,
`count-if`. That is why `junjo` implements its own `sort` — necessity, not
preference.

A trailing `?` or `!` IS now part of an identifier (fixed 2026-08-02), so
`contains?`, `starts_with?`, `ends_with?` and `to_int!` are reachable. They
were dead code in the runtime until then — registered and uncallable.

Every reachable built-in is listed in [`../docs/REFERENCE.md`](../docs/REFERENCE.md),
generated from the running interpreter with a one-line description, its
arity, and which bidama redefines it; a list kept here by hand had already
fallen behind (`get`, `assoc`, `write_file` were missing). The one to know
before you need it is `compare(a, b)`: the only total ordering primitive,
whose absence from the old list once cost an author a hand-rolled
character-ordinal table.

**A `def` named like a builtin is your package's**, inside your package: an
own definition beats a builtin (the tier order below). Inside the package
write `blue::count` for the builtin; everywhere else `count` stays the
builtin unless a file lists yours.

---

## Each bidama is a namespace

Every definition lives in its bidama's namespace, and is keyed by it at run
time (`kueri/join`), so two bidamas may define one name and neither replaces
the other, or a builtin, for anyone else.

- **Reach another bidama's name one of two ways**, and nothing else:
  qualified, `kueri::join(a, b)`, after `use("kueri")`; or listed,
  `use("retsu", [:first, :size])`, then bare `first(xs)`. A bidama your file
  does not `use` is not visible, even when something else loaded it: a bare
  name another bidama defines, reached only because it was loaded, is B0012,
  and `blue migrate FILE` writes the lists for you.
- **A bare name resolves by tier**, the first that has it winning: a local,
  then your own bidama's definitions, then the names your `use` forms list,
  then builtins. Two lists naming one name is B0009. `blue explain-name NAME
  FILE:LINE` prints the path; `blue check --format json` records every place
  a higher tier won.
- **`use` forms come first, one per bidama, sorted, each list sorted**
  (B0015); every `use` must be reached and every listed name read (B0016);
  inside a bidama the `use`s are exactly its Bluefile's `needs` (B0019).
- **Do not prefix your definitions** with your bidama's name or a short tag
  (`kueri_join`, `q_join`): the namespace already says whose it is, and
  callers write `kueri::join`. B0013 and B0014 refuse it; `blue migrate
  --strip PREFIX BIDAMA CALLER...` strips an existing prefix, rewrites the
  callers, and keeps the old spelling as a bridge with
  `legacy_names("0.1.1", "q")` until the next minor version (B0021 reports a
  caller still on it). A name whose stripped form is a reserved word or a
  builtin your bidama uses keeps its prefix, waived, and gains the stripped
  name too (`kueri::count` and `kueri::q_count` are one definition).
- `blue::name` names a builtin, and is needed only where a same-named
  definition would otherwise win (B0018 refuses a qualifier that changes
  nothing).
- `nix flake check` runs `bidama-collisions` in `namespace` scope: one
  bidama defining a name twice is red (B0017 refuses it at check).
- Before writing a name, look it up in [`CATALOG.md`](./CATALOG.md): its
  closing section lists the names several bidamas define.

## Finding what already exists

[`CATALOG.md`](./CATALOG.md) lists every package, its gloss, and every definition
with the first line of its doc comment. The `mokuroku` bidama generates it.
`nix flake check` fails when the committed copy is stale, and
`nix build .#bidama-catalog` produces a fresh one. A doc comment is the `#`
block **directly above** a `def`: a blank line in between detaches it, so put
the sentence that says what a function is for right above it.

## Output, strings and control flow (measured)

- **`if` is an expression**: `x = if c … else … end` works, written across lines.
  There is no `then`: `if c then a else b end` is a parse error ("blue's `if`
  has no `then`"). Until 2026-09-29 it parsed, with `then` as a statement of
  its own, and failed at run time as an unbound name. The formatter writes an
  `if` across lines; put a one-line choice in a small helper function.
- **One statement per line.** A statement ends at the end of its line, or at
  the `end`/`else`/`when` that closes its block, so `fn(x) x + 1 end` is one
  line. Anything else after a statement is a parse error: there is no `;`, and
  `a = f x` is refused with "a call needs parentheses: write `f(x)`". Until
  2026-09-29 the parser started a second statement there instead, silently.
- **`error(kind, msg)` builds an error VALUE; `throw(...)` raises it.** A check
  written as `error(:x, "...")` returns a value and the program carries on
  with exit 0 — a gate that can never fail. Fail a run with
  `throw(error(:kind, "why"))` (exit 1, "uncaught: #<error :kind ...>").
  `raise`, `panic`, `fail` and `exit` are unbound (measured 2026-09-23).
- **A throw CAN be caught, and nothing about it can be read.** The reachable
  spelling is `try(expr, catch(e(), handler))`: the binding is written as a
  zero-argument call, because `catch` wants the one-element list `(e)` and
  `[e]` lowers to a two-element one. Inside the handler, `error?(e)` works, but
  `error-tag` and `error-message` are kebab-case (unreachable), `to_s(e)` is
  `"error"`, and two identical errors are not `==`. So a package whose refusals
  must be tested returns them as DATA too (`kueri`'s `q_refusals` gives
  `[kind, why]`, `q_check` throws the same list), and its tests assert the
  kinds on the data and `error?` on the throw (measured 2026-09-23).
- **Maps compare by value** (okite D0001): `{a: 1} == {a: 1}`, whatever order
  the entries were added in. Until 2026-09-27 they compared by identity.
- **`to_s` of a list or map is its blue literal** (D0006): `[1, "a"]`,
  `{a: 1}`, keys sorted, so equal maps render equally and hashing
  `json_stringify(m)` or `to_s(m)` both work. It was the word `"map"`.
- **`to_s` keeps a float's point** (D0005): `to_s(1.0)` is `"1.0"`.
- **`some` is a builtin; `any` and `every` are `ronri`'s.** Reaching them
  through a transitive import works until the import changes.
- **There is no postfix indexing.** `xs[0]` is a parse error that names the
  fix: "write `nth(0, xs)` (or `first(xs)`, `last(xs)`)", and so is `f(x)[1]`.
  Until 2026-09-29 `y = xs[0]` parsed as two statements, `y = xs` and the list
  `[0]`, and bound `y` to the whole list. Use `nth(i, xs)`, `first` and `last`.
- **Interpolation works**, calls included: `"| #{name} | #{to_s(n)} |"`. It
  reads better than nested `concat`.
- **`println` prints a string with its quotes and escapes visible.** A program
  whose output is data writes it with `write_file`.
- **`glob` of an ABSOLUTE pattern returns `[]`** while `walk_dir` of the same
  root lists every file. Walk and filter with `ends_with?`, and give any scan
  a positive control so a silent zero is a failure.
- **`concat` takes any number of arguments** (D0007). `each`, `len` and `map_indexed` are unbound: `map` (for its
  effects too), `size` or `length`, and retsu's `enumerate` (`[[i, x], …]`)
  (measured 2026-09-27, writing `heni`).
- **A command's output is what it writes.** `write_stdout`/`write_stderr` write
  text exactly; `blue run` also prints the program's final value, which
  `blue run --quiet` suppresses. An installed command (`mkBlueApp`, `pkgs.blueApp`)
  runs `blue run --quiet <file> --`, so it never ends with a stray `nil` and every
  argument a user types reaches `argv()`, even one spelled like a CLI flag.
- **A program that runs blue spawns `self_exe()`**, the interpreter running it,
  not a PATH lookup: in a nix sandbox there is no `blue` on PATH (measured
  2026-09-27: heni's control run found none and, correctly, stopped).

## Name the fields

A function that returns a record as a list exports accessors (`pkg_name(r)`,
`conduct_of(p)`), and one that returns a row exports its column names
(`keishou.metric_names()`). Consumers then never write `nth(4, r)` or hard-code
how many columns there are, so adding a field breaks nothing silently.

## Run the real path once

Pure tests over hand-made inputs are necessary and not sufficient. `mokuroku`'s
ten tests passed over one record each while its real run failed: sorting two
records by name raised "expected number, got string" (junjo's keyed sorts used
`<=`, since fixed). Before committing, run the package once over real data with
a scratch program that writes its output to a file, and read the output.

## Seeds and replication

`next_float(seed)` is a pure function of the seed, and `next_seed` walks one
stream. Two streams taken one step apart replay each other, so derive
independent streams with `split_seed` (a golden-ratio offset, in `ran`), never
`seed + 1`. A simulation result from one seed is an anecdote: run replicates
and report mean, spread, min and max.

## Cost: compute a population's aggregate once

A helper that recomputes an aggregate over everyone (a mean, a pool, a share)
and is then called once per person inside a `map` is quadratic, and blue runs
roughly 20k simple agent steps a second. Measured 2026-09-23: a disclosure game
that recomputed the silent pool's mean per person ran for over ten minutes; the
same game computing it once per round ran in 16 seconds. Compute the aggregate
once, then pass it in. For "everyone meets someone" rounds, index by position
(agent i meets agent (i + k) mod n) instead of searching or sorting.

## Depth

Recursion depth is bounded: `junjo.sort` overflows near 400 elements under
`blue test` and near 100 under `cargo test`'s 2 MiB thread, and an overflow
aborts the process rather than failing a test. Prefer `map`, `filter` and
`reduce` over hand-written recursion on long lists, and use `merge_sort` when a
sort has to be deep. Keyed sorts (`sort_by`, `sort_stable_by`, `min_by`,
`merge_sort`) go through `compare`, so they order strings as well as numbers.

**For a list that can be long, use `sort_keyed(key, xs)`** (2026-09-27): a
native, stable, O(n log n) sort under `compare`'s rules, at any length (tested
at 20,000 in blue and 100,000 upstream). It is tatara-lisp's `sort-by-key`
(0.3.60), bound to a name blue can call; keys of different kinds, or a NaN,
are refused. `merge_sort` still overflows near 600, because `merge_sorted`
recurses once per element.

**`range` was a recursion too, until 2026-09-24.** tatara-lisp defines it in
Lisp, one frame per element, so `range(0, 5000)` aborted the process, and so
did everything built on it (`indexes`, `zip_with`, `enumerate`, shomei's
`chain_first_break` over a 5,000-line chain). blue's runtime now registers a
native `range`; a checkout older than that still has the ceiling.

**A DEBUG build is deeper still, and CI's `cargo test` is a debug build.**
Measured 2026-09-23 with `target/debug/blue test` (8 MiB main thread) over
every package: `angou` and `tokumei` abort with a stack overflow while all 22
others pass, and the same two abort `distribution.rs`'s gate (debug, 8 MiB),
which then names no package. `cargo test --release` passes the gate. Run a new
package's tests under the debug binary once before trusting a release-built
`blue test`.

## Growing a list is quadratic

**`push` and `cons` copy the whole list**, because a list is a vector
underneath. Measured 2026-09-24: growing a list one element at a time took
0.19 s for 10,000 elements and 2.9 s for 40,000. Build a long list in one pass
(`map`, `filter`, `split`), and do not give a long-lived value a list that
grows with every call: a log writer that kept every record it appended would
slow down with its own age. A map (`assoc`, `get`) is the index to reach for;
`get` costs ~1 µs, and `assoc` copies the map (~2 µs at 100 keys).

`retsu`'s `contains` and `index_of` were the same shape until 2026-09-24:
a recursion that copied the tail at each step (664 ms to find the last of
20,000). They are now the runtime's `member?` and `position`.

## Silent answers

- **In kueri, a string in an expression is a VALUE.** A keyword is a column
  and a string is a literal (the HoneySQL rule), so a column name a program
  computes as text (`"#{role}_seq"`) renders as `'item_seq'` inside a
  comparison and compares a constant (measured 2026-09-24: two such bugs, in
  a generated view, seen only by reading the SQL). Wrap a computed name in
  `q_c(...)` wherever it is an operand; in `q_select`, keys and sort lists a
  string is already a name.
- **A string literal containing `#{` is always interpolated.** A program that
  carries blue source as data (a mutation driver, a code generator) writes the
  brace by codepoint, `"#\u{7b}"`, which is also how the formatter prints a
  string whose value holds `#{`. Written plainly, the literal evaluates the
  code it was meant to hold (measured 2026-09-24: "unbound symbol").
- **`list?(nil)` is true.** Test `v == nil` before `list?(v)`, or `nil` takes
  the list branch (a JSON writer rendered it `[]`).
- **`find_first` answers `nil` both for "absent" and for a found `nil`.** When
  an element may be nil, ask `count_where` or `filter` instead.
- **A parameter or local named like a function shadows it** for the rest of
  the def: `def f(xs, size) size(xs) end` raises. `size`, `count`, `first`,
  `last` and `type` are the tempting ones.

## Negative numbers

Write `-n`. `0 - n` is the same tree, and the formatter rewrites it to `-n`
(measured 2026-09-29: no `0 - x` survives in the corpus). `-x * y` is
`(-x) * y`: the unary minus binds tighter than any infix operator.

---

## Tests live in the package, in blue

**A red run's mutated copy goes in a directory of its own.** `BLUE_PATH` puts
the red directory first, so any package left there from an earlier red run
shadows the real one: a mutation of `kakou` tested beside a leftover mutated
`rittai` failed because of `rittai` (measured 2026-09-27; every affected run
was redone). One fresh directory per mutation, holding only the mutated
package. **`heni` does this for you** (`heni <PKG_DIR> <MUTATIONS.json>`; `nix run
.#heni --` from blue, and on PATH only where a node installs blue's commands —
it was not on this workstation's PATH on 2026-09-29): a control run first, then each literal find/replace
(which must match exactly once) in its own copy, reported as caught / survived /
refused / blind, exiting non-zero unless every mutation is caught. A red run by
hand that rebuilds a binary leaves the mutant binary behind after the source is
restored: rebuild before probing again (measured 2026-09-27, when a stale
`target/debug/blue` made a working `--quiet` look broken).

Every bidama carries its own `test` blocks. They are run by `blue test`, and by
`cargo test` through `blue-lang-pkg/tests/distribution.rs`, which enforces that
**every package has at least one test of its own** — counted before imports
resolve, so a dependency's tests never count as yours.

```blue
test "what the behaviour is, not what the function is called"
  assert clamp(99, 1, 10) == 10
  assert clamp(-5, 1, 10) == 1
  assert clamp(5, 1, 10) == 5
end
```

**Imported packages' tests are stripped** on `use`, and `blue run` ignores test
blocks entirely — so a package with tests is still runnable and still importable.

### What makes a test worth writing

Assert the case that distinguishes a correct implementation from a plausible
one. Every one of these caught a real bug in this distribution:

- **the empty input** — `unique([])`, `sort([])`, `every(p, [])`. The vacuous
  cases are where predicate libraries go wrong: everything holds of nothing.
- **the identity that must survive** — `transpose(transpose(m)) == m`,
  `rot13(rot13(s)) == s`, `combinations(10,3) == combinations(10,7)`.
- **the value everyone can check independently** — `combinations(52,5) ==
  2598960`, 2000-01-01 was a Saturday, a Life block is stable.
- **the case a wrong formula still passes** — `variance([5,5,5]) == 0` catches a
  wrong mean; `sign(0) == 0` catches a two-branch `sign`.
- **a control** — if you assert an imported function works, also assert it
  FAILS without the import, or you have proven nothing about the import.

---

## Adding a package

1. **Run `/naming` first** — before the code. Sweep the word, its
   near-homophones and **its gloss** against the fleet. See `NAMES.md`.
2. Add the `NAMES.md` row in the same commit, or the build goes red.
3. `Bluefile`: `package("name", "0.1.0")` plus a `needs(...)` per dependency —
   and every `needs` must have a matching `use(...)` in the source, and the
   other way round: B0019 refuses a mismatch, and `mkBidama` runs the check
   stage, so a package that does not check does not build. Then `blue lock <dir>` and commit the `Bluefile.lock` with
   it: nix reads the lock, and `bidama-locks-fresh` fails on a stale one.
4. Raise the package floor in `bidamas/flake.nix`, the package and test floors
   in `distribution.rs`, and regenerate `CATALOG.md` with `nix run .#regen`.
5. Add the matching `needs(...)`/`use(...)` pair to **`zenbu`** — the facade
   bidama that declares every other one, so a consumer can take the whole
   distribution as a single dependency. It is an ordinary package with a long
   manifest, not a special case, which is precisely why nothing updates it for
   you: `granularity.rs::the_facade_is_an_ordinary_bidama_with_many_needs`
   turns the omission into a red build.

   **Write the list out anyway.** A Bluefile is blue code, so
   `needs(some_variable, …)` works. `mk-bidama.nix` used to read the graph by
   splitting the text on `needs("`, and one computed entry left blue resolving
   17 dependencies, nix seeing 16, and the built closure one bidama short, with
   nothing red. It now reads the committed `Bluefile.lock`, which is blue's own
   evaluation, so a computed entry is seen; a literal list is still the one a
   reader can check against the `use(...)` lines.
