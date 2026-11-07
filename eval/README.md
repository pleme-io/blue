# The model eval

How well a model writes blue, as a number per release (H9 in
`docs/HORIZON.md`).

## The tasks

Each directory under `tasks/` is one golden task:

| file | what it is |
|---|---|
| `prompt.md` | what the model receives, and nothing else |
| `hidden.b` | tests the answer must pass; the model never sees them |
| `reference.b` | an answer that scores |

| task | skill |
|---|---|
| `t01-doc-word` | a word with a `@doc` and a running example |
| `t02-fix-refusal` | fix a program `blue check` refuses (B0053), given the diagnostic |
| `t03-port-python` | port a Python function |
| `t04-record` | declare and use a `record` |
| `t05-test-block` | write tests that fail on a wrong definition |
| `t06-process` | `spawn`, `send` and `receive` |
| `t07-json` | parse JSON and transform it |
| `t08-use-bidama` | bring words in with `use` |
| `t09-reuse-word` | delete a copied word and call the existing one (B0070) |
| `t10-layout` | write the one layout `blue fmt` writes (B0024) |

## Scoring a model

Give the model each `prompt.md` and save its answer as `<task id>.b` in one
directory, for example `t03-port-python.b`. Then:

```
blue run eval/score.b -- answers/ answers/score.json
```

The scorer judges each task in order and stops at the first stage that fails:
`missing` (no file), `check` (`blue check` prints any diagnostic, a warning
included), `fmt` (`blue fmt --check` drifts), `test` (the hidden tests,
appended to the answer, fail under `blue test`), else `pass`. It prints one
line per task and `score: N/10`, writes the result as JSON (`total`, `passed`,
the `blue` version that scored it, and each task's `id`, `passed`, `stage` and
`detail`), and exits 0 only on a full score. `EVAL_TASKS` names another tasks
directory.

The scorer runs the answer as a program, with the capabilities of the user
who runs it. Score untrusted answers in a sandbox.

## The gate

`check("model-eval", ...)` in the root `Bluefile` runs `score_test.b` as a
flake check: every reference scores 10/10, a broken reference fails its own
task and only that one, and a warning fails the check stage. The gate expects
exactly ten tasks, so a task added or lost turns it red until the count moves
with it.

## Where a release's score is recorded

A model run happens outside CI. Record it as
`eval/scores/<blue version>/<model>.json`, the scorer's own output, committed
with the release. Not built yet: the census row over these files, so a score
cannot fall without a typed reason.
