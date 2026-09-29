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
  "host.write_read",
  "d = path_join(getenv(\"TMPDIR\", \"/tmp\"), \"blue-spec-rw\")\nrm_rf(d)\nmkdir_p(d)\nf = path_join(d, \"a.txt\")\nwrite_file(f, \"one\")\nappend_file(f, \" two\")\nr = read_file(f)\nrm_rf(d)\nr",
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
  "d = path_join(getenv(\"TMPDIR\", \"/tmp\"), \"blue-spec-ex\")\nrm_rf(d)\nmkdir_p(d)\nf = path_join(d, \"a\")\nwrite_file(f, \"\")\nr = [path_exists(f), is_file?(f), is_dir?(d), is_file?(d)]\nrm_rf(d)\nr",
  value("[true, true, true, false]"),
  covers("builtin:path_exists", "builtin:is_file?", "builtin:is_dir?"),
  host()
)

row(
  "host.size_mtime",
  "d = path_join(getenv(\"TMPDIR\", \"/tmp\"), \"blue-spec-sz\")\nrm_rf(d)\nmkdir_p(d)\nf = path_join(d, \"a\")\nwrite_file(f, \"abc\")\nr = [file_size(f), integer?(file_mtime_ms(f))]\nrm_rf(d)\nr",
  value("[3, true]"),
  covers("builtin:file_size", "builtin:file_mtime_ms"),
  host()
)

row(
  "host.ls",
  "d = path_join(getenv(\"TMPDIR\", \"/tmp\"), \"blue-spec-ls\")\nrm_rf(d)\nmkdir_p(d)\nwrite_file(path_join(d, \"b\"), \"\")\nwrite_file(path_join(d, \"a\"), \"\")\nr = map(fn(p) path_basename(p) end, ls(d))\nrm_rf(d)\nr",
  value("[\"a\", \"b\"]"),
  covers("builtin:ls"),
  host()
)

row(
  "host.glob",
  "d = path_join(getenv(\"TMPDIR\", \"/tmp\"), \"blue-spec-gl\")\nrm_rf(d)\nmkdir_p(d)\nwrite_file(path_join(d, \"x.b\"), \"\")\nr = length(glob(path_join(d, \"*.b\")))\nrm_rf(d)\nr",
  value("0"),
  covers("builtin:glob"),
  host()
)

row(
  "host.walk_dir",
  "d = path_join(getenv(\"TMPDIR\", \"/tmp\"), \"blue-spec-wd\")\nrm_rf(d)\nmkdir_p(d)\nmkdir(path_join(d, \"s\"))\nwrite_file(path_join(d, \"s/f\"), \"\")\nr = length(walk_dir(d))\nrm_rf(d)\nr",
  value("1"),
  covers("builtin:walk_dir", "builtin:mkdir"),
  host()
)

row(
  "host.rename_rm",
  "d = path_join(getenv(\"TMPDIR\", \"/tmp\"), \"blue-spec-rn\")\nrm_rf(d)\nmkdir_p(d)\na = path_join(d, \"a\")\nb = path_join(d, \"b\")\nwrite_file(a, \"x\")\nrename_file(a, b)\nr = [path_exists(a), path_exists(b)]\nrm(b)\nr2 = path_exists(b)\nrm_rf(d)\nappend(r, [r2])",
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

row("host.cwd", "string?(cwd())", value("true"), covers("builtin:cwd"), host())
row("host.argv", "list?(argv())", value("true"), covers("builtin:argv"), host())

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
  "self_exe() == nil || string?(self_exe())",
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
  "[integer?(now()), integer?(now_ms()), integer?(now_ns()), string?(now_rfc3339())]",
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
  "integer?(elapsed_since(now_ns()))",
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
