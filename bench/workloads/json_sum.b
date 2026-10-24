records = json_parse(read_file(nth(0, argv)))
write_stdout("#{reduce((a, r) -> a + json_get(r, "value"), 0, records)}\n")
