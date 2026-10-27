---
kind: tutorial
order: 3
summary: start a program with blue new, change its code, and test it
---

# A first program

A program is a project: a `Bluefile` that says how it is built, a `main.b`
that runs it, and its code in a bidama of its own. `blue new` writes one that
passes its tests as written:

```console
$ blue new tally
created tally/: Bluefile, Bluefile.lock, flake.nix, main.b, bidamas/tally/
run it   blue tally/main.b
test it  blue test tally/bidamas/tally/tally.b
$ cd tally
$ blue main.b ryn
hello, ryn
```

Now make it count words. Replace `bidamas/tally/tally.b` with this:

```blue file=bidamas/tally/tally.b
use("retsu", [:size])

def words(text)
  filter((w) -> w != "", split(text, " "))
end

def tally(text)
  size(words(text))
end

def main(args)
  write_stdout(unlines([to_s(tally(join(args, " ")))]))
end

test "words are what the spaces separate"
  assert tally("one two  three") == 3
end

test "an empty text has no words"
  assert tally("") == 0
end
```

Run the tests. `blue test` checks the file first, then runs each `test`
block:

```console
$ blue test bidamas/tally/tally.b
2 test(s): 2 passed, 0 failed
```

Run the program:

```console
$ blue main.b the quick brown fox
4
```

`main.b` stayed the same: it calls `main(argv)` from the `tally` bidama. Next,
[a first bidama](first-bidama.md) documents a package so others can use it.
