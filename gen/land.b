use("moji", %i[after_first take_chars])
use("retsu", %i[find_first first reject])
use("shisutemu", %i[status_of stderr_of stdout_of])

@doc """
land_ref: The branch a landing pushes to. CI runs the suite the scope selects on
it and fast-forwards main to it when green; a dry landing runs the suite and only
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
scoped_slug: The slug with the prefix land.yml reads: a prose landing runs the
gates that read prose, and land.yml refuses a prefix its own `--scope` disputes.

    scoped_slug("docs-row", "prose") #=> "prose-docs-row"
    scoped_slug("docs-row", "whole") #=> "docs-row"
"""
def scoped_slug(slug, scope)
  if scope == "prose"
    "prose-#{slug}"
  else
    slug
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
land_args: The words after the program: an optional slug and the flags, in any
order. --dry rehearses, --watch follows the run and takes its turn, --proven
runs the suite and pushes its proof (gen/proof.b) so CI skips cargo test.
--no-queue, --no-regen and --no-prose each turn one default off.

    land_args(["--watch", "x"]) #=> {slug: "x", dry: false, watch: true, queue: true, regen: true, prose: true, proven: false}
    land_args(["--no-queue", "--no-regen", "--no-prose", "--proven"]) #=> {slug: nil, dry: false, watch: false, queue: false, regen: false, prose: false, proven: true}
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
    watch: member?("--watch", words),
    queue: not member?("--no-queue", words),
    regen: not member?("--no-regen", words),
    prose: not member?("--no-prose", words),
    proven: member?("--proven", words)
  }
end

@doc """
unknown_flag: The first flag land does not know, so a misspelt off switch stops
the landing rather than leaving the default on; nil when all are known.

    unknown_flag(["x", "--watch", "--requeue=1", "--queue-minutes=5"]) #=> nil
    unknown_flag(["--no-qeueu"]) #=> "--no-qeueu"
"""
def unknown_flag(words)
  find_first(
    fn(w)
      starts_with?(w, "--") and
        not member?(
          w,
          %w[--dry --watch --proven --no-queue --no-regen --no-prose]
        ) and
        not starts_with?(w, "--requeue=") and
        not starts_with?(w, "--queue-minutes=")
    end,
    words
  )
end

@doc """
count_flag: The count a `--name=N` flag gives, else the default; nil for a value
that is no count, which land refuses.

    count_flag(["--requeue=0"], "--requeue=", 2) #=> 0
    count_flag([], "--requeue=", 2) #=> 2
    count_flag(["--requeue=many"], "--requeue=", 2) #=> nil
"""
def count_flag(words, name, otherwise)
  given = find_first((w) -> starts_with?(w, name), words)
  if given.nil?
    otherwise
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
requeue_of: How many times a land rebases onto a main that moved first and lands
again: the count `--requeue=N` gives, else 2. `--requeue=0` turns it off, and
then a land behind main refuses instead of rebasing; a value that is no count is
nil, and land refuses it.

    requeue_of(["--watch"]) #=> 2
    requeue_of(["--watch", "--requeue=0"]) #=> 0
    requeue_of(["--requeue=many"]) #=> nil
"""
def requeue_of(words)
  count_flag(words, "--requeue=", 2)
end

@doc """
own_job?: Whether a job, as `gh run view --json jobs` names it, is one of the
land's own rather than its suite: the fast-forward and stop-on-red, at the top
of land.yml or inside a reusable it calls.

    own_job?("fast-forward") #=> true
    own_job?("ci / stop-on-red") #=> true
    own_job?("ci / check / cargo-test") #=> false
"""
def own_job?(name)
  member?(retsu::last(split(name, " / ")), %w[fast-forward stop-on-red])
end

@doc """
moved_main?: Whether a land run's jobs, as `gh run view --json jobs` lists
them, failed only at the fast-forward with every CI job green: the failure a
main that moved first causes, and the one a rebase can fix.

    moved_main?([]) #=> false
"""
def moved_main?(jobs)
  forward = filter((j) -> json_get(j, :name) == "fast-forward", jobs)
  ci = reject((j) -> own_job?(json_get(j, :name)), jobs)
  forward != [] and
    every?((j) -> json_get(j, :conclusion) == "failure", forward) and
    every?((j) -> member?(json_get(j, :conclusion), %w[success skipped]), ci)
end

@doc """
lands_ahead: The land runs that are still running on another ref, oldest first,
as `gh run list --json databaseId,headBranch,status` lists them. A dry land moves
no main, so it holds nobody up.

    lands_ahead([], "land/x") #=> []
"""
def lands_ahead(runs, ref)
  sort_keyed(
    (r) -> json_get(r, :databaseId),
    filter(
      fn(r)
        branch = json_get(r, :headBranch)
        member?(
          json_get(r, :status),
          %w[queued in_progress requested waiting pending]
        ) and
          branch !=
            ref and
          starts_with?(
            branch,
            "land/"
          ) and not starts_with?(branch, "land/dry-")
      end,
      runs
    )
  )
end

@doc """
yields_to: The older land run this one stands behind, or nil: two lands that took
the same free turn would each run the suite for one fast-forward, so the younger
stops and queues again.

    yields_to([], "land/x", 5) #=> nil
"""
def yields_to(runs, ref, mine)
  find_first((r) -> json_get(r, :databaseId) < mine, lands_ahead(runs, ref))
end

@doc """
first_red: The first CI job that has failed, as `gh run view --json jobs` lists
them, so the rest of its suite can stop; nil while none has. The fast-forward's
refusal is the land's last word, not a suite to stop.

    first_red([]) #=> nil
"""
def first_red(jobs)
  name_of = (j) -> json_get(j, :name)
  red = find_first(
    (j) -> json_get(j, :conclusion) == "failure" and not own_job?(name_of(j)),
    jobs
  )
  if not red.nil?
    name_of(red)
  end
end

@doc """
suite_done?: Whether every CI job has finished, so nothing is left to stop.

    suite_done?([]) #=> false
"""
def suite_done?(jobs)
  ci = reject((j) -> own_job?(json_get(j, :name)), jobs)
  ci != [] and every?((j) -> json_get(j, :status) == "completed", ci)
end

def git(args)
  trim(stdout_of(exec_capture("git", *args)))
end

def say(line)
  write_stderr(unlines(["land: #{line}"]))
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

def land_runs()
  cap = exec_capture(
    "gh",
    "run",
    "list",
    "--workflow",
    "land.yml",
    "--limit",
    "40",
    "--json",
    "databaseId,headBranch,status"
  )
  if status_of(cap) == 0
    json_parse(stdout_of(cap))
  end
end

def wait_turn(ref, deadline, waited)
  runs = land_runs
  held = if runs.nil?
    "the land runs cannot be read (a rate limit answers 403), so this land holds its turn"
  else
    ahead = lands_ahead(runs, ref)
    if ahead != []
      "#{to_s(count(ahead))} land(s) ahead, first #{json_get(first(ahead), :headBranch)}; waiting for a turn, since only one reaches main; --no-queue lands beside them"
    end
  end
  if not held.nil?
    if now_ms > deadline
      say("waited the --queue-minutes limit; landing without a turn: #{held}")
    else
      if not waited
        say(held)
      end
      sleep(60)
      wait_turn(ref, deadline, true)
    end
  end
end

@doc """
run_ended: The conclusion in `gh run view --json status,conclusion` output, or nil
while the run runs or the answer cannot be read, so a rate limit reads as not yet.

    run_ended("{\"status\":\"completed\",\"conclusion\":\"failure\"}") #=> "failure"
    run_ended("{\"status\":\"in_progress\",\"conclusion\":\"\"}") #=> nil
    run_ended("HTTP 403") #=> nil
"""
def run_ended(text)
  view = json_parse(text) rescue nil
  if not view.nil? and json_get(view, :status) == "completed"
    json_get(view, :conclusion)
  end
end

@doc """
wait_run: Poll a run once a minute until it ends and return 0 when it succeeded.
`gh run watch` polls every 3 seconds, 1,200 calls an hour of a 5,000-an-hour limit,
and on 2026-11-04 `gh` answered 403 beside other agents' polling; a 403 from watch
reads as a failed land while its run goes on.
"""
def wait_run(id)
  ended = run_ended(
    stdout_of(
      exec_capture("gh", "run", "view", id, "--json", "status,conclusion")
    )
  )
  if ended.nil?
    sleep(60)
    wait_run(id)
  elsif ended == "success"
    0
  else
    1
  end
end

@doc """
stop_on_red: ci.yml's stop-on-red job on a land: read this run's jobs once a minute and
cancel the run at its first red job, because a red land cannot reach main and the
next land waits on it. An unreadable answer reads as not yet. Off: the repository
variable BLUE_LAND_STOP_ON_RED=off skips the job.
"""
def stop_on_red(id)
  jobs = json_parse(
    stdout_of(
      exec_capture(
        "gh",
        "run",
        "view",
        id,
        "--json",
        "jobs",
        "--jq",
        "[.jobs[] | {name, status, conclusion}]"
      )
    )
  ) rescue
    []
  red = first_red(jobs)
  if not red.nil?
    say(
      "#{red} is red, so this land cannot reach main; cancelling the rest of run #{id} so the next land starts"
    )
    exec_check("gh", "run", "cancel", id)
  elsif not suite_done?(jobs)
    sleep(60)
    stop_on_red(id)
  end
end

def contains_main?()
  exec_ok?("git", "merge-base", "--is-ancestor", "origin/main", "HEAD")
end

def fetch_main()
  if exec_check("git", "fetch", "-q", "origin", "main") != 0
    exit_with(1)
  end
end

def driver_args()
  if path_exists(".githooks/merge-generated")
    [
      "-c",
      "merge.blue-generated.driver=.githooks/merge-generated %O %A %B %P %Y"
    ]
  else
    []
  end
end

def blue_here()
  if path_exists(".githooks/blue")
    ".githooks/blue"
  else
    self_exe
  end
end

def regenerate()
  steps = [%w[lock .], %w[run --quiet gen/regen.b]]
  map(
    fn(args)
      r = exec_capture(blue_here, *args)
      if status_of(r) != 0
        say(
          "rebased onto origin/main, but `blue #{join(args, " ")}` failed; fix it and land again: #{stderr_of(r)}"
        )
        exit_with(1)
      end
    end,
    steps
  )
  changed = git(%w[status --porcelain --untracked-files=no])
  if changed != ""
    exec_check("git", "add", "-u")
    exec_check(
      "git",
      "commit",
      "-q",
      "-m",
      "regen after rebasing onto #{git(%w[rev-parse --short origin/main])}"
    )
    say("the rebase left generated files stale; regenerated and committed them")
  end
end

@doc """
catch_up: Rebase HEAD onto origin/main, where the merge driver regenerates a
generated file that conflicts, then regenerate what merged clean but went stale
and commit it. Any other conflict aborts the rebase, leaves HEAD as it was, names
the paths and stops: that one needs a person.
"""
def catch_up(a)
  r = exec_capture("git", *append(driver_args, %w[rebase -q origin/main]))
  if status_of(r) != 0
    paths = git(%w[diff --name-only --diff-filter=U])
    exec_check("git", "rebase", "--abort")
    say(
      if paths == ""
        "git rebase failed with no conflict: #{trim(stderr_of(r))}"
      else
        "HEAD does not rebase onto origin/main: #{replace(paths, line_break, ", ")} conflict beyond what regenerating can settle; rebase it yourself and land again"
      end
    )
    exit_with(1)
  end
  if a[:regen]
    regenerate
  end
end

def settle(a, left, minutes)
  ref = ref_for(a)
  if a[:watch] and a[:queue] and not a[:dry]
    wait_turn(ref, now_ms + minutes * 60000, false)
  end
  fetch_main
  if not contains_main?
    if left == 0
      say("HEAD does not contain origin/main, so main cannot fast-forward to it, and --requeue=0 keeps this land from rebasing. Run: git rebase origin/main")
      exit_with(1)
    end
    catch_up(a)
    settle(a, left, minutes)
  end
end

def prove(a)
  if a[:proven] and
      exec_check(self_exe, "run", "--quiet", "gen/proof.b", "--", "--prove") !=
        0
    say("no proof of HEAD's tree; land without --proven and CI runs the suite")
    exit_with(1)
  end
end

def ref_for(a)
  scoped = exec_capture(
    self_exe,
    "run",
    "--quiet",
    "gen/prepush.b",
    "--",
    "--scope",
    "origin/main",
    "HEAD"
  )
  scope = if a[:prose] and status_of(scoped) == 0
    trim(stdout_of(scoped))
  else
    "whole"
  end
  land_ref(
    scoped_slug(
      slug_for(
        a[:slug],
        git(%w[rev-parse --abbrev-ref HEAD]),
        git(%w[rev-parse --short HEAD])
      ),
      scope
    ),
    a[:dry]
  )
end

def push_land(ref)
  sha = git(%w[rev-parse HEAD])
  if exec_check("git", "push", "--force", "origin", "HEAD:refs/heads/#{ref}") !=
      0
    exit_with(1)
  end
  say(
    "#{take_chars(sha, 10)} is on #{ref}. CI runs its suite and, when green, fast-forwards main to it; when main moved first, it fails, and --watch rebases and lands again"
  )
  sha
end

def follow(a, left, minutes)
  settle(a, left, minutes)
  prove(a)
  ref = ref_for(a)
  sha = push_land(ref)
  found = run_of(ref, sha)
  if found == ""
    say("no run appeared in a minute; gh run list --branch #{ref}")
    exit_with(1)
  end
  older = if a[:queue] and not a[:dry]
    yields_to(land_runs or [], ref, to_int(found))
  end
  if not older.nil?
    say(
      "#{json_get(older, :headBranch)} took the same turn first; stopping this run and queueing behind it"
    )
    exec_check("gh", "run", "cancel", found)
    follow(a, left, minutes)
  else
    say("following run #{found}")
    status = wait_run(found)
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
    moved = fetched and not contains_main?
    if left == 0 or not moved or not moved_main?(jobs)
      exit_with(status)
    end
    say(
      "main moved while CI ran (every CI job green, the fast-forward refused); rebasing onto origin/main and landing again, #{to_s(left - 1)} more after this; --requeue=0 turns this off"
    )
    follow(a, left - 1, minutes)
  end
end

def main()
  if count(argv) == 2 and first(argv) == "--stop-on-red"
    stop_on_red(argv_get(1))
    exit_with(0)
  end
  a = land_args(argv)
  unknown = unknown_flag(argv)
  if not unknown.nil?
    say(
      "#{unknown} is no flag; land takes --dry, --watch, --proven, --no-queue, --no-regen, --no-prose, --requeue=N and --queue-minutes=N"
    )
    exit_with(2)
  end
  if git(%w[status --porcelain --untracked-files=no]) != ""
    say("tracked files differ from HEAD; commit them, since CI checks the commit")
    exit_with(1)
  end
  left = requeue_of(argv)
  minutes = count_flag(argv, "--queue-minutes=", 240)
  if left.nil? or minutes.nil?
    say("--requeue and --queue-minutes take a count, as --requeue=2; --requeue=0 turns the requeue off")
    exit_with(2)
  end
  fetch_main
  if a[:watch]
    follow(a, left, minutes)
  else
    settle(a, left, minutes)
    prove(a)
    ref = ref_for(a)
    push_land(ref)
    say("follow it with gh run list --branch #{ref}")
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

test "only a land still running on another ref holds a turn, oldest first"
  run = fn(id, branch, status)
    "{\"databaseId\":#{id},\"headBranch\":\"#{branch}\",\"status\":\"#{status}\"}"
  end
  runs = json_parse(
    "[#{join([run(9, "land/late", "queued"), run(5, "land/early", "in_progress"), run(4, "land/mine", "in_progress"), run(3, "land/dry-rehearsal", "in_progress"), run(2, "land/done", "completed"), run(1, "main", "in_progress")], ",")}]"
  )
  assert map((r) -> json_get(r, :headBranch), lands_ahead(runs, "land/mine")) ==
    %w[land/early land/late]
  assert json_get(yields_to(runs, "land/mine", 7), :headBranch) == "land/early"
  assert yields_to(runs, "land/mine", 4).nil?
  assert yields_to(runs, "land/mine", 2).nil?
end

test "the first red CI job stops a suite, and a refused fast-forward or a green suite stops nothing, as land/fc-objects' 32 minute run of 2026-11-04 shows"
  job = fn(name, status, conclusion)
    "{\"name\":\"#{name}\",\"status\":\"#{status}\",\"conclusion\":\"#{conclusion}\"}"
  end
  run = (jobs) -> json_parse("[#{join(jobs, ",")}]")
  red = run(
    [
      job("stop-on-red", "in_progress", ""),
      job("ci / check / flake-check", "in_progress", ""),
      job("ci / check / cargo-test", "completed", "failure")
    ]
  )
  assert first_red(red) == "ci / check / cargo-test"
  assert not suite_done?(red)
  green = run(
    [
      job("stop-on-red", "in_progress", ""),
      job("ci / check / flake-check", "completed", "success"),
      job("fast-forward", "completed", "failure")
    ]
  )
  assert first_red(green).nil?
  assert suite_done?(green)
  running = run([job("ci / consumers", "in_progress", "")])
  assert first_red(running).nil?
  assert not suite_done?(running)
  assert moved_main?(
    run(
      [
        job("stop-on-red", "completed", "failure"),
        job("ci / consumers", "completed", "success"),
        job("fast-forward", "completed", "failure")
      ]
    )
  )
end

test "a run's end is read from its view, and an unreadable answer is not an end"
  assert run_ended("{\"status\":\"completed\",\"conclusion\":\"success\"}") ==
    "success"
  assert run_ended("{\"status\":\"queued\",\"conclusion\":\"\"}").nil?
  assert run_ended("").nil?
  assert run_ended("failed to get run: HTTP 403").nil?
end

test "stop-on-red inside the ci reusable is the land's own job, not its suite"
  job = fn(name, status, conclusion)
    "{\"name\":\"#{name}\",\"status\":\"#{status}\",\"conclusion\":\"#{conclusion}\"}"
  end
  run = (jobs) -> json_parse("[#{join(jobs, ",")}]")
  green = run(
    [
      job("ci / stop-on-red", "in_progress", ""),
      job("ci / blue", "completed", "success"),
      job("ci / check / flake-check", "completed", "success")
    ]
  )
  assert suite_done?(green)
  assert first_red(green).nil?
  assert first_red(run([job("ci / stop-on-red", "completed", "failure")])).nil?
  assert not own_job?("ci / check / cargo-test")
end

test "--proven is a flag of its own, off unless given"
  assert unknown_flag(%w[--proven --watch]).nil?
  assert land_args(["--proven"])[:proven]
  assert not land_args(["--watch"])[:proven]
end

test "a misspelt off switch stops the land, and each off switch is one flag"
  assert unknown_flag(%w[x --watch --no-queue --no-regen --no-prose --dry]).nil?
  assert unknown_flag(["--no-qeueu"]) == "--no-qeueu"
  assert not land_args(["--no-queue"])[:queue]
  assert land_args(["--no-queue"])[:regen]
  assert land_args([])[:prose]
  assert count_flag(["--queue-minutes=5"], "--queue-minutes=", 240) == 5
  assert count_flag(["--queue-minutes=x"], "--queue-minutes=", 240).nil?
end

def source(name)
  read_file(path_join(getenv("GEN_ROOT", cwd), name))
end

def repo(dir, args)
  r = exec_capture(
    "git",
    "-C",
    dir,
    "-c",
    "user.name=t",
    "-c",
    "user.email=t@t",
    *args
  )
  if status_of(r) != 0
    raise(:git, "git #{join(args, " ")}: #{stderr_of(r)}")
  end
  trim(stdout_of(r))
end

def script(path, text)
  write_file(path, text)
  exec_capture("chmod", "+x", path)
end

def committed(dir, paths, message)
  map((p) -> write_file(path_join(dir, first(p)), retsu::last(p)), paths)
  repo(dir, %w[add -A])
  repo(dir, ["commit", "-q", "-m", message])
end

def landing_fixture()
  root = path_join(getenv("TMPDIR", "/tmp"), "land-#{to_s(now_ns)}")
  work = path_join(root, "work")
  mkdir_p(path_join(work, "gen"))
  mkdir_p(path_join(work, "notes"))
  mkdir_p(path_join(work, ".githooks"))
  write_program(path_join(work, "gen/regen.b"), source("gen/regen.b"))
  write_program(path_join(work, "gen/merge.b"), source("gen/merge.b"))
  write_program(
    path_join(work, "made.b"),
    unlines(
      [
        "root = getenv(\"GEN_ROOT\", \".\")",
        "there = (n) -> path_exists(path_join(path_join(root, \"notes\"), n))",
        "write_file(getenv(\"GEN_OUT\"), unlines(filter(there, %w[base ant bee])))"
      ]
    )
  )
  script(
    path_join(work, ".githooks/blue"),
    unlines(["#!/bin/sh", "exec #{self_exe} \"$@\""])
  )
  script(
    path_join(work, ".githooks/merge-generated"),
    unlines(["#!/bin/sh", "exec #{self_exe} run --quiet gen/merge.b -- \"$@\""])
  )
  write_file(
    path_join(work, "Bluefile"),
    unlines(
      [
        "package(\"fixture\", \"0.1.0\")",
        "generate(\"made\", \"made.txt\", \"made.b\", [\"notes\"])"
      ]
    )
  )
  write_file(path_join(work, "notes/base"), "base")
  write_file(path_join(work, "made.txt"), unlines(["base"]))
  write_file(path_join(work, "source.txt"), unlines(["base"]))
  write_file(
    path_join(work, ".gitattributes"),
    unlines(["made.txt merge=blue-generated"])
  )
  if status_of(exec_capture(self_exe, "lock", work)) != 0
    raise(:fixture, "blue lock failed in #{work}")
  end
  repo(work, %w[init -q -b main])
  repo(work, %w[config user.name t])
  repo(work, %w[config user.email t@t])
  committed(work, [], "base")
  repo(root, %w[init -q --bare -b main origin.git])
  repo(work, ["remote", "add", "origin", path_join(root, "origin.git")])
  repo(work, %w[push -q origin main])
  repo(work, %w[checkout -q -b topic])
  root
end

def main_moves(root, paths)
  work = path_join(root, "work")
  repo(work, %w[checkout -q main])
  committed(work, paths, "main moved")
  repo(work, %w[push -q origin main])
  repo(work, %w[checkout -q topic])
end

def land_in(root, flags)
  land_with([], root, flags)
end

def flatten_args(flags)
  append(
    [
      self_exe,
      "run",
      "--quiet",
      path_join(getenv("GEN_ROOT", cwd), "gen/land.b"),
      "--"
    ],
    flags
  )
end

def land_with(settings, root, flags)
  exec_capture(
    "env",
    "-u",
    "GEN_ROOT",
    "-C",
    path_join(root, "work"),
    *append(settings, flatten_args(flags))
  )
end

def landed(root, name)
  repo(
    path_join(root, "work"),
    ["show", "refs/remotes/origin/land/topic:#{name}"]
  )
end

test "a land behind main whose one conflict is a generated file rebases, regenerates and pushes"
  if self_exe != nil
    root = landing_fixture
    work = path_join(root, "work")
    committed(
      work,
      [%w[notes/bee bee], ["made.txt", unlines(%w[base bee])]],
      "topic"
    )
    main_moves(root, [%w[notes/ant ant], ["made.txt", unlines(%w[base ant])]])
    r = land_in(root, [])
    assert status_of(r) == 0
    repo(work, %w[fetch -q origin])
    assert landed(root, "made.txt") == join(%w[base ant bee], line_break)
    assert repo(work, %w[log -1 --format=%s refs/remotes/origin/land/topic]) ==
      "topic"
    repo(work, %w[merge-base --is-ancestor origin/main origin/land/topic])
    rm_rf(root)
  end
end

test "a rebase that merges clean but leaves a generated file stale commits the regeneration"
  if self_exe != nil
    root = landing_fixture
    work = path_join(root, "work")
    committed(work, [%w[other.txt other]], "topic")
    main_moves(root, [%w[notes/ant ant]])
    r = land_in(root, [])
    assert status_of(r) == 0
    assert contains?(stderr_of(r), "regenerated and committed")
    repo(work, %w[fetch -q origin])
    assert landed(root, "made.txt") == join(%w[base ant], line_break)
    rm_rf(root)
  end
end

test "--no-regen leaves that stale file as the rebase left it"
  if self_exe != nil
    root = landing_fixture
    work = path_join(root, "work")
    committed(work, [%w[other.txt other]], "topic")
    main_moves(root, [%w[notes/ant ant]])
    assert status_of(land_in(root, ["--no-regen"])) == 0
    repo(work, %w[fetch -q origin])
    assert landed(root, "made.txt") == "base"
    rm_rf(root)
  end
end

test "a conflict in a source stops the land, names the path and leaves HEAD as it was"
  if self_exe != nil
    root = landing_fixture
    work = path_join(root, "work")
    committed(work, [["source.txt", unlines(["topic"])]], "topic")
    before = repo(work, %w[rev-parse HEAD])
    main_moves(root, [["source.txt", unlines(["main"])]])
    r = land_in(root, [])
    assert status_of(r) == 1
    assert contains?(stderr_of(r), "source.txt")
    assert repo(work, %w[rev-parse HEAD]) == before
    rm_rf(root)
  end
end

test "a rebase that fails with no conflict says git's words, as a clone with no identity does in the sandbox"
  if self_exe != nil
    root = landing_fixture
    work = path_join(root, "work")
    committed(work, [%w[other.txt other]], "topic")
    before = repo(work, %w[rev-parse HEAD])
    main_moves(root, [%w[notes/ant ant]])
    repo(work, %w[config --unset user.name])
    repo(work, %w[config --unset user.email])
    repo(work, %w[config user.useConfigOnly true])
    r = land_with(
      %w[GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1],
      root,
      []
    )
    assert status_of(r) == 1
    assert contains?(stderr_of(r), "git rebase failed with no conflict")
    assert repo(work, %w[rev-parse HEAD]) == before
    rm_rf(root)
  end
end

test "--proven pushes the land only after gen/proof.b --prove succeeds"
  if self_exe != nil
    root = landing_fixture
    work = path_join(root, "work")
    committed(work, [%w[other.txt other]], "topic")
    refused = land_in(root, ["--proven"])
    assert status_of(refused) == 1
    assert contains?(stderr_of(refused), "no proof of HEAD's tree")
    assert repo(work, %w[ls-remote origin refs/heads/land/topic]) == ""
    committed(
      work,
      [["gen/proof.b", "write_file(\"#{root}/proved\", join(argv, \" \"))"]],
      "proof"
    )
    assert status_of(land_in(root, ["--proven"])) == 0
    assert read_file(path_join(root, "proved")) == "--prove"
    assert repo(work, %w[ls-remote origin refs/heads/land/topic]) != ""
    rm_rf(root)
  end
end

test "--requeue=0 refuses a land behind main, as land did before it rebased"
  if self_exe != nil
    root = landing_fixture
    work = path_join(root, "work")
    committed(work, [%w[other.txt other]], "topic")
    before = repo(work, %w[rev-parse HEAD])
    main_moves(root, [%w[notes/ant ant]])
    r = land_in(root, ["--requeue=0"])
    assert status_of(r) == 1
    assert contains?(stderr_of(r), "--requeue=0")
    assert repo(work, %w[rev-parse HEAD]) == before
    rm_rf(root)
  end
end

def fake_gh(root)
  bin = path_join(root, "bin")
  mkdir_p(bin)
  write_program(
    path_join(root, "gh.b"),
    unlines(
      [
        "log = \"#{root}/gh.log\"",
        "prior = if path_exists(log)",
        "  read_file(log)",
        "else",
        "  \"\"",
        "end",
        "args = join(argv, \" \")",
        "write_file(log, join([prior, unlines([args])], \"\"))",
        "lists = count(filter((l) -> contains?(l, \"--limit\"), split(prior, line_break)))",
        "if contains?(args, \"--limit\")",
        "  older = \"[{\\\"databaseId\\\":50,\\\"headBranch\\\":\\\"land/older\\\",\\\"status\\\":\\\"in_progress\\\"}]\"",
        "  write_stdout(if lists == 1",
        "    older",
        "  else",
        "    \"[]\"",
        "  end)",
        "elsif contains?(args, \"--branch\")",
        "  write_stdout(\"100\")",
        "elsif contains?(args, \"status,conclusion\")",
        "  write_stdout(\"{\\\"status\\\":\\\"completed\\\",\\\"conclusion\\\":\\\"success\\\"}\")",
        "end"
      ]
    )
  )
  script(
    path_join(bin, "gh"),
    unlines(
      ["#!/bin/sh", "exec #{self_exe} run --quiet #{root}/gh.b -- \"$@\""]
    )
  )
  bin
end

test "--watch yields to an older land that took the same turn, then lands and follows its run"
  if self_exe != nil
    root = landing_fixture
    work = path_join(root, "work")
    committed(work, [%w[other.txt other]], "topic")
    bin = fake_gh(root)
    r = exec_capture(
      "env",
      "-u",
      "GEN_ROOT",
      "-C",
      work,
      "PATH=#{bin}:#{getenv("PATH")}",
      self_exe,
      "run",
      "--quiet",
      path_join(getenv("GEN_ROOT", cwd), "gen/land.b"),
      "--",
      "--watch"
    )
    assert status_of(r) == 0
    calls = read_file(path_join(root, "gh.log"))
    assert contains?(calls, "run cancel 100")
    assert contains?(calls, "run view 100 --json status,conclusion")
    assert contains?(stderr_of(r), "land/older took the same turn")
    rm_rf(root)
  end
end
