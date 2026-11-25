# blue's specification

Two things live here.

- `spec/*.b` are test files: blue stating its own behaviour in `test` blocks,
  run by `blue-lang-test`'s `every_spec_file_passes`.
- `spec/rows/*.b` is the **executable conformance suite**: one row per
  observable language behaviour, run on every evaluator blue has, with a gate
  that fails when any registry entry has no row. `spec/bidamas/` holds the
  fixture packages its module rows load.

The suite is the yardstick a self-hosted blue must meet: stage 1 and stage 2
of a bootstrap must agree with stage 0 on every row.

## Running it

```
cargo test -p blue-lang-test --test conformance            # the whole suite and the gate
cargo test -p blue-lang-test --test conformance -- lists.  # rows whose id contains `lists.`
cargo test -p blue-lang-test --test conformance -- --coverage-only  # the missing-row gate alone
nix build .#checks.<system>.conformance                    # what CI runs
```

| variable | effect |
|---|---|
| `BLUE_BIN` | the `blue` binary the `cli` column runs; else `target/{debug,release}/blue` |
| `BLUE_COMPONENT`, `BLUE_WASMTIME` | the engine component (`nix build .#blue-component`) and the `wasmtime` the `component` column runs it with; without both the column is blind |
| `BLUE_CONFORMANCE_STRICT=1` | a blind `cli` or `component` column is a failure (the nix check sets it) |
| `BLUE_CONFORMANCE_JSON=path` | also write one JSON line per (row, evaluator), for DuckDB |
| `BLUE_CONFORMANCE_PROBE=1` | print every observation, not only failures |

The report gives pass, pending, fail and blind per evaluator, per area (row
file) and per blueshift position, the pending rows by gap, and the
missing-row gate's totals.

The door gate holds `blue run`'s door (`blue_lang_runtime::door::TABLE`) to
the rows: every row pending on the `vm` alone has a rule naming it, every
rule names such a row (a closed gap turns the run red until its rule goes),
and the door sends each such row's program to the walker.

## The evaluators

| column | what runs the row | what it can observe |
|---|---|---|
| `walker` | `pipeline::run_framed_accounted`, the `blue run` path, with a loader over `spec/bidamas` and `bidamas` and the account `blue run` gives, which names each definition's `def_hash` | value, failure |
| `vm` | the same check, erasure and identities, then `eval_program_vm` (batched expansion, bytecode VM) | value, failure |
| `wasm` | `blue_lang_wasm::eval_tagged`, the module's ABI (no loader) | an Int, "not an Int", or an error |
| `cli` | the `blue` binary: `run --quiet`, `fmt`, `check --format json`, `shift` | output, failure, formatting, diagnostics, rung |
| `static` | the front end in-process: `check_entry`, `format_source_lossless`, `shift_of` | diagnostics, formatting, rung |
| `memo` | the walker with the memo on, cold then warm from disk | value, failure |
| `component` | `blue-lang-component`, the engine as a wasm32-wasip2 component, under wasmtime: the second placement of the program | output, failure |
| `default` | the shipped `blue` binary as a user runs it: no step bound and every default on (fold, fusion, the membership index, the memo and native planners), a 45 s wall-clock limit as its only guard; blind to rows whose outcome is the step bound and to rows that read the node clock or a declared input | value (through `blue run --literal`), output, failure |
| `native` | `BLUE_CONFORMANCE_NATIVE=1`, on x86-64 Linux: the row lowered by `blue ast`, compiled by hashiru through `gen/native-row.b` in `:show` mode, and run | value: what a clean exit writes; any other exit or a signal is `CRASHED`, never a value |
| `scheduled` | the `default` column on four schedulers (`schedulers: 4`): a program's answers at one scheduler and at four must be equal (docs/ASYNC.md A-parity); only rows that start a process or map are run, the rest are blind | value, output, failure |
| `ir` | `BLUE_CONFORMANCE_IR=1`: the row lowered by `blue ast --resolved` and run by kuzushi's evaluator through `gen/ir-row.b` | value, and no reference left live |

`walker` is stage 0 for evaluated rows and `static` for front-end rows.
`component` is judged against `cli`: the same program run natively (`blue
run`) and as the wasm component must print the same bytes, exit the same way
and fail at the same stage with the same message. A difference fails the row
and names the first differing field (`exit`, `stdout at byte N`, `stage`,
`message at byte N`). This is the placement-parity gate (HORIZON H8).
**Any other column that disagrees with stage 0 fails, even when both meet the
row.** An evaluator that cannot observe a kind of row reports `blind`, which
is counted apart and never as a pass. Blind by design: a value on `cli` (the
final-value printer is not the literal renderer, G12), output anywhere but
`cli`, and a `host()` row on `wasm` (the host-linked ABI binds host
primitives the wasm32 module does not).

A row whose evaluator may die (a stack overflow aborts the OS process, a
runaway never returns) is marked `isolate()` and runs in a child process
with a 45 s limit; a death is an observation (`CRASHED`), never a pass.

The `native` and `ir` columns keep one driver contract, kuzushi's
`exit_for`. A driver exits 3 when the backend has no code for the row yet:
an error of a kind in `kuzushi::GAP_KINDS`, or a recursion past blue's
call-depth budget. That row is `blind`, and its reason is on stderr. Any
other error exits 5, and the row is `CRASHED`. The passing counts are
ratchets: `spec/native.baseline` and `gen/ir-rows.baseline`.

## The row format

A row file is blue source that is **parsed, never evaluated**, so reading the
rows depends on no evaluator. Each top-level form is one call:

```ruby
row(ID, SRC, EXPECTATION, OPTION...)
```

- `ID` — `area.subject.case`, unique across the suite.
- `SRC` — the program, as a string (`\n` for new lines; write `#{` as
  `#\u{7b}` so the row file does not interpolate it).
- `EXPECTATION`, one of:

| expectation | meaning | observed on |
|---|---|---|
| `value("[1, 2]")` | the final value, as its blue literal (blue's own `to_s` renderer, okite D0006) | walker, vm, wasm |
| `fails(:eval, "division by zero")` | stops at `:parse`, `:check`, `:import` or `:eval`, with this text in the message (for `:check`, a rule code) | walker, vm, wasm, cli, component |
| `prints("hi\n")` | exactly this on stdout, and a clean exit | cli, component |
| `diagnoses(["B0002"])` | exactly these check-stage codes, warnings included | static, cli |
| `formats("x = 1\n")` | the one formatting of `SRC` | static, cli |
| `fixes("find([1], (x) -> x)\n")` | what `blue check --fix` leaves of `SRC`: its machine-applicable fixes applied, formatted | static, cli |
| `shifts("annotated", ["loose"])` | the blueshift rung, and the declarations holding it back | static, cli |
| `facts(["f: last_use x (+ x 1)"])` | the ownership facts kuzushi reads from the resolved tree, one line per fact, in order (docs/PURE-BLUE.md M1) | static |
| `leaks(0)` | the bytes one run of `SRC` leaves live, read from the counting allocator: one warm-up run, then the mean of three (docs/PURE-BLUE.md C2, I3) | walker, vm |
| `closes_at(:end)` | every host handle the run opens (a connection, a listener, a serial port) is closed when the run ends | walker, vm |

- `OPTION`s:

| option | meaning |
|---|---|
| `covers("builtin:append", "form:x = 5", …)` | the registry entries this row specifies (the missing-row gate) |
| `pending("G12")` / `pending("G16", "wasm")` | the row states a destination the gap has not reached, everywhere or on one evaluator; the gap is an open row of `spec/gaps/gaps.b` |
| `pending("G1", fails(:check, "B0001"))` / `pending("G16", "wasm", value("nil"))` | the same, naming the miss: while the gap is open the row misses exactly this way, judged as an expectation is |
| `flaky("G23", "component")` | a pending mark for a gap that misses only sometimes: a pass is reported pending instead of failing the run, every other outcome is judged as `pending` judges it, and the gap stays named until its cause is fixed |
| `position("checked")` | the blueshift rung the behaviour applies at; the runner refuses the row if the program measures elsewhere |
| `host()` | the program reaches a host effect (files, processes, the clock) |
| `isolate()` | run in a child process with a time limit |
| `frontend("{types: …, enums: …}")` | the program is a view of a frontend whose generated schema table is this text (the data laws, B0048–B0052); the static door checks it, the cli door is blind to it |
| `bidama("kagi")` | the program is the source of that bidama, as the rules that judge a bidama's own file (B0056–B0060) see it; the static door checks it, the cli door is blind to it |
| `role("generator")` | the program is the program of that project row (`generator`, `service`, or a `binding` service), as the project-point rules (B0085–B0087) see it; the static door checks it |

A malformed row is refused by name and fails the run; its valid siblings
still run.

## Adding a row

1. Put it in the area's file (`spec/rows/<area>.b`), or start a new file with
   a comment saying what the area covers.
2. Write the behaviour the language **promises** — REFERENCE.md, okite's
   RULES.md, AGENTS.md — not whatever the implementation happens to do. When
   they differ, the row states the promise and is pending on the gap that owns
   the difference. If no gap owns it, open one: a `gap(…)` row in
   `spec/gaps/gaps.b` with the next free id.
3. `blue fmt --write spec/rows/<area>.b`, then run the suite.

A new builtin, form, keyword, operator, rule code or okite decision fails the
missing-row gate until a row `covers` it.

## The missing-row gate

Every entry in the tables the implementation runs on needs a row, and every
claim must name a real entry:

| key | registry |
|---|---|
| `rule:B0001` | `blue_lang_check::RULES` |
| `form:<example>` | `blue_lang_syntax::FORMS` (the `example` text) |
| `keyword:<word>` | `SURFACE_KEYWORDS` + `BLOCK_KEYWORDS` |
| `op:<op>` | `blue_lang_syntax::INFIX` |
| `builtin:<name>` | `blue_lang_runtime::docs::NAMES`, what `blue reference` prints |
| `okite:D0001` | `bidamas/okite/RULES.md`, generated from okite's ledger |
| `rung:<rung>` | the four rungs, covered by a row whose program **measures** there |

A claim is checked where it can be: a `builtin:` claim must name a symbol in
the row's parsed program, a `rule:` claim must be the code the row expects,
an `op:` or `keyword:` claim must appear in the program's text.

## The gap ledger

`spec/gaps/gaps.b` allocates every G id, one `gap(…)` row each, parsed and
never evaluated as the rows are: `gap(ID, :open or :closed, WHAT IS MISSING,
opened(DATE), OPTION...)`, with `closed(DATE)` on a closed gap, `owner(DOC)`
naming where its design lives and `was(ID)` an id it was once cited by. The
runner refuses a malformed row, an id with two rows, a mark or a
`door::TABLE` rule naming a gap the ledger does not hold, and one naming a
closed gap (`cargo test -p blue-lang-test --test gap_ledger` runs the same
check alone). A G id in another document's own table (ARIKA G1 to G9, GPU G1
to G4, …) is that document's goal label and is cited with its name.

## Pending: how a closed gap flips visibly

A pending row states the destination. While an evaluator misses it, that
cell reports `pending`. When it starts meeting the row, the cell **fails**
with "the gap may be closed — remove the mark", so a fixed gap turns the run
red until someone deletes the mark and the row becomes an ordinary one.

- A mark scoped to one evaluator (`pending("G18", "vm")`) also excuses that
  evaluator's disagreement with stage 0, but only while the evaluator meets
  the row. It flips only once the evaluator both meets the row and agrees.
  A cell that misses the row gets no excuse: its mark judges it, as the next
  list says.
- When stage 0 is pending and another evaluator already meets the row, the
  difference is listed under "divergences while pending" rather than failed.
- The ABI cannot tell one non-integer from another, so on `wasm` only an
  exact integer flips a pending row.

A mark must fail for its own gap, so the miss is part of the mark:

- A mark that names its miss (`pending("G1", fails(:check, "B0001"))`) is
  pending only while the cell misses that way. A cell that misses any other
  way fails with "the miss moved", so a gap that half-closes, or a row broken
  by something else, turns the run red.
- A mark that names no miss may not stop before the behaviour its row
  states. The stages come in the order the pipeline runs them: `:parse`,
  `:import`, `:check`, `:eval`. Imports resolve before the check. A cell
  fails when it stops at an earlier stage than the one its expectation is
  judged at: `:eval` for a value, an output or a leak; the stage that
  `fails` names; `:check` for diagnostics, formatting, fixes, a rung or
  facts. On the diagnostics door, `B0006` is a stop at parse. A rung reading
  of a program that does not parse is `none` (`shift.unparseable`), and that
  reading is a stop at parse too. A row whose program does not parse can
  never flip, whatever its gap does, so it fails until the row is fixed or
  its mark names the miss.
- The ABI cannot tell where a program stopped, so this stop rule does not
  reach a `wasm` cell. A named miss does.

The runner's negative controls check this every run:

- A wrong value fails on every evaluator.
- A pending row that passes fails, and a pending row that misses reports
  pending.
- A pending row whose program does not parse fails on the walker, the VM
  and the memo column.
- A pending row that expects a stop at `:check` fails when its import
  fails. A pending row that expects a stop at `:import` reports pending when
  its imports resolve and its check fails.
- On the static door, a pending row of each kind (diagnostics, formatting,
  fixes, a rung, facts) fails when its program does not parse, and the
  failure names the miss as a mark the row can carry. A pending diagnostics
  row also fails when its import fails.
- A row reports pending when its mark names the miss, and fails when the
  miss moved. A mark scoped to one evaluator fails there too when the miss
  moved.
- Two different messages do not agree.
