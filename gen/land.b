use("moji", %i[after_first take_chars])
use("retsu", %i[find_first first reject])
use("shisutemu", [:stdout_of])

@doc """
land_ref: The branch a landing pushes to. CI runs the whole suite on it and
fast-forwards main to it when green; a dry landing runs the suite and only
rehearses the fast-forward.

    land_ref("blue/toolchain-friction", false) #=> "land/blue/toolchain-friction"
    land_ref("blue/toolchain-friction", true) #=> "land/dry-blue/toolchain-friction"
"""
def land_ref(slug, dry)
  if dry
    "land/dry-#{slug}"
  else
    "land/#{slug}"
  end
end

@doc """
slug_for: The slug a landing takes: the one given, else the branch, else the
short commit when HEAD is main or no branch.

    slug_for(nil, "blue/toolchain-friction", "8bd5119") #=> "blue/toolchain-friction"
    slug_for(nil, "main", "8bd5119") #=> "8bd5119"
    slug_for("hard-blocks", "main", "8bd5119") #=> "hard-blocks"
"""
def slug_for(given, branch, short)
  if not given.nil?
    given
  elsif branch == "" or branch == "main" or branch == "HEAD"
    short
  else
    branch
  end
end

@doc """
land_args: The words after the program: an optional slug and the flags
--dry and --watch, in any order.

    land_args(["--watch", "x"]) #=> {slug: "x", dry: false, watch: true}
    land_args([]) #=> {slug: nil, dry: false, watch: false}
"""
def land_args(words)
  plain = reject((w) -> starts_with?(w, "--"), words)
  {
    slug: if plain == []
      nil
    else
      first(plain)
    end,
    dry: member?("--dry", words),
    watch: member?("--watch", words)
  }
end

@doc """
requeue_of: How many times `--watch` rebases onto a main that moved first and
lands again: the count `--requeue=N` gives, else 2. `--requeue=0` turns it
off; a value that is no count is nil, and land refuses it.

    requeue_of(["--watch"]) #=> 2
    requeue_of(["--watch", "--requeue=0"]) #=> 0
    requeue_of(["--requeue=many"]) #=> nil
"""
def requeue_of(words)
  given = find_first((w) -> starts_with?(w, "--requeue="), words)
  if given.nil?
    2
  else
    n = to_int(after_first(given, "="))
    if n.nil? or n < 0
      nil
    else
      n
    end
  end
end

@doc """
moved_main?: Whether a land run's jobs, as `gh run view --json jobs` lists
them, failed only at the fast-forward with every CI job green: the failure a
main that moved first causes, and the one a rebase can fix.

    moved_main?([]) #=> false
"""
def moved_main?(jobs)
  forward = filter((j) -> json_get(j, :name) == "fast-forward", jobs)
  ci = reject((j) -> json_get(j, :name) == "fast-forward", jobs)
  forward != [] and
    every?((j) -> json_get(j, :conclusion) == "failure", forward) and
    every?((j) -> member?(json_get(j, :conclusion), %w[success skipped]), ci)
end

def git(args)
  trim(stdout_of(exec_capture("git", *args)))
end

def run_of(ref, sha)
  reduce(
    fn(id, _)
      if id != ""
        id
      else
        sleep(3)
        trim(
          stdout_of(
            exec_capture(
              "gh",
              "run",
              "list",
              "--branch",
              ref,
              "--workflow",
              "land.yml",
              "--commit",
              sha,
              "--json",
              "databaseId",
              "--jq",
              ".[0].databaseId"
            )
          )
        )
      end
    end,
    "",
    range(20)
  )
end

def push_land(ref)
  sha = git(%w[rev-parse HEAD])
  if exec_check("git", "push", "--force", "origin", "HEAD:refs/heads/#{ref}") !=
      0
    exit_with(1)
  end
  write_stderr(
    unlines(
      [
        "land: #{take_chars(sha, 10)} is on #{ref}. CI runs the whole suite and, when green, fast-forwards main to it; when main moved first, it fails, and --watch rebases and lands again"
      ]
    )
  )
  sha
end

def follow(ref, left)
  sha = push_land(ref)
  found = run_of(ref, sha)
  if found == ""
    write_stderr(
      unlines(
        ["land: no run appeared in a minute; gh run list --branch #{ref}"]
      )
    )
    exit_with(1)
  end
  status = exec_check("gh", "run", "watch", found, "--exit-status")
  if status == 0
    exit_with(0)
  end
  jobs = json_parse(
    stdout_of(
      exec_capture(
        "gh",
        "run",
        "view",
        found,
        "--json",
        "jobs",
        "--jq",
        "[.jobs[] | {name, conclusion}]"
      )
    )
  ) rescue
    []
  fetched = exec_check("git", "fetch", "-q", "origin", "main") == 0
  moved = fetched and
    not exec_ok?("git", "merge-base", "--is-ancestor", "origin/main", "HEAD")
  if left == 0 or not moved or not moved_main?(jobs)
    exit_with(status)
  end
  if exec_check("git", "rebase", "-q", "origin/main") != 0
    exec_check("git", "rebase", "--abort")
    write_stderr(
      unlines(
        ["land: main moved while CI ran, and HEAD does not rebase onto origin/main cleanly; rebase it yourself and land again"]
      )
    )
    exit_with(status)
  end
  write_stderr(
    unlines(
      [
        "land: main moved while CI ran (every CI job green, the fast-forward refused); rebased onto origin/main and landing again, #{to_s(left - 1)} more after this; --requeue=0 turns this off"
      ]
    )
  )
  follow(ref, left - 1)
end

def main()
  a = land_args(argv)
  if git(%w[status --porcelain --untracked-files=no]) != ""
    write_stderr(
      unlines(
        ["land: tracked files differ from HEAD; commit them, since CI checks the commit"]
      )
    )
    exit_with(1)
  end
  if exec_check("git", "fetch", "-q", "origin", "main") != 0
    exit_with(1)
  end
  if not exec_ok?("git", "merge-base", "--is-ancestor", "origin/main", "HEAD")
    write_stderr(
      unlines(
        ["land: HEAD does not contain origin/main, so main cannot fast-forward to it. Run: git rebase origin/main"]
      )
    )
    exit_with(1)
  end
  left = requeue_of(argv)
  if left.nil?
    write_stderr(
      unlines(
        ["land: --requeue takes a count, as --requeue=2; --requeue=0 turns the requeue off"]
      )
    )
    exit_with(2)
  end
  ref = land_ref(
    slug_for(
      a[:slug],
      git(%w[rev-parse --abbrev-ref HEAD]),
      git(%w[rev-parse --short HEAD])
    ),
    a[:dry]
  )
  if a[:watch]
    follow(ref, left)
  else
    push_land(ref)
    write_stderr(unlines(["land: follow it with gh run list --branch #{ref}"]))
  end
end

test "a landing pushes to land/<slug>, and a dry one to land/dry-<slug>"
  assert land_ref(slug_for(nil, "a/b", "1234567"), false) == "land/a/b"
  assert land_ref(slug_for(nil, "main", "1234567"), true) == "land/dry-1234567"
end

test "only a run whose CI is green and whose fast-forward failed is requeued, as the five land runs of 2026-10-30 show"
  job = fn(name, conclusion)
    "{\"name\":\"#{name}\",\"conclusion\":\"#{conclusion}\"}"
  end
  run = (jobs) -> json_parse("[#{join(jobs, ",")}]")
  raced = run(
    [
      job("ci / consumers", "success"),
      job("ci / check / flake-check", "success"),
      job("fast-forward", "failure")
    ]
  )
  red = run(
    [
      job("ci / consumers", "success"),
      job("ci / check / flake-check", "failure"),
      job("fast-forward", "skipped")
    ]
  )
  stopped = run(
    [
      job("ci / check / cargo-test", "failure"),
      job("ci / check / flake-check", "cancelled"),
      job("fast-forward", "cancelled")
    ]
  )
  assert moved_main?(raced)
  assert not moved_main?(red)
  assert not moved_main?(stopped)
  assert not moved_main?(run([job("ci / consumers", "success")]))
  superseded = run(
    [
      job("ci / check / flake-check", "success"),
      job("fast-forward", "cancelled")
    ]
  )
  assert not moved_main?(superseded)
  forced = run(
    [job("ci / check / flake-check", "failure"), job("fast-forward", "failure")]
  )
  assert not moved_main?(forced)
end
