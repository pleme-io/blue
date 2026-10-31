# The append-only store, the storage_append capability. Each row is host():
# a log is a file of one-line records under TMPDIR, one directory per row.
# append_log adds a record and read_log reads every record back; nothing in
# the bundle truncates, overwrites or removes. The hold, the in-memory
# provider and the lock run in crates/blue-lang-cli/tests/storage.rs.

row(
  "storage.append_read.round_trip",
  join_lines(
    [
      "d = path_join(getenv(\"TMPDIR\", \"/tmp\"), \"blue-spec-log-rt\")",
      "rm_rf(d)",
      "f = path_join(d, \"a/b.log\")",
      "append_log(f, \"one\")",
      "append_log(f, \"\")",
      "append_log(f, \"three\")",
      "r = [read_log(f), read_file(f)]",
      "rm_rf(d)",
      "r"
    ]
  ),
  value("[[\"one\", \"\", \"three\"], \"one\\n\\nthree\\n\"]"),
  covers("builtin:append_log", "builtin:read_log"),
  host()
)

row(
  "storage.append.one_line_a_record",
  join_lines(
    [
      "d = path_join(getenv(\"TMPDIR\", \"/tmp\"), \"blue-spec-log-line\")",
      "rm_rf(d)",
      "f = path_join(d, \"l.log\")",
      "append_log(f, \"kept\")",
      "",
      "k = begin",
      "  append_log(f, \"a\\nb\")",
      "rescue :bad_option as e",
      "  e.kind",
      "end",
      "r = [k, read_log(f)]",
      "rm_rf(d)",
      "r"
    ]
  ),
  value("[:bad_option, [\"kept\"]]"),
  host()
)

row(
  "storage.read.absent_is_not_found",
  join_lines(
    [
      "f = path_join(getenv(\"TMPDIR\", \"/tmp\"), \"blue-spec-log-absent/none.log\")",
      "",
      "begin",
      "  read_log(f)",
      "rescue :not_found as e",
      "  e.kind",
      "end"
    ]
  ),
  value(":not_found"),
  host()
)

row(
  "storage.torn_tail_is_refused",
  join_lines(
    [
      "d = path_join(getenv(\"TMPDIR\", \"/tmp\"), \"blue-spec-log-torn\")",
      "rm_rf(d)",
      "mkdir_p(d)",
      "f = path_join(d, \"t.log\")",
      "write_file(f, \"a\\nb\")",
      "",
      "r = begin",
      "  read_log(f)",
      "rescue :parse_error as e",
      "  e.kind",
      "end",
      "",
      "w = begin",
      "  append_log(f, \"c\")",
      "rescue :parse_error as e",
      "  e.kind",
      "end",
      "out = [r, w, read_file(f)]",
      "rm_rf(d)",
      "out"
    ]
  ),
  value("[:parse_error, :parse_error, \"a\\nb\"]"),
  host()
)
