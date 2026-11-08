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
  - [6. A first kernel program](#6-a-first-kernel-program)
- How-to guides
  - [7. Write a test and a doctest](#7-write-a-test-and-a-doctest)
  - [8. Climb the blueshift](#8-climb-the-blueshift)
  - [9. Declare what a program may touch](#9-declare-what-a-program-may-touch)
  - [10. Write an action](#10-write-an-action)
  - [11. Publish a bidama](#11-publish-a-bidama)
  - [12. Run a pure worker](#12-run-a-pure-worker)
  - [13. Supervise processes](#13-supervise-processes)
  - [14. Virtualize a capability](#14-virtualize-a-capability)
  - [15. Test a refusal](#15-test-a-refusal)
  - [16. Pick a kernel hook](#16-pick-a-kernel-hook)
  - [17. Read a kernel field](#17-read-a-kernel-field)
  - [18. Debug a kernel refusal](#18-debug-a-kernel-refusal)
  - [19. Ship a node agent](#19-ship-a-node-agent)
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
gives it, and `kyuuji` serves HTTP:

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

The `haibi` bidama renders the declaration into everything that ships the
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


### 6. A first kernel program

A kernel program is a function in blue. Blue compiles it to BPF. The same source
then runs in two places: a pure machine that needs no kernel, and a real Linux
kernel. This tutorial writes a program that counts packets by protocol and drops
ICMP. You need no root and no Linux until the last section.

`blue new --kernel` starts a project that passes its tests as written:

```console
$ blue new --kernel pkts
created pkts/: Bluefile, Bluefile.lock, flake.nix, pkts.b
test it  cd pkts && blue test pkts.b
run it   cd pkts && sudo blue run --allow host --quiet pkts.b -- eth0
$ cd pkts
$ blue test --filter "on the machine" pkts.b
2 test(s): 2 passed, 0 failed
```

The `--filter` keeps the two tests that run on the machine. The file holds one
more test, and that test needs a kernel. Without `--filter`, a host with no kernel
says which test it skipped and why, and the tally counts it apart from a pass:

```console host
$ blue test pkts.b
SKIP on a real kernel, the program counts what the machine counts: no kernel here: this host is not Linux
3 test(s): 2 passed, 0 failed, 1 skipped
```

Now make the program drop ICMP. Replace `pkts.b` with this:

```blue file=pkts.b
use(
  "bpf",
  %i[compile declare_map map_add packet_int packet_len xdp_drop xdp_pass]
)

use("kaaneru", %i[attached install kernel_absence])
use("retsu", %i[first repeat])
use("tesuto", [:skip_for])

COUNTS = declare_map(:counts, :array, 4, 8, 256)

ICMP = 1

def filter_packets(ctx)
  if packet_len(ctx) < 34
    xdp_pass
  else
    protocol = packet_int(ctx, 23, 1)
    map_add(COUNTS, protocol, 1)
    if protocol == ICMP
      xdp_drop
    else
      xdp_pass
    end
  end
end

def program()
  compile("pkts.b", {entry: :filter_packets, kind: :xdp, on_fault: xdp_pass})
end

def frame(protocol)
  append(*[repeat(0, 23), [protocol], repeat(0, 10)])
end

def main()
  index = to_int(trim(read_file("/sys/class/net/#{first(argv)}/ifindex")))
  attached(
    program,
    {xdp: index},
    fn(live)
      sleep_ms(5000)
      dropped = kaaneru::map_int(live, :counts, ICMP)
      write_stdout(unlines(["ICMP packets dropped: #{to_s(dropped)}"]))
    end
  )
end

test "on the machine, ICMP is counted and dropped"
  p = program
  st = bpf::run(p, {packet: frame(ICMP), maps: p[:maps]})
  assert st.ret == xdp_drop
  assert bpf::map_int(st, :counts, ICMP) == 1
end

test "on the machine, TCP is counted and passed"
  p = program
  st = bpf::run(p, {packet: frame(6), maps: p[:maps]})
  assert st.ret == xdp_pass
  assert bpf::map_int(st, :counts, 6) == 1
  assert bpf::map_int(st, :counts, ICMP) == 0
end

test "on the machine, a frame too short for the field is passed and not counted"
  p = program
  st = bpf::run(p, {packet: repeat(0, 20), maps: p[:maps]})
  assert st.ret == xdp_pass
  assert bpf::map_int(st, :counts, 0) == 0
end

test "on a real kernel, the program decides as the machine decides"
  skip_for(kernel_absence)
  live = install(program)
  assert kaaneru::run(live[:prog], {packet: frame(ICMP)})[:ret] == xdp_drop
  assert kaaneru::run(live[:prog], {packet: frame(6)})[:ret] == xdp_pass
  assert kaaneru::map_int(live, :counts, ICMP) == 1
end
```

Each part has one job:

- `declare_map` states a map's shape: the machine and the kernel read the same
  shape.
- `filter_packets` is the kernel program. It runs only when compiled, and the
  compiler writes the bounds check each packet read needs.
- `compile` turns it into BPF and checks it first. `on_fault` is what the program
  answers when a read falls outside the packet.
- `bpf::run` runs the program on the pure machine. `bpf::map_int` reads a map on
  it.
- `attached` loads the program onto one hook, runs a function, and takes the
  program away whatever the function does.
- [`kaaneru::map_int`](../bidamas/CATALOG.md#kaaneru) reads a map in the kernel, with the same arguments.

Run the tests:

```console
$ blue test --filter "on the machine" pkts.b
3 test(s): 3 passed, 0 failed
```

A program the kernel cannot take stops before it reaches the kernel. Blue
fractions have no BPF form, so this program never compiles:

```blue file=../fraction.b
use("bpf", [:compile])

def half(_ctx)
  7 / 2
end

compile("fraction.b", {entry: :half, kind: :xdp, on_fault: 0})
```

```console
$ cd ..
```

```console fails
$ blue fraction.b
bpf_compile
fraction
```

#### On a real kernel

This section needs Linux and root. The test that needs a kernel runs the program
through `BPF_PROG_RUN`, which attaches nothing:

```console host
$ cd pkts
$ sudo blue test pkts.b
4 test(s): 4 passed, 0 failed
```

To see real packets, make a network namespace, so nothing on your host sees the
hook. Run the loader in one terminal:

```console host
$ sudo ip netns add demo
$ sudo ip netns exec demo ip link set lo up
$ sudo ip netns exec demo blue run --allow host --quiet pkts.b -- lo
ICMP packets dropped: 3
```

While the loader waits five seconds, ping from a second terminal. The pings get
no answer, and when the loader ends the program is gone:

```console host
$ sudo ip netns exec demo ping -c 3 -W 1 127.0.0.1
$ sudo ip netns del demo
```

Next: [pick a hook](howto/pick-a-kernel-hook.md),
[read a kernel field](howto/read-a-kernel-field.md),
[debug a refusal](howto/debug-a-kernel-refusal.md) and
[ship a node agent](howto/ship-a-node-agent.md). The words and what each has
been measured on are in [KERNEL.md](KERNEL.md).

## How-to guides

### 7. Write a test and a doctest

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

A test that cannot run on this host says why, and the tally counts it apart from
a pass. Here the reason is always there; [`kaaneru::kernel_absence`](../bidamas/CATALOG.md#kaaneru) gives a real one:

```blue file=needs.b
use("tesuto", [:skip_for])

def why_not()
  "this host has no such device"
end

test "it needs a device"
  skip_for(why_not)
  assert false
end

test "it needs nothing"
  assert true
end
```

```console
$ blue test needs.b
2 test(s): 1 passed, 0 failed, 1 skipped
```

On a host where every test must run, make each skip a failure:

```console fails
$ BLUE_TEST_SKIP=refuse blue test needs.b
skipped under BLUE_TEST_SKIP=refuse: this host has no such device
```

`blue test DIR` runs every file under a directory that holds a test, in
parallel.


### 8. Climb the blueshift

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


### 9. Declare what a program may touch

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


### 10. Write an action

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


### 11. Publish a bidama

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


### 12. Run a pure worker

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


### 13. Supervise processes

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


### 14. Virtualize a capability

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


### 15. Test a refusal

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


### 16. Pick a kernel hook

A hook is where the kernel runs your program. Pick it from what the program must
see, and compile for the kind that hook takes:

| You want to | Hook spec | Program kind | Target |
|---|---|---|---|
| decide about a packet first, at the driver | `{xdp: index}` | `:xdp` | an interface index |
| decide about a packet at traffic control | `{tcx_ingress: index}`, `{tcx_egress: index}` | `:sched_cls` | an interface index |
| hold one group of processes to a network rule | `{cgroup_inet_ingress: path}`, `{cgroup_inet_egress: path}` | `:cgroup_skb` | a cgroup directory |
| refuse a socket or a device to a group of processes | `{cgroup_inet_sock_create: path}`, `{cgroup_device: path}` | `:cgroup_sock`, `:cgroup_device` | a cgroup directory |
| decide at a netfilter hook | `{netfilter: {family: :ipv4, hook: :local_in, priority: -100}}` | `:netfilter` | the hook's place |
| count an event the kernel names | `{tracepoint: ["sched", "sched_process_exec"]}`, `{raw_tracepoint: "sched_process_exec"}` | `:tracepoint`, `:raw_tracepoint` | the event |
| watch a kernel function | `{kprobe: name}`, `{fentry: name}`, `{fexit: name}` | `:kprobe`, `:tracing` | the function |
| replace a test function's answer | `{fmod_ret: name}` | `:tracing` | the function |
| deny an operation, such as opening a file | `{lsm: "file_open"}` | `:lsm` | the LSM hook |
| walk kernel objects | `{iter: "task"}` | `:tracing` | the iterator |

[`kaaneru::hooks`](../bidamas/CATALOG.md#kaaneru) holds this table as data. Each row's kind is checked here against
it:

```blue file=hooks.b
use("kaaneru", %i[hook_row hooks])
use("retsu", [:size])

def kind_of(spec, kind)
  hook_row({kind:}, spec).kind == kind
end

test "each spec in the table takes the kind the table names"
  assert kind_of({xdp: 1}, :xdp)
  assert kind_of({tcx_ingress: 1}, :sched_cls)
  assert kind_of({tcx_egress: 1}, :sched_cls)
  assert kind_of({cgroup_inet_ingress: "/c"}, :cgroup_skb)
  assert kind_of({cgroup_inet_egress: "/c"}, :cgroup_skb)
  assert kind_of({cgroup_inet_sock_create: "/c"}, :cgroup_sock)
  assert kind_of({cgroup_device: "/c"}, :cgroup_device)
  assert kind_of({netfilter: {}}, :netfilter)
  assert kind_of({tracepoint: ["a", "b"]}, :tracepoint)
  assert kind_of({raw_tracepoint: "a"}, :raw_tracepoint)
  assert kind_of({kprobe: "f"}, :kprobe)
  assert kind_of({fentry: "f"}, :tracing)
  assert kind_of({fexit: "f"}, :tracing)
  assert kind_of({fmod_ret: "f"}, :tracing)
  assert kind_of({lsm: "file_open"}, :lsm)
  assert kind_of({iter: "task"}, :tracing)
end

test "the table is every hook"
  assert size(hooks) == 16
end
```

```console
$ blue test hooks.b
2 test(s): 2 passed, 0 failed
```

Attach with [`kaaneru::attached(compiled, spec, body)`](../bidamas/CATALOG.md#kaaneru). A spec and a kind that do
not fit stop before any call to the kernel, on any host:

```blue file=wrong.b
use("kaaneru", [:attached])

attached({kind: :xdp}, {lsm: "file_open"}, (live) -> live)
```

```console fails
$ blue wrong.b
the lsm hook takes a lsm program, and this one is xdp
```

A spec names one hook, and the refusal lists every hook when it names none or two.

The machine runs a program of any kind that reads its packet or its own memory.
It cannot run a kernel pointer, so a `:netfilter` program that reads the live
`sk_buff` is tested on a real kernel. `BPF_PROG_RUN` refuses `:lsm` with
`ENOTSUPP`, and [`kaaneru::run`](../bidamas/CATALOG.md#kaaneru) runs `:tracing` only at the kernel's test functions:
a test of those kinds attaches. Which word and which hook each has run on, with
the test that shows it, is the ledger in [KERNEL.md](KERNEL.md).

Other attachments have their own words, each with a `blue doc` page:
`attach_uprobes`, `attach_kprobes`, `attach_sampling` and `install_struct_ops`.


### 17. Read a kernel field

`kernel_read(pointer, struct, path, size)` reads one field of a kernel struct.
You name the field. The offset comes from the running kernel's BTF when the program
loads, so the program does not hold an offset that another kernel moved.

```blue file=whoami.b
use("bpf", %i[bind_fields compile helper kernel_read])

def task_pid(_ctx)
  kernel_read(helper(:get_current_task), "task_struct", ["pid"], 4)
end

def program()
  compile("whoami.b", {entry: :task_pid, kind: :tracing, on_fault: 0})
end

def task_at(offset)
  (_struct, _path) -> {offset:, size: 4}
end

test "the program names the field it reads"
  field = program[:fields][0]
  assert field[:struct] == "task_struct"
  assert field[:path] == ["pid"]
end

test "bound to an offset, the program reads the field there"
  memory = {at: 805_306_368, bytes: [0, 0, 0, 0, 42, 0, 0, 0]}
  assert bpf::run(bind_fields(program, task_at(4)), {kernel: memory}).ret == 42
end

test "a read past the struct is the fault answer, never a wrong value"
  memory = {at: 805_306_368, bytes: [1]}
  assert bpf::run(bind_fields(program, task_at(4)), {kernel: memory}).ret == 0
end

test "a field of another size on this kernel refuses to bind"
  other = (_struct, _path) -> {offset: 4, size: 8}
  assert (bind_fields(program, other) rescue :refused) == :refused
end
```

```console
$ blue test whoami.b
4 test(s): 4 passed, 0 failed
```

The tests give the machine a piece of kernel memory and an offset. `bind_fields`
does what a load does: it writes each offset into the program, and it refuses a
field whose size differs from what the program reads.

On a real kernel, `attached` finds the field in this kernel's BTF for you. This
program counts nothing and only reports. It needs Linux and root:

```blue file=watch.b
use("baito", [:bytes_int])
use("bpf", %i[compile declare_map emit helper kernel_read])
use("kaaneru", %i[attached map_named next_event open_events])

EVENTS = declare_map(:events, :ringbuf, 0, 0, 65536)

def on_open(_ctx)
  emit(EVENTS, [kernel_read(helper(:get_current_task), "task_struct", ["pid"], 4)])
  0
end

def main()
  compiled = compile("watch.b", {entry: :on_open, kind: :tracing, on_fault: 0})
  attached(
    compiled,
    {fentry: "do_sys_openat2"},
    fn(live)
      ring = open_events(map_named(live, :events))
      read_file("/proc/version")
      got = next_event(ring, 2000)
      write_stdout(unlines(["a thread opened a file: #{to_s(bytes_int(got, 0, 8) > 0)}"]))
    end
  )
end
```

```console host
$ sudo blue run --allow host --quiet watch.b
a thread opened a file: true
```

A struct or a member this kernel does not have raises `:not_found` at load, and
names it. `blue doc btf::field` shows how to read a field's place by hand.


### 18. Debug a kernel refusal

Three layers can say no, and each names its error kind. Find the layer first:

| Error kind | Who says it | When |
|---|---|---|
| `:bpf_compile` | blue's compiler | at `compile`, on any host |
| `:bpf_fault` | the pure machine | at `bpf::run`, on any host |
| `:kernel_refused` | the kernel's verifier | at load, on Linux |
| `:kernel_mismatch` | the loader | a field has another size on this kernel |
| `:unsupported` | the host | off Linux, at any word that reaches the kernel |

#### The compiler

`:bpf_compile` names the construct. Most refusals come from a value the verifier
would have to bound. Here `*` has operands of unknown range, and the compiler asks
you to bound them or to say that wrapping is what you want:

```blue file=product.b
use("bpf", %i[compile packet_int])

def product(ctx)
  packet_int(ctx, 0, 8) * packet_int(ctx, 8, 8)
end

compile("product.b", {entry: :product, kind: :xdp, on_fault: 0})
```

```console fails
$ blue product.b
bpf_compile
cannot be checked in a kernel program
```

#### The machine

`:bpf_fault` means an assembled program did something the machine does not allow.
The machine does not check as much as the verifier does, so this layer finds
faults and does not promise a load:

```blue file=fault.b
use("bpf", %i[assemble exit_program load])

def outside()
  assemble([load(:b, 0, 1, 99999), exit_program])
end

test "a read outside every region is a fault, and the message says where"
  got = begin
    bpf::run(outside)
  rescue :bpf_fault as e
    e.message
  end
  assert contains?(got, "outside every region")
end
```

```console
$ blue test fault.b
1 test(s): 1 passed, 0 failed
```

#### The verifier

`:kernel_refused` carries the errno's name and the verifier's whole log as data:
`e.data.name` and `e.data.log`. This program reads a register nothing wrote. It
needs Linux and root:

```blue file=refused.b
use("bpf", %i[alu assemble exit_program r])
use("kaaneru")

def main()
  kaaneru::load(
    assemble([alu(:mov, 0, r(5)), exit_program]),
    {kind: :xdp, name: "refused"}
  )
rescue :kernel_refused as e
  write_stdout(unlines([e.data.name, e.data.log]))
end
```

```console host
$ sudo blue run --allow host --quiet refused.b
EACCES
0: R1=ctx() R10=fp0
0: (bf) r0 = r5
R5 !read_ok
processed 1 insns (limit 1000000) max_states_per_insn 0 total_states 0 peak_states 0 mark_read 0
```

Read the log from the end. The last instruction it names is the one that failed,
and the line after it is the reason. `R5 !read_ok` says that nothing wrote `r5`.
The lines above show what the verifier knew about each register at each step.

To see the instructions by number, print the program:

```blue file=text.b
use("bpf", %i[alu assemble disassemble encode exit_program r])

test "the listing numbers each instruction as the log does"
  listed = disassemble(encode(assemble([alu(:mov, 0, r(5)), exit_program])))
  assert listed == ["r0 = r5", "exit"]
end
```

```console
$ blue test text.b
1 test(s): 1 passed, 0 failed
```

`kernel_absence` says why a host cannot load at all. A test passes it to
[`tesuto::skip_for`](../bidamas/CATALOG.md#tesuto), so the test is skipped by name and not passed. `BLUE_TEST_SKIP=refuse` turns each skip into a
failure, for a host where every test must run.


### 19. Ship a node agent

A node agent is a service that loads kernel programs on each node. You declare
the `:kernel_bpf` effect in its `Bluefile`, and blue renders the rest: a DaemonSet,
`CAP_BPF`, `CAP_PERFMON` and `CAP_NET_ADMIN`, and the `bpffs` and `tracefs` mounts.
The rendered chart is checked here. No cluster has run it yet, so test it on yours
first.

```console
$ mkdir agent
$ cd agent
```

```blue file=Bluefile
package("agent", "0.1.0")

service(
  "agent",
  {
    program: "agent.b",
    repository: "ghcr.io/example/agent",
    port: 8080,
    access: {
      effects: %i[network clock entropy environment kernel_bpf],
      host_network: true
    },
    runtime: :native,
    because: :device
  }
)

check("agent", "agent.b")
```

`runtime: :native` with `because: :device` is required: WASI reaches no kernel
ABI. The program answers health checks like any service. Load your kernel program
beside `serve_settings` with the words in
[the first kernel program](tutorial/first-kernel-program.md).

```blue file=agent.b
use("kyuuji")
use("settei")

def handle(req)
  if req[:path] == "/"
    kyuuji::text(200, unlines(["agent"]))
  else
    kyuuji::not_found(req)
  end
end

if settei::serving?
  kyuuji::serve_settings(settei::current, handle)
end

test "the root answers, and anything else is not found"
  assert handle(kyuuji::request("GET", "/", ""))[:status] == 200
  assert handle(kyuuji::request("GET", "/x", ""))[:status] == 404
end
```

```console
$ blue lock .
./Bluefile.lock: 0 source(s) pinned
$ blue test agent.b
1 test(s): 1 passed, 0 failed
```

This program shows what the declaration renders:

```blue file=../show.b
use("haibi", %i[container_security files workload_kind])
use("retsu", [:first])

m = get(json_read(read_file("agent/Bluefile.lock")), "manifest")
spec = get(get(m, "services"), "agent")
paths = map(first, files("agent", get(m, "version"), spec))
write_stdout(unlines(filter((p) -> contains?(p, "daemonset"), paths)))
write_stdout(unlines([workload_kind(spec)]))
write_stdout(unlines(container_security(spec)["capabilities"]["add"]))
```

```console
$ cd ..
$ blue show.b
chart/templates/daemonset.yaml
DaemonSet
BPF
PERFMON
NET_ADMIN
```

`host_network` and `per_node` mean nothing without the effect, so a service that
writes one without `:kernel_bpf` is refused by name when it locks:

```blue file=refused/Bluefile
package("refused", "0.1.0")

service(
  "refused",
  {
    program: "refused.b",
    repository: "ghcr.io/example/refused",
    port: 8080,
    access: {host_network: true}
  }
)
```

```blue file=refused/refused.b
def noop()
  nil
end

test "it passes"
  assert noop.nil?
end
```

```console fails
$ blue lock refused
lacks the :kernel_bpf effect
```

A real agent adds the one-line `flake.nix` that `blue new --kernel` writes. Then
nix builds the image and checks the chart against this shape:

```console host
$ nix flake check
```

`per_node: false` keeps the service a Deployment. The fields are in
[SERVICE-ACCESS.md](SERVICE-ACCESS.md), and which capability each kind of hook
needs is in [KERNEL.md](KERNEL.md) §3.

## Reference

- [Canonical forms](CANONICAL-FORMS.md): every place the surface accepts two spellings, the one blue writes, and the rule that names it
- [Commands](COMMANDS.md): every blue verb with its flags, one row each; the agents page keeps one line per verb and links here
- [Diagnostics](DIAGNOSTICS.md): what the check stage reports, every rule code, and the machine-readable shape of a diagnostic
- [blue examples](EXAMPLES.md): one tested program per common task, ready to paste as examples
- [Glossary: blue's terms and the concepts they name](GLOSSARY.md): every blue term mapped to the compiler, language or distributed-systems concept it names, in both directions, and how the parts meet in a compile, a test run and a deploy
- [blue language reference](REFERENCE.md): syntax, operators, reserved words, every built-in name and the Bluefile words
- [blue roadmap](ROADMAP.md): the one blue roadmap, one row per track with its tier, next step and done gate, and every conflict ruled once
- [Safety first: blue's posture, row by row](SAFETY.md): the safety-first posture, one row per Rust guarantee: blue today, the gate, its tier and its off switch
- [blue — the agent guide](../AGENTS.md): rules for people and agents who write blue programs or change blue itself, with the build commands from the Bluefile
- [Implementing blue — the detail behind the agent guide](implementing.md): the implementer detail behind the agent guide's "Changing blue itself": the check registry, crate map, hard-won rules, CI gates, dependencies and what is not built

## Explanation

- [ABSENCE — no undeclared nil](ABSENCE.md): no undeclared nil: how blue makes absence a declared, checked state
- [API-EVOLUTION — the API is a versioned rendering of the one model](API-EVOLUTION.md): the API as a versioned rendering of one model (design)
- [arika (在り処): the design of record](ARIKA.md): arika, blue's word search, Phase 1 built and the rest DESIGN: the recon, phases, gates with red runs, risks and every surface that names it
- [Native async: the design of record](ASYNC.md): Native async in blue, DESIGN: one ontology of every async concept as a blue word over parked processes, the mutually exclusive architectures as blueshift positions with defaults, the integration with every system blue already has, and one test matrix that runs every position against the same oracle
- [BIDAMA-COHESION — one word per job, foundations below, a complete vocabulary](BIDAMA-COHESION.md): one word per job, foundations below, a complete vocabulary across the bidamas (plan)
- [BUILD-ASSURANCE — what a blue build proves, how fast, and from which cache](BUILD-ASSURANCE.md): what a blue build proves, how fast, and from which cache (design)
- [BUILD-STACK — the default platform for a blue service, from Bluefile to a running node](BUILD-STACK.md): the default platform for a blue service, from Bluefile to a running node (design)
- [`Cargo.gen.lock` is committed, and that is a trade](CARGO-GEN-LOCK.md): why Cargo.gen.lock is committed, and what that trade costs
- [CLI-TUI — one way to build a command line and a terminal interface in blue](CLI-TUI.md): one way to build a command line and a terminal interface in blue (design, layer 1 built)
- [Competing languages — what blue takes, and what it refuses](COMPETING-LANGUAGES.md): what blue takes from competing languages on packaging and the standard library, and what it refuses
- [Compile time: Rust's static guarantees and Lua's runtime, in blue](COMPILE-TIME.md): Rust's static guarantees and Lua's runtime, brought into blue
- [Compounding: every evolution break fixes itself](COMPOUNDING.md): every break blue's evolution causes ships its own fixer
- [CST plan: a lossless tree, resilient parsing, surface blame](CST-PLAN.md): the design for a lossless CST with resilient parsing and surface blame; nothing is built yet
- [The data framework: one model, every rendering, nothing written twice](DATA-FRAMEWORK.md): the design of the data framework, one blue model rendered to schema, migrations, queries and GraphQL with nothing written twice, and the research it rests on
- [DOCUMENTATION — every blue project documents itself, and the language has a book](DOCUMENTATION.md): documentation as a battery: one source per fact, a Diátaxis book, rendered README, AGENTS.md and llms.txt (design)
- [FRONTEND-PLAN — building the blue frontend framework](FRONTEND-PLAN.md): the build plan for blue's frontend framework
- [Guard-clause `return`: the design of record](GUARD-RETURN.md): Guard-clause return, G1 BUILT: `return x` where the parser can rewrite it into if/else, refused where it cannot (B0080), so blue stays one expression per body at no run-time cost
- [HORIZON: where blue goes next](HORIZON.md): the long plan for blue, ten horizons from hygiene to a language that proves, replays and explains itself, eight authority horizons that make every host effect a capability granted from one declaration in every placement, an ontology of every concept in khipu that the tests are generated from, and the kernel as both a verified target and the enforcer of access; destination first, each horizon with its first step, its gate and what it unlocks
- [HTTP2 — blue speaks HTTP/2 and gRPC itself](HTTP2.md): blue speaks HTTP/2 and gRPC itself (design, phase 1 built)
- [KERNEL — write only blue for the Linux kernel](KERNEL.md): blue as the whole kernel toolchain, from source to a program the verifier admits, and where each part runs
- [khipu: blue's knowledge graph, the design of record](KHIPU.md): khipu, blue's knowledge graph, DESIGN: OxiRS's essence naturalized, the recon, the typed terms, the phases, the parity gates and the tier ledger
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
- [utsushi (写し): blue's history projection, the design of record](UTSUSHI.md): utsushi, blue's history projection, DESIGN: Josh's essence naturalized with six improvements, the recon, the lens and view algebra, the phases, the parity gates and the tier ledger
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
