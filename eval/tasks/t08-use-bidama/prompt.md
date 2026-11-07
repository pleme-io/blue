# t08: use a bidama

Write `longest_word(text)`: the length of the longest word in `text`, where
words are separated by any run of whitespace (spaces, tabs, newlines). It is
`nil` for a text with no words.

Do not split the text yourself: bring in the words that already exist with
`use`. The `moji` bidama has `words(s)`, which splits on runs of whitespace,
and the `kazu` bidama has `max_of(xs)`, the largest of a list or `nil` for
`[]`. Every `use` must list the names it brings in, and every listed name
must be read.

`longest_word("a  bcd\tef")` is `3`; `longest_word("   ")` is `nil`.

Answer with the whole file. It must pass `blue check` with no diagnostic and
`blue fmt --check`.
