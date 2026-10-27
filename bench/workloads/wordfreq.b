words = split(downcase(trim(read_file(nth(0, argv)))), " ")
counts = frequencies(words)

ranked = sort_keyed(
  (p) -> -nth(1, p),
  map((w) -> [w, get(counts, w)], distinct(words))
)

write_stdout(unlines([take(3, ranked)]))
