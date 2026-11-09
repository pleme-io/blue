---
kind: explanation
summary: "Native async in blue, DESIGN: one ontology of every async concept as a blue word over parked processes, the mutually exclusive architectures as blueshift positions with defaults, the integration with every system blue already has, and one test matrix that runs every position against the same oracle"
---

# Native async: the design of record

**Tier: PARTIAL (2026-11-09). The process runtime under it is built, and A1
is built: `node_time`, `sleep_for`, `sleep_until`, `after`, `deadline`,
`timeout`, `context` and `remaining` on node time, the virtual clock in `blue
test`, and `net_wait` in the node loop over the `tcp_*` words (2026-11-09).
A run replays from its receipt (`blue run --record`, `blue replay`, HORIZON
H4). Narrowing a deadline inside a process, and phases A2 to A7 are DESIGN.** Operator, 2026-11-06: *"full batteries included async
programming … native … all the semantics around async … the most purely
ontologically complete async native programming in bluelang … honors all
other systems we have and integrates with them … blueshift, in the sense that
we can complete test and express mutually exclusive architectures."* The
roadmap row is the async track in [`ROADMAP.md`](ROADMAP.md). The verbs are
the `heikou` space (並行, *concurrent*), catalogued in
`bidamas/mokuroku/graph/heikou.b` (24 verbs, all `absent`).

## Destination

Every concept async programming has is one blue word with one meaning, and
each is a property of the language, not of a library over it. A program that
declares nothing gets the best default for every conflict. A program that
needs the other side of a conflict declares a position, and `blue shift`
reports it. Every position runs against one oracle: the deterministic node
with a virtual clock, where a run is a replayable trace. So an architecture
blue can express is an architecture blue can test, and two exclusive
architectures are two rows of one matrix, not two languages.

## What exists (measured 2026-11-06)

| Piece | Where | State |
|---|---|---|
| processes: `spawn`, `spawn_link`, `send`, `receive` with timeout, `self`, `link`, `monitor`, `exit`, `trap_exit` | `crates/blue-lang-proc/src/node.rs`, docs rows in `crates/blue-lang-runtime/src/docs.rs` (Actor) | built; one VM and one interpreter per process |
| supervisors: one_for_one, one_for_all, rest_for_one, simple_one_for_one | `crates/blue-lang-proc/src/lib.rs` | built; no restart window, no backoff |
| deterministic interleaving, crash traces, bisect | `crates/blue-lang-proc/src/{node,trace,bisect}.rs` | built; the `:idle` lane is a real thread and not replayable |
| a primitive that parks and is retried with its stack intact | `tatara-lisp-eval/src/vm/run.rs` (`Vm::park`) | built; used by `receive` |
| the node loop advances to the next deadline | `node.rs` | built; it sleeps the thread when idle |
| node-time timers: `node_time`, `sleep_for`, `sleep_until`, `after` | `node.rs`, `tests/timers.rs` | built (A1); a process parks on a `Wait::Timer`, the program drives the node until the time; `after` timers fire in deadline order, ties in the order set |
| the context record: `context`, `remaining`, `deadline`, `timeout` | `node.rs` | built for the deadline field (A1): `spawn` copies it, every wait raises `:timeout` at it; the program narrows it, a process holds the one it was spawned under (narrowing inside a process is A2); cancel state, trace id and access join with A2, A3 and `mitoshi` |
| the virtual clock in `blue test` | `blue-lang-test` `Guard::clock`, `Account::clock` | built (A1): `blue test`, the conformance rows and the language server's live tests read the virtual clock; `blue run` reads the wall clock |
| readiness word `net_wait` over `poll(2)` | `node.rs` (`Wait::Net`), `readiness.rs`, the `tcp_*` words in `blue-lang-runtime/src/net/stream.rs`, `tests/net_wait.rs` | built (A1, 2026-11-09): a process parks on its sockets, the node loop polls them beside the timers; on the virtual clock a wait with nothing ready jumps to the next deadline |
| a run replayed from its receipt | `blue run --receipts DIR --record`, `blue replay <receipt>`, `HostIo::through`, `blue-lang-cli/tests/run_replay.rs` | built (HORIZON H4, 2026-11-09): every host answer on a tape per process, receipt version 6; the replayed receipt equals the original's |
| every I/O word (`http_request`, `nats_*`, `pg`, `exec_capture`, `read_file`, `sleep_ms`) | `crates/blue-lang-runtime/src/{net,sys}.rs` | blocks the node thread |
| `heikou` (map, all, any, race, scope, timeout, deadline, cancel, throttle, retry, …) | `docs/STDLIB.md`, `heikou.b` catalogue | absent |

Recorded decisions this design keeps: blue is **uncoloured by construction**
and the capability belongs to the frame (`theory/BLUE-EXCLUSIVITY.md`
§II.11); tokio is refused, one readiness word replaces it (`docs/HTTP2.md`
decision 2); processes share nothing (`docs/STDLIB.md`); supervision is the
default for a service and a `try` around a handler is refused
(`docs/BUILD-STACK.md` §5); WASM is the default runtime
(`docs/BUILD-STACK.md`). Two theory statements are stale and are corrected when
phase A1 lands: `theory/BLUE.md` §V.8 says processes share globals (each has
its own VM), and `theory/BLUE-GAPS.md` G11 says no crate depends on
`blue-lang-proc` (`blue run` does).

## The ontology: every async concept, named once

A task is a process. Everything else is defined from that, so no concept has
two mechanisms.

| Concept | Blue word | Meaning | Mechanism |
|---|---|---|---|
| task | `spawn(f)` | a computation that runs beside the caller | a process |
| handle | the value `spawn` returns | names one task; join, cancel and monitor go through it | pid plus a monitor reference |
| await | `await(h)` | the task's value, or its error raised again with the task as cause | `receive` of the monitor's result message |
| suspension point | any word that may park | where a task gives up the scheduler | `Vm::park` |
| effect `suspends` | inferred per definition, like reach | whether a definition can reach a suspension point | the reach analysis, which already separates `Cacheable` from `Volatile` |
| yield | `yield()` | give up the scheduler without waiting | a park that is ready at once |
| sleep, timer | `sleep_for(ms)`, `sleep_until(t)`, `after(ms, msg)` | wait for time; a message at a time | a node deadline, never a blocked thread; `sleep(secs)` and `sleep_ms` stay host words that block until A3 parks them |
| deadline | `deadline(at, f)` | f must finish before `at`, and so must everything it starts | a context field inherited by `spawn` |
| timeout | `timeout(ms, f)` | `deadline(now + ms, f)` | the same field |
| cancellation | `cancel(h)` | ask a task to stop; it stops at its next suspension point, then after a grace period it is killed | an exit signal with a reason, delivered at park points |
| context | `context()` | the deadline, cancel state, trace id and access that a task inherits | a record copied into every `spawn` |
| structured scope | `scope(fn(s) … end)` | tasks started with `s.spawn` cannot outlive the scope; an error in one cancels the rest | a supervisor process owned by the frame |
| all, any, race | `all(fs)`, `any(fs)`, `race(fs)` | join every result; the first success; the first to finish, the rest cancelled | `scope` plus `await` |
| map, for_each | `heikou::map(f, xs, {limit:})` | f over xs with at most `limit` running | `scope` plus a counter |
| select | `select([mail(pat), ready(sock), stream(s), after(ms)])` | wait on mail, I/O readiness, a stream and time at once; one wins | one park over the node's wait set |
| channel | `channel(capacity)` | a bounded queue between tasks | a process that owns the buffer (share nothing holds) |
| stream | `stream(source)` with `pull(s, n)` | values over time, read with demand | a process that sends at most the demand |
| backpressure | demand, capacity | a producer cannot run more than its consumer allows | capacity on channels, demand on streams, a bound on mailboxes |
| rate limit | `throttle`, `limit`, `debounce` | at most n per period | a timer and a counter in a process |
| retry | `retry(policy, f)` | f again on failure, by a `saishikou` policy | timers, never a blocked thread |
| supervision | `supervise(spec)` | restart children by strategy, within a window, with backoff | the built supervisors, reading `saishikou` |
| failure | a task's error | raised by `await`; delivered as a message to a linked or monitoring task | links and monitors |

## Invariants: bad states with no constructor

| Bad state | Why it cannot be built |
|---|---|
| an orphan task that outlives what started it | `s.spawn` exists only inside `scope`; a top-level `spawn` is a supervised child, and `blue check` refuses an unsupervised `spawn` in a service |
| a lost deadline (a callee runs past its caller's deadline) | the deadline is in the context, and `spawn` copies the context |
| a blocked scheduler (a host call that holds the node) | an I/O word parks on readiness; a call that cannot park runs on the blocking lane by declaration (`blocking(f)`), never by accident |
| an ignored failure | `await` raises it; a scope cancels siblings on it; a dropped handle with no monitor is refused by a check rule |
| an unbounded queue | every mailbox, channel and stream has a capacity; the default is bounded, and overflow is a typed refusal or the declared policy |
| a cancel that never arrives | cancellation is delivered at every suspension point, and the grace period ends in a kill |
| a flaky concurrency test | `blue test` runs on the virtual clock and the deterministic node; a failure is a trace that replays and bisects |

## Mutually exclusive architectures, on the blueshift

Each row follows `docs/COMPILE-TIME.md` §7: two ideals, each right somewhere;
a position per site (continuous) or per artifact (a line); the best default
for a program that declares nothing. A position is declared in the file or
the Bluefile, never by an environment variable, and `blue shift` reports it.

| Conflict | Ideal A (where it is right) | Ideal B (where it is right) | Position | Kind | Default |
|---|---|---|---|---|---|
| uncoloured vs coloured async | any function may suspend: glue code, scripts, no split ecosystem | every suspension point is visible in the type: audits, latency-critical code | per definition: from `checked`, a definition declares `suspends` or `never_suspends` and the reach analysis enforces it; below `checked` it is inferred | continuous | inferred (uncoloured); `restricted` requires the declaration |
| deterministic node vs parallel schedulers | one scheduler: replay, bisect, exact tests | N schedulers on N cores: throughput | per artifact: `schedulers(1)` or `schedulers(n)` in the Bluefile | line | 1 for `blue test` and scripts; a service declares n |
| virtual clock vs wall clock | virtual: tests, simulation, time travel | wall: a running service | per artifact: `clock(:virtual)` or `clock(:wall)` | line | virtual in `blue test`; wall in `blue run` and services |
| preemptive vs cooperative | preemption by reduction count: fairness, no starvation | cooperative: no preemption inside a critical section, cheaper | per process: `spawn(f, {preempt: false})` holds the scheduler until its next suspension point | continuous | preemptive |
| share-nothing process vs stackful coroutine | a process: isolation, supervision | a coroutine: cheap, one stack (§7 row L6) | per call site: `spawn` across, `coroutine` inside | both exist | both on |
| mailbox vs channel | a mailbox: one owner, selective receive | a channel: many producers, one bounded buffer | per site | both exist | mailbox; `channel` when a buffer is shared |
| push vs pull streams | push: lowest latency | pull: backpressure by demand | per stream: `stream(src, {mode: :push, capacity:})` | continuous | pull |
| overflow policy | refuse the send: no silent loss | drop the oldest or newest: telemetry, sampling | per queue: `{overflow: :refuse | :drop_oldest | :drop_newest | :block}` | continuous | `:block` for channels and streams; `:refuse` for mailboxes |
| cancel cooperatively vs kill | cooperative: cleanup runs | kill: a stuck task ends now | per cancel: `cancel(h, {grace: ms})`; `grace: 0` kills | continuous | 1000 ms grace, then kill |
| let it crash vs value errors | links and supervisors: services | errors as values: pipelines, parsers | per call: `await` raises; `await_result(h)` returns `{ok:}` or `{error:}` | both exist | `await` raises |
| readiness I/O vs the blocking lane | readiness: thousands of sockets on one thread | a blocking call on its own thread: a library that cannot be polled | per call site: `blocking(f)` | continuous | readiness |
| WASI poll vs WASI 0.3 async | `wasi:io/poll` on wasip2: available now | native WASI 0.3 async: the host schedules | per artifact | line | wasip2 poll until 0.3 is in the component toolchain |

No row is a global switch, and none turns behaviour off: both ideals exist,
and the position chooses where each applies.

## Integration with what blue already has

| System | How async meets it |
|---|---|
| reach analysis and `access` (`docs/SERVICE-ACCESS.md`, KAKOI) | an I/O word needs its capability as today; `suspends` is a reach fact beside `Volatile`; a task's access is its spawner's or narrower, never wider |
| supervision and `saishikou` | `supervise` reads a `saishikou` policy: window, backoff, max restarts; this closes the BUILD-STACK gap where `saishikou` is only a blocking retry |
| services (`docs/BUILD-STACK.md` S8) | each handler runs as a process under the service's supervisor; `eigyou/kyuuji` accepts through `net_wait`, not a 5 ms poll |
| crash traces, replay, bisect | readiness events and timer firings join the trace, so an I/O program replays: recorded responses stand in for the network |
| `blue test` | virtual clock and one scheduler by default; `after`, `deadline` and `timeout` run in virtual time, so a 30 s timeout test takes no wall time |
| `mitoshi` tracing | the trace id is in the context; each task is a span whose parent is its spawner |
| streams (`chozou/sutoriimu`, JetStream) | a JetStream consumer is a pull `stream`; acks follow demand |
| `heikou` catalogue (mokuroku) | the 24 verbs become built rows; `arika` finds them |
| the kernel bidamas (kaaneru) | a BPF ring buffer is a `stream` source |
| WASM components | the same words; the wasip2 rung parks on `wasi:io/poll` |
| the blueshift report | `blue shift` lists every async position and what holds it |
| arika and B0070 | the `heikou` words enter `WORD_SHAPES`, so a hand-rolled retry loop is named as a copy |

## The test matrix

One oracle: the deterministic node with the virtual clock. Every program in
the async conformance set runs at every line position (`schedulers`, `clock`,
the WASM rung) and at both ends of every continuous row it uses.

| Gate | Proves | Red run |
|---|---|---|
| A-ontology | each ontology row has a word, a doc row, a test and a catalogue row | delete one word's test |
| A-determinism | a program run twice at `schedulers(1)` gives byte-equal traces | seed the scheduler from the clock |
| A-parity | a program's observable results are equal at `schedulers(1)` and `schedulers(n)`, except where the program declares a race | make `all` return in finish order |
| A-time | a timeout test runs in virtual time and agrees with a wall-clock run within its tolerance | read the wall clock inside `sleep` |
| A-structure | no task outlives its scope; a failing child cancels its siblings | let `s.spawn` start an unscoped task |
| A-cancel | a cancelled task stops at its next suspension point, or is killed at the end of its grace | skip delivery at one park point |
| A-backpressure | a producer never runs more than its capacity or demand ahead | make one queue unbounded |
| A-no-block | no I/O word blocks the node: a slow socket does not delay another task | make `http_request` block |
| A-colour | at `restricted`, a definition that reaches a suspension point without declaring `suspends` is refused | drop the check |
| A-replay | a crash in an I/O program replays from its trace and bisects | drop readiness events from the trace |

## Phases

No phase builds what a later phase throws away.

| # | Deliverable | Gate | Exit |
|---|---|---|---|
| A1 | `net_wait` in the node loop; `sleep`, `after`, `timeout`, `deadline` on node time; the context record; the virtual clock for `blue test` | A-time, A-determinism | a test with a 30 s timeout runs in milliseconds and replays |

A1 as built (2026-11-06): the timers, the deadline field of the context
record, and the virtual clock. A-time: `tests/timers.rs` and
`blue-lang-cli/tests/virtual_clock.rs` (a 600 s sleep and a 30 s timeout
finish in milliseconds and observe 600 s and 30 s; red run: the virtual clock
sleeping the thread takes the full 30 s). A-determinism: one timed program
of four processes and four timers gives one answer over nine runs; timers
fire in deadline order (red run: newest first misorders, or hangs). Not
built: `net_wait` (HTTP2.md P3), narrowing a deadline inside a process (it
needs the scope compiled into the process's chunk, with A2's `scope`), the
context across `evict`, a timer cancel.

`net_wait` as built (2026-11-09): `net_wait(interests[, timeout_ms])` over
`tcp_listen`, `tcp_accept` and `tcp_connect` handles, level-triggered over
`poll(2)`. A-time and A-determinism hold for it at `schedulers(1)`:
`tests/net_wait.rs` (a 30 s wait with nothing ready takes no wall time and
observes 30 s; a parked waiter lets a ready process and a timer run first;
one program gives one answer over four runs). Red runs: no poll in the idle
loop deadlocks the parked waiter; a child wait that never parks answers
before its peer writes. Not built: `schedulers(n)` (A6), the node time a
process's wait came at on the replay tape (the root's is taped).
| A2 | handles and `await`, `await_result`; `scope`, `all`, `any`, `race`, `heikou::map`; `cancel` with grace | A-structure, A-cancel, A-ontology (first rows) | the heikou catalogue rows for these verbs are built |
| A3 | `http_request`, `exec_capture`, `read_file`, `nats_*`, `pg` park on readiness; `blocking(f)` | A-no-block, A-replay | a slow peer delays no other task |
| A4 | `channel`, `stream`, `pull`, `select`; capacities and overflow policies; `throttle`, `limit`, `debounce`, `retry` | A-backpressure | a JetStream consumer runs as a pull stream |
| A5 | `supervise` with `saishikou` windows and backoff; service handlers as processes (S8) | a supervisor fixture per strategy | a service restarts a crashing handler within its window |
| A6 | `schedulers(n)`; the `suspends` declaration and its check | A-parity, A-colour | the conformance set is green at both line positions |
| A7 | the WASM rung on `wasi:io/poll` | the conformance set on the component | the same programs pass as components |

## Tier ledger

<!-- tier-ledger -->

| Async capability | blue realization | tier |
|---|---|---|
| a task that outlives its scope | `s.spawn` exists only inside `scope` | truly-unrep |
| a callee running past its caller's deadline | the deadline travels in the context `spawn` copies | truly-unrep |
| a blocked scheduler | I/O words park; blocking is a declared `blocking(f)` | parse-time-rejected |
| an unbounded queue | capacity is a required field with a bounded default | truly-unrep |
| an unsupervised `spawn` in a service | a check rule refuses it | parse-time-rejected |
| a suspension point a `restricted` definition did not declare | the reach analysis refuses it | parse-time-rejected |
| a flaky concurrency test | the deterministic node and virtual clock | only-mitigated (C2) |
| parity between one and n schedulers | the A-parity differential | only-mitigated (C2) |

C2 is the external-world ceiling: real parallel runs and real networks are
measured, not typed.
