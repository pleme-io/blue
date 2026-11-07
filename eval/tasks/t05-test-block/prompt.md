# t05: tests that can say no

Here is a blue word:

```blue
use("junjo", [:sort])

def median(xs)
  s = sort(xs)
  n = count(s)
  h = floor(n / 2)
  if n == 0
    nil
  elsif n % 2 == 1
    s[h]
  else
    (s[h - 1] + s[h]) / 2
  end
end
```

Answer with this file, `median` kept exactly as written, plus at least three
`test` blocks that pass on it. The tests are scored by whether they fail on a
wrong `median`: a hidden harness changes one line of the definition at a time
and runs your tests again, so cover the empty list, an odd length and an even
length, with values out of order.

It must pass `blue check` with no diagnostic and `blue fmt --check`.
