---
kind: tutorial
order: 4
summary: write a documented bidama with doctests, read its docs with blue doc, and use it from a program
---

# A first bidama

A bidama is a blue package. It documents itself: a `@moduledoc` says what
the package is for, and a `@doc` above each definition says what it does,
with an example that `blue test` runs.

Start a program, then a second bidama beside its own:

```console
$ blue new shelf
created shelf/: Bluefile, Bluefile.lock, flake.nix, main.b, bidamas/shelf/
run it   blue shelf/main.b
test it  blue test shelf/bidamas/shelf/shelf.b
$ cd shelf/bidamas
$ blue new --bidama prose
created prose/: Bluefile, Bluefile.lock, prose.b
test it  blue test prose/prose.b
$ cd ..
```

Replace `bidamas/prose/prose.b` with a documented package:

```blue file=bidamas/prose/prose.b
@moduledoc """
prose: split text into words and count them.

    count_words("a b") #=> 2
"""

use("retsu", [:size])

@doc """
words: The words of a text: the runs of characters between spaces.

    words(" a  b ") #=> ["a", "b"]
"""
def words(text)
  filter((w) -> w != "", split(text, " "))
end

@doc """
count_words: How many words a text holds.

    count_words("the quick brown fox") #=> 4
"""
def count_words(text)
  size(words(text))
end

test "an empty text has no words"
  assert count_words("") == 0
end
```

Each `expr #=> value` line in a doc is a doctest. `blue test` runs them with
the `test` blocks:

```console
$ blue test bidamas/prose/prose.b
4 test(s): 4 passed, 0 failed
```

`blue doc` shows a definition as a reader sees it:

```console
$ BLUE_PATH=bidamas blue doc prose::count_words
prose::count_words(text)
  bidama prose · tier: qualified
  count_words: How many words a text holds.
  
      count_words("the quick brown fox") #=> 4
  · signature `def count_words(text)` · rung dynamic
  · pure: reaches no host capability
  example (test "an empty text has no words"):
    assert count_words("") == 0
```

Now use the package from the program. Replace `bidamas/shelf/shelf.b`:

```blue file=bidamas/shelf/shelf.b
use("prose", [:count_words])

def main(args)
  write_stdout(unlines(["#{count_words(join(args, " "))} words"]))
end

test "the program counts its arguments' words"
  assert count_words("a b c") == 3
end
```

A bidama's `Bluefile` and lock record the packages its files use. `shelf`
now uses `prose` and no longer uses `retsu`, so the check refuses the old
lock and names its fixer. Run it, then run the program:

```console
$ blue check --fix bidamas/shelf/shelf.b
$ blue main.b one two three
3 words
```

The next tutorial, [a first service](first-service.md), declares a service
in the `Bluefile`.
