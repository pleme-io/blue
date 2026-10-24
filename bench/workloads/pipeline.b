xs = map((x) -> x * 3, range(1_000_000))
evens = filter((x) -> x % 2 == 0, xs)
write_stdout("#{reduce((a, x) -> a + x, 0, evens)}\n")
