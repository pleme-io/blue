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

## Reference

- [Canonical forms](CANONICAL-FORMS.md): every place the surface accepts two spellings, the one blue writes, and the rule that names it
- [Diagnostics](DIAGNOSTICS.md): what the check stage reports, every rule code, and the machine-readable shape of a diagnostic
- [blue examples](EXAMPLES.md): one tested program per common task, ready to paste as examples
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
