# t01: a documented word

Write a blue program that defines one word, `clamp(x, lo, hi)`: the value `x`
held between `lo` and `hi` (`lo` when `x` is below it, `hi` when `x` is above
it, `x` otherwise).

Give `clamp` a `@doc` whose first sentence starts with its name, `clamp:`, and
at least one example line of the form `    expr #=> value`. The examples run
as tests, so each must be true.

Answer with the whole file. It must pass `blue check` with no diagnostic and
`blue fmt --check`.
