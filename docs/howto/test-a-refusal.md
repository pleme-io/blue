---
kind: howto
order: 9
summary: test that code refuses correctly, for an error raised by kind, a kyohi refusal returned as data, and a run held by --allow that breaches with exit 77
---

# Test a refusal

Code says no in three ways: it raises an error of a kind, it returns a
refusal as data, or blue stops a run that reaches past its `--allow`. Each
has its own test.

## An error raised by kind

`raise(:kind, message)` raises. `rescue :kind` catches only that kind.
`tesuto::raises?` tells a test whether a function raises a kind, and
`tesuto::caught` gives the test the error itself:

```blue file=port.b
use("tesuto", %i[caught raises?])

def port(text)
  n = to_int(text)
  if n.nil? or n < 1 or n > 65535
    raise(:bad_option, "port #{text} is not a number from 1 to 65535")
  end
  n
end

def port_or_default(text)
  port(text)
rescue :bad_option
  8080
end

test "a port past 65535 raises :bad_option"
  assert raises?(:bad_option, () -> port("70000"))
end

test "an empty port raises :bad_option"
  assert raises?(:bad_option, () -> port(""))
end

test "the error names the text it refused"
  e = caught(() -> port("http"))
  assert e.kind == :bad_option
  assert e.message == "port http is not a number from 1 to 65535"
end

test "a caller that rescues the kind gets the default"
  assert port_or_default("http") == 8080
  assert port_or_default("443") == 443
end
```

```console
$ blue test port.b
4 test(s): 4 passed, 0 failed
```

## A refusal returned as data

Use `kyohi` when a caller must see every fault, not only the first. A rule
takes the subject and returns a list of refusals, empty when the subject is
sound. `check` runs every rule and returns every refusal. `enforce` is its
raising form: one `:refused` error that carries the refusals as its data.

```blue file=signup.b
use("kyohi", %i[check enforce kinds refusal])
use("tesuto", [:caught])

def named(user)
  if user.name == ""
    [refusal(:blank_name, "a user needs a name")]
  else
    []
  end
end

def adult(user)
  if user.age < 18
    [refusal(:too_young, "#{user.age} is under 18")]
  else
    []
  end
end

def rules()
  [named, adult]
end

test "a sound user has no refusals"
  assert check({name: "ana", age: 30}, rules) == []
end

test "every refusal comes back, not only the first"
  assert kinds(check({name: "", age: 12}, rules)) == %i[blank_name too_young]
end

test "enforce raises one error that carries every refusal"
  e = caught(() -> enforce({name: "", age: 12}, rules))
  assert e.kind == :refused
  assert kinds(e.data) == %i[blank_name too_young]
end
```

```console
$ blue test signup.b
3 test(s): 3 passed, 0 failed
```

## A run that breaches its --allow

A host call in your own file is refused in the check stage, before the run,
and blue exits 1. A host call reached through a package is refused where it
is called. That is a capability breach, and blue exits 77.

Here the `ledger` package reads the clock:

```blue file=Bluefile
package("books", "0.1.0")
packages("bidamas")
```

```blue file=bidamas/ledger/Bluefile
package("ledger", "0.1.0")
```

```blue file=bidamas/ledger/ledger.b
def entry(text)
  "#{now_ms} #{text}"
end
```

```blue file=main.b
use("ledger", [:entry])

def main()
  write_stdout(unlines([entry("opened")]))
end
```

```blue file=direct.b
def main()
  write_stdout(unlines(["#{now_ms} opened"]))
end
```

Held to no capability, the run stops at the call in `ledger`. The error
names the call, the capability and each caller:

```console fails
$ blue run --allow none --quiet main.b
capability breach: `now_ms` reaches the host (clock), which this run's frame does not grant
  at main (main.b:4:25)
```

To test the hold, run blue from the test. `self_exe` is the blue that runs
the test, and `exec_capture` gives its exit status:

```blue file=held.b
use("shisutemu", %i[status_of stderr_of])

def held(file, allow)
  exec_capture(self_exe, "run", "--allow", allow, "--quiet", file)
end

test "the clock reached through ledger breaches a run held to none"
  cap = held("main.b", "none")
  assert status_of(cap) == 77
  assert contains?(stderr_of(cap), "capability breach")
end

test "a clock written in the file is refused before the run"
  assert status_of(held("direct.b", "none")) == 1
end

test "the same run succeeds once it grants the clock"
  assert status_of(held("main.b", "clock")) == 0
end
```

```console
$ blue test held.b
3 test(s): 3 passed, 0 failed
```
