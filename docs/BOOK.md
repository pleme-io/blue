---
kind: reference
role: book
summary: the book: tutorials and how-to guides in full, then the reference and the explanation
---

# The blue Book

blue is a general-purpose language with a Ruby/Elixir surface that parses to a tatara-lisp tree and runs on a Rust runtime. It has one formatting, rigor where you write it, safety first, and most of its vocabulary in packages called bidamas.

Tutorials teach by doing, from an empty directory. How-to guides each do one task. Reference states the facts, and explanation gives the reasons. Every blue block and every console session in the first two parts runs in `blue test`, through the project's `docs` check.

## Contents

- Tutorials
  - [1. Install blue](#1-install-blue)
  - [2. A first script](#2-a-first-script)
  - [3. A first program](#3-a-first-program)
  - [4. A first bidama](#4-a-first-bidama)
  - [5. A first service](#5-a-first-service)
- How-to guides
  - [6. Write a test and a doctest](#6-write-a-test-and-a-doctest)
  - [7. Climb the blueshift](#7-climb-the-blueshift)
  - [8. Declare what a program may touch](#8-declare-what-a-program-may-touch)
  - [9. Write an action](#9-write-an-action)
  - [10. Publish a bidama](#10-publish-a-bidama)
  - [11. Run a pure worker](#11-run-a-pure-worker)
  - [12. Supervise processes](#12-supervise-processes)
  - [13. Virtualize a capability](#13-virtualize-a-capability)
  - [14. Test a refusal](#14-test-a-refusal)
- [Reference](#reference)
- [Explanation](#explanation)

## Tutorials

### 1. Install blue

You need [Nix](https://nixos.org) with flakes turned on. Install blue into
your profile:

```console host
$ nix profile install github:pleme-io/blue
```

To try blue without installing it, put `nix run github:pleme-io/blue --` in
front of each command below.

Ask blue for a value:

```console
$ blue eval '1 + 2'
3
```

Write a file called `hello.b`:

```blue file=hello.b
write_stdout(unlines(["Olá, mundo!"]))
```

Run it:

```console
$ blue hello.b
Olá, mundo!
```

That is a whole blue program. The next tutorial, [a first script](tutorial/first-script.md),
gives it arguments.


### 2. A first script

A script is one file that runs from the command line. It needs no project
and no configuration.

Write `greet.b`:

```blue file=greet.b
#!/usr/bin/env blue
def greeting(who)
  "hello, #{who}"
end

write_stdout(unlines([greeting(argv_get(0, "world"))]))
```

[`argv_get(0, "world")`](REFERENCE.md#environment-and-arguments) reads the first argument, or `"world"` when there is
none. Run the script with and without one:

```console
$ blue greet.b
hello, world
$ blue greet.b ryn
hello, ryn
```

The first line is a shebang. After `chmod +x greet.b`, the script also runs as
`./greet.b ryn`.

blue writes one formatting. Ask it whether the file is in that form:

```console
$ blue fmt --check greet.b
```

No output means yes. `blue fmt --write` puts a file into the form.

`blue new --script` starts a script for you, already executable and already
formatted:

```console
$ blue new --script tool.b
created tool.b, executable
run it   ./tool.b  (or blue tool.b)
$ blue tool.b a b
hello, a (2 argument(s))
```

A script can `use` every standard bidama with no setup. When a script
outgrows one file, it becomes [a first program](tutorial/first-program.md).


### 3. A first program

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
[a first bidama](tutorial/first-bidama.md) documents a package so others can use it.


### 4. A first bidama

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
now uses `prose` and no longer uses [`retsu`](../bidamas/CATALOG.md#retsu), so the check refuses the old
lock and names its fixer. Run it, then run the program:

```console
$ blue check --fix bidamas/shelf/shelf.b
$ blue main.b one two three
3 words
```

The next tutorial, [a first service](tutorial/first-service.md), declares a service
in the `Bluefile`.


### 5. A first service

A service is one declaration and one program. The declaration names what the
service needs; blue renders the chart, the settings schema, the image and
the checks from it. This tutorial builds a small copy of
[ola-mundo](https://github.com/pleme-io/ola-mundo), the reference blue service.

Make a directory for the service, and declare it in a `Bluefile`:

```console
$ mkdir hello
$ cd hello
```

```blue file=Bluefile
package("hello", "0.1.0")

service(
  "hello",
  {
    program: "hello.b",
    repository: "ghcr.io/example/hello",
    port: 8080,
    config: {greeting: "Olá", subject: "mundo"}
  }
)

check("hello", "hello.b")
```

The program answers `GET /`. [`settei`](../bidamas/CATALOG.md#settei) reads the settings the declaration
gives it, and [`kyuuji`](../bidamas/CATALOG.md#kyuuji) serves HTTP:

```blue file=hello.b
use("kyuuji")
use("settei")

def greeting(s, who)
  subject = if who == nil or who == ""
    settei::setting(s, "subject")
  else
    who
  end
  "#{settei::setting(s, "greeting")}, #{subject}!"
end

def handle(s, req)
  if get(req, :method) == "GET" and get(req, :path) == "/"
    kyuuji::text(200, unlines([greeting(s, kyuuji::query_param(req, "who"))]))
  else
    kyuuji::not_found(req)
  end
end

if settei::serving?
  s = settei::current
  kyuuji::serve_settings(s, (req) -> handle(s, req))
end

def settings()
  {"greeting" => "Olá", "subject" => "mundo"}
end

test "the root greets the configured subject"
  r = handle(settings, kyuuji::request("GET", "/", ""))
  assert get(r, :status) == 200
  assert get(r, :body) == unlines(["Olá, mundo!"])
end

test "any other path is not found"
  assert get(handle(settings, kyuuji::request("GET", "/x", "")), :status) ==
    404
end
```

The handler is a function from a request to a response, so the tests call
it directly. Lock the declaration and run the tests:

```console
$ blue lock .
./Bluefile.lock: 0 source(s) pinned
$ blue test hello.b
2 test(s): 2 passed, 0 failed
```

The [`haibi`](../bidamas/CATALOG.md#haibi) bidama renders the declaration into everything that ships the
service. This program lists the files it would write:

```blue file=../show.b
use("haibi", [:files])
use("retsu", [:first])

m = get(json_read(read_file("hello/Bluefile.lock")), "manifest")
spec = get(get(m, "services"), "hello")
paths = map(first, files("hello", get(m, "version"), spec))
write_stdout(unlines(sort_keyed((p) -> p, paths)))
```

```console
$ cd ..
$ blue show.b
chart/Chart.yaml
chart/files/dashboard.json
chart/templates/NOTES.txt
chart/templates/dashboard.yaml
chart/templates/deployment.yaml
chart/templates/service.yaml
chart/templates/serviceaccount.yaml
chart/templates/slo-rules.yaml
chart/values.schema.json
chart/values.yaml
config/hello.schema.json
config/hello.yaml
```

A real service adds a one-line `flake.nix` (`blue.lib.project { src = ./.; }`,
as ola-mundo has). Then nix builds the image and runs every check:

```console host
$ nix flake check
```

The [how-to guides](howto/test-and-doctest.md) each do one task from
here.

## How-to guides

### 6. Write a test and a doctest

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


### 7. Climb the blueshift

`blue shift` names the rung a file stands on: dynamic, annotated, checked or
restricted. You climb by annotating definitions.

Start with a file that declares nothing:

```blue file=area.b
def area(w, h)
  w * h
end

def square(s)
  area(s, s)
end
```

```console
$ blue shift area.b
█░░░ dynamic  (0/2 typed, 0 nodes analysed)
no annotations — no analysis runs, and nothing is checked

  · untyped declaration      `area` has no annotation — annotate it to shift further
  · untyped declaration      `square` has no annotation — annotate it to shift further
```

Annotate `area`. The file moves up one rung, and `blue shift` names what
still holds it back:

```blue file=area.b
def area(w: Int, h: Int) -> Int
  w * h
end

def square(s)
  area(s, s)
end
```

```console
$ blue shift area.b
██░░ annotated  (1/2 typed, 3 nodes analysed)
some declarations are typed; untyped ones are unchecked

  → type annotation          `area` is annotated, so it is checked
  · untyped declaration      `square` has no annotation — annotate it to shift further
```

Annotate `square` too, and every declaration is checked:

```blue file=area.b
def area(w: Int, h: Int) -> Int
  w * h
end

def square(s: Int) -> Int
  area(s, s)
end
```

```console
$ blue shift area.b
███░ checked  (2/2 typed, 6 nodes analysed)
every declaration is typed, so the whole file is checked

  → type annotation          `area` is annotated, so it is checked
  → type annotation          `square` is annotated, so it is checked
```

A wrong annotation is now an error before the program runs:

```blue file=bad.b
def half(n: Int) -> Int
  "half"
end
```

```console fails
$ blue check bad.b
error[B0003]: `half` declares it returns Int, but its body produces Str
```

The `pleme-io/actions/blue-shift` action holds a project to a floor rung in
CI.


### 8. Declare what a program may touch

A program that runs with no flag may reach every host capability. `--allow`
holds a run to the ones you name: `none`, `host`, or any of `process`,
`filesystem`, `environment`, `clock`, `network` and `entropy`.

Here is a program that reads a file:

```blue file=peek.b
write_stdout(read_file("note.txt"))
```

```blue file=note.txt
a note
```

With `--allow none`, blue refuses it before it runs, and names the flag that
grants it:

```console fails
$ blue run --allow none --quiet peek.b
refused: `read_file` reaches the host (filesystem)
```

Grant exactly what it needs:

```console
$ blue run --allow filesystem --quiet peek.b
a note
```

A script states its capabilities in its shebang, so `./peek.b` carries them
with it:

```blue file=peek2.b
#!/usr/bin/env -S blue --allow filesystem
write_stdout(read_file("note.txt"))
```

Every Rust guarantee, the blue gate that matches it and its off switch are in
[SAFETY.md](SAFETY.md). One access declaration for a whole service, in its
`service(...)` entry, is designed in
[SERVICE-ACCESS.md](SERVICE-ACCESS.md) and not built yet.


### 9. Write an action

A pleme-io action keeps its logic in a `run.b`. The [`koutei`](../bidamas/CATALOG.md#koutei) bidama is that
file's side of the step: it reads the `INPUT_*` variables, writes outputs and
the step summary, and fails the step.

Write `run.b`:

```blue file=run.b
use("koutei", [:fail, :input_or, :output])

who = input_or("who", "world")
if who == "nobody"
  fail("there is nobody to greet")
end
output("greeting", "hello, #{who}")
```

Run it the way the runner does: inputs as `INPUT_*` variables, outputs to the
file `GITHUB_OUTPUT` names.

```console
$ INPUT_WHO=ryn GITHUB_OUTPUT=out.txt blue run --quiet run.b
$ cat out.txt
greeting<<KOUTEI_EOF
hello, ryn
KOUTEI_EOF
```

With no `GITHUB_OUTPUT`, [`koutei`](../bidamas/CATALOG.md#koutei) prints the record, so a local run shows it:

```console
$ blue run --quiet run.b
greeting<<KOUTEI_EOF
hello, world
KOUTEI_EOF
```

A refused input fails the step with an error annotation:

```console fails
$ INPUT_WHO=nobody blue run --quiet run.b
::error::there is nobody to greet
```

The `action.yml` beside it passes the inputs and runs the file:

```yaml
runs:
  using: composite
  steps:
    - shell: bash
      env:
        INPUT_WHO: ${{ inputs.who }}
      run: blue run --quiet "${{ github.action_path }}/run.b"
```

`pleme-io/actions/blue-shift` is a complete example.


### 10. Publish a bidama

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
[REGISTRY.md](REGISTRY.md).


### 11. Run a pure worker

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

Now add a timestamp to the output. [`now_ms`](REFERENCE.md#time) reads the host clock:

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
worker, and give the worker the value. To keep [`now_ms`](REFERENCE.md#time) in a program and
still get the same output at each run, give it a stepped clock:
[Virtualize a capability](howto/virtualize-a-capability.md). The other capability
names are in [Declare what a program may touch](howto/declare-access.md).


### 12. Supervise processes

A supervisor starts child processes and restarts a child that crashes. A
child is a function that loops on [`receive`](REFERENCE.md#blue-processes-and-supervision). Here each child keeps a running
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

[`supervisor(strategy, children, max_restarts)`](REFERENCE.md#blue-processes-and-supervision) starts each child from a
`[function, arguments]` pair and returns the supervisor's pid. [`children(sup)`](REFERENCE.md#blue-processes-and-supervision)
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


### 13. Virtualize a capability

The Bluefile word `virtualize` binds a host capability to a pure provider.
With `using: :deterministic_stepped`, the first [`now_ms`](REFERENCE.md#time) is `at_ms`, and each
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

#### Scope the provider to one package

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


### 14. Test a refusal

Code says no in three ways: it raises an error of a kind, it returns a
refusal as data, or blue stops a run that reaches past its `--allow`. Each
has its own test.

#### An error raised by kind

[`raise(:kind, message)`](REFERENCE.md#errors) raises. `rescue :kind` catches only that kind.
[`tesuto::raises?`](../bidamas/CATALOG.md#tesuto) tells a test whether a function raises a kind, and
[`tesuto::caught`](../bidamas/CATALOG.md#tesuto) gives the test the error itself:

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

#### A refusal returned as data

Use [`kyohi`](../bidamas/CATALOG.md#kyohi) when a caller must see every fault, not only the first. A rule
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

#### A run that breaches its --allow

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

To test the hold, run blue from the test. [`self_exe`](REFERENCE.md#environment-and-arguments) is the blue that runs
the test, and [`exec_capture`](REFERENCE.md#processes) gives its exit status:

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

## Reference

- [Canonical forms](CANONICAL-FORMS.md): every place the surface accepts two spellings, the one blue writes, and the rule that names it
- [Diagnostics](DIAGNOSTICS.md): what the check stage reports, every rule code, and the machine-readable shape of a diagnostic
- [blue examples](EXAMPLES.md): one tested program per common task, ready to paste as examples
- [Glossary: blue's terms and the concepts they name](GLOSSARY.md): every blue term mapped to the compiler, language or distributed-systems concept it names, in both directions, and how the parts meet in a compile, a test run and a deploy
- [blue language reference](REFERENCE.md): syntax, operators, reserved words, every built-in name and the Bluefile words
- [Safety first: blue's posture, row by row](SAFETY.md): the safety-first posture, one row per Rust guarantee: blue today, the gate, its tier and its off switch
- [blue — the agent guide](../AGENTS.md): rules for people and agents who write blue programs or change blue itself, with the build commands from the Bluefile
- [Implementing blue — the detail behind the agent guide](implementing.md): the implementer detail behind the agent guide's "Changing blue itself": the check registry, crate map, hard-won rules, CI gates, dependencies and what is not built

## Explanation

- [ABSENCE — no undeclared nil](ABSENCE.md): no undeclared nil: how blue makes absence a declared, checked state
- [API-EVOLUTION — the API is a versioned rendering of the one model](API-EVOLUTION.md): the API as a versioned rendering of one model (design)
- [BIDAMA-COHESION — one word per job, foundations below, a complete vocabulary](BIDAMA-COHESION.md): one word per job, foundations below, a complete vocabulary across the bidamas (plan)
- [BUILD-ASSURANCE — what a blue build proves, how fast, and from which cache](BUILD-ASSURANCE.md): what a blue build proves, how fast, and from which cache (design)
- [BUILD-STACK — the default platform for a blue service, from Bluefile to a running node](BUILD-STACK.md): the default platform for a blue service, from Bluefile to a running node (design)
- [`Cargo.gen.lock` is committed, and that is a trade](CARGO-GEN-LOCK.md): why Cargo.gen.lock is committed, and what that trade costs
- [CLI-TUI — one way to build a command line and a terminal interface in blue](CLI-TUI.md): one way to build a command line and a terminal interface in blue (design, layer 1 built)
- [Competing languages — what blue takes, and what it refuses](COMPETING-LANGUAGES.md): what blue takes from competing languages on packaging and the standard library, and what it refuses
- [Compile time: Rust's static guarantees and Lua's runtime, in blue](COMPILE-TIME.md): Rust's static guarantees and Lua's runtime, brought into blue
- [Compounding: every evolution break fixes itself](COMPOUNDING.md): every break blue's evolution causes ships its own fixer
- [CST plan: a lossless tree, resilient parsing, surface blame](CST-PLAN.md): the design for a lossless CST with resilient parsing and surface blame; nothing is built yet
- [DOCUMENTATION — every blue project documents itself, and the language has a book](DOCUMENTATION.md): documentation as a battery: one source per fact, a Diátaxis book, rendered README, AGENTS.md and llms.txt (design)
- [FRONTEND-PLAN — building the blue frontend framework](FRONTEND-PLAN.md): the build plan for blue's frontend framework
- [HTTP2 — blue speaks HTTP/2 and gRPC itself](HTTP2.md): blue speaks HTTP/2 and gRPC itself (design, phase 1 built)
- [Lessons behind the agent guide's rules](LESSONS.md): the full story behind each rule the agent page states in short
- [MARKDOWN — Markdown is a first-class blue value](MARKDOWN.md): Markdown as a first-class blue value: one typed tree, one formatting, checked links, and renderings to Markdown, HTML, PDF and the terminal (design)
- [Namespaces: a bidama definition stays in its bidama](NAMESPACES.md): a bidama definition stays in its bidama: the rule as built and its gates
- [naturalize(tree-sitter) — the destination, before the build](NATURALIZE-TREESITTER.md): tree-sitter naturalized: the grammar spec and what is emitted from it
- [OPERATORS — short notation for what blue says most, keyed to the blueshift](OPERATORS.md): short notation for what blue says most, keyed to the blueshift (design)
- [Performance: blue as a scripting language and as a tool](PERFORMANCE.md): what blue costs today, where the time goes, and the order to remove it
- [Registry](REGISTRY.md): how a blue project is published and resolved: registries as renderings of the Bluefile
- [SERVICE-ACCESS — one access declaration, enforced by every layer that builds a service](SERVICE-ACCESS.md): one access declaration, enforced by every layer that builds a service (design)
- [SERVICE-ARCHITECTURE — the default blue service](SERVICE-ARCHITECTURE.md): the default blue service and the batteries it composes (design)
- [SERVICE-DATA — Postgres, Valkey and the nervous system as defaults](SERVICE-DATA.md): Postgres, Valkey and the nervous system as the configurable defaults of a blue service (design)
- [STDLIB: blue's batteries, as one verb vocabulary](STDLIB.md): the standard library's design as one verb vocabulary (design)
- [Testing and the SDLC: one blue pipeline](TESTING.md): every kind of test and its one place beside what it tests, and the Bluefile as the one pipeline
- [Blue verb roadmap: full software verbalization](VERB-ROADMAP.md): the roadmap to full software verbalization
- [vocabularify — the surface/structure vocabulary](VOCABULARIFY-SURFACE.md): kigou and yakugo: a program's spelling separated from its meaning
- [WORKSPACES — one root, many bidamas and many crates](WORKSPACES.md): one root holding many bidamas and many crates (design)
- [Region A: data and knowledge (578 verbs, 30 spaces, 875 edges)](verbs/A/REGION.md): verb graph region A: data and knowledge
- [Region B: storage and state (2026-10-22)](verbs/B/REGION.md): verb graph region B: storage and state
- [Blue verb graph: shared brief (read fully first)](verbs/BRIEF.md): the shared brief behind the verb graph
- [Region C: communication and distributed systems](verbs/C/REGION.md): verb graph region C: communication and distributed systems
- [Region D: security and trust (2026-10-22)](verbs/D/REGION.md): verb graph region D: security and trust
- [Region E: build, ship and run (346 verbs, 567 edges, 29 spaces)](verbs/E/REGION.md): verb graph region E: build, ship and run
- [Region F: OBSERVE, TEST, QUALITY AND THE ENGINEERING PROCESS](verbs/F/REGION.md): verb graph region F: observe, test, quality and process
- [Region G: interfaces, intelligence and the physical world](verbs/G/REGION.md): verb graph region G: interfaces, intelligence and the physical world
- [H: the verb GRAPH as data blue owns (META region)](verbs/H/DESIGN.md): the verb graph as data blue owns
- [Merged graph: repairs and decisions (H0a)](verbs/merged/CHANGES.md): the merged verb graph: repairs and decisions
- [Naming sweep: what is applied and what the operator decided](verbs/names/RULINGS.md): the naming sweep of the verb graph's spaces, and the rulings
