# Host effects: files, paths, the environment, processes and the clock. Each
# row is host(): the WASM surface binds none of these in the shipped module.
# Files live under TMPDIR, one directory per row.

row(
  "host.path_join",
  "path_join(\"a\", \"b\", \"c.b\")",
  value("\"a/b/c.b\""),
  covers("builtin:path_join")
)

row(
  "host.path_basename",
  "path_basename(\"/x/y.b\")",
  value("\"y.b\""),
  covers("builtin:path_basename")
)

row(
  "host.path_dirname",
  "path_dirname(\"/x/y.b\")",
  value("\"/x\""),
  covers("builtin:path_dirname")
)

row(
  "host.path_extension",
  "path_extension(\"/x/y.b\")",
  value("\"b\""),
  covers("builtin:path_extension")
)

row(
  "host.write_program",
  join_lines(
    [
      "d = path_join(getenv(\"TMPDIR\", \"/tmp\"), \"blue-spec-wp\")",
      "rm_rf(d)",
      "mkdir_p(d)",
      "f = path_join(d, \"a.b\")",
      "write_program(f, \"x=1\")",
      "r = read_file(f)",
      "bad = write_program(f, \"def (\") rescue :refused",
      "rm_rf(d)",
      "[r, bad]"
    ]
  ),
  value("[\"x = 1\\n\", :refused]"),
  covers("builtin:write_program"),
  host()
)

row(
  "host.write_read",
  join_lines(
    [
      "d = path_join(getenv(\"TMPDIR\", \"/tmp\"), \"blue-spec-rw\")",
      "rm_rf(d)",
      "mkdir_p(d)",
      "f = path_join(d, \"a.txt\")",
      "write_file(f, \"one\")",
      "append_file(f, \" two\")",
      "r = read_file(f)",
      "rm_rf(d)",
      "r"
    ]
  ),
  value("\"one two\""),
  covers(
    "builtin:write_file",
    "builtin:append_file",
    "builtin:read_file",
    "builtin:mkdir_p",
    "builtin:rm_rf",
    "builtin:getenv"
  ),
  host()
)

row(
  "host.exists",
  join_lines(
    [
      "d = path_join(getenv(\"TMPDIR\", \"/tmp\"), \"blue-spec-ex\")",
      "rm_rf(d)",
      "mkdir_p(d)",
      "f = path_join(d, \"a\")",
      "write_file(f, \"\")",
      "r = [path_exists(f), is_file?(f), is_dir?(d), is_file?(d)]",
      "rm_rf(d)",
      "r"
    ]
  ),
  value("[true, true, true, false]"),
  covers("builtin:path_exists", "builtin:is_file?", "builtin:is_dir?"),
  host()
)

row(
  "host.size_mtime",
  join_lines(
    [
      "d = path_join(getenv(\"TMPDIR\", \"/tmp\"), \"blue-spec-sz\")",
      "rm_rf(d)",
      "mkdir_p(d)",
      "f = path_join(d, \"a\")",
      "write_file(f, \"abc\")",
      "r = [file_size(f), integer?(file_mtime_ms(f))]",
      "rm_rf(d)",
      "r"
    ]
  ),
  value("[3, true]"),
  covers("builtin:file_size", "builtin:file_mtime_ms"),
  host()
)

row(
  "host.ls",
  join_lines(
    [
      "d = path_join(getenv(\"TMPDIR\", \"/tmp\"), \"blue-spec-ls\")",
      "rm_rf(d)",
      "mkdir_p(d)",
      "write_file(path_join(d, \"b\"), \"\")",
      "write_file(path_join(d, \"a\"), \"\")",
      "r = map(fn(p) path_basename(p) end, ls(d))",
      "rm_rf(d)",
      "r"
    ]
  ),
  value("[\"a\", \"b\"]"),
  covers("builtin:ls"),
  host()
)

row(
  "host.glob",
  join_lines(
    [
      "d = path_join(getenv(\"TMPDIR\", \"/tmp\"), \"blue-spec-gl\")",
      "rm_rf(d)",
      "mkdir_p(d)",
      "write_program(path_join(d, \"x.b\"), \"\")",
      "r = length(glob(path_join(d, \"*.b\")))",
      "rm_rf(d)",
      "r"
    ]
  ),
  value("0"),
  covers("builtin:glob"),
  host()
)

row(
  "host.walk_dir",
  join_lines(
    [
      "d = path_join(getenv(\"TMPDIR\", \"/tmp\"), \"blue-spec-wd\")",
      "rm_rf(d)",
      "mkdir_p(d)",
      "mkdir(path_join(d, \"s\"))",
      "write_file(path_join(d, \"s/f\"), \"\")",
      "r = length(walk_dir(d))",
      "rm_rf(d)",
      "r"
    ]
  ),
  value("1"),
  covers("builtin:walk_dir", "builtin:mkdir"),
  host()
)

row(
  "host.rename_rm",
  join_lines(
    [
      "d = path_join(getenv(\"TMPDIR\", \"/tmp\"), \"blue-spec-rn\")",
      "rm_rf(d)",
      "mkdir_p(d)",
      "a = path_join(d, \"a\")",
      "b = path_join(d, \"b\")",
      "write_file(a, \"x\")",
      "rename_file(a, b)",
      "r = [path_exists(a), path_exists(b)]",
      "rm(b)",
      "r2 = path_exists(b)",
      "rm_rf(d)",
      "append(r, [r2])"
    ]
  ),
  value("[false, true, false]"),
  covers("builtin:rename_file", "builtin:rm"),
  host()
)

row(
  "host.read_missing",
  "read_file(\"/nonexistent/blue-spec\")",
  fails(:eval, "read_file"),
  host()
)

row("host.cwd", "string?(cwd)", value("true"), covers("builtin:cwd"), host())
row("host.argv", "list?(argv)", value("true"), covers("builtin:argv"), host())

row(
  "host.argv_get",
  "argv_get(999, :none)",
  value(":none"),
  covers("builtin:argv_get"),
  host()
)

row(
  "host.getenv_default",
  "getenv(\"BLUE_SPEC_SURELY_UNSET\", \"d\")",
  value("\"d\""),
  host()
)

row(
  "host.env_required",
  "string?(env_required(\"PATH\"))",
  value("true"),
  covers("builtin:env_required"),
  host()
)

row(
  "host.env_required.missing",
  "env_required(\"BLUE_SPEC_SURELY_UNSET\")",
  fails(:eval, "BLUE_SPEC_SURELY_UNSET"),
  host()
)

row(
  "host.self_exe",
  "self_exe == nil || string?(self_exe)",
  value("true"),
  covers("builtin:self_exe"),
  host()
)

row(
  "host.exec_capture",
  "exec_capture(\"echo\", \"hi\")",
  value("[[:status, 0], [:stdout, \"hi\\n\"], [:stderr, \"\"]]"),
  covers("builtin:exec_capture"),
  host()
)

row(
  "host.exec_check",
  "exec_check(\"true\")",
  value("0"),
  covers("builtin:exec_check"),
  host()
)

row(
  "host.exec_ok",
  "[exec_ok?(\"true\"), exec_ok?(\"false\")]",
  value("[true, false]"),
  covers("builtin:exec_ok?"),
  host()
)

row(
  "host.exec_with_env",
  "exec_with_env([[\"BLUE_SPEC_X\", \"v\"]], \"printenv\", \"BLUE_SPEC_X\")",
  value("[[:status, 0], [:stdout, \"v\\n\"], [:stderr, \"\"]]"),
  covers("builtin:exec_with_env"),
  host()
)

row(
  "host.exec_into.unstartable",
  "exec_into([[\"BLUE_SPEC_X\", \"v\"]], \"blue-spec-surely-absent-command\")",
  fails(:eval, "exec_into"),
  covers("builtin:exec_into"),
  host()
)

row(
  "host.exit_with.not_a_status",
  "exit_with(\"75\")",
  fails(:eval, "exit_with"),
  covers("builtin:exit_with"),
  host()
)

row(
  "host.exec_with_stdin",
  "exec_with_stdin(\"abc\", \"cat\")",
  value("[[:status, 0], [:stdout, \"abc\"], [:stderr, \"\"]]"),
  covers("builtin:exec_with_stdin"),
  host()
)

row(
  "host.sh_exec",
  "sh_exec(\"echo hi\")",
  value("[[:status, 0], [:stdout, \"hi\\n\"], [:stderr, \"\"]]"),
  covers("builtin:sh_exec"),
  host()
)

row(
  "host.sh_exec.configured_off",
  "sh_exec(\"echo hi\")",
  fails(:check, "B0001"),
  pending("G9"),
  host()
)

row(
  "host.now",
  "[integer?(now), integer?(now_ms), integer?(now_ns), string?(now_rfc3339)]",
  value("[true, true, true, true]"),
  covers(
    "builtin:now",
    "builtin:now_ms",
    "builtin:now_ns",
    "builtin:now_rfc3339"
  ),
  host()
)

row(
  "host.elapsed",
  "integer?(elapsed_since(now_ns))",
  value("true"),
  covers("builtin:elapsed_since"),
  host()
)

row(
  "host.sleep",
  "[sleep(0), sleep_ms(1)]",
  value("[nil, nil]"),
  covers("builtin:sleep", "builtin:sleep_ms"),
  host()
)

row(
  "host.random_bytes",
  join_lines(
    [
      "a = random_bytes(16)",
      "[length(a), length(random_bytes(0)), a == random_bytes(16), every?(fn(b) b >= 0 and b <= 255 end, a)]"
    ]
  ),
  value("[16, 0, false, true]"),
  covers("builtin:random_bytes"),
  host()
)

row(
  "host.random_bytes.count",
  "random_bytes(-1)",
  fails(:eval, "must be 0..="),
  covers("builtin:random_bytes"),
  host()
)
