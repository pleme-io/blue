use("shisutemu", %i[status_of stdout_of])

@doc """
eval_root: The directory holding eval/: GEN_ROOT under the flake check, the
current directory otherwise.

    starts_with?(path_join(eval_root, "eval"), eval_root) #=> true
"""
def eval_root()
  root = getenv("GEN_ROOT", cwd)
  if starts_with?(root, "/")
    root
  else
    path_join(cwd, root)
  end
end

@doc """
stage_references: A fresh submissions directory under TMPDIR holding every
task's reference solution as `<task id>.b`; its path.

    length(ls(stage_references)) #=> 10
"""
def stage_references()
  dir = path_join(temp_dir("blue-eval-gate"), "blue-eval-gate")
  mkdir_p(dir)
  tasks = ls(path_join(eval_root, "eval/tasks"))
  copied = map(
    fn(t)
      write_program(
        path_join(dir, "#{path_basename(t)}.b"),
        read_file(path_join(t, "reference.b"))
      )
    end,
    tasks
  )
  if length(copied) != 10
    raise(:eval, "expected ten tasks, found #{length(copied)}")
  end
  dir
end

@doc """
run_scorer: Run eval/score.b over a submissions directory; the capture and the
result it wrote, parsed.

    run_scorer(getenv("TMPDIR", "/tmp"))[1]["passed"] #=> 0
"""
def run_scorer(dir)
  out = path_join(dir, "score.json")
  cap = exec_with_env(
    [["EVAL_TASKS", path_join(eval_root, "eval/tasks")]],
    self_exe,
    "run",
    path_join(eval_root, "eval/score.b"),
    "--",
    dir,
    out
  )
  [cap, json_read(read_file(out))]
end

@doc """
failed_ids: The ids of the tasks a result marks failed, in task order.

    failed_ids({"tasks" => [{"id" => "t01", "passed" => false}]}) #=> ["t01"]
"""
def failed_ids(result)
  map((t) -> t["id"], filter((t) -> not t["passed"], result["tasks"]))
end

test "every reference solution scores, ten of ten"
  dir = stage_references
  ran = run_scorer(dir)
  assert status_of(ran[0]) == 0
  assert ran[1]["total"] == 10
  assert ran[1]["passed"] == 10
  assert contains?(stdout_of(ran[0]), "score: 10/10")
  rm_rf(dir)
end

test "a broken reference fails its own task, and only that one"
  dir = stage_references
  write_program(
    path_join(dir, "t03-port-python.b"),
    unlines(["def run_length(s)", "  map((c) -> [c, 1], chars(s))", "end"])
  )
  ran = run_scorer(dir)
  assert status_of(ran[0]) != 0
  assert ran[1]["passed"] == 9
  assert failed_ids(ran[1]) == ["t03-port-python"]
  assert contains?(stdout_of(ran[0]), "FAIL t03-port-python (test)")
  rm_rf(dir)
end

test "a warning is not clean: the copied word fails at the check stage"
  dir = stage_references
  write_program(
    path_join(dir, "t09-reuse-word.b"),
    unlines(
      [
        "def total(xs)",
        "  reduce((acc, x) -> acc + x, 0, xs)",
        "end",
        "",
        "def invoice_total(lines)",
        "  total(map((l) -> l[:price] * l[:qty], lines))",
        "end"
      ]
    )
  )
  ran = run_scorer(dir)
  assert status_of(ran[0]) != 0
  assert failed_ids(ran[1]) == ["t09-reuse-word"]
  assert contains?(stdout_of(ran[0]), "FAIL t09-reuse-word (check)")
  rm_rf(dir)
end
