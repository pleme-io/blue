# Writing a bidama — the verified idiom

**Everything here was measured against the runtime, not inferred from the
grammar.** Each surprise below cost a debugging cycle when the first seventeen
packages were written; the list exists so the next author pays once, in reading,
instead of once per package.

Run anything you doubt: `BLUE_PATH=$PWD blue run file.b`.

---

## The one that breaks structural recursion

**`cdr` of a one-element list returns `nil`, not `[]`, and `length(nil)`
ERRORS.**

```
cdr([1])            => nil
nil == []           => false      # two DIFFERENT empties
length(cdr([1]))    => runtime error: expected a string, got nil
```

So the obvious shape crashes at the last element of **every** list:

```blue
# WRONG — dies on the base case, on every input
def walk(xs)
  if length(xs) < 1
    0
  else
    1 + walk(cdr(xs))
  end
end
```

Use `retsu`'s total replacements, which exist for exactly this:

```blue
use("retsu")

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

**`/` is float division, and a float never equals an int.**

```
7 / 2               => 3.5
sqrt(25) == 5       => false      # Float(5.0) vs Int(5)
near(sqrt(25), 5)   => true       # kazu
```

Use `kazu`'s `near(a, b)` for anything that has been through `sqrt`. Use
`floor(n / 2)` where you want integer division.

**But the rule above is only half true, and the false half is the dangerous
one.** Division NORMALISES to `Int` when it divides exactly, while `sqrt` never
does:

```
6 / 3 == 2          => true       # exact division comes back Int
(0 - 6) / 3 == 0-2  => true
sqrt(16) == 4       => FALSE      # sqrt always returns Float
sqrt(0) == 0        => FALSE      # so even zero fails the obvious check
```

`sqrt(0) == 0` being false is a live trap: it breaks `n == 0` for any value that
came through a root. Comparison operators (`<`, `>`) DO work across numeric
kinds, which is the escape hatch.

**`%` and `modulo` are EUCLIDEAN, not truncating** — the result is never
negative, which is the opposite of C, Rust, JS and Ruby:

```
(0 - 7) % 3   => 2        # NOT -1
7 % (0 - 3)   => 1
5 % 0         => runtime error, not a typed one
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
[1,2,3].map { |x| x * 2 }          # PARSE ERROR — no brace blocks
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

Reachable: `length` `nth` `car` `cdr` `cons` `append` `take` `drop` `reverse`
`list` `range` `min` `max` `abs` `gcd` `lcm` `modulo` `expt` `sqrt` `sin` `cos`
`tan` `log` `exp` `floor` `ceiling` `round` `map` `filter` `reduce` `concat`
`split` `join` `chars` `upcase` `downcase` `trim` `replace` `to_s` `compare`
`some` `find` `remove` `partition` `apply` `print` `println` `to_int`
`to_float`, and — since the lexer learned trailing `?`/`!` — `contains?`
`starts_with?` `ends_with?` `to_int!`. The crypto layer (2026-09-24) adds
`blake3_hex` `ed25519_keypair` `ed25519_sign` `ed25519_verify`; reach them
through `shomei` unless you need the algorithm by name.

`compare` in particular is worth knowing before you need it: it is the only
total ordering primitive, and its absence from this list once cost an author a
hand-rolled character-ordinal table.

**Do not shadow a reachable name** with a `def` of your own unless you mean to
replace it everywhere in the file.

---

## The namespace is flat across packages

A `def` in one bidama replaces a same-named function **everywhere** in a program
that imports both, including inside the other package's own code. Measured
2026-09-23 in a private distribution: a one-argument `member` in one package
broke `shuugou.unique`, which calls the builtin `member`. The failure surfaced as
an arity error inside shuugou, far from its cause.

- Give package-level names that say whose they are (`md_cell`, `pkg_name`,
  `name_collisions`), never bare nouns (`cell`, `owners`, `collisions`).
- `nix flake check` runs `bidama-collisions`: two packages defining one name is
  a red build. A private distribution gets the same gate from
  `mkCollisionCheck { owned = [ … ]; }`.
- Before writing a name, look it up in [`CATALOG.md`](./CATALOG.md).


The collision gate compares your names with **every** package in the distribution,
including ones your program never imports: a private `status_of` collided with
`shisutemu.status_of` (2026-09-23). It is right to fail: the next program that
imports both breaks silently. Rename the newcomer.
## Finding what already exists

[`CATALOG.md`](./CATALOG.md) lists every package, its gloss, and every definition
with the first line of its doc comment. The `mokuroku` bidama generates it.
`nix flake check` fails when the committed copy is stale, and
`nix build .#bidama-catalog` produces a fresh one. A doc comment is the `#`
block **directly above** a `def`: a blank line in between detaches it, so put
the sentence that says what a function is for right above it.

## Output, strings and control flow (measured)

- **`if` is an expression**: `x = if c … else … end` works, written across lines.
  There is no one-line `if c then a else b end`: `then` is an unbound name
  (measured 2026-09-23). Put a one-line choice in a small helper function.
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
- **Maps compare by identity.** `{a: 1} == {a: 1}` is false, while lists
  compare by value. Compare what a map renders to, or its fields. There is no
  `map?`, and `keys` and `merge` are unbound; `assoc` works.
- **`to_s` drops a float's point:** `to_s(1.0)` is `"1"`. Anything emitting a
  typed literal must add it back (`kueri`'s `q_float_text`).
- **`some` is a builtin; `any` and `every` are `ronri`'s.** Reaching them
  through a transitive import works until the import changes.
- **There is no postfix indexing.** `xs[0]` is a parse error, and `f(x)[1]`
  can parse into something else and fail later as a type error (measured
  2026-09-23, twice). Use `nth(i, xs)`, `first` and `last`.
- **Interpolation works**, calls included: `"| #{name} | #{to_s(n)} |"`. It
  reads better than nested `concat`.
- **`println` prints a string with its quotes and escapes visible.** A program
  whose output is data writes it with `write_file`.
- **`glob` of an ABSOLUTE pattern returns `()`** while `walk_dir` of the same
  root lists every file. Walk and filter with `ends_with?`, and give any scan
  a positive control so a silent zero is a failure.

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

**A DEBUG build is deeper still, and CI's `cargo test` is a debug build.**
Measured 2026-09-23 with `target/debug/blue test` (8 MiB main thread) over
every package: `angou` and `tokumei` abort with a stack overflow while all 22
others pass, and the same two abort `distribution.rs`'s gate (debug, 8 MiB),
which then names no package. `cargo test --release` passes the gate. Run a new
package's tests under the debug binary once before trusting a release-built
`blue test`.

## Negative numbers

There is a unary minus, but `0 - n` is what the existing packages use and what
is proven across the corpus. `sign(0 - 7) == 0 - 1` reads oddly and works.

---

## Tests live in the package, in blue

Every bidama carries its own `test` blocks. They are run by `blue test`, and by
`cargo test` through `blue-lang-pkg/tests/distribution.rs`, which enforces that
**every package has at least one test of its own** — counted before imports
resolve, so a dependency's tests never count as yours.

```blue
test "what the behaviour is, not what the function is called"
  assert clamp(99, 1, 10) == 10
  assert clamp(0 - 5, 1, 10) == 1
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
   and every `needs` must have a matching `use(...)` in the source, which is
   also enforced.
4. Raise the count floors in `flake.nix` and `distribution.rs`, and regenerate
   `CATALOG.md` (`nix build .#bidama-catalog`).
5. Add the matching `needs(...)`/`use(...)` pair to **`zenbu`** — the facade
   bidama that declares every other one, so a consumer can take the whole
   distribution as a single dependency. It is an ordinary package with a long
   manifest, not a special case, which is precisely why nothing updates it for
   you: `granularity.rs::the_facade_is_an_ordinary_bidama_with_many_needs`
   turns the omission into a red build.

   **Do not compute that list.** A Bluefile is blue code, so
   `needs(some_variable, …)` works — and `mk-bidama.nix` reads the graph by
   splitting the text on `needs("`, so nix would not see it. Measured: one
   computed entry left blue resolving 17 dependencies, nix seeing 16, and the
   built closure one bidama short, with nothing red.
