use("fixture")
use("shisutemu")
# An app: run from the caller's directory, with the project's packages and tools.
write_file(getenv("GREET_OUT", "greet.txt"), concat(to_s(fixture_double(5)), concat(" ", stdout_of(exec_capture("hello")))))
