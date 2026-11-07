# t03: port a Python function

Port this Python function to blue as `run_length(s)`:

```python
def run_length(s):
    out = []
    for ch in s:
        if out and out[-1][0] == ch:
            out[-1][1] += 1
        else:
            out.append([ch, 1])
    return out
```

`run_length("aaab")` is `[["a", 3], ["b", 1]]`; `run_length("")` is `[]`.
Blue values do not change in place: build the answer from new values.

Answer with the whole file. It must pass `blue check` with no diagnostic and
`blue fmt --check`.
