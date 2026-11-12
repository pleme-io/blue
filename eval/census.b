use("fairu", [:absolute])
use("hadome", %i[measurement parse receipted recorded render])
use("moji", [:trim])
use("retsu", %i[first flat_map is_empty last])
use("shisutemu", [:read_or])

KIND = "model-eval-passed"

RECORD = "blue run eval/census.b -- record"

REASONS = %w[task-added task-changed rule-tightened answers-replaced]

@doc """
eval_root: The directory holding eval/: GEN_ROOT under the flake check, the
current directory otherwise.

    starts_with?(path_join(eval_root, "eval"), eval_root) #=> true
"""
def eval_root()
  absolute(getenv("GEN_ROOT", cwd))
end

@doc """
baseline_path: The census file: one `model-eval-passed: <run> <n>` row per
recorded run, and `# receipt:` lines that say why a row fell.

    ends_with?(baseline_path, "eval/score.baseline") #=> true
"""
def baseline_path()
  path_join(eval_root, "eval/score.baseline")
end

@doc """
version_rank: A release version as one number that sorts as the versions do.

    version_rank("0.0.192") < version_rank("0.1.0") #=> true
    version_rank("0.0.9") < version_rank("0.0.10") #=> true
"""
def version_rank(v)
  reduce((acc, p) -> acc * 1_000_000 + (to_int(p) or 0), 0, split(v, "."))
end

@doc """
latest_runs: Each model's most recent recorded run under a scores directory
laid out `<version>/<model>/`, as `{key:, dir:}`, by model. A directory that
does not exist holds no run.

    latest_runs("/no/such/scores") #=> []
"""
def latest_runs(scores)
  if not path_exists(scores)
    []
  else
    runs = flat_map(
      filter(is_dir?, ls(scores)),
      fn(v)
        map(
          fn(m)
            {
              key: path_basename(m),
              dir: m,
              rank: version_rank(path_basename(v))
            }
          end,
          filter(is_dir?, ls(v))
        )
      end
    )
    sort_keyed(
      (r) -> r[:key],
      map(
        fn(e)
          newest = last(sort_keyed((r) -> r[:rank], e[1]))
          {key: e[0], dir: newest[:dir]}
        end,
        map_entries(group_by(runs, (r) -> r[:key]))
      )
    )
  end
end

@doc """
stage_references: A fresh directory holding every task's reference solution
as `<task id>.b`: the run the census keys `reference`.

    length(ls(stage_references(path_join(eval_root, "eval/tasks")))) > 0 #=> true
"""
def stage_references(tasks)
  dir = path_join(temp_dir("blue-eval-census"), "reference")
  mkdir_p(dir)
  map(
    fn(t)
      write_program(
        path_join(dir, "#{path_basename(t)}.b"),
        read_file(path_join(t, "reference.b"))
      )
    end,
    ls(tasks)
  )
  dir
end

@doc """
rescore: How many tasks a run's recorded answers pass under this blue, scored
by eval/score.b into a file of its own, so the recorded score.json is never
rewritten; nil when the scorer wrote no result.

    rescore("/no/such/answers", path_join(eval_root, "eval/tasks")) #=> 0
"""
def rescore(answers, tasks)
  out = path_join(temp_dir("blue-eval-census"), "score.json")
  exec_with_env(
    [["EVAL_TASKS", tasks]],
    self_exe,
    "run",
    path_join(eval_root, "eval/score.b"),
    "--",
    answers,
    out
  )
  if path_exists(out)
    json_read(read_file(out))["passed"]
  end
end

@doc """
measure: Every run's census row as a hadome measurement: the references,
then each model's latest recorded answers, rescored now.

    measure("/no/such/scores", "/no/such/tasks") == [measurement("reference", 0)] #=> true
"""
def measure(scores, tasks)
  refs = if path_exists(tasks)
    stage_references(tasks)
  else
    "/no/such/references"
  end
  append(
    [measurement("reference", rescore(refs, tasks) or 0)],
    map(
      (r) -> measurement(r[:key], rescore(r[:dir], tasks) or 0),
      latest_runs(scores)
    )
  )
end

@doc """
problems: Each run whose rescored count fell below its row, or that has no
row, as one line naming the run and the command that records it.

    problems([], [measurement("reference", 10)]) #=> ["reference: passes 10 and the census has no row for it; record it: blue run eval/census.b -- record"]
"""
def problems(rows, measured)
  flat_map(
    measured,
    fn(m)
      was = recorded(rows, KIND, m[:key])
      if was.nil?
        [
          "#{m[:key]}: passes #{to_s(m[:size])} and the census has no row for it; record it: #{RECORD}"
        ]
      elsif m[:size] < was
        [
          "#{m[:key]}: passes #{to_s(m[:size])}, below its recorded #{to_s(was)}; a fall needs a typed reason: #{RECORD} --reason <#{join(REASONS, "|")}> --receipt \"<why>\""
        ]
      else
        []
      end
    end
  )
end

@doc """
advisories: Rows a run rose past, which `record` banks, and rows no run
measures any more.

    advisories([], []) #=> []
"""
def advisories(rows, measured)
  keys = map((m) -> m[:key], measured)
  append(
    map(
      fn(m)
        "#{m[:key]}: passes #{to_s(m[:size])}, above its row; bank it: #{RECORD}"
      end,
      filter(
        fn(m)
          was = recorded(rows, KIND, m[:key])
          was != nil and m[:size] > was
        end,
        measured
      )
    ),
    map(
      (k) -> "#{k}: recorded, and no run measures it; drop it: #{RECORD}",
      filter(
        (k) -> not member?(k, keys),
        distinct(map((r) -> r[:key], filter((r) -> r[:kind] == KIND, rows)))
      )
    )
  )
end

@doc """
fallen: The measurements below their recorded row.

    fallen([], [measurement("a", 1)]) #=> []
"""
def fallen(rows, measured)
  filter(
    fn(m)
      was = recorded(rows, KIND, m[:key])
      was != nil and m[:size] < was
    end,
    measured
  )
end

@doc """
reason_of: The typed reason `--reason` names, or the refusal when it names
none of REASONS.

    reason_of(["--reason", "task-added"]) #=> {reason: "task-added"}
    reason_of(["--reason", "felt-like-it"])[:refused] != nil #=> true
    reason_of([]) #=> {reason: nil}
"""
def reason_of(args)
  at = position("--reason", args)
  given = if at < 0
    nil
  else
    args[at + 1] rescue nil
  end
  if given.nil?
    {reason: nil}
  elsif member?(given, REASONS)
    {reason: given}
  else
    {
      refused: "--reason is \"#{given}\"; it takes one of #{join(REASONS, ", ")}"
    }
  end
end

@doc """
receipt_of: The text after `--receipt`, or nil.

    receipt_of(["--receipt", "t11 added"]) #=> "t11 added"
"""
def receipt_of(args)
  at = position("--receipt", args)
  if at >= 0
    args[at + 1] rescue nil
  end
end

@doc """
admit: Whether a record may write, as nil, or the refusal: a fall needs a
typed reason and a receipt.

    admit([], {reason: nil}, nil) #=> nil
    admit([measurement("a", 1)], {reason: nil}, nil) != nil #=> true
    admit([measurement("a", 1)], {reason: "task-added"}, "t11") #=> nil
"""
def admit(fell, reason, receipt)
  if reason[:refused] != nil
    reason[:refused]
  elsif not is_empty(fell) and (reason[:reason].nil? or receipt.nil?)
    "refused: a fall needs a typed reason: #{RECORD} --reason <#{join(REASONS, "|")}> --receipt \"<why>\""
  end
end

@doc """
record: Write the census from a fresh measure, keeping the old file's comment
lines; a fall is refused unless it carries a typed reason and a receipt, which
stay as a `# receipt:` line.

    admit([], {reason: nil}, nil) #=> nil
"""
def record(args)
  path = baseline_path
  old = read_or(path, "")
  rows = parse(old)
  measured = measure(
    path_join(eval_root, "eval/scores"),
    path_join(eval_root, "eval/tasks")
  )
  fell = fallen(rows, measured)
  reason = reason_of(args)
  receipt = receipt_of(args)
  refused = admit(fell, reason, receipt)
  if refused != nil
    write_stderr(unlines(append(problems(rows, fell), [refused])))
    exit_with(1)
  end
  note = if receipt.nil?
    nil
  elsif reason[:reason].nil?
    receipt
  else
    "#{reason[:reason]}: #{receipt}"
  end
  write_file(path, receipted(old, note, render(KIND, measured)))
  write_stdout(unlines(map((m) -> "#{m[:key]} #{to_s(m[:size])}", measured)))
end

@doc """
main: `blue run eval/census.b -- record [--reason R --receipt WHY]` writes
eval/score.baseline from a fresh measure; `check` prints each run's count and
exits 1 when one fell below its row or has none.

    REASONS[0] #=> "task-added"
"""
def main()
  if argv_get(0) == "record"
    record(drop(1, argv))
    exit_with(0)
  elsif argv_get(0) == "check"
    rows = parse(read_or(baseline_path, ""))
    measured = measure(
      path_join(eval_root, "eval/scores"),
      path_join(eval_root, "eval/tasks")
    )
    write_stdout(unlines(map((m) -> "#{m[:key]} #{to_s(m[:size])}", measured)))
    write_stderr(join(map((a) -> unlines([a]), advisories(rows, measured)), ""))
    bad = problems(rows, measured)
    if not is_empty(bad)
      write_stderr(unlines(bad))
      exit_with(1)
    end
    exit_with(0)
  else
    write_stderr(
      unlines(
        [
          "usage: #{RECORD} [--reason <#{join(REASONS, "|")}> --receipt WHY] | check"
        ]
      )
    )
    exit_with(64)
  end
end

test "a run that falls below its row is named, a held or risen run is not"
  rows = parse(unlines(["#{KIND}: reference 10", "#{KIND}: some-model 7"]))
  held = [measurement("reference", 10), measurement("some-model", 8)]
  assert problems(rows, held) == []
  fell = [measurement("reference", 10), measurement("some-model", 6)]
  assert length(problems(rows, fell)) == 1
  assert contains?(first(problems(rows, fell)), "some-model: passes 6")
  assert advisories(rows, held) ==
    ["some-model: passes 8, above its row; bank it: #{RECORD}"]
end

test "a fall records only with a typed reason and a receipt"
  fell = [measurement("some-model", 6)]
  assert admit(fell, {reason: nil}, "why") != nil
  assert admit(fell, {reason: "rule-tightened"}, nil) != nil
  assert admit(fell, reason_of(%w[--reason because]), "why") != nil
  assert admit(fell, {reason: "rule-tightened"}, "B0083 refuses t04").nil?
end

test "the latest run of each model is the one the census rescores"
  dir = path_join(temp_dir("blue-eval-census"), "scores")
  map((p) -> mkdir_p(path_join(dir, p)), %w[0.0.9/m-a 0.0.10/m-a 0.0.10/m-b])
  runs = latest_runs(dir)
  assert map((r) -> r[:key], runs) == %w[m-a m-b]
  assert ends_with?(runs[0][:dir], "0.0.10/m-a")
  rm_rf(dir)
end

test "every recorded run holds its census row"
  rows = parse(read_or(baseline_path, ""))
  measured = measure(
    path_join(eval_root, "eval/scores"),
    path_join(eval_root, "eval/tasks")
  )
  map((a) -> write_stderr(unlines([a])), advisories(rows, measured))
  bad = problems(rows, measured)
  if not is_empty(bad)
    write_stderr(unlines(bad))
  end
  assert is_empty(bad)
  assert length(measured) >= 2
  assert trim(read_or(baseline_path, "")) != ""
end
