---
kind: reference
summary: every blue verb with its flags, one row each; the agents page keeps one line per verb and links here
---

# Commands

Every `blue` verb with its flags. The agents page (`docs/agents.md`, rendered to `AGENTS.md` and `CLAUDE.md`) keeps one line per verb and links here.

| | |
|---|---|
| `blue file.b a b` | run a program as a script: quiet, every argument after the file to `argv` |
| `blue run file.b` | run a program and print its final value; `--quiet` drops it, `-- a b` passes arguments; `--allow CAP` holds it to those host capabilities; `--receipts DIR` writes an execution receipt for the run and for each process ([`docs/SAFETY.md`](SAFETY.md), row 8), and `--receipt-steps` counts in each the steps it spent; a runtime error prints the blue call stack, and `--format json` prints it as one object; `--timings` prints the wall time of each pipeline stage to stderr |
| `blue replay TRACE` | run a crashed process again from its trace and say whether it crashed the same way; a fatal exit's `.bluecrash` replays under the hold it recorded; TRACE is a file or its crash hash (`b3:<hex>`, 8 digits at least) |
| `blue crash dump\|bisect\|immunize CRASH` | a trace by file or crash hash: `dump` what it violated and where (class, host name, capability, file:line:col, hold, exit, mailbox; `--json`); `bisect` it to the fewest messages that replay to the same crash; `immunize` it into a test, red until the target is fixed (`--into FILE`) ([`docs/SAFETY.md`](SAFETY.md), row 8) |
| `blue receipt verify FILE` | recompute a receipt's name from the BLAKE3 hash of its bytes and check its form: version 1, version 2 with a server's `input_root` and `output_root`, or version 3 with `steps`; any edit fails |
| `blue new NAME` | a project; `--bidama NAME` a package, `--script NAME.b` an executable script, `--kernel NAME` a kernel program with its loader |
| `blue watch [check\|test\|run] PATH…` | rerun the command on every save (`check` by default) |
| `blue test file.b` | check it, then run its `test` blocks; a directory runs every file with tests, in parallel; `--filter NAME` keeps tests whose name contains it; `--coverage` lists each definition's calls and the uncovered ones; `--allow CAP` holds the tests to those host capabilities; `--facts FILE` (or `TAMESHI_FACTS`) writes the facts tameshi reads and `blue-test-evidence.json` beside it ([`docs/TESTING.md`](TESTING.md#declared-controls-live-2026-10-30)) |
| `blue profile file.b` | run it and list every function called: calls, inclusive and exclusive time, and allocations made in each |
| `blue trace NAME file.b` | run it and print each call of `NAME` with its arguments and value |
| `blue check file.b` | every rule (unbound names with did-you-mean, unused bindings, types, waivers); `--format json` prints one object per diagnostic, `--fix` applies the machine-applicable fixes |
| `blue query '(reaches filesystem) (unannotated)' DIR` | every definition a code query matches: `(match PATTERN)` over the resolved tree with bindings, `(reaches CAP)`, `(calls retsu/first)`, `(package P)`, `(longer-than N)`; `--json`; a Bluefile's `query(name, text)` runs as `blue query NAME` ([`docs/DIAGNOSTICS.md`](DIAGNOSTICS.md)) |
| `blue explain B0001` | what a diagnostic code means; `--list` lists them ([`docs/DIAGNOSTICS.md`](DIAGNOSTICS.md)) |
| `blue doc NAME` | a builtin, `pkg::name` or bare name: signature, doc line, namespace, tier and an example (a builtin's from its spec row, a definition's from its package's tests); `blue doc PKG` lists a package; `--file F` gives each answer's tier as F reaches it; `--json` |
| `blue verbs import\|export\|check\|findings` | the verb graph (`bidamas/mokuroku/graph`, `docs/verbs/H/DESIGN.md`): `import` TSVs into its row files, `export` them back (the only writer of TSV; the committed tables are Bluefile `generate`s, so `nix run .#regen` refreshes them through it), `check` its gates against the recorded baseline (`--record` writes it), `findings --tsv DIR` of a directory of TSVs |
| `blue fmt file.b` | print the one formatting, zero-parameter calls bare (it resolves the file to know which); `--write` rewrites, `--check` fails on drift |
| `blue reference` | the language reference as JSON |
| `blue eval 'EXPR'` | evaluate once and print the value; `blue eval file.b:LINE:COL` evaluates the top-level form there in that file's context |
| `blue repl` | an evaluation session: multi-line input, `:load`, `:expand`, `:doc`, `:reset`, `:quit`; ctrl-c stops a running evaluation |
| `blue serve` | the same session as JSON lines on stdio, for editors |
| `blue bundle FILE -o OUT` | seal a program into an appliance payload: compiled, its imports resolved, held to the capabilities its fresh `Bluefile.lock` verified (pure when it records none); `--runner blue-appliance` makes OUT one executable that takes no flags. nix builds one per Bluefile `app` as `packages.appliance-<name>`; `--sources` writes the program's text and every bidama it reaches as JSON instead, which the wasm engine in a page runs from (`crates/blue-lang-wasm/page`) |
| `blue image build [NAME]` | build a Bluefile `image` through nix: the tarball, its size and layers |
| `blue workload render [NAME]` | a Bluefile `workload` as Kubernetes objects; `--write` rewrites the committed files |
| `blue diff --context CTX` | the committed workload files against a cluster, read-only; there is no `blue apply`, GitOps applies |
| `blue registry render [BACKEND]` | a Bluefile `registry` entry (sui first, FlakeHub optional) as its publish workflow; `--write` rewrites the committed files; `blue registry status` says whether sui serves each pin. The lock stays the truth: [`docs/REGISTRY.md`](REGISTRY.md) |
