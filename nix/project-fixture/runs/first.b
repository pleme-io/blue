use("fixture", [:double])
use("shisutemu", [:stdout_of])
# A run: a value from the project's own package, and what the declared tool
# printed, written into $RUN_OUT.
out = getenv("RUN_OUT", "")
write_file(path_join(out, "value"), to_s(double(21)))
write_file(path_join(out, "tool"), stdout_of(exec_capture("hello")))
