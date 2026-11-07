# t02: fix a refused program

This program is refused by `blue check`:

```blue
def with_role(user, role)
  assoc(user, :role, role)
  user
end
```

```
t02.b:2:3: error[B0053]: the value of `assoc` is discarded; `assoc` changes nothing, it returns a new value
  help: bind it (`x = assoc(…)`) or return it; a value nobody reads is a bug or dead code
```

`with_role(user, role)` should answer the user map with its `:role` set to
`role`. Fix the program so the check passes and the word does what it says.

Answer with the whole file. It must pass `blue check` with no diagnostic and
`blue fmt --check`.
