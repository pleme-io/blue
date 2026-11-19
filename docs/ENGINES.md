# The two engines W3.4 and W4.2 wait on

Two rows of [FACTS.md](FACTS.md) §5 wait on machinery that blue does not
build yet: W4.2 (independent effects batched) on an **effect graph**, and
W3.4's search over equivalent forms on **equality saturation and a per-form
cost model**. This page is the plan for both: the destination first, then
the phases, each phase with what it reuses, its lever, its switch and the
lock that proves it. A phase is done when its lock is green on main.

## 1. The effect graph (W4.2)

### Destination

For each definition, blue knows every call that reaches the host, the
resource it touches, and which earlier calls its arguments depend on. Calls
that do not depend on each other and whose effects commute run together:
requests to one host share a round trip, independent reads overlap. The
answer, the error raised and the receipt are the ones the program gives in
the order it is written.

### Precedent

- Haxl (Marlow, Brandy, Coens, Purdy; ICFP 2014, "There is no fork"):
  independent data fetches in an applicative block are batched into one
  round trip per source, with no change to the program's text.
- In blue: `reach` already names each host capability a definition reaches,
  with a chain (`reach::host_reach`); the process tape records each effect
  call in order (`proc::trace::TapeEntry`); R15 holds the idempotent-method
  table; the scheduler pool and `proc::parallel` run work apart.

No pleme-io repository builds an effect graph (searched 2026-11-19); this
is new, and it lives in `blue-lang-runtime` beside `reach`.

### Phases

| Phase | Builds | Reuses | Lever, switch | Lock |
|---|---|---|---|---|
| E1 ✅ | `effects::graph` and `effects::graphs`: each definition's sites in evaluation order, a site a call that reaches the host (a builtin's capability, or a definition `host_reach` says reaches it), with its resource when the arguments make it a literal (an HTTP request's host and port, from the url or the literal start of an interpolation; a file word's path), the sites it depends on through locals and through the test of an `if` it runs under, and `deferred` for a site in a function written in place | the erased tree `reach` walks, `reach::builtin`, `host_reach` | none (a fact) | `effects::tests`: two GETs that share nothing are independent, one whose url reads another's answer is not, a write under a test depends on the request the test reads, a callback's site is deferred, a local named like a word is no site, a call to an effectful definition is a site with no resource |
| E2 ✅ | `effects::access` and `effects::commute`: every host word is a read (`READS`: file and directory reads, the environment, the log read), a write to the one resource its first argument names (`WRITES`), or ordered, the default for a word on neither list (a clock, entropy, a process, a session, a device, a database); an HTTP request reads when its method is one of `SAFE_METHODS`, the list R15 retries, else it is ordered. Two reads commute; a write commutes only with a call on a different named resource; an ordered word commutes with nothing | R15's method list, moved into `effects` and read by `net` | none (a table) | `effects::tests`: reads commute, a read and a write of one file do not, writes to two files do, a write to a path not known commutes with nothing, the clock and a POST are ordered; every listed word is a host word and none is both |
| E3 ✅ | rule R18 (`effects::batch`, at erasure after R17): in a body, a run of two or more local bindings one after another, each a GET, HEAD or OPTIONS `http_request` with a literal method whose arguments name none of the run's earlier bindings (independent by E1, commuting reads by E2), becomes one binding to `http_batch` and one binding per answer; a body that binds `http_request` itself is left as written. `http_batch`, a network word, sends each request on a thread of its own and answers in the order listed, raising the first error in that order; the tape records it as one call whose answer lists the answers, and replay with the same binary makes the same rewrite | `http_request`'s argument reading and sending, split out (`net::Request`); R15's retry and R16's timeout per request | `BLUE_BATCH=off`; `--timings` counts `batched` | `tests/batch.rs`: against a server that holds each request 300 ms, two GETs are held open at once, and one after the other with the switch off, with the same answers; `effects::tests` for the rewrite (a read of an earlier answer ends the run; a POST, a lone read and a shadowed word stay as written) |
| E4 ✅ | summaries across calls: `effects::graphs` gives each definition that reaches the host an access, a read when every site it makes reads (a fixed point that starts at ordered, so a helper that calls itself stays ordered), and a call to it carries that access, so two calls to a helper that only reads commute. R18 batches a call to a request helper, a definition whose whole body is one safe `http_request`, when its arguments are literals or plain names: its request is written in place with the arguments substituted, so nothing is evaluated twice, and a global it names is a resolved key no local can shadow | `chained`'s fixed-point shape, R18's rewrite | as E3 | `tests/batch.rs` `reads_behind_a_request_helper_are_sent_at_once_too`; `effects::tests`: a helper that only reads is a read and one that reads the clock is ordered; calls to a request helper join a batch, one with a computed argument does not |

Writes are not batched in this plan. A write that fails after another
succeeded leaves state that program order would not, so writes stay in order
until a row of E2 can prove a pair safe.

## 2. Equality saturation and the cost model (W3.4)

### Destination

blue's rewrites stop being passes run in a fixed order (fold, then fusion,
then the index, then R17). They become rules over one e-graph per
definition. The graph is saturated within a budget, and the form a run uses
is the cheapest one a measured cost model finds, decided once per definition
and recalled by its hash, as the fold is.

### Precedent

- egg (Willsey et al., POPL 2021): e-graphs with rebuilding, e-class
  analyses, and extraction by a cost function.
- Cranelift's aegraphs (Fallin, 2023): an acyclic e-graph in a production
  compiler's mid-end, which its authors measured at 7 to 8 % more compile
  time for about 2 % faster code. So saturation must be paid once per
  definition and cached, never per run.
- In pleme-io: mathscape realizes its lattice as an `egg` e-graph
  (`mathscape-compress/src/egraph.rs`, shipped). Read on 2026-11-19, its
  wrapper is all mathscape's own: its language (`MathscapeLang`), the bridge
  from its `Term`, its algebraic probes. The two share `egg`, not a shape, so
  blue has its own typed surface over `egg` rather than a crate extracted
  from mathscape that neither fits.

### Phases

| Phase | Builds | Reuses | Lever, switch | Lock |
|---|---|---|---|---|
| S1 ✅ | the cost model: a price per word, a cost per call and per element in steps and allocations, measured from probe programs at two sizes on the walker with every lever off, and kept by binary identity; an allocation weighs what its time against a step's solves to; `estimate` prices an erased form, a list of unknown length taken at 1000 elements (`blue_lang_runtime::cost`, `blue cost FILE`) | `--timings`' steps and allocations, the counting allocator, the cache root | none (a fact) | `tests/cost.rs`: on four pairs of equal forms (a fused chain and the chain, a length and the length of a map, a list and the list reversed twice, one map and two) the model orders each pair as `blue run` measures it, and the table is measured once and read after |
| S2 ✅ | `blue-lang-saturate`, the one typed surface blue reaches `egg` 0.11 through: an erased tree encoded one to one as a `RecExpr` over `egg`'s `SymbolLang` (a list headed by a symbol with arguments is that symbol's node, any other list a `#list` node, a literal a leaf whose name starts with a mark no symbol can start with), rules written as patterns, `equivalent` (proved, refuted when the graph saturated, or unknown at a limit) and `cheapest` (extraction by a price function of a node's name and its children's costs, the written form kept unless something is cheaper), within `Limits` | `egg` | none | `tests/saturate.rs`: every atom kind and a call with no arguments round-trip; a rule proves `reverse(reverse(xs))` equal to `xs` and refutes `reverse(xs)`; extraction returns `length(xs)` for `length(reverse(reverse(xs)))` and keeps a form with nothing cheaper |
| S3 ✅ (fusion) | `saturation::rules`: fusion as three form rules, one per stage word, each handing the tree its pattern matched to `fuse::fuse`, so which chains fuse and the purity that decides it stay fusion's own; a fused tree keeps the unfused chain as its fallback, which in the graph is the class it joins, so it goes in as an opaque leaf (`%fused:N`) whose tree a side table holds; `node_price` is the cost model node by node (a function written in place costs its body once per element, a `try` its body, a `catch` nothing); `cheapest` extracts and puts the fused trees back. `blue-lang-saturate` is published with the runtime (operator, 2026-11-19). The fold, the membership index and the builder stay passes: each is an evaluation or a data-structure choice, not a rewrite between forms | `fuse::fuse`, `cost::estimate`, `saturate::form_rule` | none (parity) | `saturation::tests`: on a reduce-filter-map chain, a map over a map, a filter over a filter, a callback that prints and a word that is no stage, saturation then extraction gives the tree fusion gives; a fused chain is cheaper, a lone stage keeps its price |
| S4 ✅ | rule R19 (`saturation::program`, in erasure in place of the fusion pass when it fires): each outermost call headed by `map`, `filter` or `reduce` that no local binds is saturated within the default limits and replaced by the cheapest form the measured table prices, the written one on a tie; only that call is rebuilt, so the definition keeps its positions, and a fused call is fusion's own tree. The decision, fused or kept, is kept in the check cache (`Pass::Saturate`) by the call's text: a recalled `fused` runs fusion again, which decides purity itself, so a stale decision can cost a speedup and never an answer. The fact it needs is a measured table, which `blue` installs from its cache and never measures during a run. `blue-lang-saturate` pins `egg` 0.9.5: 0.10 and later time each run with `quanta`, whose clock calibration cost about 200 ms on the first saturation of every process | `check_cache`, the fold's recall shape, S1's table, S3's rules | `BLUE_SATURATE=off`; `--timings` counts `saturated` | `tests/saturate.rs` (CLI): no table, the fusion pass fuses; after `blue cost`, R19 decides the chain once, recalls it after, and its switch hands it back to fusion, with the same answer each time; `saturation::tests` `a_rule_that_fires_again_on_a_tree_it_has_seen_lets_the_graph_saturate` (red at the time limit) |

The ratchet holds S4: a workload the search makes slower blocks the land,
and a tie keeps the form the author wrote.

## 3. Order

1. S1 first. The cost model is the missing fact under both engines: R17's
   decision and E3's batch size read it too.
2. E1, E2, E3, then E4. Batching gives the larger measured win on programs
   that talk to the network.
3. S2, S3, then S4.

Each phase lands on main alone, with its lock, as the W phases did.
