---
kind: howto
order: 5
summary: make a bidama reachable from other projects, and declare the registries that publish it
---

# Publish a bidama

A bidama is reachable when it sits under a `packages` root: a directory of
packages, each with its own `Bluefile`. A project finds packages through its
own `packages(...)` roots, then `BLUE_PATH`, then the distribution compiled
into `blue`.

Make a library of one package:

```console
$ mkdir lib
$ cd lib
$ blue new --bidama greet
created greet/: Bluefile, Bluefile.lock, greet.b
test it  blue test greet/greet.b
$ cd ..
```

Another project reaches it with `BLUE_PATH`:

```blue file=app.b
use("greet", [:greeting])

write_stdout(unlines([greeting(["ryn"])]))
```

```console
$ BLUE_PATH=lib blue app.b
hello, ryn
```

A project publishes itself with `registry(...)` entries in its `Bluefile`.
Each entry is one backend. The backend renders from the `Bluefile` and its
lock, which stay the truth. `package`'s third argument sets visibility once:

```blue file=lib/Bluefile
package("greetings", "0.1.0", :public)

packages(".")
registry(:sui, {outputs: ["default"]})
```

```console
$ cd lib
$ blue lock .
./Bluefile.lock: 0 source(s) pinned
```

`blue registry render --write` then writes each backend's publish workflow.
In blue's own distribution, a new package also needs a row in
`bidamas/NAMES.md`: the build is red without one. The full design is
[REGISTRY.md](../REGISTRY.md).
