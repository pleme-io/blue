records = json_parse(read_file(argv[0]))
write_stdout(unlines([reduce((a, r) -> a + json_get(r, :value), 0, records)]))
