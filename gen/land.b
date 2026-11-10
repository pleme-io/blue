use("gitto", %i[as_tester ask])
use("hizuke", [:rfc3339_of_ms])
use("moji", %i[after_first before_first take_chars])
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
        live?(r) and
          branch != ref and
          starts_with?(branch, "land/") and
          not starts_with?(branch, "land/dry-")
      end,
      runs
    )
  )
end

@doc """
live?: Whether a run, as `gh run list --json status` lists it, has not finished.

    live?(json_parse("{\"status\":\"waiting\"}")) #=> true
    live?(json_parse("{\"status\":\"completed\"}")) #=> false
"""
def live?(r)
  member?(
    json_get(r, :status),
    %w[queued in_progress requested waiting pending]
  )
end

@doc """
stamp: A UTC time, as RFC 3339 text or `gh`'s createdAt, as the number
YYYYMMDDHHMMSS, which orders as the time does.

    stamp("2026-11-10T19:30:05Z") #=> 20_261_110_193_005
    stamp("2026-11-10T19:30:05.120Z") #=> 20_261_110_193_005
"""
def stamp(text)
  to_int(
    replace(replace(replace(take_chars(text, 19), "-", ""), ":", ""), "T", "")
  )
end

@doc """
ticket_name: The branch that holds a land's place in the queue from the time it
first queued, so a land that pushes again keeps its place. No workflow runs on a
`land-queue/` branch.

    ticket_name(20_261_110_193_005, "land/queue/land-turn") #=> "land-queue/20261110193005/queue/land-turn"
"""
def ticket_name(at, ref)
  "land-queue/#{to_s(at)}/#{after_first(ref, "/")}"
end

@doc """
tickets_of: The queue tickets in `git ls-remote` output, each as `{name:, at:,
ref:}`, leaving out those queued before the cutoff: a land that died holds no
place for ever.

    tickets_of("1\trefs/heads/land-queue/20261110193005/a/b", 0) #=> [{name: "land-queue/20261110193005/a/b", at: 20_261_110_193_005, ref: "land/a/b"}]
    tickets_of("1\trefs/heads/land-queue/20261110193005/a", 20_261_111_000_000) #=> []
"""
def tickets_of(text, cutoff)
  filter(
    (t) -> not t[:at].nil? and t[:at] >= cutoff,
    map(
      fn(l)
        name = after_first(l, "refs/heads/")
        rest = after_first(name, "/")
        {
          name:,
          at: to_int(before_first(rest, "/")),
          ref: "land/#{after_first(rest, "/")}"
        }
      end,
      filter((l) -> contains?(l, "refs/heads/land-queue/"), moji::lines(text))
    )
  )
end

@doc """
queued_at: When the land on a ref first queued: its oldest ticket, else nil.

    queued_at([{name: "q", at: 5, ref: "land/a"}, {name: "p", at: 3, ref: "land/a"}], "land/a") #=> 3
    queued_at([], "land/a") #=> nil
"""
def queued_at(tickets, ref)
  ats = map((t) -> t[:at], filter((t) -> t[:ref] == ref, tickets))
  if ats != []
    reduce(
      fn(m, x)
        if x < m
          x
        else
          m
        end
      end,
      first(ats),
      ats
    )
  end
end

@doc """
place_of: A land run's place in the queue, `[time, run id]`: the time its land
first queued when it holds a ticket, else the time the run was created, as a land
from a client without tickets queues.

    place_of(json_parse("{\"databaseId\":7,\"headBranch\":\"land/a\",\"createdAt\":\"2026-11-10T19:30:05Z\"}"), []) #=> [20_261_110_193_005, 7]
"""
def place_of(run, tickets)
  at = queued_at(tickets, json_get(run, :headBranch))
  [
    if at.nil?
      created = json_get(run, :createdAt)
      if created.nil?
        0
      else
        stamp(created)
      end
    else
      at
    end,
    json_get(run, :databaseId)
  ]
end

@doc """
before?: Whether one place in the queue comes before another: the earlier time,
and on the same second the lower run id.

    before?([1, 9], [2, 3]) #=> true
    before?([2, 3], [2, 9]) #=> true
    before?([2, 9], [2, 3]) #=> false
"""
def before?(p, q)
  first(p) < first(q) or
    first(p) == first(q) and retsu::last(p) < retsu::last(q)
end

@doc """
yields_to: The running land this one stands behind, or nil: two lands that took
the same free turn would each run the suite for one fast-forward, so the one
queued later stops and queues again. The queue goes by the time a land first
queued (place_of), so a land that pushes again never passes one queued before it.

    yields_to([], "land/x", [5, 5], []) #=> nil
"""
def yields_to(runs, ref, mine, tickets)
  find_first((r) -> before?(place_of(r, tickets), mine), lands_ahead(runs, ref))
end

@doc """
waits_behind: The ticket of a land queued before this one and still waiting, or
nil; a land waiting without a run holds its place too.

    waits_behind([{name: "a", at: 1, ref: "land/a"}, {name: "b", at: 2, ref: "land/b"}], "land/b", 2) #=> {name: "a", at: 1, ref: "land/a"}
    waits_behind([{name: "a", at: 1, ref: "land/a"}, {name: "b", at: 2, ref: "land/b"}], "land/a", 1) #=> nil
"""
def waits_behind(tickets, ref, mine)
  find_first((t) -> t[:ref] != ref and t[:at] < mine, tickets)
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

@doc """
release_files: The files a release commit writes: the workspace version and the
two locks that carry it.

    release_files #=> ["Cargo.toml", "Cargo.lock", "Cargo.gen.lock"]
"""
def release_files()
  %w[Cargo.toml Cargo.lock Cargo.gen.lock]
end

@doc """
release_commit?: Whether a commit, as `{subject:, files:}`, is a release commit:
its subject names a workspace release and it writes release files only.

    release_commit?({subject: "release: workspace v0.0.165", files: ["Cargo.toml"]}) #=> true
    release_commit?({subject: "release: workspace v0.0.165", files: ["src/a.rs"]}) #=> false
"""
def release_commit?(c)
  starts_with?(c[:subject], "release: workspace v") and
    c[:files] != [] and
    every?((f) -> member?(f, release_files), c[:files])
end

@doc """
absorbable?: Whether a land whose fast-forward was refused can still reach main
without a new suite: every commit main gained since the land's base is a release
commit, and the land writes no release file, so the tree that reaches main is the
tested tree with main's release files.

    absorbable?([], ["gen/land.b"]) #=> false
"""
def absorbable?(ahead, touched)
  ahead != [] and
    every?(release_commit?, ahead) and
    not writes_release?(touched)
end

@doc """
writes_release?: Whether a land changes a release file, so a release commit
that reaches main under it cannot be absorbed and would refuse its fast-forward.

    writes_release?(["gen/land.b", "Cargo.lock"]) #=> true
    writes_release?(["gen/land.b"]) #=> false
"""
def writes_release?(touched)
  filter((f) -> member?(f, release_files), touched) != []
end

@doc """
releases_live: The auto-release runs, as `gh run list --json
databaseId,event,status,displayTitle` lists them, that can still commit a
release to main: a scheduled tick never bumps, and the push of a release commit
bumps nothing.

    releases_live([]) #=> []
"""
def releases_live(runs)
  filter(
    fn(r)
      live?(r) and
        json_get(r, :event) != "schedule" and
        not starts_with?(json_get(r, :displayTitle), "release: workspace v")
    end,
    runs
  )
end

@doc """
release_hold: Why a land waits before its suite runs, or nil: a release is in
flight and the land changes a release file, so the release commit would move
main under the suite. A land that changes none absorbs the release instead.

    release_hold([], ["Cargo.lock"]) #=> nil
"""
def release_hold(releases, touched)
  if releases != [] and writes_release?(touched)
    "auto-release run #{to_s(json_get(first(releases), :databaseId))} is in flight and this land changes #{join(filter((f) -> member?(f, release_files), touched), ", ")}; it waits for the release commit"
  end
end

@doc """
turn_refusal: Why a land run may not run its suite, or nil when it holds the
turn: an older land still runs, and only one tests at a time against the main it
fast-forwards; or main gained a commit the land was not built on and cannot
absorb, so its fast-forward would be refused after the whole suite.

    turn_refusal(nil, [], ["gen/land.b"]) #=> nil
"""
def turn_refusal(older, ahead, touched)
  if not older.nil?
    "#{json_get(older, :headBranch)} (run #{to_s(json_get(older, :databaseId))}) is older and still running; one land runs its suite at a time"
  elsif ahead != [] and not absorbable?(ahead, touched)
    "main gained #{to_s(count(ahead))} commit(s) this land was not built on"
  end
end

@doc """
refused_turn?: Whether a land run's jobs, as `gh run view --json jobs` lists
them with a `refused` flag per job, show the fast-forward refusing a run that did
not hold the turn: the run never ran its suite, so it lands again whether or not
main moved.

    refused_turn?([]) #=> false
"""
def refused_turn?(jobs)
  find_first((j) -> json_get(j, :refused) == true, jobs) != nil
end

@doc """
turn_step: The name of land.yml's fast-forward step that refuses a run which did
not hold the turn; `git land --watch` reads it from the run's jobs.

    turn_step #=> "refuse a land that does not hold the turn"
"""
def turn_step()
  "refuse a land that does not hold the turn"
end

def git_lines(args)
  filter((l) -> l != "", moji::lines(ask(args)))
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
              "databaseId,status",
              "--jq",
              "[.[] | select(.status != \"completed\")][0].databaseId // \"\""
            )
          )
        )
      end
    end,
    "",
    range(20)
  )
end

def runs_of(workflow, fields)
  cap = exec_capture(
    "gh",
    "run",
    "list",
    "--workflow",
    workflow,
    "--limit",
    "40",
    "--json",
    fields
  )
  if status_of(cap) == 0
    json_parse(stdout_of(cap)) rescue nil
  end
end

def land_runs()
  runs_of("land.yml", "databaseId,headBranch,status,createdAt")
end

def tickets()
  tickets_since(stamp(rfc3339_of_ms(now_ms - 21_600_000)))
end

def tickets_since(cutoff)
  cap = exec_capture("git", "ls-remote", "origin", "refs/heads/land-queue/*")
  if status_of(cap) == 0
    tickets_of(stdout_of(cap), cutoff)
  end
end

def enqueue(ref)
  held = tickets or []
  at = queued_at(held, ref)
  if at.nil?
    at = stamp(rfc3339_of_ms(now_ms))
    pushed = exec_capture(
      "env",
      "BLUE_PREPUSH_OFF=1",
      "git",
      "push",
      "-q",
      "origin",
      "#{ask(%w[rev-parse origin/main])}:refs/heads/#{ticket_name(at, ref)}"
    )
    if status_of(pushed) != 0
      say("no queue ticket: #{trim(stderr_of(pushed))}")
    end
  end
  at
end

def dequeue(ref)
  map(
    fn(t)
      exec_capture(
        "env",
        "BLUE_PREPUSH_OFF=1",
        "git",
        "push",
        "-q",
        "origin",
        ":refs/heads/#{t[:name]}"
      )
    end,
    filter((t) -> t[:ref] == ref, tickets_since(0) or [])
  )
end

def leave(ref, code)
  dequeue(ref)
  exit_with(code)
end

def release_runs()
  runs_of("auto-release.yml", "databaseId,event,status,displayTitle")
end

def touched_since_main()
  git_lines(%w[diff --name-only origin/main...HEAD])
end

def wait_turn(ref, deadline, waited)
  runs = land_runs
  releases = release_runs
  held = if runs.nil? or releases.nil?
    "the land or release runs cannot be read (a rate limit answers 403), so this land holds its turn"
  else
    ahead = lands_ahead(runs, ref)
    queue = tickets or []
    mine = queued_at(queue, ref)
    waiting = if mine.nil?
      nil
    else
      waits_behind(queue, ref, mine)
    end
    if ahead != []
      "#{to_s(count(ahead))} land(s) ahead, first #{json_get(first(ahead), :headBranch)}; waiting for a turn, since only one reaches main; --no-queue lands beside them"
    elsif not waiting.nil?
      "#{waiting[:ref]} queued first and waits for its turn; this land keeps its place behind it"
    else
      release_hold(releases_live(releases), touched_since_main)
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

@doc """
absorb_release: land.yml's fast-forward, after main refused the tested commit:
when main moved only by release commits and the land writes no release file,
rebase the tested commit onto main, prove the result differs from it only in
main's release files, and fast-forward main to it. Anything else exits 1, and
`--watch` requeues the land as before. Off: the repository variable
BLUE_LAND_ABSORB_RELEASE=off.
"""
def absorb_release(sha, ref, left)
  fetch_main
  base = ask(["merge-base", sha, "origin/main"])
  ahead = ahead_of(sha)
  touched = git_lines(["diff", "--name-only", base, sha])
  if not absorbable?(ahead, touched)
    say(
      "main gained #{to_s(count(ahead))} commit(s) that are not all release commits, or this land writes a release file; it needs a new suite"
    )
    exit_with(1)
  end
  exec_check("git", "checkout", "-q", "--detach", sha)
  r = exec_capture(
    "git",
    "-c",
    "user.name=github-actions[bot]",
    "-c",
    "user.email=41898282+github-actions[bot]@users.noreply.github.com",
    "rebase",
    "-q",
    "origin/main"
  )
  if status_of(r) != 0
    exec_check("git", "rebase", "--abort")
    say(
      "the tested commit does not rebase onto the release commit: #{trim(stderr_of(r))}"
    )
    exit_with(1)
  end
  extra = filter(
    (f) -> not member?(f, release_files),
    git_lines(["diff", "--name-only", sha, "HEAD"])
  )
  drift = ask(
    retsu::concat_lists(%w[diff --name-only origin/main HEAD --], release_files)
  )
  if extra != [] or drift != ""
    say(
      "the rebased tree is not the tested tree with main's release files: #{join(extra, ", ")} #{drift}"
    )
    exit_with(1)
  end
  pushed = exec_check(
    "git",
    "push",
    "--atomic",
    "origin",
    "HEAD:refs/heads/main",
    ":#{ref}"
  )
  if pushed != 0 and left > 0
    absorb_release(sha, ref, left - 1)
  elsif pushed != 0
    exit_with(1)
  else
    say(
      "main moved only by #{to_s(count(ahead))} release commit(s); fast-forwarded it to the tested tree rebased onto them, #{take_chars(ask(%w[rev-parse HEAD]), 10)}"
    )
  end
end

def read_until(reader, left)
  got = reader()
  if got.nil? and left > 0
    sleep(30)
    read_until(reader, left - 1)
  else
    got
  end
end

def ahead_of(sha)
  map(
    fn(c)
      {
        subject: ask(["log", "-1", "--format=%s", c]),
        files: git_lines(
          ["diff-tree", "--no-commit-id", "--name-only", "-r", c]
        )
      }
    end,
    git_lines(["rev-list", "#{sha}..origin/main"])
  )
end

def wait_release(touched, deadline)
  releases = read_until(() -> release_runs, 10)
  if releases.nil?
    "the release runs cannot be read"
  else
    hold = release_hold(releases_live(releases), touched)
    if hold.nil?
      nil
    elsif now_ms > deadline
      "#{hold}, and an hour passed"
    else
      say(hold)
      sleep(60)
      wait_release(touched, deadline)
    end
  end
end

@doc """
hold_turn: The turn ci.yml's blue job and land.yml's prose job take on a land
before its suite runs: print true when this run holds it, false with the reason
on stderr when it does not, and land.yml's fast-forward then refuses the run.
The turn is the server's half of the queue, so a land pushed without --watch,
with --no-queue or past a rate limit still tests alone against the main it
fast-forwards. Off: the repository variable BLUE_LAND_TURN=off.
"""
def hold_turn(id, ref, sha)
  if ask(%w[rev-parse --is-shallow-repository]) == "true"
    exec_check("git", "fetch", "-q", "--unshallow", "origin")
  end
  touched_at = fn()
    fetch_main
    git_lines(
      ["diff", "--name-only", ask(["merge-base", sha, "origin/main"]), sha]
    )
  end
  runs = read_until(() -> land_runs, 10)
  refusal = if runs.nil?
    "the land runs cannot be read"
  else
    queue = tickets or []
    own = find_first((r) -> json_get(r, :databaseId) == to_int(id), runs)
    mine = if own.nil?
      [stamp(rfc3339_of_ms(now_ms)), to_int(id)]
    else
      place_of(own, queue)
    end
    turn_refusal(yields_to(runs, ref, mine, queue), [], [])
  end
  refusal = if refusal.nil?
    wait_release(touched_at(), now_ms + 3_600_000)
  else
    refusal
  end
  refusal = if refusal.nil?
    turn_refusal(nil, ahead_of(sha), touched_at())
  else
    refusal
  end
  if refusal.nil?
    say("run #{id} holds the land turn")
    write_stdout("true")
  else
    say(
      "run #{id} does not hold the land turn: #{refusal}; the fast-forward refuses it, and git land --watch lands it again"
    )
    write_stdout("false")
  end
end

def contains_main?()
  exec_ok?("git", "merge-base", "--is-ancestor", "origin/main", "HEAD")
end

@doc """
lock_messages: The words git prints when another git in the same repository
holds a ref lock, as worktrees that share one `.git` and fetch at once do. A
fetch that fails with one of them can succeed a moment later.

    lock_messages #=> ["incorrect old value provided", "cannot lock ref", ".lock': File exists", "unable to update local ref", "failed: reference already exists"]
"""
def lock_messages()
  [
    "incorrect old value provided",
    "cannot lock ref",
    ".lock': File exists",
    "unable to update local ref",
    "failed: reference already exists"
  ]
end

@doc """
lock_race?: Whether a failed git command's stderr names a ref lock another git
holds, rather than a fault waiting cannot fix.

    lock_race?("error: cannot lock ref 'refs/remotes/origin/main': is at 1 but expected 2") #=> true
    lock_race?("fatal: 'origin' does not appear to be a git repository") #=> false
"""
def lock_race?(text)
  find_first((m) -> contains?(text, m), lock_messages) != nil
end

@doc """
fetch_main: Fetch origin's main. A ref lock another worktree holds is waited
out, up to four tries one, two and four seconds apart; any other failure, or a
lock that outlasts the tries, ends the land with git's words.
"""
def fetch_main()
  fetch_tries(4, 1)
end

def fetch_tries(left, wait)
  r = exec_capture("git", "fetch", "-q", "origin", "main")
  if status_of(r) != 0
    words = trim(stderr_of(r))
    if lock_race?(words) and left > 1
      say(
        "another git holds a ref lock (#{words}); retrying the fetch in #{to_s(wait)} s"
      )
      sleep(wait)
      fetch_tries(left - 1, wait * 2)
    else
      say("git fetch origin main failed: #{words}")
      exit_with(1)
    end
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
  changed = ask(%w[status --porcelain --untracked-files=no])
  if changed != ""
    exec_check("git", "add", "-u")
    exec_check(
      "git",
      "commit",
      "-q",
      "-m",
      "regen after rebasing onto #{ask(%w[rev-parse --short origin/main])}"
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
    paths = ask(%w[diff --name-only --diff-filter=U])
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
        ask(%w[rev-parse --abbrev-ref HEAD]),
        ask(%w[rev-parse --short HEAD])
      ),
      scope
    ),
    a[:dry]
  )
end

@doc """
repush?: Whether a land must clear its ref before it pushes: the ref already
names HEAD, as `git ls-remote` prints it, so a push would be up to date, start no
run, and --watch would follow the run it cancelled or the turn refused.

    repush?("4f5a9a07\trefs/heads/land/x", "4f5a9a07") #=> true
    repush?("", "4f5a9a07") #=> false
    repush?("61dee1bd\trefs/heads/land/x", "4f5a9a07") #=> false
"""
def repush?(listed, sha)
  first(split(trim(listed), "\t")) == sha
end

def push_land(ref)
  sha = ask(%w[rev-parse HEAD])
  if repush?(ask(["ls-remote", "origin", "refs/heads/#{ref}"]), sha)
    say(
      "#{ref} already names #{take_chars(sha, 10)}; deleting it first, so the push starts a new run"
    )
    if exec_check("git", "push", "-q", "origin", ":refs/heads/#{ref}") != 0
      exit_with(1)
    end
  end
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
    queue = tickets or []
    at = queued_at(queue, ref)
    runs = land_runs or []
    mine = if at.nil?
      own = find_first((r) -> json_get(r, :databaseId) == to_int(found), runs)
      if own.nil?
        [stamp(rfc3339_of_ms(now_ms)), to_int(found)]
      else
        place_of(own, queue)
      end
    else
      [at, to_int(found)]
    end
    yields_to(runs, ref, mine, queue)
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
      leave(ref, 0)
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
          "[.jobs[] | {name, conclusion, refused: ([.steps[]? | select(.name == \"#{turn_step}\" and .conclusion == \"failure\")] != [])}]"
        )
      )
    ) rescue
      []
    fetch_main
    moved = not contains_main?
    turned = refused_turn?(jobs)
    if left == 0 or not moved_main?(jobs) or not (moved or turned)
      leave(ref, status)
    end
    say(
      if turned
        "the run did not hold the land turn and ran no suite; queueing and landing again, #{to_s(left - 1)} more after this; --requeue=0 turns this off"
      else
        "main moved while CI ran (every CI job green, the fast-forward refused); rebasing onto origin/main and landing again, #{to_s(left - 1)} more after this; --requeue=0 turns this off"
      end
    )
    follow(a, left - 1, minutes)
  end
end

def main()
  if count(argv) == 2 and first(argv) == "--stop-on-red"
    stop_on_red(argv_get(1))
    exit_with(0)
  end
  if count(argv) == 4 and first(argv) == "--turn"
    hold_turn(argv_get(1), argv_get(2), argv_get(3))
    exit_with(0)
  end
  if count(argv) == 3 and first(argv) == "--absorb-release"
    absorb_release(argv_get(1), argv_get(2), 2)
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
  if ask(%w[status --porcelain --untracked-files=no]) != ""
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
    if a[:queue] and not a[:dry]
      enqueue(ref_for(a))
    end
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
  assert json_get(yields_to(runs, "land/mine", [0, 7], []), :headBranch) ==
    "land/early"
  assert yields_to(runs, "land/mine", [0, 4], []).nil?
  assert yields_to(runs, "land/mine", [0, 2], []).nil?
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

test "a land refused only because main gained a release commit reaches main without a new suite, as koutei/bounded-fail's run 42464912784 of 2026-11-08 shows"
  release = {
    subject: "release: workspace v0.0.165",
    files: %w[Cargo.gen.lock Cargo.lock Cargo.toml]
  }
  other = {subject: "prepush: regen is a land gate", files: ["gen/prepush.b"]}
  forged = {subject: "release: workspace v0.0.166", files: ["gen/land.b"]}
  assert absorbable?([release], %w[bidamas/koutei/koutei.b README.md])
  assert absorbable?([release, release], ["gen/land.b"])
  assert not absorbable?([release, other], ["gen/land.b"])
  assert not absorbable?([forged], ["gen/land.b"])
  assert not absorbable?([release], %w[gen/land.b Cargo.toml])
  assert not absorbable?([release], ["Cargo.lock"])
  assert not absorbable?([], ["gen/land.b"])
end

test "one land holds the turn: an older running land refuses a younger, and main moving under a land refuses it unless it can absorb a release, as land/native-gate-roots' run 42814489810 of 2026-11-10 shows"
  run = fn(id, branch, status)
    "{\"databaseId\":#{id},\"headBranch\":\"#{branch}\",\"status\":\"#{status}\"}"
  end
  runs = json_parse(
    "[#{join([run(42_813_678_972, "land/h5/arika-khipu", "in_progress"), run(42_814_489_810, "land/native-gate-roots", "in_progress")], ",")}]"
  )
  older = yields_to(runs, "land/native-gate-roots", [0, 42_814_489_810], [])
  assert contains?(
    turn_refusal(older, [], ["gen/land.b"]),
    "land/h5/arika-khipu (run 42813678972) is older"
  )
  assert turn_refusal(
    yields_to(runs, "land/h5/arika-khipu", [0, 42_813_678_972], []),
    [],
    []
  ).nil?
  release = {
    subject: "release: workspace v0.0.183",
    files: %w[Cargo.gen.lock Cargo.lock Cargo.toml]
  }
  h5 = {
    subject: "HORIZON H5 wave 3",
    files: ["crates/blue-lang-cli/src/arika.rs"]
  }
  assert turn_refusal(nil, [release], ["gen/land.b"]).nil?
  assert contains?(
    turn_refusal(nil, [h5, release], ["gen/land.b"]),
    "2 commit(s)"
  )
  assert contains?(turn_refusal(nil, [release], ["Cargo.lock"]), "1 commit(s)")
  assert turn_refusal(nil, [], ["Cargo.lock"]).nil?
end

test "a land that changes a release file waits while a release is in flight, as land/speed/compile-plan's run 42788192992 of 2026-11-10 shows, and a scheduled tick or a release commit's own push holds nobody"
  run = fn(id, event, status, title)
    "{\"databaseId\":#{id},\"event\":\"#{event}\",\"status\":\"#{status}\",\"displayTitle\":\"#{title}\"}"
  end
  runs = json_parse(
    "[#{join([run(3, "schedule", "in_progress", "auto-release"), run(2, "push", "in_progress", "release: workspace v0.0.180"), run(1, "workflow_dispatch", "completed", "auto-release")], ",")}]"
  )
  assert releases_live(runs) == []
  dispatched = json_parse(
    "[#{run(42_786_952_460, "workflow_dispatch", "in_progress", "auto-release")}]"
  )
  assert map((r) -> json_get(r, :databaseId), releases_live(dispatched)) ==
    [42_786_952_460]
  assert contains?(
    release_hold(releases_live(dispatched), %w[Cargo.toml Cargo.lock src/a.rs]),
    "changes Cargo.toml, Cargo.lock"
  )
  assert release_hold(releases_live(dispatched), ["gen/land.b"]).nil?
  assert release_hold([], ["Cargo.lock"]).nil?
end

test "a run whose fast-forward refused it at the turn is read from its steps, so --watch lands it again though main did not move"
  jobs = json_parse("[{\"name\":\"ci / blue\",\"conclusion\":\"success\",\"refused\":false},{\"name\":\"ci / check\",\"conclusion\":\"skipped\",\"refused\":false},{\"name\":\"fast-forward\",\"conclusion\":\"failure\",\"refused\":true}]")
  assert refused_turn?(jobs)
  assert moved_main?(jobs)
  assert not refused_turn?(
    json_parse("[{\"name\":\"fast-forward\",\"conclusion\":\"failure\",\"refused\":false}]")
  )
end

test "land.yml refuses at the step --watch reads, and both suites take the turn first"
  land = source(".github/workflows/land.yml")
  ci = source(".github/workflows/ci.yml")
  assert contains?(land, "name: #{turn_step}")
  assert contains?(land, "gen/land.b -- --turn")
  assert contains?(ci, "gen/land.b -- --turn")
  assert contains?(ci, "needs.blue.outputs.held != 'false'")
end

test "the queue goes by the time a land first queued, so a land that pushes again never passes one queued before it, as land/docs/iphone's runs passed land/queue/land-turn for five hours on 2026-11-10"
  run = fn(id, branch, created)
    "{\"databaseId\":#{id},\"headBranch\":\"#{branch}\",\"status\":\"in_progress\",\"createdAt\":\"#{created}\"}"
  end
  queue = tickets_of(
    unlines(
      [
        "1\trefs/heads/land-queue/20261110143900/queue/land-turn",
        "2\trefs/heads/land-queue/20261110184300/docs/iphone"
      ]
    ),
    0
  )
  iphone = json_parse(
    "[#{run(42_886_900_000, "land/docs/iphone", "2026-11-10T19:30:00Z")}]"
  )
  mine = [queued_at(queue, "land/queue/land-turn"), 42_886_928_469]
  assert yields_to(iphone, "land/queue/land-turn", mine, queue).nil?
  turn = json_parse(
    "[#{run(42_886_928_469, "land/queue/land-turn", "2026-11-10T19:31:00Z")}]"
  )
  theirs = place_of(first(iphone), queue)
  assert json_get(
    yields_to(turn, "land/docs/iphone", theirs, queue),
    :headBranch
  ) == "land/queue/land-turn"
  assert waits_behind(queue, "land/docs/iphone", 20_261_110_184_300)[:ref] ==
    "land/queue/land-turn"
  assert waits_behind(queue, "land/queue/land-turn", 20_261_110_143_900).nil?
  old = json_parse(
    "[#{run(42_800_000_000, "land/old-client", "2026-11-10T15:00:00Z")}]"
  )
  assert yields_to(old, "land/queue/land-turn", mine, queue).nil?
  assert json_get(
    yields_to(old, "land/docs/iphone", theirs, queue),
    :headBranch
  ) == "land/old-client"
  assert tickets_of(
    "1\trefs/heads/land-queue/20261110143900/queue/land-turn",
    20_261_110_150_000
  ) == []
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

def script(path, text)
  write_file(path, text)
  exec_capture("chmod", "+x", path)
end

def committed(dir, paths, message)
  map((p) -> write_file(path_join(dir, first(p)), retsu::last(p)), paths)
  as_tester(dir, %w[add -A])
  as_tester(dir, ["commit", "-q", "-m", message])
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
        "@moduledoc \"\"\"",
        "made: the fixture's generator, one line per note the checkout holds.",
        "",
        "    path_join(\"notes\", \"ant\") #=> \"notes/ant\"",
        "\"\"\"",
        "",
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
  as_tester(work, %w[init -q -b main])
  as_tester(work, %w[config user.name t])
  as_tester(work, %w[config user.email t@t])
  committed(work, [], "base")
  as_tester(root, %w[init -q --bare -b main origin.git])
  as_tester(work, ["remote", "add", "origin", path_join(root, "origin.git")])
  as_tester(work, %w[push -q origin main])
  as_tester(work, %w[checkout -q -b topic])
  root
end

def main_moves(root, paths)
  work = path_join(root, "work")
  as_tester(work, %w[checkout -q main])
  committed(work, paths, "main moved")
  as_tester(work, %w[push -q origin main])
  as_tester(work, %w[checkout -q topic])
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
  as_tester(
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
    as_tester(work, %w[fetch -q origin])
    assert landed(root, "made.txt") == join(%w[base ant bee], line_break)
    assert as_tester(
      work,
      %w[log -1 --format=%s refs/remotes/origin/land/topic]
    ) == "topic"
    as_tester(work, %w[merge-base --is-ancestor origin/main origin/land/topic])
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
    as_tester(work, %w[fetch -q origin])
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
    as_tester(work, %w[fetch -q origin])
    assert landed(root, "made.txt") == "base"
    rm_rf(root)
  end
end

test "a conflict in a source stops the land, names the path and leaves HEAD as it was"
  if self_exe != nil
    root = landing_fixture
    work = path_join(root, "work")
    committed(work, [["source.txt", unlines(["topic"])]], "topic")
    before = as_tester(work, %w[rev-parse HEAD])
    main_moves(root, [["source.txt", unlines(["main"])]])
    r = land_in(root, [])
    assert status_of(r) == 1
    assert contains?(stderr_of(r), "source.txt")
    assert as_tester(work, %w[rev-parse HEAD]) == before
    rm_rf(root)
  end
end

test "a rebase that fails with no conflict says git's words, as a clone with no identity does in the sandbox"
  if self_exe != nil
    root = landing_fixture
    work = path_join(root, "work")
    committed(work, [%w[other.txt other]], "topic")
    before = as_tester(work, %w[rev-parse HEAD])
    main_moves(root, [%w[notes/ant ant]])
    as_tester(work, %w[config --unset user.name])
    as_tester(work, %w[config --unset user.email])
    as_tester(work, %w[config user.useConfigOnly true])
    r = land_with(
      %w[GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1],
      root,
      []
    )
    assert status_of(r) == 1
    assert contains?(stderr_of(r), "git rebase failed with no conflict")
    assert as_tester(work, %w[rev-parse HEAD]) == before
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
    assert as_tester(work, %w[ls-remote origin refs/heads/land/topic]) == ""
    committed(
      work,
      [["gen/proof.b", "write_file(\"#{root}/proved\", join(argv, \" \"))"]],
      "proof"
    )
    assert status_of(land_in(root, ["--proven"])) == 0
    assert read_file(path_join(root, "proved")) == "--prove"
    assert as_tester(work, %w[ls-remote origin refs/heads/land/topic]) != ""
    rm_rf(root)
  end
end

test "--requeue=0 refuses a land behind main, as land did before it rebased"
  if self_exe != nil
    root = landing_fixture
    work = path_join(root, "work")
    committed(work, [%w[other.txt other]], "topic")
    before = as_tester(work, %w[rev-parse HEAD])
    main_moves(root, [%w[notes/ant ant]])
    r = land_in(root, ["--requeue=0"])
    assert status_of(r) == 1
    assert contains?(stderr_of(r), "--requeue=0")
    assert as_tester(work, %w[rev-parse HEAD]) == before
    rm_rf(root)
  end
end

def locking_git(root, held)
  real = trim(stdout_of(exec_capture("sh", "-c", "command -v git")))
  bin = path_join(root, "git-bin")
  mkdir_p(bin)
  lock = path_join(root, "work/.git/refs/remotes/origin/main.lock")
  write_file(lock, "")
  write_program(
    path_join(root, "git.b"),
    unlines(
      [
        "use(\"shisutemu\", %i[status_of stderr_of stdout_of])",
        "r = exec_capture(\"#{real}\", *argv)",
        "write_stdout(stdout_of(r))",
        "write_stderr(stderr_of(r))",
        "if argv_get(0) == \"fetch\" and #{to_s(not held)}",
        "  rm_rf(\"#{lock}\")",
        "end",
        "exit_with(status_of(r))"
      ]
    )
  )
  script(
    path_join(bin, "git"),
    unlines(
      ["#!/bin/sh", "exec #{self_exe} run --quiet #{root}/git.b -- \"$@\""]
    )
  )
  bin
end

def land_locked(root, held)
  work = path_join(root, "work")
  committed(work, [%w[other.txt other]], "topic")
  base = as_tester(work, %w[rev-parse origin/main])
  main_moves(root, [%w[notes/ant ant]])
  as_tester(work, ["update-ref", "refs/remotes/origin/main", base])
  bin = locking_git(root, held)
  land_with(["PATH=#{bin}:#{getenv("PATH")}"], root, [])
end

test "a fetch that meets a ref lock another worktree holds waits it out and lands, as the speed and runtime agents' lands of 2026-11-10 did not"
  if self_exe != nil
    root = landing_fixture
    r = land_locked(root, false)
    assert status_of(r) == 0
    assert contains?(stderr_of(r), "another git holds a ref lock")
    work = path_join(root, "work")
    assert as_tester(work, %w[show HEAD:notes/ant]) == "ant"
    assert contains?(
      as_tester(work, %w[ls-remote origin refs/heads/land/topic]),
      as_tester(work, %w[rev-parse HEAD])
    )
    rm_rf(root)
  end
end

test "a ref lock that outlasts the tries, or any other fetch failure, ends the land with git's words"
  if self_exe != nil
    root = landing_fixture
    held = land_locked(root, true)
    assert status_of(held) == 1
    assert contains?(stderr_of(held), "git fetch origin main failed")
    assert contains?(stderr_of(held), "lock")
    rm_rf(root)
    root = landing_fixture
    work = path_join(root, "work")
    committed(work, [%w[other.txt other]], "topic")
    as_tester(
      work,
      ["remote", "set-url", "origin", path_join(root, "gone.git")]
    )
    gone = land_in(root, [])
    assert status_of(gone) == 1
    assert contains?(stderr_of(gone), "git fetch origin main failed")
    assert not contains?(stderr_of(gone), "another git holds a ref lock")
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
        "lists = count(filter((l) -> contains?(l, \"land.yml --limit\"), split(prior, line_break)))",
        "if contains?(args, \"auto-release.yml\")",
        "  write_stdout(\"[]\")",
        "elsif contains?(args, \"land.yml --limit\")",
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
    as_tester(
      work,
      %w[push -q origin HEAD:refs/heads/land-queue/20000101000000/topic]
    )
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
    assert as_tester(work, %w[ls-remote origin refs/heads/land-queue/*]) == ""
    rm_rf(root)
  end
end

def fake_runs_gh(root, lands, releases)
  bin = path_join(root, "turn-bin")
  mkdir_p(bin)
  write_file(path_join(root, "lands.json"), lands)
  write_file(path_join(root, "releases.json"), releases)
  write_program(
    path_join(root, "turn-gh.b"),
    unlines(
      [
        "args = join(argv, \" \")",
        "if contains?(args, \"land.yml\")",
        "  write_stdout(read_file(\"#{root}/lands.json\"))",
        "elsif contains?(args, \"auto-release.yml\")",
        "  write_stdout(read_file(\"#{root}/releases.json\"))",
        "end"
      ]
    )
  )
  script(
    path_join(bin, "gh"),
    unlines(
      ["#!/bin/sh", "exec #{self_exe} run --quiet #{root}/turn-gh.b -- \"$@\""]
    )
  )
  bin
end

def turn_in(root, bin)
  work = path_join(root, "work")
  exec_capture(
    "env",
    "-u",
    "GEN_ROOT",
    "-C",
    work,
    "PATH=#{bin}:#{getenv("PATH")}",
    *flatten_args(
      ["--turn", "100", "land/topic", as_tester(work, %w[rev-parse HEAD])]
    )
  )
end

test "--turn holds a land alone on the main it fast-forwards, and refuses one behind an older land or a main it was not built on"
  if self_exe != nil
    root = landing_fixture
    work = path_join(root, "work")
    committed(work, [%w[other.txt other]], "topic")
    free = fake_runs_gh(root, "[]", "[]")
    held = turn_in(root, free)
    assert status_of(held) == 0
    assert stdout_of(held) == "true"
    older = fake_runs_gh(
      root,
      "[{\"databaseId\":50,\"headBranch\":\"land/older\",\"status\":\"in_progress\"},{\"databaseId\":150,\"headBranch\":\"land/younger\",\"status\":\"queued\"}]",
      "[]"
    )
    behind = turn_in(root, older)
    assert status_of(behind) == 0
    assert stdout_of(behind) == "false"
    assert contains?(stderr_of(behind), "land/older (run 50) is older")
    main_moves(root, [["Cargo.toml", "[workspace]"]])
    as_tester(work, %w[checkout -q main])
    as_tester(
      work,
      ["commit", "-q", "--amend", "-m", "release: workspace v0.0.2"]
    )
    as_tester(work, %w[push -q --force origin main])
    as_tester(work, %w[checkout -q topic])
    absorbed = turn_in(root, fake_runs_gh(root, "[]", "[]"))
    assert stdout_of(absorbed) == "true"
    main_moves(root, [%w[notes/ant ant]])
    stale = turn_in(root, fake_runs_gh(root, "[]", "[]"))
    assert stdout_of(stale) == "false"
    assert contains?(stderr_of(stale), "main gained 2 commit(s)")
    rm_rf(root)
  end
end

test "a land again of the same HEAD clears its ref and pushes, so a run cancelled for an older land or refused at the turn is followed by a new run, not by itself"
  if self_exe != nil
    root = landing_fixture
    work = path_join(root, "work")
    committed(work, [%w[other.txt other]], "topic")
    script(
      path_join(root, "origin.git/hooks/post-receive"),
      unlines(["#!/bin/sh", "cat >> #{root}/received"])
    )
    as_tester(
      path_join(root, "origin.git"),
      ["config", "core.hooksPath", path_join(root, "origin.git/hooks")]
    )
    assert status_of(land_in(root, [])) == 0
    again = land_in(root, [])
    assert status_of(again) == 0
    assert contains?(stderr_of(again), "deleting it first")
    sha = as_tester(work, %w[rev-parse HEAD])
    pushed = filter(
      (l) -> contains?(l, "#{sha} refs/heads/land/topic"),
      moji::lines(read_file(path_join(root, "received")))
    )
    assert count(pushed) == 2
    assert as_tester(work, %w[ls-remote origin refs/heads/land/topic]) != ""
    rm_rf(root)
  end
end
