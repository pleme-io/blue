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
| `BLUE_CONFORMANCE_STRICT=1` | a blind `cli` column is a failure (the nix check sets it) |
| `BLUE_CONFORMANCE_JSON=path` | also write one JSON line per (row, evaluator), for DuckDB |
| `BLUE_CONFORMANCE_PROBE=1` | print every observation, not only failures |

The report gives pass, pending, fail and blind per evaluator, per area (row
file) and per blueshift position, the pending rows by gap, and the
missing-row gate's totals.

## The evaluators

| column | what runs the row | what it can observe |
|---|---|---|
| `walker` | `pipeline::run_in_surface`, the `blue run` path, with a loader over `spec/bidamas` and `bidamas` | value, failure |
| `vm` | the same check and erasure, then `eval_program_vm` (batched expansion, bytecode VM) | value, failure |
| `wasm` | `blue_lang_wasm::eval_tagged`, the module's ABI (no loader) | an Int, "not an Int", or an error |
| `cli` | the `blue` binary: `run --quiet`, `fmt`, `check --format json`, `shift` | output, failure, formatting, diagnostics, rung |
| `static` | the front end in-process: `check_entry`, `format_source_lossless`, `shift_of` | diagnostics, formatting, rung |

`walker` is stage 0 for evaluated rows and `static` for front-end rows.
**Any other column that disagrees with stage 0 fails, even when both meet the
row.** An evaluator that cannot observe a kind of row reports `blind`, which
is counted apart and never as a pass. Blind by design: a value on `cli` (the
final-value printer is not the literal renderer, G12), output anywhere but
`cli`, and a `host()` row on `wasm` (the host-linked ABI binds host
primitives the wasm32 module does not).

A row whose evaluator may die (a stack overflow aborts the OS process, a
runaway never returns) is marked `isolate()` and runs in a child process
with a 45 s limit; a death is an observation (`CRASHED`), never a pass.

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
| `fails(:eval, "division by zero")` | stops at `:parse`, `:check`, `:import` or `:eval`, with this text in the message (for `:check`, a rule code) | walker, vm, wasm, cli |
| `prints("hi\n")` | exactly this on stdout, and a clean exit | cli |
| `diagnoses(["B0002"])` | exactly these check-stage codes, warnings included | static, cli |
| `formats("x = 1\n")` | the one formatting of `SRC` | static, cli |
| `shifts("annotated", ["loose"])` | the blueshift rung, and the declarations holding it back | static, cli |

- `OPTION`s:

| option | meaning |
|---|---|
| `covers("builtin:append", "form:x = 5", …)` | the registry entries this row specifies (the missing-row gate) |
| `pending("G5")` / `pending("G16", "wasm")` | the row states a destination the gap has not reached, everywhere or on one evaluator |
| `position("checked")` | the blueshift rung the behaviour applies at; the runner refuses the row if the program measures elsewhere |
| `host()` | the program reaches a host effect (files, processes, the clock) |
| `isolate()` | run in a child process with a time limit |

A malformed row is refused by name and fails the run; its valid siblings
still run.

## Adding a row

1. Put it in the area's file (`spec/rows/<area>.b`), or start a new file with
   a comment saying what the area covers.
2. Write the behaviour the language **promises** — REFERENCE.md, okite's
   RULES.md, AGENTS.md, theory/BLUE.md — not whatever the implementation
   happens to do. When they differ, the row states the promise and is pending
   on the gap that owns the difference (add one to `theory/BLUE-GAPS.md` if
   none does).
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

## Pending: how a closed gap flips visibly

A pending row states the destination. While an evaluator misses it, that
cell reports `pending`. When it starts meeting the row, the cell **fails**
with "the gap may be closed — remove the mark", so a fixed gap turns the run
red until someone deletes the mark and the row becomes an ordinary one.

- A mark scoped to one evaluator (`pending("G18", "vm")`) also excuses that
  evaluator's disagreement with stage 0, and flips only once it both meets
  the row and agrees.
- When stage 0 is pending and another evaluator already meets the row (the
  VM bounds recursion depth, G6), the difference is listed under
  "divergences while pending" rather than failed.
- The ABI cannot tell one non-integer from another, so on `wasm` only an
  exact integer flips a pending row.

The runner's negative controls check this every run: a wrong value must fail
on every evaluator, a pending row that passes must fail, a pending row that
misses must report pending, and two different messages must not agree.
