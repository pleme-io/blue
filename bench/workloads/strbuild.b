s = join(map((i) -> to_s(i % 10), range(1_000_000)), "")
write_stdout("#{length(s)}\n")
