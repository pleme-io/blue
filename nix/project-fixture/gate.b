# Not a word of the fixture: blue's `checks.project-fixture` reads the
# fixture's built outputs with this, one test per lowering.

def fixture_read(dir, file)
  trim(read_file(path_join(getenv(dir, ""), file)))
end

test "a run writes through RUN_OUT, and sees the project's own package"
  assert fixture_read("FIRST", "value") == "42"
end

test "a declared tool is on a run's PATH"
  assert fixture_read("FIRST", "tool") == "Hello, world!"
end

test "a run reads the run it names through RUN_READS"
  assert fixture_read("SECOND", "value") == "43"
end

test "an app runs from the caller's directory with the packages and tools"
  assert trim(read_file(getenv("GREET", ""))) == "10 Hello, world!"
end
