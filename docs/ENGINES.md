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
| E3 | rule R18: a run of independent, commuting reads in one block runs at once: HTTP reads to one host over one kept-alive connection, others on the scheduler pool; the first error in program order is raised, and the tape records the calls in program order | `proc::parallel`, `net`'s per-host state (R16) | `BLUE_BATCH=off`; `--timings` counts `batched` | a conformance column that runs with batching on and off and holds both to the walker; replay of a batched run reads the same tape |
| E4 | a definition's effect summary: a call to a definition whose sites are all reads is a read, so independence crosses calls | `chained` (the join `host_reach` and `suspension_reach` share) | as E3 | E3's column on rows whose reads sit behind helpers |

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
  (`mathscape-compress/src/egraph.rs`, shipped). blue
  is the second use, so the wrapper is extracted into a shared typed surface
  before blue writes a second one.

### Phases

| Phase | Builds | Reuses | Lever, switch | Lock |
|---|---|---|---|---|
| S1 ✅ | the cost model: a price per word, a cost per call and per element in steps and allocations, measured from probe programs at two sizes on the walker with every lever off, and kept by binary identity; an allocation weighs what its time against a step's solves to; `estimate` prices an erased form, a list of unknown length taken at 1000 elements (`blue_lang_runtime::cost`, `blue cost FILE`) | `--timings`' steps and allocations, the counting allocator, the cache root | none (a fact) | `tests/cost.rs`: on four pairs of equal forms (a fused chain and the chain, a length and the length of a map, a list and the list reversed twice, one map and two) the model orders each pair as `blue run` measures it, and the table is measured once and read after |
| S2 | a shared e-graph crate: the typed surface over `egg` that mathscape and blue both use, with the language given by the caller | mathscape's `egraph.rs` wrapper, moved, not copied | none | mathscape's equivalence tests and blue's new ones, both on the moved crate |
| S3 | blue's rewrites as rules: fusion's `REWRITES`, the fold as a constant analysis, R17's rename; each rule a row with a witness and an okite law that both sides agree on every input class | `fuse::STAGES`, `fold`, the FORM axis's law shape | none (parity) | on the whole corpus, saturation then extraction gives the forms today's passes give |
| S4 | rule R19: saturate each definition within a node and time budget, extract by S1's cost, keep the old form when the costs tie, and cache the choice by definition hash | `check_cache` (a new `Pass::Saturate`), the fold's recall | `BLUE_SATURATE=off`; `--timings` counts `saturated` with cost before and after | the bench gate holds or improves every workload; a conformance column with saturation on agrees with the walker |

The ratchet holds S4: a workload the search makes slower blocks the land,
and a tie keeps the form the author wrote.

## 3. Order

1. S1 first. The cost model is the missing fact under both engines: R17's
   decision and E3's batch size read it too.
2. E1, E2, E3, then E4. Batching gives the larger measured win on programs
   that talk to the network.
3. S2, S3, then S4.

Each phase lands on main alone, with its lock, as the W phases did.
