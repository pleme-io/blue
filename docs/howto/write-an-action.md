---
kind: howto
order: 4
summary: write a GitHub Actions step in blue with koutei, and run it locally before CI does
---

# Write an action

A pleme-io action keeps its logic in a `run.b`. The `koutei` bidama is that
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

With no `GITHUB_OUTPUT`, `koutei` prints the record, so a local run shows it:

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
