use("moji", %i[lines take_chars])
use("shisutemu", %i[status_of stderr_of stdout_of])

@doc """
absolute: The path made absolute against the current directory; an absolute
path is answered as it is.

    absolute("/srv/eval") #=> "/srv/eval"
"""
def absolute(path)
  if starts_with?(path, "/")
    path
  else
    path_join(cwd, path)
  end
end

@doc """
verdict: One task's result as data: its id, whether it passed, the stage that
decided it and the first lines of what that stage printed.

    verdict("t01", "pass", "")[:passed] #=> true
    verdict("t01", "fmt", "drift")[:passed] #=> false
"""
def verdict(id, stage, detail)
  {id:, passed: stage == "pass", stage:, detail: take_chars(detail, 600)}
end

@doc """
check_clean?: Whether a `blue check --format json` capture exited 0 and printed
no diagnostic at all, a warning included.

    check_clean?([[:status, 0], [:stdout, ""], [:stderr, ""]]) #=> true
    check_clean?([[:status, 0], [:stdout, "{}"], [:stderr, ""]]) #=> false
"""
def check_clean?(cap)
  status_of(cap) == 0 and lines(stdout_of(cap)) == []
end

@doc """
said: What a capture printed, stdout then stderr, as one text.

    lines(said([[:status, 1], [:stdout, "a"], [:stderr, "b"]])) #=> ["a", "b"]
"""
def said(cap)
  join_lines(filter((s) -> s != "", [stdout_of(cap), stderr_of(cap)]))
end

@doc """
graded_program: The program the hidden tests run on: the submission, then the
task's hidden tests after one blank line.

    lines(graded_program(unlines(["a"]), unlines(["b"]))) #=> ["a", "", "b"]
"""
def graded_program(submission, hidden)
  join_lines([submission, hidden])
end

@doc """
run_hidden: Run the task's hidden tests against a submission in a directory
of its own under TMPDIR, with EVAL_SUBMISSION naming the submission file; the
capture of `blue test`.

    status_of(run_hidden("/no/such/task", "/no/such.b", "")) != 0 #=> true
"""
def run_hidden(task_dir, path, text)
  dir = path_join(getenv("TMPDIR", "/tmp"), "blue-eval-#{to_s(now_ns)}")
  mkdir_p(dir)
  hidden = path_join(task_dir, "hidden.b")
  cap = if path_exists(hidden)
    graded = path_join(dir, path_basename(path))
    write_program(graded, graded_program(text, read_file(hidden)))
    exec_with_env([["EVAL_SUBMISSION", path]], self_exe, "test", graded)
  else
    [[:status, 2], [:stdout, ""], [:stderr, "no hidden tests at #{hidden}"]]
  end
  rm_rf(dir)
  cap
end

@doc """
judge: One task's verdict for the submissions in a directory, which holds the
task's answer as `<task id>.b`. The stages run in order and the first that
fails decides: missing, check (`blue check` prints a diagnostic), fmt (`blue
fmt --check` drifts), test (the hidden tests fail), else pass.

    judge("/no/such/t01", "/no/such/dir")[:stage] #=> "missing"
"""
def judge(task_dir, submissions)
  id = path_basename(task_dir)
  path = absolute(path_join(submissions, "#{id}.b"))
  if not path_exists(path)
    verdict(id, "missing", "no file #{path}")
  else
    checked = exec_capture(self_exe, "check", "--format", "json", path)
    formatted = exec_capture(self_exe, "fmt", "--check", path)
    if not check_clean?(checked)
      verdict(id, "check", said(checked))
    elsif status_of(formatted) != 0
      verdict(id, "fmt", said(formatted))
    else
      tested = run_hidden(absolute(task_dir), path, read_file(path))
      if status_of(tested) == 0
        verdict(id, "pass", "")
      else
        verdict(id, "test", said(tested))
      end
    end
  end
end

@doc """
score: Every task under tasks_dir judged against the submissions directory,
in task order. A tasks_dir that does not exist has no tasks.

    score("/no/such/tasks", "/no/such/dir") #=> []
"""
def score(tasks_dir, submissions)
  if path_exists(tasks_dir)
    map((t) -> judge(t, submissions), ls(tasks_dir))
  else
    []
  end
end

@doc """
result: The machine-readable result of a run: the suite, the blue that scored
it, the total, the passed count and every task's verdict.

    result([verdict("t01", "pass", "")], "blue 0.0.1")[:passed] #=> 1
"""
def result(verdicts, version)
  {
    suite: "blue-model-eval",
    blue: version,
    total: length(verdicts),
    passed: length(filter((v) -> v[:passed], verdicts)),
    tasks: verdicts
  }
end

@doc """
report_line: One task's line for a person: PASS or FAIL, the id, and for a
failure the stage that decided it.

    report_line(verdict("t03", "test", "boom")) #=> "FAIL t03 (test)"
"""
def report_line(v)
  if v[:passed]
    "PASS #{v[:id]}"
  else
    "FAIL #{v[:id]} (#{v[:stage]})"
  end
end

@doc """
main: Score a directory of submissions: `blue run eval/score.b -- DIR [OUT]`.
Prints a line per task and the total, writes the result as JSON to OUT
(default DIR/score.json), and exits 0 only when every task passed. EVAL_TASKS
names the tasks directory (default eval/tasks).

    report_line(verdict("t01", "pass", "")) #=> "PASS t01"
"""
def main()
  if argv == []
    write_stderr(
      unlines(["usage: blue run eval/score.b -- SUBMISSIONS_DIR [OUT.json]"])
    )
    exit_with(2)
  end
  submissions = argv[0]
  out = if length(argv) > 1
    argv[1]
  else
    path_join(submissions, "score.json")
  end
  verdicts = score(absolute(getenv("EVAL_TASKS", "eval/tasks")), submissions)
  version = trim(stdout_of(exec_capture(self_exe, "--version")))
  doc = result(verdicts, version)
  write_file(out, json_stringify(doc))
  score_line = "score: #{doc[:passed]}/#{doc[:total]}"
  write_stdout(unlines(append(map(report_line, verdicts), [score_line])))
  exit_with(
    if doc[:passed] == doc[:total] and doc[:total] > 0
      0
    else
      1
    end
  )
end
