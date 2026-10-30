---
kind: howto
order: 6
summary: write a pure data transformation, run it under --allow none, and see the check stage refuse a variant that reaches the host
---

# Run a pure worker

A pure worker turns data into data. It reads no file, no clock and no
environment. `--allow none` holds a run to that, and blue proves it before
the program starts.

Write the transformation and its tests in one file:

```blue file=totals.b
def line_total(item)
  item.price * item.qty
end

def total(items)
  reduce((sum, item) -> sum + line_total(item), 0, items)
end

test "an empty order costs nothing"
  assert total([]) == 0
end

test "a total sums price times quantity"
  assert total([{price: 2, qty: 3}, {price: 5, qty: 1}]) == 11
end

def main()
  order = [{price: 2, qty: 3}, {price: 5, qty: 1}]
  write_stdout(unlines(["total: #{total(order)}"]))
end
```

Test it:

```console
$ blue test totals.b
2 test(s): 2 passed, 0 failed
```

Run it with no host capability:

```console
$ blue run --allow none --quiet totals.b
total: 11
```

Now add a timestamp to the output. `now_ms` reads the host clock:

```blue file=stamped.b
def total(items)
  reduce((sum, item) -> sum + item.price * item.qty, 0, items)
end

def main()
  order = [{price: 2, qty: 3}, {price: 5, qty: 1}]
  write_stdout(unlines(["#{now_ms} total: #{total(order)}"]))
end
```

The check stage refuses this variant, and no line of it runs. The message
names the call, the capability and the flag that grants it:

```console fails
$ blue run --allow none --quiet stamped.b
blue: 1 error(s) in the check stage:
stamped.b: refused: `now_ms` reaches the host (clock), which this run does not allow; pass --allow clock to grant it
```

Keep the host call out of the worker. Make the call in the code that uses the
worker, and give the worker the value. To keep `now_ms` in a program and
still get the same output at each run, give it a stepped clock:
[Virtualize a capability](virtualize-a-capability.md). The other capability
names are in [Declare what a program may touch](declare-access.md).
