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

`cost` copies each workload out of the project, runs it once, prints a table
with the wall time (reported, never gated), and judges it against
`bench/cost.baseline` with hadome's `failures_within`: steps may grow 5 per
mille, allocations and bytes 20 per mille. A workload past its tolerance, or
with no row, fails and is named with its delta. A host with no allocation rows
is advisory for them and still gated on steps. `--record` is the only writer
of the baseline: it banks every fall, keeps the old row for a rise inside the
tolerance so the baseline cannot creep, and refuses a rise past it without
`--receipt`, which stays in the file as a `# receipt:` line, as in
`reuse.baseline`.

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

The reports were 57 s for `fmt --check` and 70 to 90 s for regen. The
release build measured 9.3 s CPU before this branch. The dev build (`cargo
build`, the binary `cargo test` and `cargo run` use) takes 26.8 s CPU and 36 s
wall for the same command after this branch. By the same ratio it took
about 60 s before it (an estimate, not measured). The dev profile compiles the evaluator crates at `opt-level = 3`, but not
`blue-lang-check`, `blue-lang-syntax`, `blue-lang-fmt` and `blue-lang-pkg`,
which do the work of `fmt` and `check`. Evaluation in the dev build is near
release speed (`fib` 0.39 s against 0.31 s CPU).

### 1.4 The VM against the tree-walker

`blue run` evaluates with the tree-walker. The bytecode VM runs only blue
processes. A probe build sent the whole program to
`Interpreter::eval_program_vm` instead. User CPU time, s:

| workload | tree-walker | VM |
|---|---|---|
| fib | 0.31 | 0.26 |
| pipeline | 0.85 | 1.64 |
| strbuild | 0.57 | 0.83 |
| spawn | 0.30 | 0.32 |

The VM is 15% faster on a plain recursive function and up to 2× slower when a
lambda goes to `map`, `filter` or `reduce`. Section 2.2 gives the cause.

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
and `tatara-rust-emit` on `PATH`. The VM has no entry that runs a program,
so it has no column.

| program | tree-walker (N) | chuuzou (big N) | Rust (big N) | chuuzou / Rust | tree-walker / Rust per unit of work |
|---|---|---|---|---|---|
| fib (30; 38) | 1243 (cpu 1221) | 88.9 (cpu 87.8) | 68.9 (cpu 66.6) | 1.32 | 861 |
| loop (3M; 300M) | 2685 (cpu 2679) | 246 (cpu 245) | 153 (cpu 149) | 1.65 | 1796 |
| mutual (depth 10,000) | 40 (cpu 22) | 8.6 (cpu 1.6) | 9.1 (cpu 1.6) | 1.00 | 14 |
| shapes, records (1M; 100M) | 7697 (cpu 7684) | 125 (cpu 124) | 133 (cpu 131) | 0.95 | 5875 |
| sums, lists (100k; 10M) | 473 (cpu 467) | 41.6 (cpu 38.0) | 29.0 (cpu 25.1) | 1.51 | 1860 |

chuuzou keeps every `+`, `-`, `*` checked and counts recursion depth
against the board's bound; the twin, as release Rust does, wraps and
counts nothing. That is the gap on fib and loop. On shapes chuuzou is
faster than the twin: a typed parameter is the record's own struct by value
(no tag), an untyped one is `Rec`, whose variants each hold only their
record, and every value is `Copy`. `bench/native.baseline` holds each
path's CPU over Rust's (per unit of work for the tree-walker), per host, in
per mille; the run fails when a path passes its row by more than 500 per
mille, and `--record [--receipt "<why>"]` rewrites it.

sums builds a list of N words one append at a time and sums it by index,
twice: once refcounted and once in a region (`reclaim(:arena, …)`), so
both reclamation strategies run in one program. An append of a literal list
is a push (`kiban_heap::rc_push`, `Region::push_onto`): before that, each
step made a one-word list and appended it, and sums ran at 8.8 times the
twin; after, 1.5. The rest of the gap is the twin's vectorised sum against a
checked add and a bounds-checked index per word.

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

- A lambda that the VM compiles and gives to a native higher-order function is
  lifted back to a tree-walker closure on each call
  (`CompiledClosure::lift_to_closure`, `vm/run.rs`). So `map`, `filter` and
  `reduce` callbacks pay the walker's cost plus the lift.
- `LoadGlobal` looks a global up by name on each access.
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

## 3. The destination

blue runs scripts at the speed of Python and Ruby or better, and checks and
formats a whole tree in well under a second, through one pipeline (parse →
check → erase → run). Each item below names its expected gain. A gain marked
measured comes from section 1 or 4; every other gain is an estimate from the
sample shares in section 2. The items are in order of gain over risk.

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

Then make the VM the evaluator of `blue run`. The semantic difference that
`BLUE-EXECUTION.md` II.1 records (a macro that calls an earlier top-level
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
   correct, so eviction is safe (`BLUE-ENGINE.md` §3.6). Native code is not
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
output (`BLUE-ENGINE.md` §3.6). A run that imports kueri then reads the
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

The hot-definition counter with VM promotion (3.4) is not built, because 1.4
shows the VM is slower on the common script shape today.
