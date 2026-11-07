# t04: a record

Declare a blue record `item` with three fields, in this order: `name` (a
string), `price` (an integer) and `qty` (an integer). Then write:

- `total(items)`: the sum of `price * qty` over a list of items; `0` for `[]`.
- `restock(i, n)`: a copy of item `i` with `qty` raised by `n`. The original
  item is unchanged.

`item("pen", 2, 5)` must build an item, and `item?(x)` must tell an item from
a plain map with the same keys.

Answer with the whole file. It must pass `blue check` with no diagnostic and
`blue fmt --check`.
