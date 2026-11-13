use("gitto", %i[as_tester ask])
use("hizuke", [:rfc3339_of_ms])
use("kazu", [:min])
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
          %w[--dry --watch --proven --no-queue --no-regen --no-prose --no-batch]
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
  marks_of(text, "land-queue", cutoff)
end

@doc """
beat_name: The branch a waiting land renames each minute to say it is alive; a
ticket whose land stopped beating gives up its place.

    beat_name(20_261_110_233_000, "land/fetch/lock-retry") #=> "land-beat/20261110233000/fetch/lock-retry"
"""
def beat_name(at, ref)
  "land-beat/#{to_s(at)}/#{after_first(ref, "/")}"
end

@doc """
beats_of: The heartbeats in `git ls-remote` output, each as `{name:, at:, ref:}`.

    beats_of("1\trefs/heads/land-beat/20261110233000/a") #=> [{name: "land-beat/20261110233000/a", at: 20_261_110_233_000, ref: "land/a"}]
"""
def beats_of(text)
  marks_of(text, "land-beat", 0)
end

@doc """
alive?: Whether a ticket's land still waits: it queued after `since`, or it beat
after `since`. A land whose client died stops beating, and ten minutes later the
lands behind it pass it.

    alive?({at: 5, ref: "land/a"}, [], 4) #=> true
    alive?({at: 1, ref: "land/a"}, [{at: 5, ref: "land/a"}], 4) #=> true
    alive?({at: 1, ref: "land/a"}, [{at: 5, ref: "land/b"}], 4) #=> false
"""
def alive?(ticket, beats, since)
  ticket[:at] >= since or
    find_first((b) -> b[:ref] == ticket[:ref] and b[:at] >= since, beats) != nil
end

@doc """
run_slug: The land a run's branch stands for: its slug without the prose scope,
and a batch's run stands for the land it is named after.

    run_slug("land/batch-h7/speed") #=> "h7/speed"
    run_slug("land/prose-batch-docs-row") #=> "docs-row"
    run_slug("land/h8/reach") #=> "h8/reach"
"""
def run_slug(branch)
  slug = member_slug(branch)
  if starts_with?(slug, "batch-")
    after_first(slug, "-")
  else
    slug
  end
end

@doc """
stale_tickets: The tickets of other lands that died in the queue: queued before
`since`, no heartbeat since, and no live run that stands for them (run_slug). A
land that ended without leaving the queue, as one did on 2026-11-12 with exit 1
and no word, leaves such a ticket; the next land reaps it.

    stale_tickets([{name: "q", at: 1, ref: "land/a"}], [], [], "land/b", 5) #=> [{name: "q", at: 1, ref: "land/a"}]
    stale_tickets([{name: "q", at: 1, ref: "land/a"}], [{at: 6, ref: "land/a"}], [], "land/b", 5) #=> []
    stale_tickets([{name: "q", at: 1, ref: "land/a"}], [], ["land/batch-a"], "land/b", 5) #=> []
    stale_tickets([{name: "q", at: 1, ref: "land/b"}], [], [], "land/b", 5) #=> []
"""
def stale_tickets(tickets, beats, live, ref, since)
  serving = map(run_slug, live)
  filter(
    fn(t)
      t[:ref] != ref and
        not alive?(t, beats, since) and
        not member?(member_slug(t[:ref]), serving)
    end,
    tickets
  )
end

@doc """
stale_verdicts: The verdicts no land will read: a land reads its verdict only
beside its ticket (verdict_on), so a verdict whose ticket is gone, queued before
`since`, was left by a land that ended without removing it, as six were left on
2026-11-11 and 2026-11-12; the next land reaps it.

    stale_verdicts("2\trefs/heads/land-verdict/1/a", "land/b", 5) #=> [{name: "land-verdict/1/a", at: 1, ref: "land/a"}]
    stale_verdicts(unlines(["1\trefs/heads/land-queue/1/a", "2\trefs/heads/land-verdict/1/a"]), "land/b", 5) #=> []
    stale_verdicts("2\trefs/heads/land-verdict/9/a", "land/b", 5) #=> []
    stale_verdicts("2\trefs/heads/land-verdict/1/b", "land/b", 5) #=> []
"""
def stale_verdicts(text, ref, since)
  filter(
    fn(v)
      v[:ref] != ref and
        v[:at] < since and
        head_of(text, ticket_name(v[:at], v[:ref])).nil?
    end,
    verdicts_of(text)
  )
end

def reap_minutes()
  30
end

def reap(ref, runs)
  text = queue_refs
  if not text.nil?
    live = map((r) -> json_get(r, :headBranch), filter(live?, runs))
    beaten = beats_of(text)
    map(
      fn(t)
        gone = exec_capture(
          "env",
          "BLUE_PREPUSH_OFF=1",
          "git",
          "push",
          "-q",
          "origin",
          ":refs/heads/#{t[:name]}",
          *map(
            (b) -> ":refs/heads/#{b[:name]}",
            filter((b) -> b[:ref] == t[:ref], beaten)
          )
        )
        if status_of(gone) == 0
          say(
            "reaped the stale ticket #{t[:name]}: #{t[:ref]} has no heartbeat in #{to_s(reap_minutes)} minutes and no live run, so its land ended without leaving the queue"
          )
        end
      end,
      stale_tickets(
        tickets_of(text, 0),
        beaten,
        live,
        ref,
        stamp(rfc3339_of_ms(now_ms - reap_minutes * 60000))
      )
    )
    map(
      fn(v)
        gone = exec_capture(
          "env",
          "BLUE_PREPUSH_OFF=1",
          "git",
          "push",
          "-q",
          "origin",
          ":refs/heads/#{v[:name]}"
        )
        if status_of(gone) == 0
          say(
            "reaped the stale verdict #{v[:name]}: #{v[:ref]} has no ticket beside it, so no land will read it"
          )
        end
      end,
      stale_verdicts(
        text,
        ref,
        stamp(rfc3339_of_ms(now_ms - reap_minutes * 60000))
      )
    )
  end
end

def marks_of(text, kind, cutoff)
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
      filter((l) -> contains?(l, "refs/heads/#{kind}/"), moji::lines(text))
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
nil; a land waiting without a run holds its place too, while it is alive?.

    waits_behind([{name: "a", at: 1, ref: "land/a"}, {name: "b", at: 2, ref: "land/b"}], "land/b", 2, [], 0) #=> {name: "a", at: 1, ref: "land/a"}
    waits_behind([{name: "a", at: 1, ref: "land/a"}, {name: "b", at: 2, ref: "land/b"}], "land/a", 1, [], 0) #=> nil
    waits_behind([{name: "a", at: 1, ref: "land/a"}], "land/b", 2, [], 2) #=> nil
"""
def waits_behind(tickets, ref, mine, beats, since)
  find_first(
    (t) -> t[:ref] != ref and t[:at] < mine and alive?(t, beats, since),
    tickets
  )
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
releases_beside_main?: Whether an auto-release workflow, as its text reads,
releases in tag mode: the release commit sits beside main, reachable only by
its tag, so it never moves main and a land has nothing to wait for.

    releases_beside_main?("      release-ref-mode: tag") #=> true
    releases_beside_main?("      release-ref-mode: branch") #=> false
    releases_beside_main?("") #=> false
"""
def releases_beside_main?(workflow)
  find_first(
    (l) -> trim(l) == "release-ref-mode: tag",
    moji::lines(workflow)
  ) != nil
end

@doc """
held_by_release: The release hold for a land, or nil when the repository's
auto-release workflow releases beside main: release_hold is then off, since a
release run never writes main.

    held_by_release("release-ref-mode: tag", [], ["Cargo.lock"]) #=> nil
"""
def held_by_release(workflow, releases, touched)
  if not releases_beside_main?(workflow)
    release_hold(releases_live(releases), touched)
  end
end

def auto_release_workflow()
  path = ".github/workflows/auto-release.yml"
  if path_exists(path)
    read_file(path)
  else
    ""
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

@doc """
indent_of: How many spaces a line of YAML starts with.

    indent_of("    - main") #=> 4
    indent_of("on:") #=> 0
"""
def indent_of(line)
  length(line) - length(trim(concat(line, "x"))) + 1
end

@doc """
block_under: The lines nested under the first line `key` names, a YAML mapping
key at any depth, up to the next line no deeper than it; [] when no line names it.

    block_under(["on:", "  push:", "    branches: [main]", "  schedule:"], "push:") #=> ["    branches: [main]"]
"""
def block_under(ls, key)
  rest = retsu::drop_while((l) -> trim(l) != key, ls)
  if rest == []
    []
  else
    depth = indent_of(first(rest))
    retsu::take_while(
      (l) -> trim(l) == "" or indent_of(l) > depth,
      drop(1, rest)
    )
  end
end

@doc """
unquoted: A YAML scalar without its quotes.

    unquoted("\"main\"") #=> "main"
    unquoted("main") #=> "main"
"""
def unquoted(text)
  trim(replace(replace(trim(text), "\"", ""), "'", ""))
end

@doc """
main_push_of: How a workflow's push to main starts it: :all when any push to
main does, :paths when only a push that touches its paths does, nil when a push
to main starts it never. A land's fast-forward is a push made with a token that
starts no workflow, so land.yml must start each :all workflow itself.

    main_push_of(unlines(["on:", "  push:", "    branches: [main]"])) #=> :all
    main_push_of(unlines(["\"on\":", "  push:", "    branches:", "      - \"main\"", "    paths:", "      - \"kernel/**\""])) #=> :paths
    main_push_of(unlines(["on:", "  push:", "    branches:", "      - \"land/**\""])) #=> nil
    main_push_of(unlines(["on:", "  workflow_dispatch: {}"])) #=> nil
"""
def main_push_of(yml)
  ls = moji::lines(yml)
  on = if block_under(ls, "on:") == []
    block_under(ls, "\"on\":")
  else
    block_under(ls, "on:")
  end
  push = block_under(on, "push:")
  inline = find_first((l) -> starts_with?(trim(l), "branches: ["), push)
  branches = if inline.nil?
    map(
      (l) -> unquoted(after_first(trim(l), "- ")),
      filter((l) -> starts_with?(trim(l), "- "), block_under(push, "branches:"))
    )
  else
    map(unquoted, split(before_first(after_first(inline, "["), "]"), ","))
  end
  if member?("main", branches)
    if find_first(
      fn(l)
        starts_with?(trim(l), "paths:") or
          starts_with?(trim(l), "paths-ignore:")
      end,
      push
    ).nil?
      :all
    else
      :paths
    end
  end
end

@doc """
dispatched_of: The workflows land.yml's fast-forward job starts on main after it
pushes, as its `for w in ...; do gh workflow run` step names them.

    dispatched_of("        run: for w in a.yml b.yml; do gh workflow run \"$w\" --ref main; done") #=> ["a.yml", "b.yml"]
"""
def dispatched_of(land_yml)
  line = find_first(
    (l) -> contains?(l, "for w in ") and contains?(l, "gh workflow run"),
    moji::lines(land_yml)
  )
  if line.nil?
    []
  else
    split(trim(before_first(after_first(line, "for w in "), ";")), " ")
  end
end

@doc """
undispatched: The workflows a push to main starts that land.yml does not start
after a fast-forward, each with why: ci.yml's suite already ran on the same
commit inside the land run (land.yml calls it), and a :paths workflow would run
on every land if dispatched, since a dispatch ignores the paths.

    get(undispatched, "ci.yml") #=> "the land run already ran ci.yml on this commit"
"""
def undispatched()
  {"ci.yml" => "the land run already ran ci.yml on this commit"}
end

@doc """
batch_off_step: The name of land.yml's fast-forward step that refuses a batch
while the repository variable BLUE_LAND_BATCH is off; the land that pushed it
reads the step and lands alone.

    batch_off_step #=> "refuse a batch while BLUE_LAND_BATCH is off"
"""
def batch_off_step()
  "refuse a batch while BLUE_LAND_BATCH is off"
end

@doc """
batches?: Whether a land tests the lands queued behind it with it when it reaches
the front of the queue (land_batch): on for a land that follows its run and
queues; --no-batch turns it off, and a dry land or one that carries its own proof
(--proven, a proof of its tree alone) lands alone.

    batches?({batch: true, watch: true, queue: true, dry: false, proven: false}) #=> true
    batches?({batch: false, watch: true, queue: true, dry: false, proven: false}) #=> false
    batches?({batch: true, watch: true, queue: true, dry: false, proven: true}) #=> false
"""
def batches?(a)
  a[:batch] and a[:watch] and a[:queue] and not a[:dry] and not a[:proven]
end

@doc """
batch_ref?: Whether a land ref carries a batch, main plus the lands queued behind
the one that pushed it; BLUE_LAND_BATCH=off refuses such a ref at the turn. A
slug that starts with batch- reads as one, as a slug that starts with dry- or
prose- reads as a dry or a prose land.

    batch_ref?("land/batch-a/b") #=> true
    batch_ref?("land/prose-batch-a") #=> true
    batch_ref?("land/land/batch-and-settle") #=> false
"""
def batch_ref?(ref)
  starts_with?(ref, "land/batch-") or starts_with?(ref, "land/prose-batch-")
end

@doc """
batch_off: Why a batch stops while the repository variable BLUE_LAND_BATCH is
off: the turn refuses it and the land that leads it lands alone.

    starts_with?(batch_off, "batching is off") #=> true
"""
def batch_off()
  "batching is off (the repository variable BLUE_LAND_BATCH=off); the land that leads this batch lands alone"
end

@doc """
batch_refusal: Why the turn refuses a land ref, or nil: a batch, while the
repository variable BLUE_LAND_BATCH is off, runs no suite, and the land that
pushed it reads land.yml's batch_off_step and lands alone.

    batch_refusal("land/batch-a", "off") == batch_off #=> true
    batch_refusal("land/a", "off") #=> nil
    batch_refusal("land/batch-a", "") #=> nil
"""
def batch_refusal(ref, setting)
  if setting == "off" and batch_ref?(ref)
    batch_off
  end
end

@doc """
batch_cap: The most lands one batch holds, the one that leads it included; a red
batch of 8 finds its breaking land in at most 3 more runs.

    batch_cap #=> 8
"""
def batch_cap()
  8
end

@doc """
verdict_name: The branch the land that leads a batch writes a queued land's
verdict on, beside the land's ticket. No workflow runs on it.

    verdict_name("land-queue/20261110193005/a/b") #=> "land-verdict/20261110193005/a/b"
"""
def verdict_name(ticket)
  "land-verdict/#{after_first(ticket, "/")}"
end

@doc """
head_of: The commit a branch names in `git ls-remote` output, or nil.

    head_of(unlines(["abc\trefs/heads/land-queue/1/a", "def\trefs/heads/land-queue/1/a/b"]), "land-queue/1/a") #=> "abc"
    head_of("", "land-queue/1/a") #=> nil
"""
def head_of(text, name)
  line = find_first(
    (l) -> ends_with?(l, "\trefs/heads/#{name}"),
    moji::lines(text)
  )
  if not line.nil?
    first(split(line, "\t"))
  end
end

@doc """
undecided: The tickets no batch has decided: a ticket with a verdict beside it
waits only for its own land to read the verdict and remove both, so it holds no
place, even when that land died.

    undecided(tickets_of("1\trefs/heads/land-queue/5/a", 0), unlines(["1\trefs/heads/land-queue/5/a", "2\trefs/heads/land-verdict/5/a"])) #=> []
    count(undecided(tickets_of("1\trefs/heads/land-queue/5/a", 0), "1\trefs/heads/land-queue/5/a")) #=> 1
"""
def undecided(tickets, text)
  filter((t) -> head_of(text, verdict_name(t[:name])).nil?, tickets)
end

@doc """
verdicts_of: The verdict branches in `git ls-remote` output, each as `{name:, at:,
ref:}`, so a land that ends removes its own.

    verdicts_of("2\trefs/heads/land-verdict/5/a/b") #=> [{name: "land-verdict/5/a/b", at: 5, ref: "land/a/b"}]
"""
def verdicts_of(text)
  marks_of(text, "land-verdict", 0)
end

@doc """
batch_of: The queued lands the land at the front of the queue tests with it, in
queue order: those queued after it, never its own ticket, up to batch_cap with it.

    map((t) -> t[:ref], batch_of(tickets_of(unlines(["1\trefs/heads/land-queue/3/c", "1\trefs/heads/land-queue/1/a", "1\trefs/heads/land-queue/2/b"]), 0), "land/a", 1)) #=> ["land/b", "land/c"]
"""
def batch_of(tickets, ref, mine)
  take(
    batch_cap - 1,
    sort_keyed(
      (t) -> t[:name],
      filter((t) -> t[:ref] != ref and t[:at] > mine, tickets)
    )
  )
end

@doc """
halves: A red batch split for its next tries: the front half, the larger when the
count is odd, then the rest.

    halves(%w[a b c d]) #=> [["a", "b"], ["c", "d"]]
    halves(%w[a b c]) #=> [["a", "b"], ["c"]]
"""
def halves(xs)
  n = count(xs) - floor(count(xs) / 2)
  [take(n, xs), drop(n, xs)]
end

@doc """
bisect: Land a batch as far as its suite allows. `attempt` tests a list of lands
as one tree on main and answers `{verdict:, why:}`, the verdict :green, :red,
:halt or :short. A green try lands all of it. A red try splits in halves and tries
the front first; when the whole front lands, the back on the new main is the tree
that was red, so it runs no suite again and a lone land in it is blamed with that
red. A land is blamed only alone. :halt stops the batch and leaves its lands
undecided. :short, before any suite runs, names in `out:` the lands the tree does
not hold, each with why: they leave the batch to land alone, and the rest is
tried again. The answer: what landed, what was blamed with why, what must land
alone with why, what is left, why it halted, and every try in order.

    bisect(["a"], nil, (_b) -> {verdict: :green, why: ""})[:landed] #=> ["a"]
    bisect(["a"], nil, (_b) -> {verdict: :red, why: "red"})[:blamed] #=> [["a", "red"]]
    bisect(["a"], nil, (_b) -> {verdict: :short, why: "", out: [["a", "lost"]]})[:alone] #=> [["a", "lost"]]
"""
def bisect(batch, known, attempt)
  none = {landed: [], blamed: [], alone: [], left: [], halted: nil, tried: []}
  if batch == []
    none
  elsif count(batch) == 1 and not known.nil?
    {**none, blamed: [[first(batch), known]]}
  elsif known.nil?
    r = attempt(batch)
    if r[:verdict] == :green
      {**none, landed: batch, tried: [batch]}
    elsif r[:verdict] == :halt
      {**none, left: batch, halted: r[:why], tried: [batch]}
    elsif r[:verdict] == :short
      gone = map((p) -> first(p), r[:out])
      rest = bisect(reject((m) -> member?(m, gone), batch), nil, attempt)
      {**rest, alone: append(r[:out], rest[:alone])}
    else
      rest = bisect(batch, r[:why], attempt)
      {**rest, tried: append([batch], rest[:tried])}
    end
  else
    [front, back] = halves(batch)
    one = bisect(front, nil, attempt)
    two = if one[:left] != []
      {**none, left: back}
    elsif one[:blamed] == [] and one[:alone] == []
      bisect(back, known, attempt)
    else
      bisect(back, nil, attempt)
    end
    {
      landed: append(one[:landed], two[:landed]),
      blamed: append(one[:blamed], two[:blamed]),
      alone: append(one[:alone], two[:alone]),
      left: append(one[:left], two[:left]),
      halted: if one[:halted].nil?
        two[:halted]
      else
        one[:halted]
      end,
      tried: append(one[:tried], two[:tried])
    }
  end
end

@doc """
verdict_text: The message of the commit the land that leads a batch writes on a
queued land's verdict branch: the verdict, then why.

    verdict_of(verdict_text(false, "run 7 is red at ci / check / cargo-test")) #=> {landed: false, why: "run 7 is red at ci / check / cargo-test"}
"""
def verdict_text(landed, why)
  unlines(
    [
      if landed
        "land verdict: landed"
      else
        "land verdict: red"
      end,
      "",
      why
    ]
  )
end

@doc """
verdict_of: A verdict read back from its commit message, or nil for a message
that is none.

    verdict_of(verdict_text(true, "main is 1234567"))[:landed] #=> true
    verdict_of("land: a commit") #=> nil
"""
def verdict_of(message)
  ls = moji::lines(message)
  head = if ls == []
    ""
  else
    first(ls)
  end
  if member?(head, ["land verdict: landed", "land verdict: red"])
    {
      landed: head == "land verdict: landed",
      why: trim(join(drop(2, ls), line_break))
    }
  end
end

@doc """
alone_name: The branch the land that leads a batch writes beside a queued land's
ticket when the batch cannot hold that land: the land keeps its ticket and its
place, reads why, and lands alone next. Unlike a verdict it decides nothing, so
the ticket stays undecided.

    alone_name("land-queue/20261110193005/a/b") #=> "land-alone/20261110193005/a/b"
"""
def alone_name(ticket)
  "land-alone/#{after_first(ticket, "/")}"
end

@doc """
member_slug: The slug a land ref carries, without the prose scope, so a batch is
named after the first land it holds, scoped again by the batch's own tree.

    member_slug("land/a/b") #=> "a/b"
    member_slug("land/prose-docs-row") #=> "docs-row"
"""
def member_slug(ref)
  slug = after_first(ref, "/")
  if starts_with?(slug, "prose-")
    after_first(slug, "-")
  else
    slug
  end
end

@doc """
own_of: A land's own commits, as `git log --no-merges --format=%H%x09%ae%x09%at%x09%s`
prints them, each as `{sha:, id:, subject:}`. The id is the author, the author time
and the subject, which a rebase keeps when it rewrites a commit's sha and patch.

    own_of("abc\tt@t\t1700000000\tfix") #=> [{sha: "abc", id: "t@t 1700000000 fix", subject: "fix"}]
    own_of("") #=> []
"""
def own_of(text)
  map(
    fn(l)
      parts = split(l, "\t")
      subject = join(drop(3, parts), "\t")
      {
        sha: first(parts),
        id: join(append(take(2, drop(1, parts)), [subject]), " "),
        subject:
      }
    end,
    filter((l) -> l != "", moji::lines(text))
  )
end

@doc """
cherry_new: The commits `git cherry <tip> <head> <base>` marks `+`: no commit with
the same patch-id reaches the tip.

    cherry_new(unlines(["+ abc", "- def"])) #=> ["abc"]
"""
def cherry_new(text)
  map(
    (l) -> after_first(l, " "),
    filter((l) -> starts_with?(l, "+ "), moji::lines(text))
  )
end

@doc """
missing: A land's own commits that a tree does not hold: those whose patch-id
reaches it nowhere (cherry_new) and whose rebased identity (own_of) is not among the
tree's commits. A settled lock changes a commit's patch-id, never its identity.

    missing(["a"], [{sha: "a", id: "t 1 x", subject: "x"}], []) #=> [{sha: "a", id: "t 1 x", subject: "x"}]
    missing(["a"], [{sha: "a", id: "t 1 x", subject: "x"}], ["t 1 x"]) #=> []
    missing([], [{sha: "a", id: "t 1 x", subject: "x"}], []) #=> []
"""
def missing(fresh, own, held)
  filter((c) -> member?(c[:sha], fresh) and not member?(c[:id], held), own)
end

@doc """
missing_text: Why a tree does not hold a land, naming the commits it lacks.

    missing_text([{sha: "abcdef0123", id: "", subject: "fix"}], "1234567") #=> "1234567 lacks 1 of its commits: abcdef0 fix"
"""
def missing_text(lacked, tip)
  "#{tip} lacks #{to_s(count(lacked))} of its commits: #{join(map((c) -> "#{take_chars(c[:sha], 7)} #{c[:subject]}", lacked), ", ")}"
end

@doc """
stale_lock: The refusal for an index lock in this land's own worktree that is
older than the land and that no live process holds: a git that died left it, and
the next rebase would die on it. nil for a lock a running git holds or one made
after the land started. `holders` is what `lsof -t` printed, or nil when lsof could
not run.

    stale_lock("/r/.git/index.lock", 1_000, 2_000, "") #=> "/r/.git/index.lock is older than this land and no process holds it, so a git that died left it; rebasing here would die on it. Remove it (rm /r/.git/index.lock) and land again"
    stale_lock("/r/.git/index.lock", 1_000, 2_000, "4242") #=> nil
    stale_lock("/r/.git/index.lock", 3_000, 2_000, "") #=> nil
"""
def stale_lock(path, made, started, holders)
  if made < started and (holders.nil? or trim(holders) == "")
    who = if holders.nil?
      "lsof could not run to say whether a process holds it"
    else
      "no process holds it"
    end
    "#{path} is older than this land and #{who}, so a git that died left it; rebasing here would die on it. Remove it (rm #{path}) and land again"
  end
end

def git_lines(args)
  filter((l) -> l != "", moji::lines(ask(args)))
end

def own_commits(head, base)
  own_of(
    ask(
      [
        "log",
        "--no-merges",
        "--format=%H%x09%ae%x09%at%x09%s",
        "#{base}..#{head}"
      ]
    )
  )
end

@doc """
lacks: Why a tree does not hold a land whose commits end at `head`, or nil when
it does: each of the land's own commits (those past its merge-base with main)
reaches the tree by patch-id or by its rebased identity. A head main already
holds lacks nothing.
"""
def lacks(head, tip)
  base = ask(["merge-base", head, "origin/main"])
  lacked = missing(
    cherry_new(ask(["cherry", tip, head, base])),
    own_commits(head, base),
    map((c) -> c[:id], own_commits(tip, base))
  )
  if lacked != []
    missing_text(lacked, ask(["rev-parse", "--short", tip]))
  end
end

def held_out(m, tip)
  if not has_own_commits?(m[:head])
    "#{take_chars(m[:head] or "", 10)} has no commits beyond main"
  else
    lacks(m[:head], tip)
  end
end

def index_lock()
  ask(%w[rev-parse --path-format=absolute --git-path index.lock])
end

@doc """
guard_lock: Refuse, with the exact path, a land whose own worktree holds an
index lock older than the land that no process holds (stale_lock). Another
worktree's lock is never read or removed; git names each worktree's own.
"""
def guard_lock(a)
  path = index_lock
  if path != "" and path_exists(path)
    holders = stdout_of(exec_capture("lsof", "-t", "--", path)) rescue nil
    refusal = stale_lock(path, file_mtime_ms(path), a[:started], holders)
    if not refusal.nil?
      quit(1, refusal)
    end
  end
end

@doc """
state_dir: Where one land keeps its log, its lock and its exit: under the
repository's common git directory, at the branch slug its ticket carries, so two
lands of two branches never write one file, and two worktrees of one repository
find the same land of a branch.

    state_dir("/r/.git", "h7/speed") #=> "/r/.git/land/h7/speed"
"""
def state_dir(common, slug)
  path_join(path_join(common, "land"), slug)
end

@doc """
internal_verb?: Whether the words name one of the verbs CI runs on a land's run
(the turn, stop-on-red, absorbing a release), which keep no state of a land.

    internal_verb?(["--turn", "1", "land/a", "abc"]) #=> true
    internal_verb?(["--watch"]) #=> false
    internal_verb?([]) #=> false
"""
def internal_verb?(words)
  words != [] and
    member?(first(words), %w[--turn --stop-on-red --absorb-release])
end

def state_of(words)
  if not internal_verb?(words) and
      ask(%w[rev-parse --is-inside-work-tree]) == "true"
    state_dir(
      ask(%w[rev-parse --path-format=absolute --git-common-dir]),
      slug_for(
        land_args(words)[:slug],
        ask(%w[rev-parse --abbrev-ref HEAD]),
        ask(%w[rev-parse --short HEAD])
      )
    )
  end
end

kept = state_of(argv)

def log_of(dir)
  path_join(dir, "land.log")
end

def tell(line)
  write_stderr(unlines(["land: #{line}"]))
end

def say(line)
  tell(line)
  if not kept.nil? and path_exists(kept)
    append_file(
      log_of(kept),
      unlines(["#{rfc3339_of_ms(now_ms)} land: #{line}"])
    )
  end
end

@doc """
exit_text: The record a land leaves when it ends, its code and its reason, so a
land that attached to it ends with the same code and says the same reason.

    exit_of(exit_text(1, "run 7 is red at cargo-test")) #=> {code: 1, why: "run 7 is red at cargo-test"}
    exit_of("") #=> nil
"""
def exit_text(code, why)
  unlines([to_s(code), why])
end

def exit_of(text)
  code = to_int(trim(before_first(text, line_break)))
  if not code.nil?
    {code:, why: trim(after_first(text, line_break))}
  end
end

def own_pid()
  trim(stdout_of(exec_capture("sh", "-c", "echo $PPID")))
end

def running?(pid)
  pid != "" and exec_ok?("kill", "-0", pid)
end

def held_dir(dir)
  path_join(dir, "held")
end

@doc """
holder_of: The land that holds a branch, as its lock file reads: `{pid:, since:}`,
or nil for a file that names none.

    holder_of(unlines(["812", "1762900000000"])) #=> {pid: "812", since: 1_762_900_000_000}
    holder_of("") #=> nil
"""
def holder_of(text)
  ls = moji::lines(text)
  if ls != [] and trim(first(ls)) != ""
    {
      pid: trim(first(ls)),
      since: if count(ls) > 1
        to_int(trim(ls[1]))
      end
    }
  end
end

def holder(dir)
  file = path_join(held_dir(dir), "pid")
  if path_exists(file)
    h = holder_of(read_file(file))
    if not h.nil? and running?(h[:pid])
      h
    end
  end
end

@doc """
quit: End a land with a code and the reason, always both: the reason goes to the
terminal and the land's log, the code and the reason to its exit record, and a
lock this land holds is let go. No land ends with a bare code.
"""
def quit(code, why)
  say(why)
  if not kept.nil? and path_exists(kept)
    write_file(path_join(kept, "exit"), exit_text(code, why))
    h = holder(kept)
    if not h.nil? and h[:pid] == own_pid
      rm_rf(held_dir(kept))
    end
  end
  exit_with(code)
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

def queue_refs()
  cap = exec_capture(
    "git",
    "ls-remote",
    "origin",
    "refs/heads/land-queue/*",
    "refs/heads/land-beat/*",
    "refs/heads/land-verdict/*",
    "refs/heads/land-alone/*"
  )
  if status_of(cap) == 0
    stdout_of(cap)
  end
end

def tickets()
  text = queue_refs
  if not text.nil?
    undecided(tickets_of(text, stamp(rfc3339_of_ms(now_ms - 21_600_000))), text)
  end
end

def tickets_since(cutoff)
  text = queue_refs
  if not text.nil?
    tickets_of(text, cutoff)
  end
end

def beats()
  beats_of(queue_refs or "")
end

def beat(ref)
  old = map(
    (b) -> ":refs/heads/#{b[:name]}",
    filter((b) -> b[:ref] == ref, beats)
  )
  exec_capture(
    "env",
    "BLUE_PREPUSH_OFF=1",
    "git",
    "push",
    "-q",
    "--atomic",
    "origin",
    "#{ask(%w[rev-parse origin/main])}:refs/heads/#{beat_name(stamp(rfc3339_of_ms(now_ms)), ref)}",
    *old
  )
end

@doc """
enqueue: Hold this land's place in the queue: its ticket, created at the time it
first queued and kept after, names the commit a batch tests for it (HEAD), or
main's commit for a land that does not batch, which no batch takes.
"""
def enqueue(ref, head)
  held = tickets or []
  at = queued_at(held, ref)
  if at.nil?
    at = stamp(rfc3339_of_ms(now_ms))
  end
  pushed = exec_capture(
    "env",
    "BLUE_PREPUSH_OFF=1",
    "git",
    "push",
    "-q",
    "--force",
    "origin",
    "#{head}:refs/heads/#{ticket_name(at, ref)}"
  )
  if status_of(pushed) != 0
    say("no queue ticket: #{trim(stderr_of(pushed))}")
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
    filter(
      (t) -> t[:ref] == ref,
      append(
        append(tickets_since(0) or [], beats),
        append(
          verdicts_of(queue_refs or ""),
          marks_of(queue_refs or "", "land-alone", 0)
        )
      )
    )
  )
end

def leave(ref, code, why)
  dequeue(ref)
  quit(code, why)
end

def release_runs()
  runs_of("auto-release.yml", "databaseId,event,status,displayTitle")
end

def touched_since_main()
  git_lines(%w[diff --name-only origin/main...HEAD])
end

def verdict_on(ticket)
  said = beside(ticket, verdict_name)
  if not said.nil?
    verdict_of(said)
  end
end

def beside(ticket, named)
  text = queue_refs
  if not text.nil? and not ticket.nil?
    name = named(ticket)
    at = head_of(text, name)
    if at.nil?
      nil
    elsif exec_check("git", "fetch", "-q", "origin", "refs/heads/#{name}") != 0
      nil
    elsif ask(["rev-parse", "#{at}^"]) == head_of(text, ticket)
      ask(["log", "-1", "--format=%B", at])
    end
  end
end

def take_alone(ref, ticket)
  why = beside(ticket, alone_name)
  if not why.nil?
    say("#{trim(why)}; this land keeps its place and lands alone next")
    enqueue(ref, ask(%w[rev-parse origin/main]))
    exec_capture(
      "env",
      "BLUE_PREPUSH_OFF=1",
      "git",
      "push",
      "-q",
      "origin",
      ":refs/heads/#{alone_name(ticket)}"
    )
    true
  else
    false
  end
end

@doc """
confirm_landed: A land that is about to report landed proves it: the commits of
its branch (`home`), else of HEAD, are on the main it fetches now. A land whose
commits are not there, as when its branch moved while it ran or a batch named for
it did not hold it, says which commits and exits 1 rather than 0.
"""
def confirm_landed(ref, home)
  fetch_main
  head = if home.nil? or home == ""
    ask(%w[rev-parse HEAD])
  else
    ask(["rev-parse", "refs/heads/#{home}"])
  end
  why = lacks(head, "origin/main")
  if not why.nil?
    leave(ref, 1, "#{ref} was reported landed, but main #{why}; land again")
  end
end

@doc """
wait_turn: Wait while a land runs ahead, a land queued first waits, or a release
would move main under the suite. A land whose ticket a batch decided (land_batch)
stops waiting: it says the verdict and ends, 0 when it landed in the batch, 1
with the reason when it was blamed. The verdict is read after the queue, and a
batch writes its verdicts before its leader leaves the queue, so a land never
reads the queue empty and its verdict not yet written.
"""
def wait_turn(ref, deadline, waited, ticket?, home?)
  runs = land_runs
  releases = release_runs
  held = if runs.nil? or releases.nil?
    "the land or release runs cannot be read (a rate limit answers 403), so this land holds its turn"
  else
    reap(ref, runs)
    ahead = lands_ahead(runs, ref)
    queue = tickets or []
    mine = queued_at(queue, ref)
    waiting = if mine.nil?
      nil
    else
      beat(ref)
      waits_behind(
        queue,
        ref,
        mine,
        beats,
        stamp(rfc3339_of_ms(now_ms - 600_000))
      )
    end
    if ahead != []
      "#{to_s(count(ahead))} land(s) ahead, first #{json_get(first(ahead), :headBranch)}; waiting for a turn, since only one reaches main; --no-queue lands beside them"
    elsif not waiting.nil?
      "#{waiting[:ref]} queued first and waits for its turn; this land keeps its place behind it"
    else
      held_by_release(auto_release_workflow, releases, touched_since_main)
    end
  end
  verdict = verdict_on(ticket)
  if not verdict.nil?
    if verdict[:landed]
      confirm_landed(ref, home)
      leave(ref, 0, verdict[:why])
    end
    leave(ref, 1, verdict[:why])
  end
  told = take_alone(ref, ticket)
  if held.nil?
    told
  elsif now_ms > deadline
    say("waited the --queue-minutes limit; landing without a turn: #{held}")
    told
  else
    if not waited
      say(held)
    end
    sleep(poll_seconds)
    later = wait_turn(ref, deadline, true, ticket, home)
    told or later
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
reads as a failed land while its run goes on. The land that leads a batch passes
`tick`, its heartbeat, so the lands it holds see it alive while its run goes on.
"""
def wait_run(id, tick?)
  if not tick.nil?
    tick()
  end
  ended = run_ended(
    stdout_of(
      exec_capture("gh", "run", "view", id, "--json", "status,conclusion")
    )
  )
  if ended.nil?
    sleep(poll_seconds)
    wait_run(id, tick)
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
    sleep(poll_seconds)
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
    quit(
      1,
      "main gained #{to_s(count(ahead))} commit(s) that are not all release commits, or this land writes a release file; it needs a new suite"
    )
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
    quit(
      1,
      "the tested commit does not rebase onto the release commit: #{trim(stderr_of(r))}"
    )
  end
  extra = filter(
    (f) -> not member?(f, release_files),
    git_lines(["diff", "--name-only", sha, "HEAD"])
  )
  drift = ask(
    retsu::concat_lists(%w[diff --name-only origin/main HEAD --], release_files)
  )
  if extra != [] or drift != ""
    quit(
      1,
      "the rebased tree is not the tested tree with main's release files: #{join(extra, ", ")} #{drift}"
    )
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
    quit(
      1,
      "main refused the fast-forward to the tested tree rebased onto its release commits on every try"
    )
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
    hold = held_by_release(auto_release_workflow, releases, touched)
    if hold.nil?
      nil
    elsif now_ms > deadline
      "#{hold}, and an hour passed"
    else
      say(hold)
      sleep(poll_seconds)
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
  off = batch_refusal(ref, getenv("BLUE_LAND_BATCH", ""))
  refusal = if not off.nil?
    off
  elsif runs.nil?
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
      quit(1, "git fetch origin main failed: #{words}")
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

def regen_failure()
  failed = reduce(
    fn(why, args)
      if not why.nil?
        why
      else
        r = exec_capture(blue_here, *args)
        if status_of(r) != 0
          "rebased onto origin/main, but `blue #{join(args, " ")}` failed; fix it and land again: #{stderr_of(r)}"
        end
      end
    end,
    nil,
    [%w[lock .], %w[run --quiet gen/regen.b]]
  )
  if failed.nil? and ask(%w[status --porcelain --untracked-files=no]) != ""
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
  failed
end

def regenerate()
  failed = regen_failure
  if not failed.nil?
    quit(1, failed)
  end
end

@doc """
lock_conflict?: Whether every path a rebase stopped on is one of the two Cargo
locks, the conflict land settles itself; a conflict on any other path, or on
none, still needs a person.

    lock_conflict?(["Cargo.gen.lock"]) #=> true
    lock_conflict?(["Cargo.gen.lock", "Cargo.lock"]) #=> true
    lock_conflict?(["Cargo.gen.lock", "source.txt"]) #=> false
    lock_conflict?([]) #=> false
"""
def lock_conflict?(paths)
  paths != [] and
    every?((p) -> member?(p, %w[Cargo.gen.lock Cargo.lock]), paths)
end

@doc """
settle_steps: The commands that settle a lock conflict once main's side of each
conflicted lock is taken, the three a person ran by hand: cargo adds the branch's
crates back to main's Cargo.lock when that lock conflicted, `gen build .` ties
Cargo.gen.lock to it, and `cargo metadata --locked` checks the result.

    settle_steps(["Cargo.gen.lock"]) #=> [["gen", "build", "."], ["cargo", "metadata", "--format-version", "1", "--locked"]]
    count(settle_steps(["Cargo.gen.lock", "Cargo.lock"])) #=> 3
"""
def settle_steps(paths)
  checked = [%w[gen build .], %w[cargo metadata --format-version 1 --locked]]
  if member?("Cargo.lock", paths)
    append([%w[cargo metadata --format-version 1]], checked)
  else
    checked
  end
end

@doc """
rebase_stop: What land says when a rebase onto main stops for good: git's words
when nothing conflicts, why settling the locks failed when it tried, else the
paths that need a person.

    rebase_stop([], "no identity", nil) #=> "git rebase failed with no conflict: no identity"
    rebase_stop(["source.txt"], "", nil) #=> "HEAD does not rebase onto origin/main: source.txt conflict beyond what regenerating can settle; rebase it yourself and land again"
    rebase_stop(["Cargo.gen.lock"], "", "`gen build .` failed") #=> "HEAD does not rebase onto origin/main: settling Cargo.gen.lock failed, `gen build .` failed; rebase it yourself and land again"
"""
def rebase_stop(paths, why, settling)
  if paths == []
    "git rebase failed with no conflict: #{why}"
  elsif not settling.nil?
    "HEAD does not rebase onto origin/main: settling #{join(paths, ", ")} failed, #{settling}; rebase it yourself and land again"
  else
    "HEAD does not rebase onto origin/main: #{join(paths, ", ")} conflict beyond what regenerating can settle; rebase it yourself and land again"
  end
end

def settle_locks(paths)
  map(
    (p) -> exec_check("git", "checkout", "--ours", "--", p),
    filter((p) -> member?(p, %w[Cargo.gen.lock Cargo.lock]), paths)
  )
  failure = reduce(
    fn(why, step)
      if not why.nil?
        why
      else
        r = exec_capture(*step)
        if status_of(r) != 0
          "`#{join(step, " ")}` failed: #{trim(stderr_of(r))}"
        end
      end
    end,
    nil,
    settle_steps(paths)
  )
  if failure.nil?
    exec_check(
      "git",
      *append(
        %w[add --],
        filter((p) -> path_exists(p), %w[Cargo.gen.lock Cargo.lock])
      )
    )
  end
  failure
end

def continue_rebase()
  if exec_ok?("git", "diff", "--cached", "--quiet")
    exec_capture("git", *append(driver_args, %w[rebase --skip]))
  else
    exec_capture(
      "env",
      "GIT_EDITOR=true",
      "git",
      *append(driver_args, %w[rebase --continue])
    )
  end
end

def through(a, r)
  if status_of(r) != 0
    paths = git_lines(%w[diff --name-only --diff-filter=U])
    if a[:regen] and lock_conflict?(paths)
      failure = settle_locks(paths)
      if failure.nil?
        say(
          "settled #{join(paths, ", ")} at #{ask(%w[log -1 --format=%h REBASE_HEAD])}: main's side, #{join(map((s) -> join(s, " "), settle_steps(paths)), ", ")}"
        )
        through(a, continue_rebase)
      else
        {paths:, why: "", settling: failure}
      end
    else
      {paths:, why: trim(stderr_of(r)), settling: nil}
    end
  end
end

@doc """
catch_up: Rebase HEAD onto origin/main, where the merge driver regenerates a
generated file that conflicts, then regenerate what merged clean but went stale
and commit it. A commit that stops only on the Cargo locks is settled and the
rebase goes on (settle_steps); --no-regen leaves that stop to a person. Any other
conflict aborts the rebase, leaves HEAD as it was, names the paths and stops:
that one needs a person.
"""
def catch_up(a)
  guard_lock(a)
  stopped = through(
    a,
    exec_capture("git", *append(driver_args, %w[rebase -q origin/main]))
  )
  if not stopped.nil?
    exec_check("git", "rebase", "--abort")
    quit(1, rebase_stop(stopped[:paths], stopped[:why], stopped[:settling]))
  end
  if a[:regen]
    regenerate
  end
end

def settle(a, left, minutes)
  ref = ref_for(a)
  told = if a[:watch] and a[:queue] and not a[:dry]
    wait_turn(ref, now_ms + minutes * 60000, false, a[:ticket], a[:home])
  end
  b = if told == true
    assoc(a, :batch, false)
  else
    a
  end
  fetch_main
  if not contains_main?
    if left == 0
      quit(
        1,
        "HEAD does not contain origin/main, so main cannot fast-forward to it, and --requeue=0 keeps this land from rebasing. Run: git rebase origin/main"
      )
    end
    catch_up(b)
    settle(b, left, minutes)
  else
    b
  end
end

def prove(a)
  if a[:proven] and
      exec_check(self_exe, "run", "--quiet", "gen/proof.b", "--", "--prove") !=
        0
    quit(
      1,
      "no proof of HEAD's tree; land without --proven and CI runs the suite"
    )
  end
end

def ref_for(a)
  ref_at(
    a,
    "HEAD",
    slug_for(
      a[:slug],
      ask(%w[rev-parse --abbrev-ref HEAD]),
      ask(%w[rev-parse --short HEAD])
    )
  )
end

def ref_at(a, rev, slug)
  scoped = exec_capture(
    self_exe,
    "run",
    "--quiet",
    "gen/prepush.b",
    "--",
    "--scope",
    "origin/main",
    rev
  )
  scope = if a[:prose] and status_of(scoped) == 0
    trim(stdout_of(scoped))
  else
    "whole"
  end
  land_ref(scoped_slug(slug, scope), a[:dry])
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
  push_at(ref, ask(%w[rev-parse HEAD]), [])
end

def push_at(ref, sha, settings)
  if repush?(ask(["ls-remote", "origin", "refs/heads/#{ref}"]), sha)
    say(
      "#{ref} already names #{take_chars(sha, 10)}; deleting it first, so the push starts a new run"
    )
    if exec_check(
        "env",
        *append(settings, ["git", "push", "-q", "origin", ":refs/heads/#{ref}"])
      ) != 0
      quit(
        1,
        "git could not delete #{ref} before pushing it again; git's words are above"
      )
    end
  end
  if exec_check(
      "env",
      *append(
        settings,
        ["git", "push", "--force", "origin", "#{sha}:refs/heads/#{ref}"]
      )
    ) != 0
    quit(
      1,
      "git could not push #{take_chars(sha, 10)} to #{ref}; git's words are above"
    )
  end
  say(
    "#{take_chars(sha, 10)} is on #{ref}. CI runs its suite and, when green, fast-forwards main to it; when main moved first, it fails, and --watch rebases and lands again"
  )
  sha
end

def older_than(a, ref, found)
  if a[:queue] and not a[:dry]
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
end

def jobs_of(found)
  json_parse(
    stdout_of(
      exec_capture(
        "gh",
        "run",
        "view",
        found,
        "--json",
        "jobs",
        "--jq",
        "[.jobs[] | {name, conclusion, refused: ([.steps[]? | select(.name == \"#{turn_step}\" and .conclusion == \"failure\")] != []), off: ([.steps[]? | select(.name == \"#{batch_off_step}\" and .conclusion == \"failure\")] != [])}]"
      )
    )
  ) rescue
    []
end

@doc """
batch_off?: Whether a batch's run, as jobs_of reads it, was refused at land.yml's
batch_off_step: BLUE_LAND_BATCH is off, and the land that leads lands alone.

    batch_off?(json_parse("[{\"name\":\"fast-forward\",\"conclusion\":\"failure\",\"refused\":false,\"off\":true}]")) #=> true
    batch_off?([]) #=> false
"""
def batch_off?(jobs)
  find_first((j) -> json_get(j, :off) == true, jobs) != nil
end

def has_own_commits?(sha)
  if sha.nil?
    false
  else
    (to_int(ask(["rev-list", "--count", "origin/main..#{sha}"])) or 0) > 0
  end
end

def batch_members(ref, ticket)
  text = queue_refs
  queue = if text.nil?
    []
  else
    filter(
      (t) -> head_of(text, alone_name(t[:name])).nil?,
      undecided(
        tickets_of(text, stamp(rfc3339_of_ms(now_ms - 21_600_000))),
        text
      )
    )
  end
  mine = queued_at(queue, ref)
  since = stamp(rfc3339_of_ms(now_ms - 600_000))
  behind = if mine.nil? or ticket.nil?
    []
  else
    batch_of(filter((t) -> alive?(t, beats_of(text), since), queue), ref, mine)
  end
  if behind != []
    exec_capture(
      "git",
      "fetch",
      "-q",
      "origin",
      *map((t) -> "refs/heads/#{t[:name]}", behind)
    )
  end
  filter(
    (m) -> has_own_commits?(m[:head]),
    map((t) -> {**t, head: head_of(text, t[:name])}, behind)
  )
end

@doc """
compose: A batch's tree: each land's own commits, in queue order, rebased onto
main and the lands before it as catch_up rebases one (the merge driver, the
settled locks), then regenerated once. It works on a detached HEAD and returns to
the branch, so the branch never moves. Answers `{tip:, stop:}`, stop naming the
land that does not rebase or the regeneration that failed.
"""
def compose(a, b)
  guard_lock(a)
  home = ask(%w[symbolic-ref -q --short HEAD])
  back = if home == ""
    ask(%w[rev-parse HEAD])
  else
    home
  end
  exec_check("git", "checkout", "-q", "--detach", "origin/main")
  got = reduce(
    fn(acc, m)
      if not acc[:stop].nil?
        acc
      else
        stopped = through(
          a,
          exec_capture(
            "git",
            *append(
              driver_args,
              [
                "rebase",
                "-q",
                "--onto",
                acc[:tip],
                ask(["merge-base", m[:head], "origin/main"]),
                m[:head]
              ]
            )
          )
        )
        if stopped.nil?
          {tip: ask(%w[rev-parse HEAD]), stop: nil}
        else
          exec_check("git", "rebase", "--abort")
          {
            tip: acc[:tip],
            stop: "#{m[:ref]} does not rebase onto main and the lands before it: #{rebase_stop(stopped[:paths], stopped[:why], stopped[:settling])}"
          }
        end
      end
    end,
    {tip: ask(%w[rev-parse origin/main]), stop: nil},
    b
  )
  stop = if got[:stop].nil? and a[:regen]
    regen_failure
  else
    got[:stop]
  end
  tip = ask(%w[rev-parse HEAD])
  exec_check("git", "checkout", "-q", back)
  {tip:, stop:}
end

def try_batch(a, b, left, minutes)
  names = join(map((m) -> m[:ref], b), ", ")
  home = ref_for(a)
  wait_turn(home, now_ms + minutes * 60000, false)
  fetch_main
  c = compose(a, b)
  out = if c[:stop].nil?
    retsu::flat_map(
      b,
      fn(m)
        why = held_out(m, c[:tip])
        if not why.nil?
          [[m, why]]
        end
      end
    )
  else
    []
  end
  if not c[:stop].nil?
    say(c[:stop])
    {verdict: :red, why: c[:stop]}
  elsif out != []
    map(
      fn(p)
        say("the batch tree does not hold #{first(p)[:ref]}: #{retsu::last(p)}")
      end,
      out
    )
    {verdict: :short, why: "", out:}
  else
    ref = ref_at(a, c[:tip], "batch-#{member_slug(first(b)[:ref])}")
    push_at(ref, c[:tip], ["BLUE_PREPUSH_OFF=1"])
    found = run_of(ref, c[:tip])
    older = if found == ""
      nil
    else
      older_than(a, ref, found)
    end
    if found == ""
      {verdict: :halt, why: "no run appeared for #{ref} in a minute"}
    elsif not older.nil?
      say(
        "#{json_get(older, :headBranch)} took the same turn first; stopping run #{found} and trying the batch again behind it"
      )
      exec_check("gh", "run", "cancel", found)
      try_batch(a, b, left, minutes)
    else
      say("following run #{found} of #{names}")
      if wait_run(found, () -> beat(home)) == 0
        fetch_main
        {
          verdict: :green,
          why: "#{names} landed together in run #{found}; main is #{ask(%w[rev-parse --short origin/main])}"
        }
      else
        jobs = jobs_of(found)
        fetch_main
        moved = not exec_ok?(
          "git",
          "merge-base",
          "--is-ancestor",
          "origin/main",
          c[:tip]
        )
        again = moved_main?(jobs) and (refused_turn?(jobs) or moved)
        if batch_off?(jobs)
          {verdict: :halt, why: batch_off}
        elsif again and left > 0
          say(
            "run #{found} of #{names} was refused at the fast-forward or the turn; composing on main again, #{to_s(left - 1)} more after this"
          )
          try_batch(a, b, left - 1, minutes)
        elsif again
          {
            verdict: :halt,
            why: "main moved or the turn was refused on every try of #{names}; --requeue=N allows more"
          }
        else
          {
            verdict: :red,
            why: "run #{found} of #{names} is red at #{first_red(jobs) or "the fast-forward"}"
          }
        end
      end
    end
  end
end

def give_alone(m, why)
  pushed = mark_beside(m, alone_name(m[:name]), why)
  say(
    "#{m[:ref]} is not in the batch: #{why}; it keeps its place and lands alone next#{if pushed != 0
  "; the notice could not be written, so it waits on"
else
  ""
end}"
  )
end

def mark_beside(m, name, message)
  sha = ask(
    ["commit-tree", "#{m[:head]}^{tree}", "-p", m[:head], "-m", message]
  )
  if sha == ""
    1
  else
    status_of(
      exec_capture(
        "env",
        "BLUE_PREPUSH_OFF=1",
        "git",
        "push",
        "-q",
        "--force",
        "origin",
        "#{sha}:refs/heads/#{name}"
      )
    )
  end
end

def give_verdict(m, landed, why)
  pushed = mark_beside(m, verdict_name(m[:name]), verdict_text(landed, why))
  say(
    "#{m[:ref]} #{if landed
  "landed"
else
  "is blamed"
end}: #{why}#{if pushed != 0
  "; its verdict could not be written, so its land waits on"
else
  ""
end}"
  )
end

@doc """
land_batch: LANDING L1, batched lands. The land at the front of the queue tests
main plus the lands queued behind it (batch_of), in queue order, as one tree
(compose); green fast-forwards main through all of them. Red halves the batch
until the land that breaks it is alone (bisect). Each queued land gets its
verdict on a branch beside its ticket, and its --watch ends with it (wait_turn).
Off: --no-batch, or the repository variable BLUE_LAND_BATCH=off, which refuses a
batch at the turn; this land then lands alone.
"""
def land_batch(a, ref, members, left, minutes)
  me = {name: a[:ticket], ref:, head: ask(%w[rev-parse HEAD])}
  batch = append([me], members)
  say(
    "#{to_s(count(members))} land(s) queued behind this one: #{join(map((m) -> m[:ref], members), ", ")}; testing them with it as one tree on main, in queue order; --no-batch lands alone"
  )
  done = bisect(batch, nil, (b) -> try_batch(a, b, left, minutes))
  others = (ms) -> reject((m) -> m[:ref] == ref, ms)
  map(
    (p) -> give_alone(first(p), retsu::last(p)),
    reject((p) -> first(p)[:ref] == ref, done[:alone])
  )
  apart = find_first((p) -> first(p)[:ref] == ref, done[:alone])
  map(
    (m) -> give_verdict(m, true, "landed in the batch #{ref} led"),
    others(done[:landed])
  )
  map(
    (p) -> give_verdict(first(p), false, retsu::last(p)),
    reject((p) -> first(p)[:ref] == ref, done[:blamed])
  )
  mine = find_first((p) -> first(p)[:ref] == ref, done[:blamed])
  if done[:halted] == batch_off
    say(done[:halted])
    follow(assoc(a, :batch, false), left, minutes)
  elsif member?(ref, map((m) -> m[:ref], done[:landed]))
    confirm_landed(ref, a[:home])
    leave(
      ref,
      0,
      "landed in a batch with #{to_s(count(others(done[:landed])))} other land(s)"
    )
  elsif not apart.nil?
    say("this land is not in the batch: #{retsu::last(apart)}; it lands alone")
    follow(assoc(a, :batch, false), left, minutes)
  elsif not mine.nil?
    leave(ref, 1, "blamed: #{retsu::last(mine)}")
  else
    leave(
      ref,
      1,
      "the batch stopped: #{done[:halted]}; #{to_s(count(done[:left]))} land(s) stay queued"
    )
  end
end

@doc """
end_reason: Why a land that followed its run ends there instead of landing again,
from the run's jobs as jobs_of reads them: a red job, a run that ended with no
verdict of its own, a fast-forward refused though main did not move, or the
requeues spent. Nil when it lands again.

    end_reason("7", json_parse("[{\"name\":\"ci / check / cargo-test\",\"conclusion\":\"failure\"}]"), 2, false, false) #=> "run 7 is red at ci / check / cargo-test; fix it and land again"
    end_reason("7", [], 2, false, false) #=> "run 7 ended with no red job and no green fast-forward (cancelled, or a step outside the suite failed); see gh run view 7, then land again"
    end_reason("7", json_parse("[{\"name\":\"fast-forward\",\"conclusion\":\"failure\"}]"), 0, true, false) #=> "main moved while run 7 ran and the requeues are spent (--requeue=N allows more); land again"
    end_reason("7", json_parse("[{\"name\":\"fast-forward\",\"conclusion\":\"failure\"}]"), 2, true, false) #=> nil
"""
def end_reason(id, jobs, left, moved, turned)
  red = first_red(jobs)
  if not red.nil?
    "run #{id} is red at #{red}; fix it and land again"
  elsif not moved_main?(jobs)
    "run #{id} ended with no red job and no green fast-forward (cancelled, or a step outside the suite failed); see gh run view #{id}, then land again"
  elsif not (moved or turned)
    "the fast-forward of run #{id} failed though main did not move and the turn was held; see gh run view #{id}, then land again"
  elsif left == 0
    "main moved while run #{id} ran and the requeues are spent (--requeue=N allows more); land again"
  end
end

@doc """
moved_home: Why a land stops because its worktree's branch is no longer the one
it holds, or nil: another git that shares the worktree checked out another
branch, and a land that went on would build and name a batch from commits that
are not its own.

    moved_home("h7/speed", "h7/speed") #=> nil
    moved_home("", "main") #=> nil
    moved_home("h7/speed", "h10/ecosystem") #=> "this land holds h7/speed, but its worktree is now on h10/ecosystem: another git shares the worktree; land from a worktree of its own"
"""
def moved_home(home, now)
  if home != "" and home != now
    "this land holds #{home}, but its worktree is now on #{if now == ""
  "a detached HEAD"
else
  now
end}: another git shares the worktree; land from a worktree of its own"
  end
end

def follow(given, left, minutes)
  if not given[:home].nil?
    moved = moved_home(given[:home], ask(%w[symbolic-ref -q --short HEAD]))
    if not moved.nil?
      quit(1, moved)
    end
  end
  a = settle(given, left, minutes)
  prove(a)
  ref = ref_for(a)
  if batches?(a)
    members = batch_members(ref, a[:ticket])
    if members != []
      land_batch(a, ref, members, left, minutes)
    end
  end
  sha = push_land(ref)
  found = run_of(ref, sha)
  if found == ""
    quit(1, "no run appeared in a minute; gh run list --branch #{ref}")
  end
  older = older_than(a, ref, found)
  if not older.nil?
    say(
      "#{json_get(older, :headBranch)} took the same turn first; stopping this run and queueing behind it"
    )
    exec_check("gh", "run", "cancel", found)
    follow(a, left, minutes)
  else
    say("following run #{found}")
    status = wait_run(
      found,
      if a[:ticket].nil?
        nil
      else
        () -> beat(ref)
      end
    )
    if status == 0
      confirm_landed(ref, a[:home])
      leave(ref, 0, "landed: run #{found} is green and main holds #{ref}")
    end
    jobs = jobs_of(found)
    fetch_main
    turned = refused_turn?(jobs)
    why = end_reason(found, jobs, left, not contains_main?, turned)
    if not why.nil?
      leave(ref, status, why)
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
  a = assoc(
    assoc(
      assoc(land_args(argv), :batch, not member?("--no-batch", argv)),
      :started,
      now_ms
    ),
    :home,
    ask(%w[symbolic-ref -q --short HEAD])
  )
  unknown = unknown_flag(argv)
  if not unknown.nil?
    tell(
      "#{unknown} is no flag; land takes --dry, --watch, --proven, --no-queue, --no-regen, --no-prose, --no-batch, --requeue=N and --queue-minutes=N"
    )
    exit_with(2)
  end
  if ask(%w[status --porcelain --untracked-files=no]) != ""
    tell("tracked files differ from HEAD; commit them, since CI checks the commit")
    exit_with(1)
  end
  left = requeue_of(argv)
  minutes = count_flag(argv, "--queue-minutes=", 240)
  if left.nil? or minutes.nil?
    tell("--requeue and --queue-minutes take a count, as --requeue=2; --requeue=0 turns the requeue off")
    exit_with(2)
  end
  if not kept.nil?
    hold_branch(kept, a[:watch])
    say("this land's log: #{log_of(kept)}")
  end
  fetch_main
  if a[:watch]
    ticket = if a[:queue] and not a[:dry]
      ref = ref_for(a)
      head = if batches?(a)
        ask(%w[rev-parse HEAD])
      else
        ask(%w[rev-parse origin/main])
      end
      ticket_name(enqueue(ref, head), ref)
    end
    follow(assoc(a, :ticket, ticket), left, minutes)
  else
    settle(a, left, minutes)
    prove(a)
    ref = ref_for(a)
    push_land(ref)
    quit(0, "pushed; follow it with gh run list --branch #{ref}")
  end
end

def poll_seconds()
  n = to_int(getenv("BLUE_LAND_POLL_SECONDS", "60"))
  if n.nil? or n < 1
    60
  else
    n
  end
end

@doc """
hold_branch: LANDING R1, one land per branch. A land with --watch takes the
branch's lock, a directory `held` beside its log that only one mkdir can make,
naming its pid. While a live land holds it, a second --watch of the branch
attaches to the first (attach) and pushes nothing, and a land without --watch
refuses, so no second land composes or pushes the batch the first one runs. A
lock whose pid no longer runs is taken over, saying so.
"""
def hold_branch(dir, watching)
  mkdir_p(dir)
  h = holder(dir)
  mine = own_pid
  if not h.nil? and h[:pid] != mine
    if watching
      attach(dir, h)
    end
    tell(
      "a --watch land of this branch runs as pid #{h[:pid]} and lands it; follow its log #{log_of(dir)}, or stop it before landing again"
    )
    exit_with(2)
  end
  if watching
    lock = held_dir(dir)
    if not exec_ok?("mkdir", lock)
      stale = holder_of(
        if path_exists(path_join(lock, "pid"))
          read_file(path_join(lock, "pid"))
        else
          ""
        end
      )
      if not holder(dir).nil?
        attach(dir, holder(dir))
      end
      rm_rf(lock)
      if not exec_ok?("mkdir", lock)
        tell("another land took #{lock} at the same moment; attaching to it")
        attach(dir, holder(dir) or {pid: "", since: nil})
      end
      tell(
        "took over the lock of a land that no longer runs#{if stale.nil?
  ""
else
  " (pid #{stale[:pid]})"
end}"
      )
    end
    if path_exists(log_of(dir))
      rename_file(log_of(dir), "#{log_of(dir)}.1")
    end
    rm_rf(path_join(dir, "exit"))
    write_file(path_join(lock, "pid"), unlines([mine, to_s(now_ms)]))
  end
end

@doc """
attach: Follow the land that holds this branch instead of landing again: print
its log as it grows, and when its pid ends, end with the code and the reason it
recorded. Its run, its batch and its ticket are left as they are.
"""
def attach(dir, h)
  tell(
    "a land of this branch already runs as pid #{h[:pid]}; attaching to its log #{log_of(dir)} instead of landing again, so its run is left as it is"
  )
  watch_log(dir, h[:pid], 0)
end

def watch_log(dir, pid, seen)
  ls = if path_exists(log_of(dir))
    moji::lines(read_file(log_of(dir)))
  else
    []
  end
  map((l) -> write_stderr(unlines([l])), drop(seen, ls))
  if running?(pid)
    sleep(min(poll_seconds, 10))
    watch_log(dir, pid, count(ls))
  else
    file = path_join(dir, "exit")
    ended = if path_exists(file)
      exit_of(read_file(file))
    end
    if ended.nil?
      tell(
        "pid #{pid} ended and recorded no exit; its log is #{log_of(dir)}; land again"
      )
      exit_with(1)
    end
    tell(
      "the land it attached to ended with #{to_s(ended[:code])}: #{ended[:why]}"
    )
    exit_with(ended[:code])
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

test "a repository whose auto-release runs in tag mode holds no land for a release in flight, since the release commit never reaches main (v0.0.193 tagged at cafef4c8 beside main), and blue's own workflow is one"
  dispatched = json_parse("[{\"databaseId\":42786952460,\"event\":\"workflow_dispatch\",\"status\":\"in_progress\",\"displayTitle\":\"auto-release\"}]")
  touched = %w[Cargo.toml Cargo.lock]
  assert held_by_release(
    unlines(["    with:", "      release-ref-mode: tag"]),
    dispatched,
    touched
  ).nil?
  assert contains?(
    held_by_release(
      unlines(["    with:", "      source-paths: x"]),
      dispatched,
      touched
    ),
    "changes Cargo.toml, Cargo.lock"
  )
  assert held_by_release("", [], touched).nil?
  assert releases_beside_main?(source(".github/workflows/auto-release.yml"))
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
  assert get(
    waits_behind(queue, "land/docs/iphone", 20_261_110_184_300, [], 0),
    :ref
  ) == "land/queue/land-turn"
  assert waits_behind(
    queue,
    "land/queue/land-turn",
    20_261_110_143_900,
    [],
    0
  ).nil?
  dead = tickets_of("1\trefs/heads/land-queue/20261110211916/docs/iphone", 0)
  since = 20_261_110_231_300
  assert waits_behind(
    dead,
    "land/fetch/lock-retry",
    20_261_110_222_321,
    [],
    since
  ).nil?
  alive = beats_of("1\trefs/heads/land-beat/20261110232000/docs/iphone")
  assert get(
    waits_behind(
      dead,
      "land/fetch/lock-retry",
      20_261_110_222_321,
      alive,
      since
    ),
    :ref
  ) == "land/docs/iphone"
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
  root = path_join(temp_dir("land"), "land")
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

def fast_forward(sha, root)
  "exec_check(\"git\", \"-C\", \"#{root}/origin.git\", \"merge-base\", \"--is-ancestor\", \"main\", #{sha}) == 0 and exec_check(\"git\", \"-C\", \"#{root}/origin.git\", \"update-ref\", \"refs/heads/main\", #{sha}) == 0"
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
        "  write_file(\"#{root}/run-sha\", argv_get(7))",
        "  write_stdout(\"100\")",
        "elsif contains?(args, \"status,conclusion\")",
        "  #{fast_forward("read_file(\"#{root}/run-sha\")", root)}",
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
    assert as_tester(
      work,
      %w[ls-remote origin refs/heads/land-queue/* refs/heads/land-beat/*]
    ) == ""
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

def manifest(top, bottom)
  dep = (n) -> "dep #{n}"
  unlines(
    retsu::concat_lists(
      retsu::concat_lists(["[top]"], map(dep, top)),
      retsu::concat_lists(["[middle]", "[bottom]"], map(dep, bottom))
    )
  )
end

def cargo_files(top, bottom)
  names = retsu::concat_lists(top, bottom)
  [
    ["Cargo.toml", manifest(top, bottom)],
    ["Cargo.lock", unlines(retsu::concat_lists(["lock"], names))],
    [
      "Cargo.gen.lock",
      unlines([join(retsu::concat_lists(%w[gen lock], names), " ")])
    ]
  ]
end

def locks_on_main(root)
  work = path_join(root, "work")
  as_tester(work, %w[checkout -q main])
  committed(work, cargo_files(["base"], []), "locks")
  as_tester(work, %w[push -q origin main])
  as_tester(work, %w[checkout -q topic])
  as_tester(work, %w[reset -q --hard main])
end

def fake_locks(root)
  bin = path_join(root, "lock-bin")
  mkdir_p(bin)
  logged = fn(name)
    [
      "use(\"moji\", %i[after_first])",
      "log = \"#{root}/#{name}.log\"",
      "prior = if path_exists(log)",
      "  read_file(log)",
      "else",
      "  \"\"",
      "end",
      "write_file(log, join([prior, unlines([join(argv, \" \")])], \"\"))"
    ]
  end
  write_program(
    path_join(root, "cargo.b"),
    unlines(
      retsu::concat_lists(
        logged("cargo"),
        [
          "deps = map((l) -> after_first(l, \"dep \"), filter((l) -> starts_with?(l, \"dep \"), moji::lines(read_file(\"Cargo.toml\"))))",
          "resolved = unlines(append([\"lock\"], deps))",
          "if member?(\"--locked\", argv)",
          "  if path_exists(\"#{root}/cargo-refuses\") or read_file(\"Cargo.lock\") != resolved",
          "    write_stderr(\"error: the lock file Cargo.lock needs to be updated but --locked was passed to prevent this\")",
          "    exit_with(101)",
          "  end",
          "else",
          "  write_file(\"Cargo.lock\", resolved)",
          "end"
        ]
      )
    )
  )
  write_program(
    path_join(root, "gen.b"),
    unlines(
      retsu::concat_lists(
        logged("gen"),
        ["write_file(\"Cargo.gen.lock\", unlines([concat(\"gen \", join(moji::lines(read_file(\"Cargo.lock\")), \" \"))]))"]
      )
    )
  )
  map(
    fn(name)
      script(
        path_join(bin, name),
        unlines(
          [
            "#!/bin/sh",
            "exec #{self_exe} run --quiet #{root}/#{name}.b -- \"$@\""
          ]
        )
      )
    end,
    %w[cargo gen]
  )
  bin
end

def calls_of(root, name)
  log = path_join(root, "#{name}.log")
  if path_exists(log)
    moji::lines(read_file(log))
  else
    []
  end
end

def on_path(bin)
  ["PATH=#{bin}:#{getenv("PATH")}"]
end

test "a land whose rebase stops only on Cargo.gen.lock settles it commit by commit: main's side, gen build ., cargo metadata --locked, as five refusals of 2026-11-10 were settled by hand"
  if self_exe != nil
    root = landing_fixture
    work = path_join(root, "work")
    locks_on_main(root)
    committed(work, cargo_files(["base"], ["bee"]), "bee")
    committed(work, cargo_files(["base"], %w[bee cat]), "cat")
    main_moves(root, cargo_files(%w[ant base], []))
    r = land_with(on_path(fake_locks(root)), root, [])
    assert status_of(r) == 0
    as_tester(work, %w[fetch -q origin])
    assert as_tester(
      work,
      %w[
        log
        --format=%s
        refs/remotes/origin/main..refs/remotes/origin/land/topic
      ]
    ) == join(%w[cat bee], line_break)
    assert landed(root, "Cargo.gen.lock") == "gen lock ant base bee cat"
    assert as_tester(
      work,
      %w[show refs/remotes/origin/land/topic~1:Cargo.gen.lock]
    ) == "gen lock ant base bee"
    assert landed(root, "Cargo.lock") ==
      join(%w[lock ant base bee cat], line_break)
    assert calls_of(root, "gen") == ["build .", "build ."]
    assert calls_of(root, "cargo") ==
      [
        "metadata --format-version 1 --locked",
        "metadata --format-version 1 --locked"
      ]
    assert contains?(stderr_of(r), "settled Cargo.gen.lock")
    rm_rf(root)
  end
end

test "a rebase that stops on both locks takes main's Cargo.lock and lets cargo add the branch's crates back before gen build"
  if self_exe != nil
    root = landing_fixture
    work = path_join(root, "work")
    locks_on_main(root)
    committed(work, cargo_files(["base"], ["bee"]), "bee")
    main_moves(root, cargo_files(%w[base bat], []))
    r = land_with(on_path(fake_locks(root)), root, [])
    assert status_of(r) == 0
    as_tester(work, %w[fetch -q origin])
    assert landed(root, "Cargo.lock") == join(%w[lock base bat bee], line_break)
    assert landed(root, "Cargo.gen.lock") == "gen lock base bat bee"
    assert calls_of(root, "cargo") ==
      ["metadata --format-version 1", "metadata --format-version 1 --locked"]
    rm_rf(root)
  end
end

test "a lock that does not check after settling, and --no-regen, stop the land with the old refusal and leave HEAD as it was"
  if self_exe != nil
    root = landing_fixture
    work = path_join(root, "work")
    locks_on_main(root)
    committed(work, cargo_files(["base"], ["bee"]), "bee")
    before = as_tester(work, %w[rev-parse HEAD])
    main_moves(root, cargo_files(%w[ant base], []))
    path = on_path(fake_locks(root))
    write_file(path_join(root, "cargo-refuses"), "")
    refused = land_with(path, root, [])
    assert status_of(refused) == 1
    assert contains?(
      stderr_of(refused),
      "cargo metadata --format-version 1 --locked"
    )
    assert as_tester(work, %w[rev-parse HEAD]) == before
    assert as_tester(work, %w[status --porcelain --untracked-files=no]) == ""
    assert as_tester(work, %w[ls-remote origin refs/heads/land/topic]) == ""
    rm_rf(path_join(root, "cargo-refuses"))
    kept = land_with(path, root, ["--no-regen"])
    assert status_of(kept) == 1
    assert contains?(
      stderr_of(kept),
      "Cargo.gen.lock conflict beyond what regenerating can settle"
    )
    assert as_tester(work, %w[rev-parse HEAD]) == before
    rm_rf(root)
  end
end

test "a lock conflict beside a source conflict in one commit stops the land, names the source and settles nothing"
  if self_exe != nil
    root = landing_fixture
    work = path_join(root, "work")
    locks_on_main(root)
    committed(
      work,
      retsu::concat_lists(
        cargo_files(["base"], ["bee"]),
        [["source.txt", unlines(["topic"])]]
      ),
      "bee"
    )
    before = as_tester(work, %w[rev-parse HEAD])
    main_moves(
      root,
      retsu::concat_lists(
        cargo_files(%w[ant base], []),
        [["source.txt", unlines(["main"])]]
      )
    )
    r = land_with(on_path(fake_locks(root)), root, [])
    assert status_of(r) == 1
    assert contains?(stderr_of(r), "source.txt")
    assert contains?(stderr_of(r), "beyond what regenerating can settle")
    assert as_tester(work, %w[rev-parse HEAD]) == before
    assert calls_of(root, "cargo") == []
    rm_rf(root)
  end
end

test "a green batch lands whole in one run, and a red one is halved until the land that breaks it is alone and blamed, as LANDING L1 asks"
  breaks = fn(bad)
    fn(b)
      if find_first((x) -> member?(x, bad), b).nil?
        {verdict: :green, why: ""}
      else
        {verdict: :red, why: "#{join(bad, " ")} red with #{join(b, " ")}"}
      end
    end
  end
  green = bisect(%w[a b c d], nil, breaks([]))
  assert green[:landed] == %w[a b c d]
  assert green[:tried] == [%w[a b c d]]
  c = bisect(%w[a b c d], nil, breaks(["c"]))
  assert c[:landed] == %w[a b d]
  assert c[:blamed] == [["c", "c red with c"]]
  assert c[:tried] == [%w[a b c d], %w[a b], ["c"], ["d"]]
  d = bisect(%w[a b c d], nil, breaks(["d"]))
  assert d[:landed] == %w[a b c]
  assert d[:blamed] == [["d", "d red with a b c d"]]
  assert d[:tried] == [%w[a b c d], %w[a b], ["c"]]
  lead = bisect(%w[a b c d], nil, breaks(["a"]))
  assert lead[:landed] == %w[b c d]
  assert map((p) -> first(p), lead[:blamed]) == ["a"]
  assert lead[:tried] == [%w[a b c d], %w[a b], ["a"], ["b"], %w[c d]]
  two = bisect(%w[a b c d e], nil, breaks(%w[b e]))
  assert two[:landed] == %w[a c d]
  assert map((p) -> first(p), two[:blamed]) == %w[b e]
  assert two[:left] == []
end

test "a batch that cannot hold a turn stops and leaves its undecided lands queued, and a lone land is the single land it was"
  stuck = bisect(
    %w[a b c d],
    nil,
    fn(b)
      if count(b) == 4
        {verdict: :red, why: "red"}
      else
        {verdict: :halt, why: "main moved 3 times"}
      end
    end
  )
  assert stuck[:landed] == []
  assert stuck[:blamed] == []
  assert stuck[:left] == %w[a b c d]
  assert stuck[:halted] == "main moved 3 times"
  assert stuck[:tried] == [%w[a b c d], %w[a b]]
  alone = bisect(["a"], nil, (_b) -> {verdict: :red, why: "run 7 is red"})
  assert alone[:blamed] == [["a", "run 7 is red"]]
  assert alone[:tried] == [["a"]]
  assert halves(%w[a b]) == [["a"], ["b"]]
end

test "a batch is the lands queued after its leader, in queue order, without a decided ticket, up to its cap"
  listed = unlines(
    [
      "1\trefs/heads/land-queue/20261110140000/lead",
      "2\trefs/heads/land-queue/20261110130000/older",
      "3\trefs/heads/land-queue/20261110160000/third",
      "4\trefs/heads/land-queue/20261110150000/second",
      "5\trefs/heads/land-queue/20261110155000/decided",
      "6\trefs/heads/land-verdict/20261110155000/decided"
    ]
  )
  queue = undecided(tickets_of(listed, 0), listed)
  assert map((t) -> t[:ref], queue) ==
    %w[land/lead land/older land/third land/second]
  behind = batch_of(queue, "land/lead", 20_261_110_140_000)
  assert map((t) -> t[:ref], behind) == %w[land/second land/third]
  assert head_of(listed, first(behind)[:name]) == "4"
  many = tickets_of(
    unlines(
      map(
        fn(i)
          "#{to_s(i)}\trefs/heads/land-queue/#{to_s(20_261_110_150_010 + i)}/l#{to_s(i)}"
        end,
        range(12)
      )
    ),
    0
  )
  assert count(batch_of(many, "land/lead", 0)) == batch_cap - 1
  assert waits_behind(queue, "land/lead", 20_261_110_140_000, [], 0)[:ref] ==
    "land/older"
  assert map((v) -> v[:ref], verdicts_of(listed)) == ["land/decided"]
end

test "a verdict is read back as it was written, so a blamed land's watch exits with the reason"
  red = verdict_of(
    verdict_text(false, "run 42 is red at ci / check / cargo-test")
  )
  assert not red[:landed]
  assert red[:why] == "run 42 is red at ci / check / cargo-test"
  assert verdict_of(verdict_text(true, "main is 1234567"))[:landed]
  assert verdict_of("").nil?
  assert batch_ref?(land_ref(scoped_slug("batch-x", "prose"), false))
  assert not batch_ref?(land_ref(scoped_slug("x", "whole"), false))
end

def batch_gh(root, on_list)
  bin = path_join(root, "batch-bin")
  mkdir_p(bin)
  write_program(
    path_join(root, "batch-gh.b"),
    unlines(
      retsu::concat_lists(
        retsu::concat_lists(
          [
            "use(\"shisutemu\", %i[status_of stdout_of])",
            "log = \"#{root}/gh.log\"",
            "prior = if path_exists(log)",
            "  read_file(log)",
            "else",
            "  \"\"",
            "end",
            "args = join(argv, \" \")",
            "write_file(log, join([prior, unlines([args])], \"\"))",
            "if contains?(args, \"auto-release.yml\")",
            "  write_stdout(\"[]\")",
            "elsif contains?(args, \"land.yml --limit\")"
          ],
          on_list
        ),
        [
          "  write_stdout(\"[]\")",
          "elsif contains?(args, \"--branch\")",
          "  id = 100 + count(filter((l) -> contains?(l, \"--branch\"), split(prior, line_break)))",
          "  write_file(concat(\"#{root}/run-\", to_s(id)), argv_get(7))",
          "  write_stdout(to_s(id))",
          "elsif contains?(args, \"status,conclusion\")",
          "  sha = read_file(concat(\"#{root}/run-\", argv_get(2)))",
          "  red = status_of(exec_capture(\"git\", \"-C\", \"#{root}/origin.git\", \"cat-file\", \"-e\", concat(sha, \":breaks.txt\"))) == 0",
          "  if not red",
          "    #{fast_forward("sha", root)}",
          "  end",
          "  write_stdout(if red",
          "    \"{\\\"status\\\":\\\"completed\\\",\\\"conclusion\\\":\\\"failure\\\"}\"",
          "  else",
          "    \"{\\\"status\\\":\\\"completed\\\",\\\"conclusion\\\":\\\"success\\\"}\"",
          "  end)",
          "elsif contains?(args, \"--json jobs\")",
          "  write_stdout(\"[{\\\"name\\\":\\\"ci / check / cargo-test\\\",\\\"conclusion\\\":\\\"failure\\\",\\\"refused\\\":false,\\\"off\\\":false}]\")",
          "end"
        ]
      )
    )
  )
  script(
    path_join(bin, "gh"),
    unlines(
      ["#!/bin/sh", "exec #{self_exe} run --quiet #{root}/batch-gh.b -- \"$@\""]
    )
  )
  bin
end

def queued(root, branch, files, at)
  work = path_join(root, "work")
  as_tester(work, ["checkout", "-q", "-b", branch, "main"])
  committed(work, files, branch)
  name = ticket_name(at, "land/#{branch}")
  as_tester(work, ["push", "-q", "origin", "HEAD:refs/heads/#{name}"])
  as_tester(work, %w[checkout -q topic])
  name
end

def recently(seconds)
  stamp(rfc3339_of_ms(now_ms - seconds * 1000))
end

def watched(root, bin, flags)
  land_with(["PATH=#{bin}:#{getenv("PATH")}"], root, append(["--watch"], flags))
end

def branch_calls(root)
  filter(
    (l) -> contains?(l, "--branch"),
    moji::lines(read_file(path_join(root, "gh.log")))
  )
end

def remote_message(work, name)
  as_tester(work, ["fetch", "-q", "origin", "refs/heads/#{name}"])
  as_tester(work, %w[log -1 --format=%B FETCH_HEAD])
end

test "the land at the front of the queue tests the land queued behind it with it as one tree, and a green run lands both and tells the other its verdict"
  if self_exe != nil
    root = landing_fixture
    work = path_join(root, "work")
    committed(work, [%w[other.txt other]], "topic")
    lead = ticket_name(recently(120), "land/topic")
    as_tester(work, ["push", "-q", "origin", "HEAD:refs/heads/#{lead}"])
    member = queued(root, "member", [%w[member.txt member]], recently(60))
    r = watched(root, batch_gh(root, []), [])
    assert status_of(r) == 0
    assert contains?(
      stderr_of(r),
      "1 land(s) queued behind this one: land/member"
    )
    as_tester(work, %w[fetch -q origin])
    assert as_tester(
      work,
      %w[log --format=%s main..refs/remotes/origin/land/batch-topic]
    ) == join(%w[member topic], line_break)
    assert count(branch_calls(root)) == 1
    assert starts_with?(
      remote_message(work, verdict_name(member)),
      "land verdict: landed"
    )
    assert as_tester(work, ["ls-remote", "origin", "refs/heads/#{lead}"]) == ""
    assert as_tester(work, ["ls-remote", "origin", "refs/heads/#{member}"]) !=
      ""
    rm_rf(root)
  end
end

test "a red batch is halved: the leader lands alone and the land that breaks it is blamed without a run of its own, and --no-batch takes no one"
  if self_exe != nil
    root = landing_fixture
    work = path_join(root, "work")
    committed(work, [%w[other.txt other]], "topic")
    lead = ticket_name(recently(120), "land/topic")
    as_tester(work, ["push", "-q", "origin", "HEAD:refs/heads/#{lead}"])
    member = queued(root, "member", [%w[breaks.txt red]], recently(60))
    bin = batch_gh(root, [])
    r = watched(root, bin, [])
    assert status_of(r) == 0
    assert count(branch_calls(root)) == 2
    as_tester(work, %w[fetch -q origin])
    assert as_tester(
      work,
      %w[log --format=%s main..refs/remotes/origin/land/batch-topic]
    ) == "topic"
    said = remote_message(work, verdict_name(member))
    assert starts_with?(said, "land verdict: red")
    assert contains?(said, "is red at ci / check / cargo-test")
    rm_rf(root)
    root = landing_fixture
    work = path_join(root, "work")
    committed(work, [%w[other.txt other]], "topic")
    lead = ticket_name(recently(120), "land/topic")
    as_tester(work, ["push", "-q", "origin", "HEAD:refs/heads/#{lead}"])
    member = queued(root, "member", [%w[member.txt member]], recently(60))
    alone = watched(root, batch_gh(root, []), ["--no-batch"])
    assert status_of(alone) == 0
    assert map(
      (l) -> contains?(l, "--branch land/topic"),
      branch_calls(root)
    ) == [true]
    assert as_tester(
      work,
      ["ls-remote", "origin", "refs/heads/#{verdict_name(member)}"]
    ) == ""
    rm_rf(root)
  end
end

test "a queued land whose batch blamed it ends its watch with the reason and leaves the queue, and never pushes a land of its own"
  if self_exe != nil
    root = landing_fixture
    work = path_join(root, "work")
    committed(work, [%w[other.txt other]], "topic")
    head = as_tester(work, %w[rev-parse HEAD])
    mine = ticket_name(recently(60), "land/topic")
    as_tester(work, ["push", "-q", "origin", "HEAD:refs/heads/#{mine}"])
    writes = [
      "  if not path_exists(\"#{root}/verdict-written\")",
      "    write_file(\"#{root}/verdict-written\", \"\")",
      "    sha = trim(stdout_of(exec_capture(\"git\", \"-C\", \"#{work}\", \"commit-tree\", \"#{head}^{tree}\", \"-p\", \"#{head}\", \"-m\", \"land verdict: red\", \"-m\", \"run 7 is red at ci / check / cargo-test\")))",
      "    exec_capture(\"git\", \"-C\", \"#{work}\", \"push\", \"-q\", \"origin\", concat(sha, \":refs/heads/#{verdict_name(mine)}\"))",
      "  end"
    ]
    r = watched(root, batch_gh(root, writes), [])
    assert status_of(r) == 1
    assert contains?(stderr_of(r), "run 7 is red at ci / check / cargo-test")
    assert as_tester(
      work,
      %w[ls-remote origin refs/heads/land-queue/* refs/heads/land-verdict/*]
    ) == ""
    assert as_tester(work, %w[ls-remote origin refs/heads/land/topic]) == ""
    rm_rf(root)
  end
end

test "land.yml starts every workflow a push to main starts, since its fast-forward pushes with a token that starts none, as post-merge started no run on any land after 110d3b86 (run 43017445507) until 43072181560 was dispatched by hand"
  dir = path_join(getenv("GEN_ROOT", cwd), ".github/workflows")
  started = dispatched_of(read_file(path_join(dir, "land.yml")))
  assert member?("post-merge.yml", started)
  names = map(
    (p) -> retsu::last(split(p, "/")),
    filter((p) -> ends_with?(p, ".yml"), walk_dir(dir))
  )
  skipped = undispatched
  missed = filter(
    fn(n)
      main_push_of(read_file(path_join(dir, n))) == :all and
        not member?(n, started) and
        get(skipped, n).nil?
    end,
    names
  )
  assert missed == []
  assert member?("post-merge.yml", names)
  assert main_push_of(read_file(path_join(dir, "post-merge.yml"))) == :all
end

test "land.yml refuses a batch at a step of its own while BLUE_LAND_BATCH is off, before the turn, and both turns read the variable"
  land = source(".github/workflows/land.yml")
  ci = source(".github/workflows/ci.yml")
  assert contains?(land, "name: #{batch_off_step}")
  assert length(before_first(land, "name: #{batch_off_step}")) <
    length(before_first(land, "name: #{turn_step}"))
  assert contains?(land, "BLUE_LAND_BATCH: ${{ vars.BLUE_LAND_BATCH }}")
  assert contains?(ci, "BLUE_LAND_BATCH: ${{ vars.BLUE_LAND_BATCH }}")
end

test "the turn refuses a batch while BLUE_LAND_BATCH is off and holds the same land when it is not a batch"
  if self_exe != nil
    root = landing_fixture
    work = path_join(root, "work")
    committed(work, [%w[other.txt other]], "topic")
    free = fake_runs_gh(root, "[]", "[]")
    turn = fn(ref)
      exec_capture(
        "env",
        "-u",
        "GEN_ROOT",
        "-C",
        work,
        "PATH=#{free}:#{getenv("PATH")}",
        "BLUE_LAND_BATCH=off",
        *flatten_args(
          ["--turn", "100", ref, as_tester(work, %w[rev-parse HEAD])]
        )
      )
    end
    off = turn("land/batch-topic")
    assert stdout_of(off) == "false"
    assert contains?(stderr_of(off), "batching is off")
    assert stdout_of(turn("land/topic")) == "true"
    rm_rf(root)
  end
end

def lead_topic(root, files)
  work = path_join(root, "work")
  committed(work, files, "topic")
  lead = ticket_name(recently(120), "land/topic")
  as_tester(work, ["push", "-q", "origin", "HEAD:refs/heads/#{lead}"])
  lead
end

def between(work, ref)
  as_tester(work, %w[fetch -q origin])
  trim(
    stdout_of(
      exec_capture(
        "git",
        "-C",
        work,
        "log",
        "--format=%s",
        "main..refs/remotes/origin/#{ref}"
      )
    )
  )
end

def pushed_refs(root)
  map((l) -> before_first(after_first(l, "--branch "), " "), branch_calls(root))
end

def alone_mark(work, ticket)
  as_tester(
    work,
    ["ls-remote", "origin", "refs/heads/land-alone/#{after_first(ticket, "/")}"]
  )
end

test "a batch is named after the first land it holds, so the back half of a red batch whose leader broke it runs on its own name, never on the leader's, as land/batch-service/component-bidamas' run 43028336649 of 2026-11-11 did"
  if self_exe != nil
    root = landing_fixture
    work = path_join(root, "work")
    lead_topic(root, [%w[breaks.txt red]])
    member = queued(root, "member", [%w[member.txt member]], recently(60))
    r = watched(root, batch_gh(root, []), [])
    assert status_of(r) == 1
    assert contains?(stderr_of(r), "blamed")
    assert pushed_refs(root) ==
      %w[land/batch-topic land/batch-topic land/batch-member]
    assert between(work, "land/batch-topic") == "topic"
    assert between(work, "land/batch-member") == "member"
    assert starts_with?(
      remote_message(work, verdict_name(member)),
      "land verdict: landed"
    )
    rm_rf(root)
  end
end

test "a leader whose HEAD another git moved off its commits is not claimed by the batch: the batch runs on its member's name, and the leader, landed alone, exits 1 naming the commit main lacks"
  if self_exe != nil
    root = landing_fixture
    work = path_join(root, "work")
    lead_topic(root, [%w[other.txt other]])
    member = queued(root, "member", [%w[member.txt member]], recently(60))
    moves = [
      "  if not path_exists(\"#{root}/detached\")",
      "    write_file(\"#{root}/detached\", \"\")",
      "    exec_check(\"git\", \"-C\", \"#{work}\", \"checkout\", \"-q\", \"--detach\", \"origin/main\")",
      "  end"
    ]
    r = watched(root, batch_gh(root, moves), ["topic"])
    assert status_of(r) == 1
    assert contains?(stderr_of(r), "the batch tree does not hold land/topic")
    assert contains?(
      stderr_of(r),
      "this land holds topic, but its worktree is now on a detached HEAD"
    )
    assert as_tester(work, %w[ls-remote origin refs/heads/land/batch-topic]) ==
      ""
    assert between(work, "land/batch-member") == "member"
    assert starts_with?(
      remote_message(work, verdict_name(member)),
      "land verdict: landed"
    )
    rm_rf(root)
  end
end

test "a member the batch tree does not hold is told so beside its ticket, keeps its ticket and gets no verdict, and the batch lands without it"
  if self_exe != nil
    root = landing_fixture
    work = path_join(root, "work")
    lines = (ls) -> unlines(ls)
    main_moves(root, [["lines.txt", lines(%w[a b c d e f g h])]])
    as_tester(work, %w[reset -q --hard main])
    lead_topic(root, [["lines.txt", lines(%w[a B c d e f g H])]])
    member = queued(
      root,
      "member",
      [["lines.txt", lines(%w[a B c d e f g h])]],
      recently(60)
    )
    r = watched(root, batch_gh(root, []), [])
    assert status_of(r) == 0
    assert contains?(stderr_of(r), "land/member is not in the batch")
    assert alone_mark(work, member) != ""
    assert alone_mark(work, member) == "" or
      contains?(
        remote_message(work, "land-alone/#{after_first(member, "/")}"),
        "lacks 1 of its commits"
      )
    assert as_tester(work, ["ls-remote", "origin", "refs/heads/#{member}"]) !=
      ""
    assert as_tester(
      work,
      ["ls-remote", "origin", "refs/heads/#{verdict_name(member)}"]
    ) == ""
    assert between(work, "land/batch-topic") == "topic"
    rm_rf(root)
  end
end

test "a queued land told it is not in a batch keeps its place and lands alone next, taking no land queued behind it"
  if self_exe != nil
    root = landing_fixture
    work = path_join(root, "work")
    committed(work, [%w[other.txt other]], "topic")
    head = as_tester(work, %w[rev-parse HEAD])
    mine = ticket_name(recently(60), "land/topic")
    as_tester(work, ["push", "-q", "origin", "HEAD:refs/heads/#{mine}"])
    queued(root, "later", [%w[later.txt later]], recently(30))
    told = "land-alone/#{after_first(mine, "/")}"
    writes = [
      "  if not path_exists(\"#{root}/told\")",
      "    write_file(\"#{root}/told\", \"\")",
      "    sha = trim(stdout_of(exec_capture(\"git\", \"-C\", \"#{work}\", \"commit-tree\", \"#{head}^{tree}\", \"-p\", \"#{head}\", \"-m\", \"batch 9 lacks 1 of its commits\")))",
      "    exec_capture(\"git\", \"-C\", \"#{work}\", \"push\", \"-q\", \"origin\", concat(sha, \":refs/heads/#{told}\"))",
      "  end"
    ]
    r = watched(root, batch_gh(root, writes), [])
    assert status_of(r) == 0
    assert contains?(stderr_of(r), "batch 9 lacks 1 of its commits")
    assert contains?(stderr_of(r), "lands alone next")
    assert pushed_refs(root) == ["land/topic"]
    assert as_tester(work, ["ls-remote", "origin", "refs/heads/#{told}"]) == ""
    rm_rf(root)
  end
end

test "a stale index lock in the land's own worktree stops the land before it rebases, naming the exact path, and another worktree's lock is neither read nor removed"
  if self_exe != nil
    root = landing_fixture
    work = path_join(root, "work")
    committed(work, [%w[other.txt other]], "topic")
    before = as_tester(work, %w[rev-parse HEAD])
    main_moves(root, [%w[notes/ant ant]])
    as_tester(
      work,
      ["worktree", "add", "-q", "--detach", path_join(root, "beside"), "main"]
    )
    theirs = as_tester(
      path_join(root, "beside"),
      %w[rev-parse --path-format=absolute --git-path index.lock]
    )
    lock = as_tester(
      work,
      %w[rev-parse --path-format=absolute --git-path index.lock]
    )
    write_file(theirs, "")
    write_file(lock, "")
    exec_capture("touch", "-t", "2001010000", lock)
    exec_capture("touch", "-t", "2001010000", theirs)
    r = land_in(root, [])
    assert status_of(r) == 1
    assert contains?(stderr_of(r), "#{lock} is older than this land")
    assert contains?(stderr_of(r), "rm #{lock}")
    assert path_exists(lock)
    assert as_tester(work, %w[rev-parse HEAD]) == before
    rm_rf(lock)
    assert status_of(land_in(root, [])) == 0
    assert path_exists(theirs)
    rm_rf(root)
  end
end

def land_state(root, slug)
  path_join(path_join(path_join(root, "work"), ".git/land"), slug)
end

def quick(root, bin, flags)
  land_with(
    ["PATH=#{bin}:#{getenv("PATH")}", "BLUE_LAND_POLL_SECONDS=1"],
    root,
    append(["--watch"], flags)
  )
end

def lands_of(root)
  work = path_join(root, "work")
  as_tester(work, %w[ls-remote origin refs/heads/land/*])
end

test "two lands of two branches keep two logs, each holding only its own land, as three lands of 2026-11-11 overwrote one shared land.log"
  if self_exe != nil
    root = landing_fixture
    work = path_join(root, "work")
    committed(work, [%w[other.txt other]], "topic")
    assert status_of(land_in(root, [])) == 0
    as_tester(work, %w[checkout -q -b second main])
    committed(work, [%w[second.txt second]], "second")
    assert status_of(land_in(root, [])) == 0
    one = path_join(land_state(root, "topic"), "land.log")
    two = path_join(land_state(root, "second"), "land.log")
    assert path_exists(one)
    assert path_exists(two)
    assert contains?(read_file(one), "is on land/topic")
    assert not contains?(read_file(one), "land/second")
    assert contains?(read_file(two), "is on land/second")
    assert not contains?(read_file(two), "land/topic")
    rm_rf(root)
  end
end

test "a land whose run is red ends saying where, on the terminal, in its log and in its exit record, as a land of 2026-11-12 exited 1 with no word"
  if self_exe != nil
    root = landing_fixture
    work = path_join(root, "work")
    committed(work, [%w[breaks.txt red]], "topic")
    r = quick(root, batch_gh(root, []), ["--no-batch"])
    assert status_of(r) == 1
    said = "run 100 is red at ci / check / cargo-test; fix it and land again"
    assert contains?(stderr_of(r), said)
    dir = land_state(root, "topic")
    assert contains?(read_file(log_of(dir)), said)
    assert exit_of(read_file(path_join(dir, "exit"))) == {code: 1, why: said}
    assert not path_exists(held_dir(dir))
    rm_rf(root)
  end
end

test "a ticket whose land stopped beating and has no live run is reaped by the next land, which says so, as a stale land-queue ticket stayed behind on 2026-11-12"
  if self_exe != nil
    root = landing_fixture
    work = path_join(root, "work")
    committed(work, [%w[other.txt other]], "topic")
    stale = ticket_name(recently(7200), "land/gone")
    as_tester(work, ["push", "-q", "origin", "HEAD:refs/heads/#{stale}"])
    r = quick(root, batch_gh(root, []), ["--no-batch"])
    assert status_of(r) == 0
    assert contains?(stderr_of(r), "reaped the stale ticket #{stale}")
    assert as_tester(work, ["ls-remote", "origin", "refs/heads/#{stale}"]) == ""
    rm_rf(root)
  end
end

test "a verdict whose ticket is gone is reaped by the next land, which says so, and a verdict beside its ticket stays, as six verdicts stayed behind on 2026-11-11 and 2026-11-12"
  if self_exe != nil
    root = landing_fixture
    work = path_join(root, "work")
    committed(work, [%w[other.txt other]], "topic")
    at = recently(7200)
    orphan = verdict_name(ticket_name(at, "land/gone"))
    waiting = ticket_name(at, "land/kept")
    beside = verdict_name(waiting)
    as_tester(
      work,
      [
        "push",
        "-q",
        "origin",
        "HEAD:refs/heads/#{orphan}",
        "HEAD:refs/heads/#{beside}",
        "HEAD:refs/heads/#{waiting}"
      ]
    )
    r = quick(root, batch_gh(root, []), ["--no-batch"])
    assert status_of(r) == 0
    assert contains?(stderr_of(r), "reaped the stale verdict #{orphan}")
    assert as_tester(work, ["ls-remote", "origin", "refs/heads/#{orphan}"]) ==
      ""
    assert as_tester(work, ["ls-remote", "origin", "refs/heads/#{beside}"]) !=
      ""
    rm_rf(root)
  end
end

test "a ticket that beats, or whose land's batch runs, is not reaped"
  assert stale_tickets(
    [{name: "q", at: 1, ref: "land/a"}],
    [{at: 9, ref: "land/a"}],
    [],
    "land/b",
    5
  ) == []
  assert stale_tickets(
    [{name: "q", at: 1, ref: "land/prose-a"}],
    [],
    ["land/prose-batch-a"],
    "land/b",
    5
  ) == []
end

test "a second --watch of a branch whose land runs attaches to it: it pushes nothing, cancels nothing, and ends with the first land's code and reason; a land without --watch refuses, as re-entered lands of 2026-11-12 re-pushed batch-h7/speed for two hours"
  if self_exe != nil
    root = landing_fixture
    work = path_join(root, "work")
    committed(work, [%w[other.txt other]], "topic")
    dir = land_state(root, "topic")
    mkdir_p(held_dir(dir))
    pid = trim(
      stdout_of(exec_capture("sh", "-c", "sleep 8 >/dev/null 2>&1 & echo $!"))
    )
    write_file(path_join(held_dir(dir), "pid"), unlines([pid, to_s(now_ms)]))
    write_file(log_of(dir), unlines(["land: following run 77"]))
    write_file(
      path_join(dir, "exit"),
      exit_text(0, "landed: run 77 is green and main holds land/topic")
    )
    bin = batch_gh(root, [])
    plain = land_in(root, [])
    assert status_of(plain) == 2
    assert contains?(stderr_of(plain), "runs as pid #{pid}")
    r = quick(root, bin, [])
    assert status_of(r) == 0
    assert contains?(stderr_of(r), "already runs as pid #{pid}")
    assert contains?(stderr_of(r), "land: following run 77")
    assert contains?(stderr_of(r), "landed: run 77 is green")
    assert not path_exists(path_join(root, "gh.log"))
    assert lands_of(root) == ""
    assert as_tester(work, %w[ls-remote origin refs/heads/land-queue/*]) == ""
    rm_rf(root)
  end
end

test "a lock whose land no longer runs is taken over and the land goes on"
  if self_exe != nil
    root = landing_fixture
    work = path_join(root, "work")
    committed(work, [%w[other.txt other]], "topic")
    dir = land_state(root, "topic")
    mkdir_p(held_dir(dir))
    write_file(path_join(held_dir(dir), "pid"), unlines(%w[999999 1]))
    r = quick(root, batch_gh(root, []), ["--no-batch"])
    assert status_of(r) == 0
    assert contains?(stderr_of(r), "took over the lock")
    assert not path_exists(held_dir(dir))
    rm_rf(root)
  end
end

test "two lands that join while a batch runs leave its run untouched, wait without pushing, and form the next batch together"
  if self_exe != nil
    root = landing_fixture
    work = path_join(root, "work")
    committed(work, [%w[other.txt other]], "topic")
    as_tester(work, %w[checkout -q -b member main])
    committed(work, [%w[member.txt member]], "member")
    sha = as_tester(work, %w[rev-parse HEAD])
    as_tester(work, %w[checkout -q topic])
    later = ticket_name(stamp(rfc3339_of_ms(now_ms + 120_000)), "land/member")
    running = [
      "  lists = count(filter((l) -> contains?(l, \"land.yml --limit\"), split(prior, line_break)))",
      "  if lists == 1",
      "    exec_capture(\"git\", \"-C\", \"#{work}\", \"push\", \"-q\", \"origin\", \"#{sha}:refs/heads/#{later}\")",
      "  end",
      "  if lists < 3",
      "    write_stdout(\"[{\\\"databaseId\\\":77,\\\"headBranch\\\":\\\"land/batch-lead\\\",\\\"status\\\":\\\"in_progress\\\",\\\"createdAt\\\":\\\"2026-01-01T00:00:00Z\\\"}]\")",
      "    exit_with(0)",
      "  end"
    ]
    r = quick(root, batch_gh(root, running), [])
    assert status_of(r) == 0
    calls = read_file(path_join(root, "gh.log"))
    assert not contains?(calls, "cancel")
    assert count(branch_calls(root)) == 1
    order = moji::lines(calls)
    first_push = first(
      filter((i) -> contains?(order[i], "--branch"), range(count(order)))
    )
    lists_before = count(
      filter((l) -> contains?(l, "land.yml --limit"), take(first_push, order))
    )
    assert lists_before > 3
    as_tester(work, %w[fetch -q origin])
    assert as_tester(
      work,
      %w[log --format=%s main..refs/remotes/origin/land/batch-topic]
    ) == join(%w[member topic], line_break)
    assert starts_with?(
      remote_message(work, verdict_name(later)),
      "land verdict: landed"
    )
    rm_rf(root)
  end
end

test "land.yml cancels a running land only when BLUE_LAND_CANCEL_IN_PROGRESS is on, so a second push to a batch's ref waits for the run instead of killing it"
  land = read_file(
    path_join(getenv("GEN_ROOT", cwd), ".github/workflows/land.yml")
  )
  assert contains?(
    land,
    "cancel-in-progress: ${{ vars.BLUE_LAND_CANCEL_IN_PROGRESS == 'on' }}"
  )
end
