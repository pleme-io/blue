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

Use `kazu`'s `near(a, b)` for anything that has been through `sqrt`, a division
or a mean. Use `floor(n / 2)` where you want integer division.

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

Blue's lexer treats `-` as an operator and does not accept `?`/`!` in
identifiers, so a chunk of the underlying tatara-lisp stdlib is **unreachable**:
`every?`, `sort-by`, `string-length`, `count-if`. That is why `junjo`
implements its own `sort` — not preference, necessity.

Reachable: `length` `nth` `car` `cdr` `cons` `append` `take` `drop` `reverse`
`list` `range` `min` `max` `abs` `gcd` `lcm` `modulo` `expt` `sqrt` `sin` `cos`
`tan` `log` `exp` `floor` `ceiling` `round` `map` `filter` `reduce` `concat`
`split` `join` `chars` `upcase` `downcase` `trim` `replace` `to_s`.

**Do not shadow a reachable name** with a `def` of your own unless you mean to
replace it everywhere in the file.

---

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
4. Raise the count floors in `flake.nix` and `distribution.rs`.
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
