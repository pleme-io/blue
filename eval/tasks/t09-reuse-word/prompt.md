# t09: call the word that already exists

`blue check` warns about this program:

```blue
def total(xs)
  reduce((acc, x) -> acc + x, 0, xs)
end

def invoice_total(lines)
  total(map((l) -> l[:price] * l[:qty], lines))
end
```

```
t09.b:1:5: warning[B0070]: `total` is the shape of `kazu::sum`
  help: use the word: `use("kazu", [:sum])`; `blue check --fix` forwards `total` to it
```

`total` copies a word blue already has. Remove the copy: delete `total` and
have `invoice_total` call the existing word. `invoice_total` must answer what
it answers today.

Answer with the whole file. It must pass `blue check` with no diagnostic, not
even a warning, and `blue fmt --check`.
