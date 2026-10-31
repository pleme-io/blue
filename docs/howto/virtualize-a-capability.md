---
kind: howto
order: 8
summary: give a program a stepped clock with the Bluefile word virtualize, so now_ms is the same at every run, and scope it to one package with for:
---

# Virtualize a capability

The Bluefile word `virtualize` binds a host capability to a pure provider.
With `using: :deterministic_stepped`, the first `now_ms` is `at_ms`, and each
read after it adds `step_ms`. The program reads the same times at every run.

```blue file=Bluefile
package("stamps", "0.1.0")
packages("bidamas")
virtualize(:clock, {using: :deterministic_stepped, at_ms: 1000, step_ms: 5})
```

```blue file=main.b
def main()
  write_stdout(unlines(["#{now_ms}", "#{now_ms}", "#{now_ms}"]))
end
```

Lock the project, then run it. `blue lock` checks the declaration and records
the provider in `Bluefile.lock`. A Bluefile with no `source` locks offline.

```console
$ blue lock .
./Bluefile.lock: 0 source(s) pinned
$ blue run --quiet main.b
1000
1005
1010
```

The provider is not the host. So the same program runs under `--allow none`:

```console
$ blue run --allow none --quiet main.b
1000
1005
1010
```

## Scope the provider to one package

`for:` gives the provider only to the packages it names, and to what they
use. The rest of the program gets the host clock, or a refusal when the
Bluefile does not `allow` it. Here `allow([])` grants nothing, and only the
`ledger` package gets the stepped clock:

```blue file=books/Bluefile
package("books", "0.1.0")
packages("bidamas")
allow([])

virtualize(
  :clock,
  {using: :deterministic_stepped, at_ms: 0, step_ms: 1000, for: ["ledger"]}
)
```

A package under `bidamas/` has its own Bluefile. Without one, `blue lock`
counts the package's code as the root's.

```blue file=books/bidamas/ledger/Bluefile
package("ledger", "0.1.0")
```

```blue file=books/bidamas/ledger/ledger.b
def entry(text)
  "#{now_ms} #{text}"
end
```

```blue file=books/main.b
use("ledger", [:entry])

def main()
  write_stdout(unlines([entry("opened"), entry("paid"), entry("closed")]))
end
```

```console
$ blue lock books
books/Bluefile.lock: 0 source(s) pinned
$ blue run --quiet books/main.b
0 opened
1000 paid
2000 closed
```

Now read the clock in the root itself:

```blue file=books/late.b
use("ledger", [:entry])

def main()
  write_stdout(unlines([entry("opened"), "#{now_ms} closed"]))
end
```

The run refuses it in the check stage, and `blue lock` refuses the project:

```console fails
$ blue run --quiet books/late.b
books/late.b: refused: `now_ms` reaches the host (clock), which this run does not allow; pass --allow clock to grant it
$ blue lock books
blue: [books::main: needs 'clock'] violates ceiling [] (clock is virtualized only for [ledger] and what they use)
```

The other providers are `:seeded_prng` for `:entropy`, and
`:in_memory_overlay` and `:null_sink` for `:filesystem`.
`blue reference` lists each one with its options, under `bluefile`.
