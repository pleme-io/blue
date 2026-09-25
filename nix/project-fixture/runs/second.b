# A run that reads another: `first`'s value through $RUN_READS, plus one.
first = to_int(read_file(path_join(path_join(getenv("RUN_READS", ""), "first"), "value")))
write_file(path_join(getenv("RUN_OUT", ""), "value"), to_s(first + 1))
