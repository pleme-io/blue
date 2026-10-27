words = split(downcase(trim(read_file(argv[0]))), " ")
counts = frequencies(words)

ranked = sort_keyed(
  (p) -> -p[1],
  map((w) -> [w, get(counts, w)], distinct(words))
)

write_stdout(unlines([take(3, ranked)]))
