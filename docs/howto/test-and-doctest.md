---
kind: howto
order: 1
summary: write a test block and a doctest, read a failure, and run one test by name
---

# Write a test and a doctest

Put a `test` block beside the code it tests, in the same file. `assert`
fails the test when its expression is false:

```blue file=math.b
@doc """
double: Twice a number.

    double(21) #=> 42
"""
def double(n)
  n * 2
end

test "double of zero is zero"
  assert double(0) == 0
end

test "double of a negative stays negative"
  assert double(-3) == -6
end
```

The `#=>` line in the `@doc` is a doctest: `blue test` runs it beside the
`test` blocks.

```console
$ blue test math.b
3 test(s): 3 passed, 0 failed
```

Run only the tests whose name holds a word:

```console
$ blue test --filter negative math.b
1 test(s): 1 passed, 0 failed
```

A failure prints the expression as you wrote it, with both sides:

```blue file=wrong.b
test "two and two"
  assert 2 + 2 == 5
end
```

```console fails
$ blue test wrong.b
FAIL two and two
  assert 2 + 2 == 5
```

`blue test DIR` runs every file under a directory that holds a test, in
parallel.
