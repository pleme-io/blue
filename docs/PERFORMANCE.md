---
kind: explanation
summary: what blue costs today, where the time goes, and the order to remove it
---

# Performance: blue as a scripting language and as a tool

This file records what blue costs today, where the time goes, and the order in
which to remove it. Every number has a command that produces it. The
destination is in section 3; section 4 lists what is already built.

## 0. How to measure

`bench/bench.b` produces the tables in section 1. It writes its own data (a
1.3 MB JSON file and a 4.7 MB text file), copies the workloads in
`bench/workloads/` to a directory outside any project, and runs each one
under hyperfine. Run it from the repository root:

```text
nix shell nixpkgs#python3 nixpkgs#ruby nixpkgs#hyperfine
blue bench/bench.b BLUE PYTHON RUBY WORKDIR [RUNS]
blue bench/bench.b compile TARGET
```

`BLUE`, `PYTHON` and `RUBY` are the executables to compare. `RUNS` is the
hyperfine run count (10 when absent). The `compile` form measures `cargo build
-p blue-lang-cli` in the target directory `TARGET`, with sccache off: clean,
then after a touch of a leaf crate (`blue-lang-art`), then after a touch of
`blue-lang-runtime`, for the dev and the release profile. It removes `TARGET`
before and after.

`blue run --timings FILE` prints the wall time of each pipeline stage to
stderr. A stage reached inside another stage is charged once, to itself.

The profiles in section 2 come from macOS `sample` (1 ms interval) on a
release build, demangled with `rustfilt`. Inclusive counts per function come
from a DuckDB query over the call graph that charges a recursive function once
per stack. `blue profile FILE` gives the same view per blue definition.

Machine: Apple M4 Pro, 14 cores, 48 GiB, macOS 26.7.1. blue 0.0.111 at
`8bd5119`, tatara-lisp-eval 0.4.9, rustc 1.98.1, release profile. Python
3.13.12 and Ruby 3.3.10 from nixpkgs. hyperfine 1.20.0, `-N`, 2 warm-up runs.

The machine ran other builds during every measurement (load average 20 to
120). Wall times carry that noise. The `user` column is CPU time of the
measured process and is the more stable figure. Compare ratios, not absolute
values.

### 0.1 The cost ratchet

Wall time on a shared machine is noise, so the gate reads costs that do not
move with load. `blue run --no-memo --timings` prints, after the stage times,
`steps` (evaluation steps of the root program, the same count
`--receipt-steps` writes) and `allocs` and `bytes` (allocations made on the
evaluating thread inside the eval and main stages, so startup, the
environment and the check stage do not count). Steps are the same on every
host and build profile. Allocations agree between a debug and a release build
to a few counts, and differ between hosts, so their rows carry the host.

```text
blue bench/bench.b cost BLUE WORKDIR [--quick]
blue bench/bench.b cost BLUE WORKDIR --record [--receipt "<why>"]
```

`cost` copies each workload out of the project, runs it once on the walker
door (`blue run --door walker`: steps are the walker's count, and the VM's
cost is gated in 1.4.1), prints a table
with the wall time (reported, never gated), and judges it against
`bench/cost.baseline` with hadome's `failures_within`: steps may grow 5 per
mille, allocations and bytes 20 per mille. A workload past its tolerance, or
with no row, fails and is named with its delta. A host with no allocation rows
is advisory for them and still gated on steps. `--record` is the only writer
of the baseline: it banks every fall, keeps the old row for a rise inside the
tolerance so the baseline cannot creep, and refuses a rise past it without
`--receipt`, which stays in the file as a `# receipt:` line, as in
`reuse.baseline`. A receipt is typed: `--receipt "<kind>: <why>"`, with a
kind of `first-measure`, `measurement`, `correctness`, `capability`,
`platform` or `un-gain` (the one grammar every ledger takes, `hadome`'s
`receipt_kinds` and `receipt_refusal`); any other reason is refused, on
`cost`, `native` and `lever` alike. A host with no row for a kind is told the
record that starts judging it, `--receipt "first-measure: <host> <kind>"`. A
program a native path stops running is judged on every machine; only the
ratios wait for the machine that recorded them.

The cost rows include the lever rows of 1.6 (`memo`, `bake`, `incremental`,
`hexmsg`), so the levers are gated in CI by their steps: a build where the
memo stops answering, or a hex word falls back to blue code, is red.

Red run, 2026-11-11: the same release binary with shinsuu's old hex words on
`BLUE_PATH` (a deliberately slower build of the distribution) fails the
ratchet: `bench-steps: hexmsg measures 5561541, past its recorded 357841 by
5203700, beyond its 5 per mille tolerance`, with the allocation and byte rows
red beside it.

`--quick` (empty, hello, fib) is the pre-push gate `bench`, run when a landing
touches `crates/**` or `bench/**`. The full set is `checks.bench-ratchet`,
which CI runs with `nix flake check`.

What it cannot see: time a builtin spends without allocating, and the
evaluation steps of spawned processes (their allocations on the evaluating
thread do count). Those show only in the wall column.

## 1. Measurements

### 1.1 Scripts: blue against Python and Ruby

Each cell is mean ± σ in ms, user CPU time in parentheses. The ratio is
blue's mean over the other language's mean. "Before" is `8bd5119`; "after" is
this branch.

| workload | blue before | blue after | python | ruby | after/python | after/ruby |
|---|---|---|---|---|---|---|
| empty | 6.3 ± 0.3 (3.9) | 6.7 ± 0.3 (4.0) | 13.0 ± 1.5 (8.4) | 33.3 ± 0.5 (23.6) | 0.5× | 0.2× |
| hello | 6.5 ± 0.3 (4.0) | 6.4 ± 0.1 (3.9) | 12.9 ± 0.3 (8.7) | 33.0 ± 0.5 (23.7) | 0.5× | 0.2× |
| fib | 313.6 ± 10.2 (305.4) | 334.3 ± 66.4 (309.2) | 31.8 ± 0.7 (28.0) | 44.1 ± 0.9 (34.9) | 10.5× | 7.6× |
| pipeline | 1032.7 ± 281 (912.6) | 950.8 ± 39.5 (914.2) | 96.5 ± 1.4 (92.2) | 102.3 ± 0.6 (92.2) | 9.9× | 9.3× |
| strbuild | 620.4 ± 38 (568.4) | 592.4 ± 14.8 (562.5) | 110.6 ± 2.7 (101.9) | 92.5 ± 2.5 (82.3) | 5.4× | 6.4× |
| json_sum | 130.5 ± 4.4 (69.8) | 119.6 ± 2.9 (66.9) | 29.4 ± 3.5 (22.2) | 48.2 ± 1.5 (37.0) | 4.1× | 2.5× |
| wordfreq | 89,144 ± 9,804 (82,191) | 120.7 ± 14.4 (104.1) | 67.6 ± 0.6 (59.2) | 98.3 ± 1.6 (83.5) | 1.8× | 1.2× |
| spawn | 399.8 ± 14.9 (306.8) | 402.6 ± 6.5 (304.9) | 71.4 ± 1.0 (59.2) | 64.2 ± 1.3 (32.4) | 5.6× | 6.3× |

Python and Ruby columns are from the "after" run; the "before" run agrees
within noise. Only `wordfreq` changed: 740× faster. The other workloads
measure the evaluator, which this branch does not change.

| tooling (bench.b) | before | after |
|---|---|---|
| `fmt --check bidamas/kueri/kueri.b` | 118.4 ± 3.5 (102.5) | 95.3 ± 0.9 (86.4) |
| `fmt --check` on all tracked `.b` files | 9,298 ± 185 (8,586) | 4,269 ± 30 (3,799) |
| `check`, one process per file, all files | 23,462 (one run) | 14,212 (one run) |

The workloads, written the idiomatic way in each language:

| workload | what it does |
|---|---|
| empty | an empty file |
| hello | print one line |
| fib | recursive `fib(27)` |
| pipeline | map, filter and reduce over 1,000,000 Ints |
| strbuild | 1,000,000 one-character strings joined into one |
| json_sum | parse the 1.3 MB JSON file and sum one field |
| wordfreq | count the words of the 4.7 MB file and take the three most frequent |
| spawn | start 10,000 processes (asyncio tasks, Ruby fibers) that each send one message |

### 1.2 Stages of one `blue run`

`blue run --timings`, release, after this branch, the median of three runs.
Values in ms.

| stage | hello.b outside a project | hello.b inside the repository | a script that imports kueri |
|---|---|---|---|
| read | 0.18 | 0.99 | 11.5 |
| format | 0.04 | 0.04 | 0.10 |
| runtime | 1.07 | 1.08 | 1.06 |
| names | 0.46 | 0.47 | 0.46 |
| parse | 0.004 | 0.003 | 0.008 |
| resolve | 0.05 | 0.17 | 21.9 |
| check | 0.21 | 0.24 | 31.6 |
| erase | 0.006 | 0.008 | 14.1 |
| eval | 0.009 | 0.011 | 1.5 |
| total in process | 2.1 | 3.0 | 82.2 |

"read" holds what no other stage claims: the file read, project discovery and
`canonical_entry`, the resolution walk the formatter door runs before the
pipeline (2.6). The process itself adds about 4 ms (exec, dyld, page faults
of a 16 MB binary; hyperfine measures 6.4 ms for hello). Before this branch,
"read" inside the repository was 5 to 10 ms, because each run evaluated the
root Bluefile twice and searched for a suggestion for each of its words.

### 1.3 Tooling

| command | before | after |
|---|---|---|
| `blue fmt --check` on all 358 tracked `.b` files, user s | 9.3 | 4.0 |
| `blue run gen/regen.b` (`nix run .#regen`), user s | 75.4 | 6.8 |
| a script that imports kueri, user ms | 145 | 88 |

Re-measured 2026-11-16 at `e6e5b200`, on a host loaded with other builds:
`blue run gen/regen.b` took 154.0 s user (3 min 33 s wall) with a release-local
binary, against 6.8 s above, and a script that imports kueri spends 110 to
140 ms in the check stage, against 31.6 ms in 1.2. Load does not explain a 22x
rise in user time. The cause is not found yet; finding it is the first item of the plan.

The reports were 57 s for `fmt --check` and 70 to 90 s for regen. The
release build measured 9.3 s CPU before this branch. The dev build (`cargo
build`, the binary `cargo test` and `cargo run` use) takes 26.8 s CPU and 36 s
wall for the same command after this branch. By the same ratio it took
about 60 s before it (an estimate, not measured). The dev profile compiles the evaluator crates at `opt-level = 3`, but not
`blue-lang-check`, `blue-lang-syntax`, `blue-lang-fmt` and `blue-lang-pkg`,
which do the work of `fmt` and `check`. Evaluation in the dev build is near
release speed (`fib` 0.39 s against 0.31 s CPU).

### 1.4 The VM against the tree-walker

Since 2026-11-11 `blue run` takes the VM as its default door where the
conformance columns agree (`crates/blue-lang-runtime/src/door.rs`): every
construct the program uses is agreed, and it reaches no host effect (the
door's one `Unreplayable` rule). Otherwise it takes the
tree-walker. A fault on the VM runs the program again on the walker, with its
output words silenced, so the error carries its place and stack and the output
is written once. `--door walker` or `BLUE_DOOR=walker` turns the VM door off;
`--timings` names the door, and `--door-receipt FILE` writes which door ran
and why. The conformance runner holds the door's table to the rows pending on
the VM, in both directions, and routes each such row through the door, which
must send it to the walker (the door gate). The memo, `--record`,
`--receipt-steps` and `blue watch` keep a run on the walker.

Before that, `blue run` evaluated with the tree-walker and the bytecode VM ran
only blue processes. A probe build sent the whole program to
`Interpreter::eval_program_vm` instead. User CPU time, s:

| workload | tree-walker | VM |
|---|---|---|
| fib | 0.31 | 0.26 |
| pipeline | 0.85 | 1.64 |
| strbuild | 0.57 | 0.83 |
| spawn | 0.30 | 0.32 |

The VM is 15% faster on a plain recursive function and up to 2× slower when a
lambda goes to `map`, `filter` or `reduce`. Section 2.2 gives the cause. On
2026-11-16 (tatara-lisp-eval 0.4.21) the VM began to run such a callback
itself, and the door's rule that sent a program handing a function to a
native word to the walker went, since it was no longer true: `pipeline`
evaluates in 576 ms on the walker and 401 ms on the VM, `strbuild` in 358
and 306 ms.
`a_call_through_a_value_stays_on_the_walker_and_a_lambda_argument_takes_the_vm`
in `crates/blue-lang-cli/tests/door.rs` holds the lambda on the VM.

2026-11-16, tatara-lisp-eval 0.4.19: the VM caches each global under the
environment's write stamps, runs `+ - * < > <= >= =` on two Ints or two Floats
in place, finds a native function through an index instead of a linear scan,
and calls a compiled function without allocating. hyperfine, 10 runs, user CPU:
`fib(27)` on the VM door 248.4 to 81.2 ms (3.06x), 4,449,574 to 233
allocations; `strbuild` on the walker 535.3 to 446.4 ms (the index alone).
Each cache is sound without an invalidation step: a frame's version is drawn
from a counter that never repeats, so an equal version means no write.

Since 2026-11-16 `blue run` also plans the call memo by itself. When nothing
names a memo mode (`BLUE_MEMO` unset, no `--no-memo`, the shipped bounds) and a
pure definition calls itself at two or more places in its body (overlapping
subproblems, `door::overlapping`), the run takes the walker with an
in-process memo and the door receipt says so ("the memo answers `fib` …");
otherwise the door is chosen as above. `fib(27)`: eval 70.9 ms on the VM,
0.13 ms planned. The memo forced on `strbuild` costs 13 %, so the planner
leaves programs without that shape alone, and a tree recursion with an effect
is refused by the memo's own purity proof and stays on the VM.
`BLUE_MEMO=off` turns the planner off. Locks: `crates/blue-lang-cli/tests/door.rs`.

### 1.4.0 The default cascade

Each lever below is a rule over a definition's own facts (its purity, its
shape in the tree, the arguments at a call). It fires with no flag, names
itself in `blue run --timings`, runs the old path when its guard fails, and
has one switch that turns it off. The conformance rows of each run on every
evaluator, with the lever on.

The rows of this table are the `kitei` bidama's registry; `tests/kitei_gate.rs`
fails when an id or a switch here differs from it.

| rule | facts → lever | receipt | switch | measured | locks |
|---|---|---|---|---|---|
| R1 | constructs every column agrees on → the VM | door receipt | `BLUE_DOOR=walker` | §1.4 | `tests/door.rs` |
| R2 | pure, calls itself at two or more places → call memo | door receipt | `BLUE_MEMO=off` | `fib(27)` eval 70.9 to 0.13 ms | `tests/door.rs` |
| R3 | a `map`/`filter`/`reduce` chain of callbacks that only compute → one pass, the unfused chain on the first error | `fused` row | `BLUE_FUSE=off` | pipeline, 1M Ints, VM 395 to 300 ms | `spec/rows/fusion.b`, `tests/fusion.rs` |
| R4 | a pure definition of the program called with literal arguments where the call can run more than once → its value, computed before the run | `folded` row | `BLUE_FOLD=off` | `tests/fold.rs` program, walker 87.4 to 7.5 ms, VM 44.1 to 5.6 ms | `spec/rows/fold.b`, `tests/fold.rs`, `fold` unit tests |
| R5 | a call of an operator on two Ints or two Floats → computed in place, the tag check its guard; blue adopts its own `equal?` and `not=` (what `==` and `!=` lower to) as operators | none: the in-place path answers what the function answers | registering the name again withdraws it | a loop on `i == 0`, VM 675 to 408 ms | `spec/rows/equality.b`, tatara `tests/vm_operators.rs` |
| R7 | a definition with a native artifact whose outermost calls averaged 0.2 ms or more in earlier runs when the artifact has a library (20 ms when it has only an executable) → its calls answered by the artifact, in process through the library (R6 folded in) | door receipt | `BLUE_NATIVE=off` | `fib(30)` 1041 to 22 ms (§1.7.1); 300 calls of `fib(16..18)`, 2.09 s to 0.02 s from the second run | `tests/native_tier.rs` |
| R8 | a pure definition of the program with a stored result (this node's store or a shared root) that cost 20 ms or more → its calls answered from the store, new results added | door receipt ("the store answers") | `BLUE_MEMO=off` | the `tests/fleet_memo.rs` program, debug build, 277 to 3.6 ms total | `tests/fleet_memo.rs` |
| R9 | a record type → its shape (tag, field keys, field types) fixed at its declaration, built once per type, so constructing a record only places its values | none: a record is the same map | none | 300,000 constructions, VM: 254 to 213 ms (release) | `record.rs` unit tests (red with the shape table bypassed), conformance's record rows |
| R10 | a callback of `map`, `filter`, `reduce`, `any?`, `all?`, `find` or `count` that tests `member?(x, s)` on a local the definition never assigns and the callback names nowhere else → an index of `s` for that one call, built after 8 lookups; `member?` itself scans natively with blue's equality | `indexed` row | `BLUE_INDEX=off` | 5,000 tests against a 5,000-element list: 2,801 ms (release, the Lisp `member?`) to 52 ms (debug, native scan) to 2.0 ms (debug, indexed) | `tests/member_index.rs` (every case on both doors, index on against off; red with an Int key that misses its Float), `member_index` unit tests, `spec/rows/member_index.b` |
| R11 | a closed region of list-holding definitions under a root that takes and returns no list → an arena | not shipped | — | chuuzou, 20,000,000 appends then an indexed sum: refcount 44.9 ms, inferred arena 43.7 ms ± 2.7 (1.03 ± 0.07, same output); at 3,000,000 all variants 9.2 to 9.6 ms | measured 2026-11-17 and refused by the ratchet: the arena saves a free per list, and a region keeps a short-lived list alive until its root call returns, so memory grows where refcounting frees promptly; `reclaim(:arena, "f")` stays the author's choice |
| R12 | a placement that forbids writable code (iPhone, wasm) → ahead-of-time code only | holds by construction | — | — | `tests/placement_tiers.rs`: blue-lang-ios, blue-lang-component and blue-lang-wasm link no blue-lang-cli (whose native tier runs artifacts), and no crate maps executable memory (`PROT_EXEC`, `MAP_JIT`, `mprotect`), so a JIT tier cannot land without a placement gate; the scan's own red test |
| R13 | a `reduce` whose callback appends to its string accumulator, which it reads nowhere else (`"#{s}…"`) → the string built once: its start, then the `join` of each step's appended parts; the loop as written for an empty list or a non-list | `built` row | `BLUE_BUILDER=off` | 200,000 appends: 2.87 s to 0.08 s (debug) | `spec/rows/builder.b`, `tests/builder.rs`, `builder` unit tests |
| R14 | a pure definition of a program whose last run evaluated for 20 ms or more (`memo::note_slow`, a mark per program text in the `slow` tier) → its results recorded to the store with their cost on the next run, so R8 answers the costly ones from the run after | door receipt ("the store records") | `BLUE_MEMO=off` | `slow(3_000_000)`: 0.55 s each run before; now 0.55 s, 0.93 s (it records), then 0.01 s | `tests/fleet_memo.rs` |
| R15 | an `http_request` whose method is GET, HEAD or OPTIONS (idempotent, RFC 9110) fails before an answer, the connection refused or reset → sent again, up to twice, 50 then 100 ms apart, within the call's one deadline; a timeout, a refusal or a malformed answer is never retried | `retried` row | `BLUE_RETRY=off` | a GET to a server that comes up 30 ms late: a raise before, the answer now | `tests/net.rs` |
| R16 | an `http_request` whose `timeout_ms` is nil, to a host this process has heard from → its timeout ten times the slowest answer that host gave, at least 1 s; 30 s for a host not yet heard from | none: the timeout is the request's own | `BLUE_TIMEOUT=fixed` | a host that answered at once and then hangs: the next nil-timeout request times out within 1 s, not 30 s | `tests/net.rs` |
| R17 | a `map` whose callback only computes, in a project that declares more than one scheduler → `par_map`: the first call prices the rest, which runs on the schedulers when it saves more than twice a worker's start | `--timings` counts each parallel map (`parallel`) | `BLUE_PARMAP=off` | eight 400,000-step calls: 0.67 s on one scheduler, 0.30 s on four, the same answer | `tests/schedulers.rs` |
| R18 | two or more local bindings in a row, each a GET, HEAD or OPTIONS `http_request` with a literal method whose arguments name none of the run's earlier bindings → one `http_batch`: the requests sent at once, the answers bound in order, the first error in order raised | `--timings` counts each batch (`batched`) | `BLUE_BATCH=off` | two GETs to a server that holds each for 300 ms: both held open at once, against one after the other with the switch off; the same answers | `tests/batch.rs` |
| R19 | a `map`/`filter`/`reduce` chain fusion fuses (R3's callbacks that only compute, read over the whole program in their own scope), in a binary whose cost table is measured → the outermost call it is in saturated over blue's rules and replaced by fusion's tree when the table prices that cheaper, the written call on a tie; the choice kept under the hash of the definition the call is in, and recalled | `--timings` counts each call it changed (`saturated`) and names each chain fused | `BLUE_SATURATE=off` | two reduce-filter-map chains, debug build on a loaded host: erasure takes 1.09 ms the run that decides, 0.50 ms recalled, 0.35 ms with the switch off, the same answer and the same fused chains; recalled with 120 other programs' decisions in the cache, 0.53 ms, where one bucket shared by every program took 1.82 ms, more than deciding (1.32 ms) | `tests/saturate.rs`, `tests/saturation_memory.rs` |
| R20 | a `par_map` that runs apart, its first call timed and a worker's start measured → the pool is the largest k, at least 2 and at most the schedulers, whose k-th worker saves more than twice a worker's start (the load over k(k-1)) | `--timings` counts the workers each parallel map started (`workers`) | `BLUE_POOL=fixed` | sixteen 20,000-step calls on sixteen schedulers: 5 workers, not 15, the same 0.07 s wall time on half the CPU (0.10 s, not 0.20 s), the same answer | `tests/schedulers.rs` |
| R21 | a check, memo or test store that evicts, its files dated by their last use → its bound twice the bytes its files used within the last day, at least the declared bound (256 MiB) and at most sixteen times it | none: the store keeps what it holds | `BLUE_CACHE=fixed` | forty entries used today, about 38 KiB, in a store declared at 16 KiB: all kept, where the fixed bound evicts them to 16 KiB | `blue-lang-mondou` store tests |

The conformance suite runs its in-process columns under a step bound
(`ROW_STEPS`), where R4 and R10 stand down, so those columns hold the path
without the rewrite. Its `default` column runs `blue run` as a user does, with
no step bound and every default on, so every row also holds the rewritten path
(a broken index turns it red); `tests/fold.rs` and `tests/member_index.rs`
compare the two paths directly.

`blue shift --defaults FILE` names, per definition, the rules in this table
that fire on it and the fact a rule that does not fire is missing, under the
switches in force (`docs/FACTS.md` §4).

R4 evaluates each call once in a fresh interpreter under 100,000 steps and
64 MiB (1,000,000 steps for the whole pass). A call that raises, runs past a
bound or answers a value no literal spells (a map, a function, a record)
stays as written and runs at its own time, so its error is the program's
own. A folded value is kept only when its literal evaluates back to a value
of the same kind and content (`4.0` stays a Float). A call in `main` or at
the top level runs once, so R4 leaves it alone: folding it would only move
its cost. `blue bundle` prepares at build time, so a bundle carries the
value, not the call.

#### R6 — folded into R7

R6, a guard dropped where a definition's argument types are proven, has no
row in the table: kitei holds it as `:folded`, and §1.7.1 says why R7
carries it.

### 1.4.1 Every execution path against Rust

`blue bench/bench.b native BLUE WORKDIR` runs each program in
`native_programs` (from `native/corpus`) three ways: `blue run` (the
tree-walker), chuuzou's host image (`native/build/host.b`, board `host64`),
and the program's hand-written Rust twin in `bench/native`, built with
`rustc -C opt-level=3`. A program's `N = …` line sets its size: the
tree-walker runs it as written, chuuzou and Rust at a big `N` (`work` times
the work), so a native run is long enough that process start does not
decide it. The interpreter's output must equal the twin's at the small `N`,
the image's the twin's at the big one, before anything is timed. hyperfine,
3 runs; wall ms, then CPU (user + system) ms. It needs `hyperfine`, `rustc`
and `tatara-rust-emit` on `PATH`. The VM column is `blue run --vm`, which
compiles the whole program, its `main` call included, to one chunk; BLUE
must be a build that has the flag.

| program | tree-walker (N) | VM (N) | chuuzou (big N) | Rust (big N) | chuuzou / Rust | VM / Rust per unit of work | tree-walker / Rust per unit of work |
|---|---|---|---|---|---|---|---|
| fib (30; 38) | 1181 (cpu 1170) | 1062 (cpu 1052) | 92.8 (cpu 89.6) | 70.7 (cpu 69.8) | 1.28 | 708 | 788 |
| loop (3M; 300M) | 2589 (cpu 2561) | 2749 (cpu 2726) | 141 (cpu 138) | 162 (cpu 157) | 0.88 | 1742 | 1637 |
| mutual (depth 10,000) | 26 (cpu 19) | 27 (cpu 18) | 4.7 (cpu 1.3) | 6.7 (cpu 1.3) | 1.00 | 14 | 15 |
| shapes, records (1M; 100M) | 8099 (cpu 7803) | 7062 (cpu 7044) | 127 (cpu 122) | 133 (cpu 132) | 0.93 | 5344 | 5920 |
| sums, lists (100k; 10M) | 420 (cpu 416) | 417 (cpu 411) | 47.6 (cpu 43.4) | 36.2 (cpu 32.9) | 1.32 | 1250 | 1264 |

chuuzou checks `+`, `-` and `*` for overflow and counts recursion depth
against the board's bound; the twin, as release Rust does, wraps and counts
nothing. A check a range proves cannot fire is left out: an Int parameter
every call keeps at zero or above (the largest such set, an inductive
invariant over every call site) and the facts an `if` establishes (`n < 2`
false means `n >= 2`) make a difference of two non-negative values a plain
`-`, and a non-negative value's Euclidean remainder by a positive literal a
plain `%`. That took loop from 1.61 to 0.88 of the twin; fib keeps its
depth count and its checked `+`.

sums builds a list of N words one append at a time and sums it by index,
twice: once refcounted and once in a region (`reclaim(:arena, …)`), so
both reclamation strategies run in one program. An append of a literal list
is a push (`kiban_heap::rc_push`, `Region::push_onto`): before that, each
step made a one-word list and appended it, and sums ran at 8.8 times the
twin; after, 1.5. The rest of the gap is the twin's vectorised sum against a
checked add and a bounds-checked index per word.

### 1.6 Lever rows: doing less work than a Rust program of the same job

`blue bench/bench.b lever BLUE WORKDIR [--record --receipt "<kind>: <why>"]`
runs each program in `bench/levers` (and, for memo, the `fib` workload at
`N = 38`) against its plain Rust twin in `bench/native`, after checking that both print the same. The blue run starts
from the store its build left (restored before each run), so it never answers
from its own previous run. hyperfine, 5 runs; CPU ms; the ratio is blue's CPU
over Rust's, gated per host in `bench/lever.baseline` with a 500 per mille
tolerance. It needs `hyperfine`, `rustc` and `rsync` on `PATH`. Apple M4 Pro,
release build, 2026-11-11:

| row | lever | blue | Rust | blue / Rust |
|---|---|---|---|---|
| memo (naive `fib(38)`) | memo by identity, in process | 56.8 | 125.9 | 0.45 |
| bake (64 chunks of 50,000 steps, the store a build filled) | bake | 16.1 | 15.5 | 1.04 |
| incremental (the same, one input changed) | incremental, through the store | 59.1 | 15.5 | 3.81 |
| hexmsg (400 framed 67-byte messages to hex and back) | a linear library word (3.1) | 63.7 | 3.0 | 21.2 |

memo is faster than the Rust program: blue knows `fib` is pure and answers
each repeated call from its table, and the Rust program recomputes them. bake
and incremental do the work of one chunk or none; their cost is the
interpreter's start and 64 lookups. The rows are cost rows too (0.1).

`hexmsg` is the shape a message decoder measured at 0.5 to 1 million
evaluation steps per message: bytes to hex and back through shinsuu's
`bytes_hex` and `hex_bytes`, which were blue code (a digit table, a `map` per
byte). The native words `hex_encode` and `hex_decode` (one pass each, in
`stdlib.rs`) now do the work, and the shinsuu words wrap them. Steps fell from
5,561,541 to 357,841 (15.5 times fewer), CPU from 455 ms to 64 ms, and the
ratio to Rust from 157 to 21. Byte concatenation was not on the profile
(`append` is already native), so no concatenation word was added.

### 1.7 Ahead of time to a wasm component

chuuzou compiles a program in its subset for the board `wasm32` (kiban's
`kb_wasm32`: host64's word and depth, `wasm32-wasip2` with the standard
library), and links it with `native/seam/wasm32/seam.rs` into a WASI preview 2
component, which wasmtime runs: the host a `runtime: :wasm` service and an
engenho wasm pod run on. `native/corpus/hex.b` is the hex words written in
that subset (bytes as Int lists, 64 random cases per seed, each encoded,
printed, decoded and compared). `checks.native-wasm` (`native/checks/wasm.b`)
compiles it for four seeds and requires the component to print what the
interpreter prints. Red run: a seam that writes `b` for `a` fails it.
hyperfine, 10 runs: the interpreter 118.7 ms (user 99.9), the component under
wasmtime 10.8 ms (user 5.4), 11 times faster.

#### 1.7.1 One derivation per `def_hash` (tier T3, first slice)

Tier T3 of blue's speed plan: a definition chuuzou can lower becomes a
nix derivation whose input is its resolved tree, keyed by `def_hash`, built
once in the fleet. What is built (2026-11-16):

| step | where | what it does |
|---|---|---|
| hash and slice | `blue ast --resolved --defs FILE` (`crates/blue-lang-cli/src/native.rs`, `defs`) | each definition of the file with the `def_hash` `def_hash(f)` answers (`@doc` included) and its slice: the resolved forms of every entry definition it reaches, each function and value renamed `%root/d_<hex>` after its own hash, so a rename changes no byte of it |
| manifest | `native/build/defs.b`, `generate("native-defs", …)` in `native/Bluefile` | one JSON line per definition of each program under `native/defs/`, with `native` true when chuuzou compiles it for the tier (`cz_def_native`) and `refused` saying why when not; committed and gated fresh (`checks.native-generated-native-defs-fresh`) |
| one derivation per hash | `nix/native-defs.nix` (`artifact`, `defs`, `root`) | `blue-native-<hex>`: its only program input is the slice (`passAsFile`); chuuzou lowers it with the definition as `pub fn entry(io, args: &Args) -> i64` (`cz_lower_def`) and links it with `native/seam/def64/seam.rs`; the seam set is narrowed to the four files it links, so a board's own seam changing rebuilds no definition |
| the store layout | `blue_lang_mondou::store::native_artifact` (`NATIVE_TIER`, `NATIVE_LAYOUT`) | `<root>/native/v1/<hex>/def`, found through `BLUE_CACHE_SHARED` as the check, memo and test tiers are; `root` joins a manifest's artifacts into one such root (`packages.native-defs-base`) |
| the run-time seam | `native::Tier` (a `CallObserver`), on by default (R7); `BLUE_NATIVE=on` answers every call it can, `off` none | a call of a function whose hash has an artifact, every argument an Int, a Bool, a Float, a Str, a list of Ints or a record of Ints as its signature names it (a Str, a list or a record through value tokens, `blue_def_call`), is answered by the artifact: in process through `def.so` when the build made one (loaded once with `dlopen`, `crates/blue-lang-cli/src/dl.rs`, the one unsafe seam), else by running `def`; any other call, and an artifact that faults, prints or refuses, runs in the interpreter |
| the node's builder | `native/build/wanted.b`, packaged as `native-build` (`nix/native.nix`) | a run whose evaluation took 20 ms or more, with a native tier present, writes `<cache>/blue/native/wanted/<content hash of the text>` and starts `BLUE_NATIVE_BUILDER`; the builder builds each function chuuzou compiles into `<cache>/blue/native/v1/<hex>/`, which `store::native_roots` reads before `BLUE_CACHE_SHARED` |
| the library | `native/seam/def64/lib.rs`, linked by `cz_def_image` from the same rlibs as `def` | `blue_def_entry(args, len, out)`: the definition on a thread with the board's stack, 0 with the result, 1 when it faulted or printed (its own panic hook is silent), 2 on a null pointer |
| the profile | `blue_lang_mondou::store::profile` (`PROFILE_TIER`, `PROFILE_LAYOUT`), `native::planned` | `<cache_root>/profile/v1/<hex>`: the total nanoseconds and the count of a definition's outermost calls, added to by every run that times it; keyed by `def_hash`, so it never goes stale |

**The key is the content.** `checks.native-def-keys` reads `.drvPath` at
evaluation for the three programs in `native/defs/` (`base.b`; `edited.b`,
where only `square`'s body changed; `renamed.b`, where `fib` is
`fibonacci`) and fails the evaluation unless: `square` and `sum_squares`
(which calls it) move, `fib` (which does not) keeps its `.drvPath`, and
`fibonacci` has `fib`'s `.drvPath` exactly. It writes the five rows with both
paths, for example `fib` in base and in edited:
`yna5w03s…-blue-native-9390dea3….drv` both times. Red run: expecting `fib` in
base to equal `sum_squares` in edited fails the evaluation with `native def
keys: a definition the edit does not reach broke the content key`.

**The artifact answers what the interpreter answers.** `checks.native-defs`
(`native/checks/defs.b`) runs `square(12)`, `sum_squares(100, 0)` and
`fib(20)` through `blue run` and through each artifact and requires the same
output; then it shelves `square`'s artifact under `fib`'s hash and requires
`BLUE_NATIVE=on blue run` of `fib(5)` to print 25 (off: 5), so the answer
comes from the store, by `def_hash`.

Measured on an Apple M4 Pro, release build, 2026-11-16, `hyperfine -N -r 5
-w 1`, a program that is `native/defs/base.b` and then
`write_stdout(unlines([to_s(fib(30))]))`; ROOT is a root holding the base
fixture's artifacts:

| run | wall ms | CPU ms (user + system) |
|---|---|---|
| `BLUE_NATIVE=off blue run --quiet fib30.b` | 1041 | 1030 |
| `BLUE_NATIVE=on BLUE_CACHE_SHARED=<empty> blue run --quiet fib30.b` (no artifact: the observed walker) | 1513 | 1218 |
| `BLUE_NATIVE=on BLUE_CACHE_SHARED=ROOT blue run --quiet fib30.b` | 22.0 | 19.3 |
| `ROOT/native/v1/9390dea3…/def 30` (the artifact alone) | 5.6 | 3.7 |
| `ROOT/native/v1/1428e7a9…/def 1` (`square(1)`: a process start) | 3.2 | 1.8 |

The run with the tier answers `fib(30)` 47 times faster than the interpreter;
what is left is blue's own start (about 16 ms) and one process start. With
the tier on and nothing to answer from, the run is 1.45 times slower, since
an observed run takes the walker and pays the observer on every call.

**On by default (rule R7 of the default cascade).** With `BLUE_NATIVE` unset,
`blue run` asks the native planner about every program. When no root
`BLUE_CACHE_SHARED` names holds a native tier, it answers nothing and the run
is as before: the door picks the VM or the walker, and no profile is written.
When the program has a definition with an artifact, the run takes the tier if
that definition is hot (its outermost calls averaged 20 ms or more in earlier
runs, `native::HOT_NS`) or has no profile yet; it then answers the hot ones
natively, times the rest, and adds the times to the profile tier. A
definition whose profile is cold never makes the run leave the VM again. The
door receipt names each definition the tier answers or times. Locks:
`crates/blue-lang-cli/tests/native_tier.rs` (an artifact that answers a
different number shows which side answered: interpreted on the first run,
native on the second, never for the cold definition, interpreted under `off`;
red with the default mode set to off), the profile store's unit test. Rule
R6 (a guard dropped where types are proven) is folded in here: blue emits no
run-time type guard on the interpreter, so the only check left to drop is
the tier's Int test of the arguments, which a process start dwarfs.

**What the run-time seam still needs.** The artifact is a process, so a call
costs a process start (about 3 ms here): the tier wins on a call that does
more interpreter work than that, and loses on a small one called often.
The destination, in order:

1. **In process.** The same program rlib linked as a `cdylib` exporting
   `extern "C" fn blue_def(args: *const i64, n: usize, out: *mut i64) -> u32`,
   a fault caught with `catch_unwind` at that boundary (a panic must not cross
   it). The loader is one crate under `#![deny(unsafe_code)]` with one
   `#[allow]`: `dlopen` and `dlsym` declared in pure Rust (CONTAIN THE C: no
   `-sys` crate), the library kept open per run. `native::Tier::enter`
   (`crates/blue-lang-cli/src/native.rs:210`) then calls a function pointer
   instead of `native::call` (`native.rs:194`); nothing else moves.
2. **The VM door.** An observed run takes the tree-walker
   (`run_observed_accounted`, `crates/blue-lang-runtime/src/pipeline.rs:663`,
   evaluates with `Executor::Walker`), so `BLUE_NATIVE=on` gives up the VM for
   every other definition. The VM's call of a global needs the same `enter`
   hook, read through one view of the globals, the registry and the
   expander.
3. **Which definitions.** Today every definition of a manifest chuuzou accepts
   is built. The hot set is T2's call counter keyed by `def_hash`; a fleet
   counter names what nix builds, and the sui cache serves it to every node.
4. **Any program, not a fixture.** The manifest is generated per program the
   Bluefile names. A project word (`native(name, program)`) that lowers to the
   generate entry and the root makes any program's hot definitions a
   declaration.
5. **Values beyond Int.** The guard is an Int per argument and an Int result.
   Records and lists need a value ABI across the seam; a definition that
   reaches a board word (it prints) is refused, so the interpreter's output
   order is never interleaved with an artifact's.
6. **The layout's identity.** `v1/<hex>` names the protocol, not the chuuzou
   and toolchain that built it; a root joined from two builds of one hash keeps
   the first. The directory should carry the builder's identity as the check
   tier's does.

### 1.5 Compile times

`bench/bench.b compile`, sccache off, `cargo build -p blue-lang-cli`, wall
seconds, load average 40 to 68 during the run:

| profile | clean | leaf crate (`blue-lang-art`) touched | `blue-lang-runtime` touched |
|---|---|---|---|
| dev | 36.1 | 1.2 | 2.2 |
| release | 39.7 | 5.3 | 15.0 |

A change to `blue-lang-runtime` costs 15 s in release, because every crate
above it recompiles with full optimization; the dev profile does the same in
2.2 s. The dev profile already builds the evaluator crates at `opt-level =
3`, so a dev binary evaluates near release speed (1.3).

## 2. Where the time goes

### 2.1 Execution: the tree-walker's cost per call

Profile of `fib(32)`: 2,203 samples, grouped by the function at the top of
the stack:

| function | share | why |
|---|---|---|
| `malloc`, `free`, `realloc`, `memset` | 24% | each call makes a new `Frame`: a `Mutex<HashMap>` behind an `Arc`, plus a grown `Vec<Arc<Frame>>` |
| SipHash (`hash_one::<&str>`, `Hasher::write`), `memcmp` | 24% | every variable read hashes its name with SipHash, in every frame it walks |
| `Env::lookup` | 7% | the walk from the innermost frame out to the globals |
| `pthread_mutex_lock` / `unlock`, mutex init | 12% | every frame read and write takes a lock; the first lock of a frame initializes a pthread mutex |
| `SpecialForm::from_symbol` | 1% | each list form is matched against the special-form names as text |
| `Counting::alloc` / `dealloc` (blue's allocator) | 2% | the per-thread counters `blue profile` reads |

The same functions lead `pipeline`, `strbuild` and the regen run after its fix
(`Env::lookup` 2,910 of 12,229 samples, `Env::define` 1,463, `Env::push`
1,098). All of them are in tatara-lisp-eval's `env.rs`. Python and Ruby
resolve a local to a slot at compile time; blue resolves it by name at run
time.

### 2.2 Why the VM is not faster

- Until tatara-lisp-eval 0.4.21, a lambda that the VM compiled and gave to a
  native higher-order function was lifted back to a tree-walker closure on
  each call (`CompiledClosure::lift_to_closure`, `vm/run.rs`), so `map`,
  `filter` and `reduce` callbacks paid the walker's cost plus the lift. Since
  0.4.21 the native word runs the callback on one VM it keeps for the whole
  traversal. A callback still lifts when its body falls back to the walker's
  evaluation (`Op::EvalSexp`) or when a call observer is installed.
- `LoadGlobal` looked a global up by name on each access. Since 2026-11-16 it
  reads an inline cache that a write to any frame of the globals invalidates.
- Captured variables are `Arc<Mutex<Value>>` cells.

The VM tier alone does not close the gap to Python and Ruby. fib on the VM is
9× Python (0.26 s against 0.028 s CPU).

### 2.3 Algorithms in the library, not the evaluator

| program | cause | cost |
|---|---|---|
| wordfreq | `distinct` was tatara's Lisp fold over `member?`: O(n × unique) | 98 s |
| wordfreq, after `distinct` | `frequencies` was a Lisp fold that called a closure and rebuilt a map per element | 1.5 s |
| regen | `shuugou::unique` folded over `member`; `mokuroku::name_collisions` filtered all pairs once per name: 15 million closure calls | 90% of 75 s |

After this branch, 42 of the 292 documented builtins are still Lisp closures
in blue's interpreter (44 before it). They include words a script calls in its
inner loop: `get`, `assoc`, `first`, `rest`, `count`, `last`, `inc`,
`even?`, `zip`. Each call to one of them is an interpreted call with the
costs of 2.1. A blue program cannot see which builtins run as Lisp. (Measured
by asking `interpreter_hostless().lookup_global` for each `docs::NAMES` row.)

### 2.4 Processes

`spawn` of 50,000 processes, sampled after the spawns: 41 of 51 samples are in
the drop of a child interpreter, 33 of them in the drop of its macro table
(`HashMap<String, MacroDef>`). `fork` copies the macro table for each child.
The sample is small; the share is a direction, not a figure.

### 2.5 Tooling: `fmt --check`

Before this branch, 4,390 samples over all files:

| function | inclusive | why |
|---|---|---|
| `NameTable::candidates` (did-you-mean) | 2,569 (59%) | every manifest word of every Bluefile read was unbound, so the check searched the whole name table for a suggestion that nothing printed |
| `read_bluefile` | 1,294 (29%) | each file evaluated its project's Bluefile again |
| `format_tree_lossless` | < 300 (7%) | the formatter itself |

After this branch, 3,260 samples: `check_entry` 63% (`resolve_uses` 26%,
`check_stage` 32%), `read_bluefile` 19%, `builtin_names_with` 15% (built
again for each file), `format_tree_lossless` 10%.

### 2.6 One run resolves the program four times

For a script that imports kueri, 60% of the samples are in the erase stage,
and most of that is `resolve_program` inside `lower`. The check stage already
walked the same tree. `blue run` also runs `check_entry` and
`canonical_entry` before the pipeline, to spell bare nullary calls. So one run
parses and resolves each imported file twice and walks the names four times.

### 2.7 Two regressions in the front end (measured 2026-11-16)

Two changes made the check and resolve stages grow faster than the programs
they read. Both are fixed. Release build, load average 50 to 80, user CPU.

| cause | where | cost before the fix |
|---|---|---|
| B0079 (`records::check`, a48bdb8b) and the union rules (`unions::check`, 89ab6c59) each resolved the whole program again when any file in it declared a `record` or a `union`. kyohi declares a union since aa2f88ce, so every program that imports kyohi paid two extra resolutions in each check stage. | `crates/blue-lang-check/src/records.rs`, `unions.rs` | 85% of the check stage of a script that imports zenbu |
| `Standard::needs` parsed every file of a bidama tree on each call (0414c002), and the resolver calls it once for each level it loads. A tree with N levels was parsed N + 1 times. | `crates/blue-lang-pkg/src/embedded.rs` | 80% of the resolve stage of the same script |

Now the check stage resolves a program once: records, unions and the B0083
points read the stage's resolution (the check cache's when it is warm), and
`names::program_resolutions` counts each walk. `Standard::needs` reads each
tree once per process (`embedded::tree_parses`).

| command | before | after |
|---|---|---|
| `blue run` of a script that imports zenbu, check cache cold, user s | 6.3 | 2.7 |
| `blue run` of a script that imports kueri, check cache warm, hyperfine, user ms | 289 | 165 |
| `blue run gen/regen.b`, all caches cold (`BLUE_CHECK_CACHE=off`, `BLUE_GEN_CACHE=off`), user s | 152.7 | 134.8 |

The kueri script is still above the 88 ms of 1.3 because kueri imports more
code than it did: shisutemu now imports settei (92 KB) and its imports. A
script that imports retsu alone costs what it did (11.1 ms at bded2f8c, 13.3
ms now). The regen time is no longer in the front end. The generators that
did not exist on 2026-10-24 cost most of it: `obligation-discovery` 22 s,
`arika-snapshot` 22 s, `word-shapes` 21 s, and the three verb tables 9.5 s
each, mostly in evaluation. A second regen with the generator cache on reruns
no unchanged generator and costs 6.3 s.

## 3. The destination

### 3.0 The doctrine: blue wins by doing less work

Operator, 2026-11-10: *"we need to be 10000 times faster than rust not
slower"*, then *"blue CAN know those things due to its nature"*.

On the same instructions, no compiler beats Rust by orders of magnitude:
both reach the machine's limit. That is a world-fact. Blue beats a Rust
program of the same job by doing less work, because blue knows facts about
the program that rustc must not assume:

| Blue knows | Because | Lever it enables |
|---|---|---|
| each definition's identity | `def_hash`, the b3 of the resolved tree (mondou, H3) | memo: a repeated call with the same inputs is a lookup, across calls, frames, runs and machines |
| which definitions are pure | capabilities name every effect (SAFETY.md) | memo and reordering are safe exactly where no capability is used |
| the whole program and its data at build time | the Bluefile, the lock, the generators | bake: what is computable at build time costs nothing at run time |
| which inputs changed | content identity of inputs and definitions | incremental: work in proportion to the change, never to the whole state |
| that a pure map runs over a grid or a list | the AST and the types | data-parallel: one GPU compute pass (engawa) instead of a CPU loop |
| which arguments are constant | rules and configuration are blue data | partial evaluation: an interpreter of rules folds into straight code |
| that a run is deterministic | seeded randomness, no wall clock, declared capabilities | results cache and replay exactly (H4) |

The floor is parity: `chuuzou` compiles blue to native code at 0.98x to
1.61x of Rust today (section 1.4.1). Above the floor, every gain comes from
a lever in the table.

**The rule for every design and every change in blue:** name the lever the
work can use, or say why none applies. A design doc carries the question in
its decisions; a hot path carries its lever in its `@doc`.

**The receipt:** a speed claim is a ratio per workload, measured against a
straightforward Rust program of the same job, with the command that
produces it, and held by the bench ratchet (HORIZON H7). "N times faster
than Rust" is never a slogan; it is a row with its workload, its lever, its
ratio and its baseline. The game engine design (branch
`engine/hd2d-tactics`, `docs/ENGINE.md` section 4.1) names where it uses
each lever.

blue runs scripts at the speed of Python and Ruby or better, and checks and
formats a whole tree in well under a second, through one pipeline (parse →
check → erase → run). Each item below names its expected gain. A gain marked
measured comes from section 1 or 4; every other gain is an estimate from the
sample shares in section 2. The items are in order of gain over risk.

### 3.0.1 Five rules for speed work

Blue wins speed by doing less work, from what it knows (section 3.0). Five rules follow:

- **Measure the term before the lever.** A run costs build, start, front end, dispatch,
  name lookup and the program's own work; profile which one leads (`blue run --timings`,
  `sample`) before changing anything, and keep the change only on a measured gain.
- **Levers are chosen by default.** Blue picks the lever from a fact it holds (a
  definition's content hash, its purity, a frame's version, the nix store), names the
  choice in a receipt (the door receipt), and gives it an off switch (`BLUE_MEMO=off`,
  `BLUE_DOOR=walker`, `BLUE_FUSE=off`, `BLUE_FOLD=off`, `BLUE_NATIVE=off`). The author never needs a flag
  to be fast. The shipped rules are the table in section 1.4.0: a pure definition that
  calls itself twice runs memoized, a chain of pure callbacks runs as one pass, and a
  pure call on literals in a loop runs once.
- **Defaults cascade per atom.** A definition (then a region in it) takes its
  defaults from its own facts: its blueshift position on each axis, its effects over
  the call graph, its shape in the AST, its placement. Each default is a Horn rule
  (facts imply a lever), so annotating or purifying one definition turns on defaults
  for it and for every caller it completes. A new capability names the rule it adds.
  This is not only about speed: every automatic choice blue makes is a fact, a rule,
  an exact fallback and a receipt with a switch, and meets the contract in
  [FACTS.md](FACTS.md) §2 before it ships.
- **A cache is keyed by a fact that only grows**, so it has a miss path and no
  invalidation: content hashes, frame versions, store paths.
- **Rust is for what blue cannot reach**: the evaluator and its seams. Every decision,
  plan, rule and library word is blue. A word moved to Rust for a measured speed-up
  goes back to blue once chuuzou compiles it to native code, and the road ends with
  blue hosting itself.

### 3.1 Linear library words, with a gate (built in part)

Make every builtin that a script uses on a large list native and linear. Done
for `distinct`, `frequencies`, `shuugou::unique` and
`mokuroku::name_collisions` (section 4). Next: a census of the builtins that
still run as Lisp (42 today), each moved to Rust, and
a conformance row per word with a size that a quadratic form cannot finish
inside the row's budget. Gain: 10× to 1000× on the affected programs.

### 3.2 Lexical addressing in the tree-walker (upstream, tatara-lisp-eval)

Resolve each local to `(depth, slot)` when a closure is made. Keep frames as
`Vec<Value>` without a lock (a frame is never shared across threads; `Send` is
kept by the value types, not by a lock per frame). Intern symbols to integers
and hash globals with a fast hash. Do not allocate a frame for a call that
captures nothing. The functions in 2.1 are about two thirds of the `fib`
samples. Expected gain (estimate): 2× to 2.5× on call-heavy code.

### 3.3 A real VM tier (upstream, tatara-lisp-eval)

- `Caller` runs a VM-compiled closure in the VM. No lift to the walker.
- `LoadGlobal` reads a slot that is resolved when the chunk is linked, with a
  guard on the global's version.
- Captures without a lock.
- Type-directed opcodes for the blueshift rungs that know a type: `AddInt`,
  `LtInt` with an overflow check, so a typed `def` skips the dispatch on
  `Value`.

Then make the VM the evaluator of `blue run`. One semantic difference (a macro that calls an earlier top-level
definition) must close first, with a conformance row. Expected gain: 2× to 3×
over 3.2, which puts `fib` near Python.

### 3.4 Tiered execution: interpret, count, compile the hot definitions

This is just-in-time partial compilation, keyed by content.

1. **Tier 0, the walker.** Every definition starts here, so startup pays no
   compile cost.
2. **Counting.** Each definition has a call and loop-back counter, keyed by its
   `def_hash` (mondou's identity: the resolved tree with each callee replaced
   by its hash). A definition that passes a threshold is hot.
3. **Tier 1, bytecode.** A hot definition compiles to a VM chunk. The chunk is
   content-addressed by `def_hash` and the engine identity (blue version,
   tatara-lisp-eval version, opcode set). A chunk changes only when the
   definition or a callee changes.
4. **Tier 2, native code.** A definition that stays hot in tier 1 and whose
   type feedback is stable (for example, only Ints reach `fib`) compiles to
   machine code through Cranelift. Cranelift is pure Rust, so it keeps CONTAIN
   THE C: no C is linked.
5. **Deoptimization.** Each tier-2 function guards its assumptions (the
   argument is an Int, an add did not overflow, a global still has the version
   the code was compiled against). A failed guard returns to tier 1 at that
   call with the frame rebuilt from the guard's map of live values. Tier 1
   returns to the walker in the same way when a form needs `Dispatch`.
6. **Persistence.** The chunk store lives in
   `$XDG_CACHE_HOME/blue/<engine-identity>/<def_hash>`. A second run of the
   same script loads tier-1 chunks instead of compiling them. A miss is always
   correct, so eviction is safe. Native code is not
   persisted at first; it is cheap to recompile from the chunk.
7. **The AOT twin.** `native/` already lowers a checked program to a typed
   Rust AST (`chuuzou`) and emits it through `tatara-rust-emit`. Its passes
   (qualify, represent, tail calls to loops) are the same passes tier 2 needs.
   Tier 2 reuses them and emits Cranelift IR instead of Rust text, so the AOT
   path and the JIT share one lowering.

**Honest evaluation.** Measured today, the VM is not faster than the walker
(1.4). A counter that promotes to the VM now would make `pipeline` 2× slower.
So the order is fixed: 3.2 and 3.3 first, then the counter and tier 1, then
tier 2. Tier 2 costs (not measured here): Cranelift adds to the binary size
and to the time before a hot function runs fast, and the wasm surface cannot
carry it (that surface keeps tiers 0 and 1). Tier 2 is worth building only when a measured
workload is still CPU-bound after tier 1.

### 3.5 Resolve once per run

`check_stage` returns its resolution, and `lower` uses it instead of walking
the tree again (a resolution keys references by node address, so the same
tree must reach both). `blue run` formats from the pipeline's own check
instead of running `check_entry` first. A process keeps a cache of parsed and
admitted bidama files, keyed by path and content hash, and of the builtin
name table. Expected gain: the kueri script from 82 ms to about 40 ms;
`fmt --check` on all files from 4.0 s to about 2.5 s.

### 3.6 Shared bidama analysis

`mkBidama` writes each bidama's parse, resolution and check result as an
output. A run that imports kueri then reads the
result instead of computing it. Expected gain: an import-heavy run from about
40 ms (after 3.5) to about 10 ms.

### 3.7 Processes share the macro table

`fork` shares the macro table by `Arc` and copies it only on a write. The drop
of the copies leads the `spawn` profile (2.4). Expected gain: 2× or more on
`spawn`; measure before and after.

### 3.8 A startup image

A snapshot of the evaluated stdlib and of the builtin name table, keyed by the
blue version, loaded by `mmap`. Today the runtime stage is 1.1 ms and the name
table 0.5 ms of a 2.1 ms run. blue already starts faster than Python
(6.4 ms against 12.9 ms for hello) and Ruby (33.0 ms). Gain: at most 2 to 3 ms per run. Low
priority.

### 3.9 Optimize the tooling crates in the dev profile (built 2026-11-09)

`blue-lang-check`, `blue-lang-syntax`, `blue-lang-fmt` and `blue-lang-pkg`
build at `opt-level = 3` in the dev profile, as the evaluator crates do.
Measured on a shared machine, `blue fmt --check` over the 528 tracked `.b`
files with the dev binary: 97.2, 98.5, 106.9 s wall (user 95.6 to 101.3)
before, 22.2, 19.6, 19.7 s (user 18.5 to 18.8) after. A one-line change to
`blue-lang-check` then rebuilds `cargo build -p blue-lang-cli` in 6.1 to
9.6 s wall (user 2.7) against 5.6 to 5.9 s (user 2.6) before.

`cargo build --profile release-local` is the release build for the machine
it runs on: incremental, 256 codegen units. After a one-line change to
`blue-lang-runtime` it rebuilds `blue` in 4.0 to 4.8 s wall (user 2.3)
where `--release` takes 23.8 to 25.7 s (user 39.5), and its `blue test
bidamas/isshou` runs within noise of the release binary (6.4 s both). The
shipped build stays on `release`.

### 3.10 Not planned

- A content-hash cache for the formatter. `canonical.rs` measured the corpus at
  0.08 s CPU for formatting alone, and section 2.5 agrees: the formatter is 10%
  of `fmt --check`.
- Removing the counting allocator. It costs about 2%, and `blue profile`
  needs it.

## 4. Built on this branch

| change | where | before | after |
|---|---|---|---|
| `blue run --timings` | `blue-lang-runtime::timings`, the pipeline, `canonical.rs` | none | stage times on stderr |
| manifest words bound in the Bluefile's name table | `bluefile.rs` `manifest_names` | 17 unbound names and a suggestion search per Bluefile read | none |
| a Bluefile text is evaluated once per process | `bluefile.rs` `read_bluefile` | once per file and twice per run | once |
| did-you-mean candidates computed once per name and scope | `names.rs` `Walker::suggestions` | once per unbound reference | once per distinct name |
| native `distinct` (same meaning: `blue_equal`, first kept) | `stdlib.rs` | O(n × unique), Lisp | O(n), Rust |
| native `frequencies` (same keys as `hash-map`) | `stdlib.rs` | Lisp fold, a closure call per element | one Rust pass |
| `shuugou::unique` is `distinct` | `bidamas/shuugou` | O(n × unique) | O(n) |
| `mokuroku::name_collisions` groups once | `bidamas/mokuroku` | a filter of all pairs per name | `group_by` |

Effect: `fmt --check` on all files 9.3 → 4.0 s, regen 75 → 6.8 s, wordfreq
98 s → 0.10 s, a kueri import 145 → 88 ms (user CPU).

Each change has a test with a recorded red run: the manifest-name test fails
with 17 unbound words when the scope is not pushed; the read-once test counts
2 evaluations when the cache is bypassed; the `distinct` test fails when the
registration is renamed and when an Int is keyed apart from a Float; the
`frequencies` test fails when the registration is renamed and when a count is
wrong. Spec row `lists.distinct.keys` pins the keys `distinct` must keep
apart.

## Ledger

One row for each item of section 3.

✅ built and tested · ⏳ in progress · ❌ not built

| Item | State | What makes it true |
|---|---|---|
| 3.1 Linear library words | ⏳ in progress | `distinct`, `frequencies`, `shuugou::unique` and `mokuroku::name_collisions` are linear (section 4, spec row `lists.distinct.keys`). `hex_encode` and `hex_decode` are native, and shinsuu's `bytes_hex` and `hex_bytes` wrap them (1.6, spec rows `strings.hex_*`). The census of the builtins that still run as Lisp, and a size row per word, do not exist. |
| 3.2 Lexical addressing in the tree-walker | ❌ not built | The work is in tatara-lisp-eval. This repository holds no measurement of it. |
| 3.3 A real VM tier | ⏳ in progress | `blue run` takes the VM as its default door where the conformance columns agree, and the walker otherwise (1.4, `crates/blue-lang-runtime/src/door.rs`, `crates/blue-lang-cli/tests/door.rs`, the conformance door gate). Built in tatara-lisp-eval 0.4.19: globals cached under write stamps, operators in place, allocation-free calls (`tests/vm_operators.rs`, `tests/vm_allocations.rs`). Built in 0.4.21: a closure handed to a native higher-order word runs on one VM for the whole traversal (`a_hof_callback_runs_on_one_reused_vm_and_never_lifts` in tatara-lisp-eval's `vm/parity.rs`), so a lambda argument keeps a program on the VM door. Not built: captures without a lock, and a callback that falls back to the walker's evaluation still lifts. |
| 3.4 Tiered execution | ⏳ in progress | The R7 profile counts each definition's outermost calls by `def_hash` (`store::profile`), which picks the native tier; no VM promotion exists. The VM was slower than the walker on the common script shape until tatara-lisp-eval 0.4.21 (1.4), which is why 3.2 and 3.3 were put first. |
| 3.4 T3: ahead of time per `def_hash` | ⏳ in progress | One derivation per `def_hash` from a slice that is a function of the hash (`nix/native-defs.nix`, `checks.native-def-keys`), the `native` tier of the store (`store::native_artifact`), and `BLUE_NATIVE=on` answering an Int call from an artifact (`checks.native-defs`), all built (1.7.1). An in-process call is built (W1 of docs/FACTS.md): 2,000 calls of a native `fib` ran 4.01 s as processes and 0.06 s through the library (debug build, the same answer, and the interpreter 0.19 s). Values beyond Int: Bool, Float and Str cross the native tier (FACTS.md W1). Not built: the VM door, the hot set from a fleet counter, a project word for any program, values beyond those scalars. |
| 3.5 Resolve once per run | ⏳ in progress | `lower` takes the check stage's `ResolvedProgram` (`crates/blue-lang-runtime/src/pipeline.rs`). A check cache keyed by definition hash is on by default (`crates/blue-lang-runtime/src/check_cache.rs`, `BLUE_CHECK_CACHE`). Each check stage resolves its program at most once, and its rules read that resolution (2.7, `the_check_stage_resolves_a_program_at_most_once`). `blue run` still runs two check stages, `check_entry` for the formatter and the pipeline's own. |
| 3.6 Shared bidama analysis | ⏳ in progress | `mkAnalysis` (`bidamas/mk-bidama.nix`) writes each bidama's check entries, and `mkBlueWithBidamas` points `BLUE_CACHE_SHARED` at them. Measured 2026-11-16 on a loaded host: a script that imports kueri spends the same check time with the shared store as without it (137 and 142 ms cold), so no gain is shown yet. Re-measure on a quiet host. |
| 3.7 Processes share the macro table | ❌ not built | The work is in tatara-lisp-eval. No measurement of `spawn` before and after exists. |
| 3.8 A startup image | ❌ not built | No snapshot of the stdlib or the name table exists. |
| 3.9 Optimize the tooling crates in the dev profile | ✅ built | `Cargo.toml` sets `opt-level = 3` in the dev profile for `blue-lang-check`, `blue-lang-syntax`, `blue-lang-fmt` and `blue-lang-pkg` (section 3.9 has the measurement). |
