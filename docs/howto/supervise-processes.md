---
kind: howto
order: 7
summary: start worker processes under a supervisor, crash one, and see its restart strategy bring it back
---

# Supervise processes

A supervisor starts child processes and restarts a child that crashes. A
child is a function that loops on `receive`. Here each child keeps a running
sum and raises on a negative number:

```blue file=tally.b
def tally(parent, sum)
  n = receive()
  if n < 0
    raise(:negative, "cannot add #{n}")
  end
  send(parent, [:sum, self, sum + n])
  tally(parent, sum + n)
end

def add(worker, n)
  send(worker, n)
  receive([:sum, worker, :_])[2]
end

def crash(worker)
  send(worker, -1)
  receive(:never, 50)
end

def after_middle_crash(strategy)
  sup = supervisor(
    strategy,
    [[tally, [self, 0]], [tally, [self, 0]], [tally, [self, 0]]],
    3
  )
  workers = children(sup)
  map((w) -> add(w, 1), workers)
  crash(workers[1])
  map((w) -> add(w, 1), workers)
end

test "one_for_one restarts only the child that crashed"
  assert after_middle_crash(:one_for_one) == [2, 1, 2]
end

test "one_for_all restarts every child"
  assert after_middle_crash(:one_for_all) == [1, 1, 1]
end

test "rest_for_one restarts the crashed child and the ones after it"
  assert after_middle_crash(:rest_for_one) == [2, 1, 1]
end

test "past max_restarts the supervisor gives up"
  sup = supervisor(:one_for_one, [[tally, [self, 0]]], 1)
  worker = first(children(sup))
  crash(worker)
  assert alive?(worker)
  crash(worker)
  assert not alive?(worker)
end

def main()
  sup = supervisor(:one_for_one, [[tally, [self, 0]]], 3)
  worker = first(children(sup))
  add(worker, 2)
  write_stdout(unlines(["before the crash: #{add(worker, 3)}"]))
  crash(worker)
  write_stdout(unlines(["after the restart: #{add(worker, 4)}"]))
end
```

`supervisor(strategy, children, max_restarts)` starts each child from a
`[function, arguments]` pair and returns the supervisor's pid. `children(sup)`
gives the child pids in order. `crash` sends a negative number, then waits
50 ms for a message that never comes. The supervisor restarts the child in
that time.

Run it:

```console
$ blue run --quiet tally.b
before the crash: 5
after the restart: 4
```

The restarted child keeps its pid, so `add(worker, 4)` reaches it. It starts
again from its arguments, `[self, 0]`, with an empty mailbox, so its sum
starts again at 0. Blue also writes each crash to stderr, with the path of a
trace. `blue replay TRACE` runs the crash again.

The strategy says which children restart:

| Strategy | Restarts |
|---|---|
| `:one_for_one` | the child that crashed |
| `:one_for_all` | every child |
| `:rest_for_one` | the child that crashed and every child declared after it |

The tests crash the middle child of three, then add 1 to each child. A 2 is
a child that kept its sum. A 1 is a child that restarted. The last argument,
`max_restarts`, is 3 when you omit it. Past it, the supervisor stops and the
child stays down. The last test shows this with a limit of 1:

```console
$ blue test tally.b
4 test(s): 4 passed, 0 failed
```
