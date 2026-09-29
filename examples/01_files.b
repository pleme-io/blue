# Reading and writing files
#
# write_file replaces a file, append_file adds to it, read_file reads it whole.
# Paths are built with path_join, and a scratch directory is removed with rm_rf.
# read_file raises on a missing file; shisutemu's read_or answers a default.
use("moji", [:lines])
use("retsu", [:size])
use("shisutemu", [:read_or])

def scratch_dir(name)
  dir = path_join(getenv("TMPDIR", "/tmp"), "blue-example-#{name}")
  rm_rf(dir)
  mkdir_p(dir)
  dir
end

# Append one line per entry, then read the file back as a list of lines.
def log_lines(path, entries)
  map(fn(e) append_file(path, "#{e}\n") end, entries)
  lines(read_file(path))
end

test "a file written, appended to and read back"
  dir = scratch_dir("files")
  path = path_join(dir, "notes.txt")
  write_file(path, "first\n")
  assert log_lines(path, ["second", "third"]) == ["first", "second", "third"]
  assert is_file?(path)
  assert size(ls(dir)) == 1
  rm_rf(dir)
  assert !path_exists(dir)
end

test "a missing file is a default, not a crash, through read_or"
  assert read_or("/no/such/file", "") == ""
end

test "the parts of a path"
  assert path_basename("reports/2026/q3.csv") == "q3.csv"
  assert path_dirname("reports/2026/q3.csv") == "reports/2026"
  assert path_extension("reports/2026/q3.csv") == "csv"
end
