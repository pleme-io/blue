# t06: processes

Write `squares(xs)`, which answers the square of each integer in `xs`, in the
order of `xs`, computed by blue processes: start one process per element with
`spawn`, have each send its answer to the caller with `send`, and collect the
answers with `receive`. `squares([])` is `[]`; `squares([3, 1, 2])` is
`[9, 1, 4]`.

Answers can arrive in any order, so tag each message so the caller can put it
back in place.

Answer with the whole file. It must pass `blue check` with no diagnostic and
`blue fmt --check`.
