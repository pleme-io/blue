use("deeta", [:get_int, :get_str])

use(
  "gamen",
  [
    :color_default,
    :duration_text,
    :show,
    :show_step,
    :step,
    :styled,
    :terminal?
  ]
)

use(
  "hyouka",
  [
    :first_out,
    :installable,
    :plan_build,
    :resolve,
    :store_hash,
    :store_name,
    :store_path?
  ]
)

use("kyohi", [:ok?, :refusal_of, :value])

use("moji", [:drop_chars, :includes, :lines, :take_chars, :trim])

use(
  "retsu",
  [
    :concat_lists,
    :drop_n,
    :drop_while,
    :first,
    :index_of,
    :is_empty,
    :last,
    :rest,
    :size,
    :take_n
  ]
)

use("shisutemu", [:read_or, :stdout_of])

def attr_for(kind, host)
  if kind == "nixos"
    "nixosConfigurations.#{host}.config.system.build.toplevel"
  else
    "darwinConfigurations.#{host}.system"
  end
end

def policy(base_s, cap_s)
  {base_ms: base_s * 1000, cap_ms: cap_s * 1000}
end

def backoff_ms(failures, pol)
  if failures < 1 or get(pol, :base_ms) < 1
    0
  else
    blue::min(get(pol, :cap_ms), get(pol, :base_ms) * expt(2, failures - 1))
  end
end

def entry(out, outcome, at_ms, why)
  {out:, outcome:, at_ms:, why:}
end

def streak_step(acc, e)
  if get(e, :out) != get(acc, :out)
    acc
  elsif get(e, :outcome) == "failed"
    assoc(assoc(acc, :n, get(acc, :n) + 1), :last_ms, get(e, :at_ms))
  else
    assoc(assoc(acc, :n, 0), :last_ms, nil)
  end
end

def streak(history, out)
  reduce(streak_step, {out:, n: 0, last_ms: nil}, history)
end

@doc """
decide: switch, hold or no-op from state and backoff.
"""
def decide(desired, current, history, now_ms, pol)
  if store_path?(desired) == false
    {action: :refuse, why: "no system to switch to: #{to_s(desired)}"}
  elsif desired == current
    {action: :noop, why: "the system already runs #{store_name(desired)}"}
  else
    h = hold_for(desired, history, now_ms, pol)
    if h.nil?
      {action: :switch, why: "#{label(desired)} differs from #{label(current)}"}
    else
      h
    end
  end
end

def hold_for(key, history, now_ms, pol)
  s = streak(history, key)
  wait = backoff_ms(get(s, :n), pol)
  if wait > 0 and now_ms < get(s, :last_ms) + wait
    {
      action: :hold,
      why: "#{to_s(get(s, :n))} failed attempt(s) of #{label(key)}; next try in #{to_s(floor((get(s, :last_ms) + wait - now_ms) / 1000))}s",
      until_ms: get(s, :last_ms) + wait,
      key:
    }
  end
end

def hex40?(t)
  length(t) == 40 and every?((c) -> includes("0123456789abcdef", c), chars(t))
end

def pinned?(flake)
  any?(hex40?, split(flake, "/")) or includes(flake, "rev=")
end

def label(p)
  if store_path?(p)
    "#{take_chars(store_hash(p), 8)}-#{store_name(p)}"
  else
    to_s(p)
  end
end

def parse_entry(line)
  d = json_parse(line) rescue nil
  if d.nil?
    nil
  else
    assoc(
      entry(
        get_str(d, "out", ""),
        get_str(d, "outcome", ""),
        get_int(d, "at_ms", 0),
        get_str(d, "why", "")
      ),
      :plan_ms,
      get_int(d, "plan_ms", 0)
    )
  end
end

def history(path)
  filter(
    (e) -> e != nil,
    map(parse_entry, filter((l) -> trim(l) != "", lines(read_or(path, ""))))
  )
end

def entry_line(e)
  json_stringify(
    {
      out: get(e, :out),
      outcome: get(e, :outcome),
      at_ms: get(e, :at_ms),
      why: get(e, :why),
      plan_ms: get(e, :plan_ms) or 0
    }
  )
end

def keep_last(xs, n)
  if size(xs) > n
    drop_n(xs, size(xs) - n)
  else
    xs
  end
end

@doc """
record: append one outcome to the switch history.
"""
def record(path, e)
  kept = keep_last(concat_lists(history(path), [e]), 200)
  mkdir_p(path_dirname(path))
  tmp = "#{path}.kirikae-tmp"
  write_file(tmp, concat(join(map(entry_line, kept), "\n"), "\n"))
  rename_file(tmp, path)
  e
end

@doc """
plan: what a system switch would do, as data.
"""
def plan(flake, host, kind, current_link, hist, now_ms, pol)
  inst = installable(flake, attr_for(kind, host))
  early = if pinned?(flake)
    hold_for(inst, hist, now_ms, pol)
  end
  if early.nil?
    evaluated(flake, inst, current_link, hist, now_ms, pol)
  else
    assoc(early, :plan_ms, 0)
  end
end

def evaluated(flake, inst, current_link, hist, now_ms, pol)
  started = now_ns
  b = plan_build(inst, [])
  ms = floor(elapsed_since(started) / 1_000_000)
  if ok?(b)
    p = value(b)
    desired = first_out(p)
    current = resolve(current_link)
    d = decide(desired, current, hist, now_ms, pol)
    assoc_all(
      d,
      [
        [:key, desired],
        [:desired, desired],
        [:current, current],
        [:build, size(get(p, :build))],
        [:fetch, size(get(p, :fetch))],
        [:plan_ms, ms]
      ]
    )
  else
    {
      action: :refuse,
      why: "the system did not evaluate: #{to_s(refusal_of(b))}",
      refusal: refusal_of(b),
      key: if pinned?(flake)
        inst
      end,
      plan_ms: ms
    }
  end
end

def assoc_all(m, pairs)
  reduce((acc, kv) -> assoc(acc, first(kv), nth(1, kv)), m, pairs)
end

def settings()
  {
    flake: getenv("KIRIKAE_FLAKE", "."),
    host: getenv("KIRIKAE_HOST", trim(stdout_of_host)),
    kind: getenv("KIRIKAE_KIND", kind_of_host),
    current: getenv("KIRIKAE_CURRENT", "/run/current-system"),
    verify: verify_flag(getenv("KIRIKAE_VERIFY_SWITCH", "1")),
    history: getenv(
      "KIRIKAE_HISTORY",
      path_join(getenv("HOME", "/tmp"), ".local/state/kirikae/history.jsonl")
    ),
    policy: policy(
      to_int(getenv("KIRIKAE_BACKOFF_BASE_S", "0")),
      to_int(getenv("KIRIKAE_BACKOFF_CAP_S", "21600"))
    ),
    wait_s: to_int(getenv("KIRIKAE_WAIT_S", "0")),
    poll_s: to_int(getenv("KIRIKAE_POLL_S", "15"))
  }
end

def stdout_of_host()
  stdout_of(exec_capture("hostname", "-s") rescue nil)
end

def kind_of_host()
  if trim(stdout_of(exec_capture("uname", "-s") rescue nil)) == "Linux"
    "nixos"
  else
    "darwin"
  end
end

def checkout_path(flake)
  if pinned?(flake)
    nil
  elsif flake == "." or starts_with?(flake, "/")
    flake
  elsif starts_with?(flake, "path:")
    drop_chars(flake, 5)
  elsif starts_with?(flake, "git+file://")
    first(split(drop_chars(flake, 11), "?"))
  end
end

def git_out(dir, args)
  cap = exec_with_env(
    [["GIT_TERMINAL_PROMPT", "0"]],
    "git",
    "-C",
    dir,
    *args
  ) rescue
    nil
  if cap.nil? or shisutemu::status_of(cap) != 0
    nil
  else
    trim(stdout_of(cap))
  end
end

def checkout_of(dir, branch)
  remote = git_out(dir, ["ls-remote", "origin", "refs/heads/#{branch}"])
  {
    head: git_out(dir, ["rev-parse", "HEAD"]),
    dirty: git_out(dir, ["status", "--porcelain", "--untracked-files=no"]),
    remote: if remote.nil?
      nil
    else
      first(split(remote, "\t"))
    end,
    branch:
  }
end

def checkout_refusal(c)
  if get(c, :head).nil?
    [:not_a_checkout, "the flake is not a git checkout kirikae can read"]
  elsif get(c, :dirty) != nil and get(c, :dirty) != ""
    [:dirty, "the checkout has uncommitted changes; plan a committed rev"]
  elsif get(c, :remote).nil? or get(c, :remote) == ""
    [
      :remote_unknown,
      "origin's #{get(c, :branch)} could not be read, so the checkout cannot be shown to be the published rev"
    ]
  elsif get(c, :head) != get(c, :remote)
    [
      :unpublished,
      "the checkout is at #{take_chars(get(c, :head), 8)} but origin's #{get(c, :branch)} is #{take_chars(get(c, :remote), 8)}; plan only the published rev"
    ]
  end
end

def base_name(t)
  last(split(t, "/"))
end

def writer_line?(l, host)
  ws = filter((w) -> w != "", split(trim(l), " "))
  heads = map(base_name, take_n(ws, 2))
  rebuild = member?("darwin-rebuild", heads) or member?("nixos-rebuild", heads)
  evaluation = not is_empty(ws) and
    base_name(first(ws)) == "nix" and
    any?((w) -> w == "build" or w == "eval", ws) and
    any?(
      (w) -> includes(w, "Configurations.#{host}") or ends_with?(w, "##{host}"),
      ws
    )
  rebuild or evaluation
end

def writers(ps_text, host)
  filter((l) -> writer_line?(l, host), lines(ps_text))
end

def ps_bin()
  if path_exists("/bin/ps")
    "/bin/ps"
  else
    "ps"
  end
end

def busy_refusal(ws)
  if is_empty(ws)
    nil
  else
    [
      :busy,
      "another evaluation or rebuild of this machine is running: #{take_chars(trim(first(ws)), 160)}",
      writer_of(first(ws))
    ]
  end
end

@doc """
writer_of: a writer's process line, shortened to its command and the rev it builds.

    writer_of("/nix/store/x-nix/bin/nix build --no-link github:o/r/b548e3a24f88a08d1c673ad27ac494293ac5cac1#ryn") #=> "nix build at b548e3a2"
"""
def writer_of(line)
  ws = filter((w) -> w != "", split(trim(line), " "))
  verb = filter((w) -> not starts_with?(w, "-"), take_n(rest(ws), 1))
  parts = reduce(
    (acc, w) -> concat_lists(acc, split(w, "/")),
    [],
    map((w) -> last(split(first(split(w, "#")), "=")), ws)
  )
  revs = filter(hex40?, parts)
  at = if is_empty(revs)
    ""
  else
    " at #{take_chars(first(revs), 8)}"
  end
  "#{join(concat_lists(map(base_name, take_n(ws, 1)), verb), " ")}#{at}"
end

def heartbeat_noop(hb_text, head, current)
  d = json_parse(hb_text) rescue nil
  if d.nil? or head.nil?
    nil
  elsif get_str(d, "outcome", "") == "unchanged" and
      get_str(d, "head_rev", "") == head
    {
      action: :noop,
      why: "the gitops loop already runs #{take_chars(head, 8)} (#{label(current)}); nothing evaluated",
      desired: current,
      current:,
      key: current,
      build: 0,
      fetch: 0,
      plan_ms: 0
    }
  end
end

def busy_hold(r, now)
  {action: :hold, why: nth(1, r), refusal: r, until_ms: now + 60000, plan_ms: 0}
end

def refused_plan(r)
  {action: :refuse, why: nth(1, r), refusal: r, plan_ms: 0}
end

@doc """
survey: the facts the guard judges: the checkout and its refusal, and a refusal naming another writer of the machine.

    get(survey({flake: "github:pleme-io/nix/b548e3a24f88a08d1c673ad27ac494293ac5cac1", host: "kirikae-no-such-host"}), :checkout) #=> nil
"""
def survey(s)
  dir = checkout_path(get(s, :flake))
  c = if dir.nil?
    nil
  else
    checkout_of(dir, getenv("KIRIKAE_BRANCH", "main"))
  end
  stale = if c.nil? or getenv("KIRIKAE_ALLOW_UNPUBLISHED", "") != ""
    nil
  else
    checkout_refusal(c)
  end
  busy = if getenv("KIRIKAE_ALLOW_CONCURRENT", "") != ""
    nil
  else
    busy_refusal(
      writers(
        stdout_of(exec_capture(ps_bin, "-axww", "-o", "command=") rescue nil),
        get(s, :host)
      )
    )
  end
  {checkout: c, stale:, busy:}
end

@doc """
guard_of: the guard's verdict on surveyed facts: a refusal, a busy hold, the loop's no-op, or nil to go on and plan.

    guard_of({checkout: nil, stale: nil, busy: nil}, {}) #=> nil
"""
def guard_of(f, s)
  c = get(f, :checkout)
  if get(f, :stale) != nil
    refused_plan(get(f, :stale))
  elsif get(f, :busy) != nil
    busy_hold(get(f, :busy), now_ms)
  elsif c != nil
    heartbeat_noop(
      read_or(
        getenv(
          "KIRIKAE_GITOPS_HEARTBEAT",
          "/var/log/pleme-gitops/heartbeat.json"
        ),
        ""
      ),
      get(c, :head),
      resolve(get(s, :current))
    )
  end
end

def guard(s)
  guard_of(survey(s), s)
end

@doc """
judged: the guard's surveyed facts with its verdict on them, so the guard's closing line can name both.

    get(get(judged({flake: "/nonexistent/kirikae", host: "kirikae-no-such-host"}), :verdict), :action) #=> :refuse
"""
def judged(s)
  f = survey(s)
  assoc(f, :verdict, guard_of(f, s))
end

@doc """
planned: guard, wait and plan, each told as a phase when the narration is full, and the plan they reach.

    get(planned({narrate: :off, flake: "/nonexistent/kirikae", host: "kirikae-no-such-host"}), :action) #=> :refuse
"""
def planned(s)
  d = {
    host: get(s, :host),
    poll_s: get(s, :poll_s),
    wait_s: get(s, :wait_s),
    current: get(s, :current)
  }
  g0 = get(phase(s, :guard, d, () -> judged(s)), :verdict)
  g = if g0 != nil and busy_hold?(g0)
    phase(
      s,
      :wait,
      assoc(d, :writer, nth(2, get(g0, :refusal))),
      () -> await_writers(s, g0, now_ms + get(s, :wait_s) * 1000, nil, 0)
    )
  else
    tell(
      s,
      :skipped,
      :wait,
      "no other writer of #{get(s, :host)} is running; nothing to wait for",
      nil
    )
    g0
  end
  if g.nil?
    phase(
      s,
      :plan,
      assoc(d, :expect, expected_plan(history(get(s, :history)))),
      () -> plan_unguarded(s)
    )
  else
    tell(
      s,
      :skipped,
      :plan,
      "the guard decided before any evaluation: #{to_s(get(g, :action))}",
      nil
    )
    g
  end
end

def plan_now(s)
  planned(s)
end

def plan_unguarded(s)
  plan(
    get(s, :flake),
    get(s, :host),
    get(s, :kind),
    get(s, :current),
    history(get(s, :history)),
    now_ms,
    get(s, :policy)
  )
end

def summary(p)
  work = if get(p, :build).nil?
    ""
  else
    " (planned in #{to_s(get(p, :plan_ms))} ms; #{to_s(get(p, :build))} to build, #{to_s(get(p, :fetch))} to fetch)"
  end
  "kirikae: #{to_s(get(p, :action))} — #{get(p, :why)}#{work}\n"
end

def node_step(acc, a)
  if get(acc, :skip) > 0
    assoc(acc, :skip, get(acc, :skip) - 1)
  elsif get(acc, :node) != nil
    acc
  elsif a == "--nix-option"
    assoc(acc, :skip, 2)
  elsif starts_with?(a, "-")
    acc
  else
    assoc(acc, :node, a)
  end
end

def node_arg(cmd)
  after = drop_while((a) -> a != "rebuild", cmd)
  get(reduce(node_step, {skip: 0, node: nil}, rest(after)), :node)
end

def settings_for(cmd)
  n = node_arg(cmd)
  if n.nil?
    settings
  else
    assoc(settings, :host, n)
  end
end

def busy_hold?(p)
  get(p, :action) == :hold and first(get(p, :refusal)) == :busy
end

def keep_waiting?(p, now, deadline_ms)
  busy_hold?(p) and now < deadline_ms
end

@doc """
say_wait?: true when the waiting line changed or a minute passed since it was printed, so a long wait shows it is alive.

    say_wait?("a", "a", 60000, 0) #=> true
"""
def say_wait?(why, said, now, said_ms)
  why != said or now - said_ms >= 60000
end

@doc """
waiting_note: the line a long wait repeats: who holds the machine and how long kirikae will still wait.

    waiting_note("darwin-rebuild build at b548e3a2", 1500000) #=> "still held by darwin-rebuild build at b548e3a2; 25m 00s left"
"""
def waiting_note(writer, left_ms)
  "still held by #{writer}; #{duration_text(left_ms)} left"
end

def await_writers(s, p, deadline_ms, said, said_ms)
  if keep_waiting?(p, now_ms, deadline_ms)
    spoke = said != nil and say_wait?(get(p, :why), said, now_ms, said_ms)
    if spoke
      tell(
        s,
        :running,
        :wait,
        waiting_note(nth(2, get(p, :refusal)), deadline_ms - now_ms),
        now_ms - deadline_ms + get(s, :wait_s) * 1000
      )
    end
    at = if spoke or said.nil?
      now_ms
    else
      said_ms
    end
    sleep(get(s, :poll_s))
    await_writers(s, guard(s), deadline_ms, get(p, :why), at)
  else
    p
  end
end

@doc """
run: build and activate the planned system.
"""
def run(cmd)
  s = assoc(
    settings_for(cmd),
    :narrate,
    narrate_level(getenv("KIRIKAE_NARRATE", "full"))
  )
  started = now_ms
  say(s, opening(s))
  p = planned(s)
  if get(s, :narrate) == :brief
    write_stderr(summary(p))
  end
  a = get(p, :action)
  forced = getenv("KIRIKAE_FORCE", "") != ""
  out = if a == :noop and not forced
    outcome_of(0, "noop")
  elsif a == :hold and not forced
    outcome_of(exit_hold, "hold")
  elsif a == :refuse
    if get(p, :key) != nil
      record(
        get(s, :history),
        assoc(
          entry(get(p, :key), "failed", now_ms, get(p, :why)),
          :plan_ms,
          get(p, :plan_ms) or 0
        )
      )
    end
    outcome_of(exit_refused, "refuse")
  end
  if out != nil
    tell(s, :skipped, :switch, "nothing to switch: #{get(p, :why)}", nil)
    tell(s, :skipped, :verify, "nothing was switched", nil)
    say(
      s,
      closing(
        "#{text_of(out)} — #{get(p, :why)}",
        get(out, :status),
        now_ms - started
      )
    )
    out
  else
    switched(s, p, cmd, started)
  end
end

@doc """
switched: hand the planned switch to the rebuild command, verify it, record the outcome, and close the run.

    text_of(switched({narrate: :off, history: path_join(getenv("TMPDIR", "/tmp"), "kirikae-doc", "history.jsonl"), current: "/nonexistent", verify: false}, {desired: "x"}, ["false"], 0)) #=> "failed"
"""
def switched(s, p, cmd, started)
  d = {
    host: get(s, :host),
    current: get(s, :current),
    ran: join(map(base_name, take_n(cmd, 2)), " "),
    plan: p,
    target: label(get(p, :desired))
  }
  status = phase(s, :switch, d, () -> exec_check(*cmd))
  v = if status == 0 and get(s, :verify)
    phase(
      s,
      :verify,
      d,
      () -> verify_switch(get(p, :desired), resolve(get(s, :current)))
    )
  else
    tell(
      s,
      :skipped,
      :verify,
      if status != 0
        "the switch failed, so there is nothing to verify"
      else
        "KIRIKAE_VERIFY_SWITCH is 0"
      end,
      nil
    )
    nil
  end
  out = settle(s, p, status, v, last(cmd))
  say(
    s,
    closing(
      "#{text_of(out)} #{label(get(p, :desired))}",
      get(out, :status),
      now_ms - started
    )
  )
  out
end

def settle(s, p, status, v, ran)
  if v != nil and get(s, :narrate) == :brief
    write_stderr("kirikae: #{to_s(get(v, :verdict))} — #{get(v, :why)}\n")
  end
  if v != nil and get(v, :verdict) == :not_switched
    record(
      get(s, :history),
      assoc(
        entry(get(p, :desired), "failed", now_ms, get(v, :why)),
        :plan_ms,
        get(p, :plan_ms) or 0
      )
    )
    outcome_of(exit_not_switched, "not-switched")
  else
    outcome = if status == 0
      "activated"
    else
      "failed"
    end
    record(
      get(s, :history),
      assoc(
        entry(
          get(p, :desired),
          outcome,
          now_ms,
          "#{ran} exited #{to_s(status)}"
        ),
        :plan_ms,
        get(p, :plan_ms) or 0
      )
    )
    outcome_of(status, outcome)
  end
end

@doc """
narrate_level: the KIRIKAE_NARRATE text as a level: full tells each phase before and after it runs, brief only the verdict, off nothing.

    narrate_level("brief") #=> :brief
"""
def narrate_level(t)
  if t == "full"
    :full
  elsif t == "brief"
    :brief
  elsif t == "off"
    :off
  else
    raise(:usage, "KIRIKAE_NARRATE is full, brief or off, not #{t}")
  end
end

@doc """
phases: the five phases of a run, in the order they run.

    phases #=> [:guard, :wait, :plan, :switch, :verify]
"""
def phases()
  [:guard, :wait, :plan, :switch, :verify]
end

@doc """
phase_line: one phase's step record: its state, its place among the phases, its name, a note and the time it took.

    get(phase_line(:done, :plan, "x", nil), :at) #=> 3
"""
def phase_line(state, name, note, ms)
  {
    state:,
    at: index_of(phases, name) + 1,
    of: size(phases),
    name: to_s(name),
    note:,
    ms:
  }
end

@doc """
tell: one phase line on stderr when the narration is full, and nothing otherwise.

    tell({narrate: :off}, :done, :guard, "clean", 12) #=> nil
"""
def tell(s, state, name, note, ms)
  if get(s, :narrate) == :full
    show_step(phase_line(state, name, note, ms), {})
  end
  nil
end

@doc """
say: a whole line on stderr when the narration is full, painted as the phase lines are.

    say({narrate: :off}, "x") #=> nil
"""
def say(s, node)
  if get(s, :narrate) == :full
    show(node, {to: :stderr, color: color_default and terminal?(2)})
  end
  nil
end

@doc """
phase: run one phase between the line that says what it will do and the line that says what it found, and return its result.

    phase({narrate: :off}, :switch, {ran: "x"}, () -> 0) #=> 0
"""
def phase(s, name, d, work)
  if get(s, :narrate) == :full
    tell(s, :running, name, lesson(name, d), nil)
  end
  t = now_ms
  r = work()
  if get(s, :narrate) == :full
    f = finding(name, assoc(d, :result, r))
    tell(s, first(f), name, nth(1, f), now_ms - t)
  end
  r
end

@doc """
expected_plan: the median time of the last five timed plans in a history and how many there were, or nil when none was timed.

    expected_plan([{plan_ms: 3000}, {plan_ms: 0}, {plan_ms: 1000}, {plan_ms: 2000}]) #=> {ms: 2000, n: 3}
"""
def expected_plan(hist)
  timed = keep_last(
    map(
      (e) -> get(e, :plan_ms),
      filter((e) -> (get(e, :plan_ms) or 0) > 0, hist)
    ),
    5
  )
  if is_empty(timed)
    nil
  else
    ms = sort_keyed((x) -> x, timed)
    {ms: nth(floor(size(ms) / 2), ms), n: size(ms)}
  end
end

@doc """
lesson: what a phase is about to do and why it matters, as one sentence for the line that opens it.

    lesson(:verify, {current: "/run/current-system", target: "abc"}) #=> "/run/current-system must now resolve to abc; a switch that exits 0 but leaves the old system counts as a failure"
"""
def lesson(name, d)
  host = get(d, :host)
  if name == :guard
    "is the checkout clean and at origin's rev, and is anything else evaluating or rebuilding #{host}? kirikae builds only a published rev, one writer at a time"
  elsif name == :wait
    "#{get(d, :writer)} is writing #{host} (often the gitops loop, sentinela, building the same machine); two writers race for one profile, so kirikae asks again every #{to_s(get(d, :poll_s))}s for up to #{duration_text(get(d, :wait_s) * 1000)}, then plans"
  elsif name == :plan
    e = get(d, :expect)
    usual = if e.nil?
      "no past plan is recorded to time it by"
    else
      "usually about #{duration_text(get(e, :ms))} (the median of the last #{to_s(get(e, :n))} timed plans)"
    end
    "nix build --dry-run evaluates #{host}'s whole system: it reads every module to find the one store path to switch to, and which paths are built here or fetched from a cache; nothing prints until it ends, #{usual}"
  elsif name == :switch
    p = get(d, :plan)
    work = if get(p, :build).nil?
      "what the plan names"
    else
      "the #{to_s(get(p, :build))} planned path(s) and fetches #{to_s(get(p, :fetch))}"
    end
    "#{get(d, :ran)} builds #{work}, then activates #{get(d, :target)}; its own output follows"
  else
    "#{get(d, :current)} must now resolve to #{get(d, :target)}; a switch that exits 0 but leaves the old system counts as a failure"
  end
end

@doc """
finding: what a phase found, as the state its closing line shows and one sentence.

    finding(:switch, {ran: "darwin-rebuild", result: 0}) #=> [:done, "darwin-rebuild exited 0"]
"""
def finding(name, d)
  r = get(d, :result)
  host = get(d, :host)
  if name == :guard
    v = get(r, :verdict)
    c = get(r, :checkout)
    if v.nil?
      at = if c.nil?
        "the flake is pinned"
      else
        "#{take_chars(get(c, :head), 8)} is origin's #{get(c, :branch)}"
      end
      [:done, "#{at}; no other writer of #{host}"]
    elsif busy_hold?(v)
      [:warn, "held by #{nth(2, get(v, :refusal))}"]
    elsif get(v, :action) == :refuse
      [:failed, get(v, :why)]
    else
      [:done, get(v, :why)]
    end
  elsif name == :wait
    if r != nil and busy_hold?(r)
      [:warn, "still held; kirikae holds (exit 75) and changes nothing"]
    else
      [:done, "#{host} is free"]
    end
  elsif name == :plan
    a = get(r, :action)
    if a == :switch
      [
        :done,
        "switch to #{label(get(r, :desired))}: #{to_s(get(r, :build))} to build, #{to_s(get(r, :fetch))} to fetch"
      ]
    elsif a == :noop
      [:done, get(r, :why)]
    elsif a == :hold
      [:warn, get(r, :why)]
    else
      [:failed, get(r, :why)]
    end
  elsif name == :switch
    [
      if r == 0
        :done
      else
        :failed
      end,
      "#{get(d, :ran)} exited #{to_s(r)}"
    ]
  else
    [
      get(
        {switched: :done, not_switched: :failed, unverified: :warn},
        get(r, :verdict)
      ),
      get(r, :why)
    ]
  end
end

@doc """
opening: the first line of a narrated run: what is rebuilt, from where, and the phases ahead.

    styled(opening({host: "ryn", kind: "darwin", flake: "."}), {color: false, theme: nil}) #=> "kirikae · rebuilding ryn (darwin) from . — guard, wait, plan, switch, verify"
"""
def opening(s)
  [
    {text: "kirikae", bold: true, ink: :bright_cyan},
    " · rebuilding ",
    {text: get(s, :host), bold: true},
    " (#{get(s, :kind)}) from #{get(s, :flake)}",
    {text: " — #{join(map(to_s, phases), ", ")}", ink: :bright_black}
  ]
end

@doc """
closing: the last line of a narrated run: a coloured circle for the verdict, the outcome, and how long the whole run took.

    styled(closing("activated", 0, 1051000), {color: false, theme: nil}) #=> "🟢 kirikae: activated (17m 31s)"
"""
def closing(text, status, ms)
  circle = if status == 0
    "🟢"
  elsif status == exit_hold
    "🟡"
  else
    "🔴"
  end
  [
    "#{circle} ",
    {text: "kirikae", bold: true, ink: :bright_cyan},
    ": #{text} ",
    {text: "(#{duration_text(ms)})", ink: :bright_black}
  ]
end

def verify_switch(desired, after)
  if store_path?(desired) == false
    {
      verdict: :unverified,
      why: "no planned system to compare /run/current-system against"
    }
  elsif after == desired
    {verdict: :switched, why: "the system now runs #{label(desired)}"}
  else
    {
      verdict: :not_switched,
      step: :activation,
      desired:,
      current: after,
      why: "the switch step did not take effect: built #{desired}, but the current system resolves to #{to_s(after)}"
    }
  end
end

def verify_flag(t)
  if t == "1"
    true
  elsif t == "0"
    false
  else
    raise(:usage, "KIRIKAE_VERIFY_SWITCH is 0 or 1, not #{t}")
  end
end

def exit_hold()
  75
end

def exit_not_switched()
  76
end

def exit_refused()
  78
end

def outcome_of(status, text)
  {status:, text:}
end

def exit_status_of(answer)
  if map?(answer)
    get(answer, :status)
  else
    0
  end
end

def text_of(answer)
  if map?(answer)
    get(answer, :text)
  else
    answer
  end
end

def main()
  a = answer(argv)
  write_stdout("#{text_of(a)}\n")
  if exit_status_of(a) != 0
    exit_with(exit_status_of(a))
  end
  nil
end

def answer(args)
  verb = if is_empty(args)
    "plan"
  else
    first(args)
  end
  if verb == "plan"
    ps = assoc(
      settings,
      :narrate,
      narrate_level(getenv("KIRIKAE_NARRATE", "brief"))
    )
    p = planned(ps)
    if get(ps, :narrate) == :brief
      write_stderr(summary(p))
    end
    json_stringify(p)
  elsif verb == "demo"
    join(
      map(
        (n) -> styled(n, {color: color_default and terminal?(1), theme: nil}),
        demo_lines
      ),
      "\n"
    )
  elsif verb == "run"
    if size(args) < 2
      raise(:usage, "kirikae run <command> [args...]")
    end
    run(rest(args))
  elsif verb == "record"
    if size(args) < 3
      raise(:usage, "kirikae record <store-path> <activated|failed> [why]")
    end
    json_stringify(
      record(
        get(settings, :history),
        entry(
          nth(1, args),
          nth(2, args),
          now_ms,
          if size(args) > 3
            nth(3, args)
          else
            ""
          end
        )
      )
    )
  else
    raise(
      :usage,
      "kirikae plan | run <command> [args...] | record <store-path> <outcome> [why] | demo"
    )
  end
end

@doc """
demo_lines: a whole narrated run on a scripted plan, line by line, built by the same words a real run prints with: a busy writer that clears, a plan with paths to build and fetch, a switch, and its verification.

    size(demo_lines) #=> 13
"""
def demo_lines()
  host = "ryn"
  s = {host:, kind: "darwin", flake: "."}
  desired = "/nix/store/8i7qwqjaxhlhb4k0n58i5yi96a7kw0h2-darwin-system-25.11.ebec37a"
  writer = "darwin-rebuild build at b548e3a2"
  busy = busy_hold(
    [:busy, "another evaluation or rebuild of this machine is running", writer],
    0
  )
  d = {
    host:,
    poll_s: 15,
    wait_s: 1800,
    current: "/run/current-system",
    writer:,
    expect: {ms: 551_000, n: 5},
    ran: "fleet rebuild",
    target: label(desired),
    plan: {action: :switch, desired:, build: 12, fetch: 340}
  }
  line = fn(name, result, ms)
    f = finding(name, assoc(d, :result, result))
    step(phase_line(first(f), name, nth(1, f), ms))
  end
  open = (name) -> step(phase_line(:running, name, lesson(name, d), nil))
  [
    opening(s),
    open(:guard),
    line(:guard, {checkout: nil, verdict: busy}, 412),
    open(:wait),
    step(phase_line(:running, :wait, waiting_note(writer, 1_740_000), 60000)),
    line(:wait, nil, 135_000),
    open(:plan),
    line(:plan, get(d, :plan), 548_000),
    open(:switch),
    line(:switch, 0, 362_000),
    open(:verify),
    line(:verify, verify_switch(desired, desired), 3),
    closing("activated #{label(desired)}", 0, 1_046_000)
  ]
end

def sys(h)
  "/nix/store/#{h}-darwin-system-25.11.ebec37a"
end

def a()
  sys("f97whj20l07gbd9ir1m3kd6lizx2mc1h")
end

def b()
  sys("8i7qwqjaxhlhb4k0n58i5yi96a7kw0h2")
end

test "the same system is nothing to do, a different one is a switch"
  pol = policy(0, 0)
  assert get(decide(a, a, [], 0, pol), :action) == :noop
  assert get(decide(b, a, [], 0, pol), :action) == :switch
  assert get(decide(b, nil, [], 0, pol), :action) == :switch
  assert get(decide(nil, a, [], 0, pol), :action) == :refuse
  assert get(decide("/run/current-system", a, [], 0, pol), :action) == :refuse
end

test "an exact system that keeps failing waits longer each time, and only that system"
  pol = policy(300, 3600)
  h = [entry(b, "failed", 1000, "x"), entry(b, "failed", 2000, "x")]
  d = decide(b, a, h, 3000, pol)
  assert get(d, :action) == :hold
  assert get(d, :until_ms) == 2000 + 600_000
  assert get(decide(b, a, h, 2000 + 600_000, pol), :action) == :switch
  assert get(
    decide(sys("00000000000000000000000000000000"), a, h, 3000, pol),
    :action
  ) == :switch
  assert backoff_ms(0, pol) == 0
  assert backoff_ms(1, pol) == 300_000
  assert backoff_ms(5, pol) == 3_600_000
end

test "a success clears the streak, and a zero base never holds"
  pol = policy(300, 3600)
  h = [entry(b, "failed", 1000, "x"), entry(b, "activated", 2000, "ok")]
  assert get(streak(h, b), :n) == 0
  assert get(decide(b, a, h, 2001, pol), :action) == :switch
  off = policy(0, 3600)
  assert get(
    decide(b, a, [entry(b, "failed", 1000, "x")], 1001, off),
    :action
  ) == :switch
  assert get(streak([], b), :n) == 0
end

test "the history file round-trips and keeps only its tail"
  dir = path_join(getenv("TMPDIR", "/tmp"), "kirikae-test-#{to_s(now_ns)}")
  p = path_join(dir, "history.jsonl")
  assert history(p) == []
  record(p, entry(b, "failed", 1000, "first"))
  record(p, entry(b, "failed", 2000, "second"))
  h = history(p)
  assert size(h) == 2
  assert get(last(h), :why) == "second"
  assert get(streak(h, b), :n) == 2
  write_file(p, "not json\n#{entry_line(entry(a, "activated", 5, ""))}\n")
  assert size(history(p)) == 1
  assert size(keep_last([1, 2, 3, 4], 2)) == 2
  assert keep_last([1, 2], 5) == [1, 2]
  rm_rf(dir)
end

test "the node a rebuild names is the host it plans for"
  assert node_arg(["fleet", "rebuild"]).nil?
  assert node_arg(["/x/bin/fleet", "rebuild", "--show-trace", "plo"]) == "plo"
  assert node_arg(["fleet", "rebuild", "--nix-option", "cores", "8", "rio"]) ==
    "rio"
  assert node_arg(["fleet", "rebuild", "--nix-option", "cores", "8"]).nil?
  assert node_arg(["darwin-rebuild"]).nil?
end

test "a switch names both systems by hash, since their names agree"
  d = decide(b, a, [], 0, policy(0, 0))
  assert label(b) == "8i7qwqja-darwin-system-25.11.ebec37a"
  assert get(d, :why) ==
    "8i7qwqja-darwin-system-25.11.ebec37a differs from f97whj20-darwin-system-25.11.ebec37a"
  assert label(nil) == ""
end

test "a refusal of a pinned revision holds before anything evaluates; a moving ref never does"
  pol = policy(300, 3600)
  pin = "github:pleme-io/nix/b548e3a24f88a08d1c673ad27ac494293ac5cac1"
  inst = installable(pin, attr_for("darwin", "ryn"))
  assert pinned?(pin) == true
  assert pinned?(".") == false
  assert pinned?("github:pleme-io/nix") == false
  assert pinned?("git+file:///x?rev=b548e3a24f88a08d1c673ad27ac494293ac5cac1") ==
    true
  h = [entry(inst, "failed", 1000, "eval"), entry(inst, "failed", 2000, "eval")]
  d = plan(pin, "ryn", "darwin", "/run/current-system", h, 3000, pol)
  assert get(d, :action) == :hold
  assert get(d, :key) == inst
  assert get(d, :plan_ms) == 0
  assert hold_for(inst, h, 2000 + 600_000, pol).nil?
  assert hold_for(inst, [], 3000, pol).nil?
end

test "only a clean checkout at origin's rev is planned"
  pub = "b548e3a24f88a08d1c673ad27ac494293ac5cac1"
  old = "cb22456a00000000000000000000000000000000"
  assert checkout_refusal(
    {head: pub, dirty: "", remote: pub, branch: "main"}
  ).nil?
  assert first(
    checkout_refusal({head: old, dirty: "", remote: pub, branch: "main"})
  ) == :unpublished
  assert first(
    checkout_refusal(
      {head: pub, dirty: " M flake.nix", remote: pub, branch: "main"}
    )
  ) == :dirty
  assert first(
    checkout_refusal({head: pub, dirty: "", remote: nil, branch: "main"})
  ) == :remote_unknown
  assert first(
    checkout_refusal({head: nil, dirty: nil, remote: pub, branch: "main"})
  ) == :not_a_checkout
  assert checkout_path(".") == "."
  assert checkout_path("/x/nix") == "/x/nix"
  assert checkout_path("git+file:///x/nix?ref=main") == "/x/nix"
  assert checkout_path("github:pleme-io/nix/#{pub}").nil?
  assert checkout_path("github:pleme-io/nix").nil?
end

test "a running evaluation or rebuild of this machine refuses the plan; others do not"
  ps = "/usr/sbin/cron\n/run/current-system/sw/bin/darwin-rebuild build --flake github:pleme-io/nix/abc#ryn -L\nnix build --no-link .#checks.aarch64-darwin.promotion-gate\n"
  assert size(writers(ps, "ryn")) == 1
  assert first(busy_refusal(writers(ps, "ryn"))) == :busy
  assert writers(
    "nix build --dry-run --json .#nixosConfigurations.rio.config.system.build.toplevel\n",
    "rio"
  ) != []
  assert writers(
    "nix build --dry-run --json .#nixosConfigurations.rio.config.system.build.toplevel\n",
    "plo"
  ) == []
  assert writers("blue run kirikae plan darwin-rebuild switch\n", "ryn") == []
  assert writers(
    "zsh -c pgrep -lf 'darwin-rebuild ' ; nix build #ryn\n",
    "ryn"
  ) == []
  assert size(
    writers(
      "/nix/store/x-nix-2.31.5/bin/nix build --no-link github:o/r/abc#ryn\n",
      "ryn"
    )
  ) == 1
  assert busy_refusal([]).nil?
  h = busy_hold([:busy, "x"], 1000)
  assert get(h, :action) == :hold
  assert get(h, :until_ms) == 61000
end

test "a run waits out another writer only while its wait lasts, and never a backoff hold"
  h = busy_hold([:busy, "x"], 1000)
  assert keep_waiting?(h, 1000, 2000)
  assert keep_waiting?(h, 2000, 2000) == false
  assert keep_waiting?(h, 1000, 1000) == false
  assert keep_waiting?({action: :hold, why: "backoff"}, 1000, 2000) == false
  assert keep_waiting?({action: :switch}, 1000, 2000) == false
  assert say_wait?("a", nil, 0, 0)
  assert say_wait?("a", "a", 30000, 0) == false
  assert say_wait?("a", "a", 60000, 0)
  assert say_wait?("b", "a", 1000, 0)
end

test "a loop that already runs the checkout's rev answers the plan without evaluating"
  head = "b548e3a24f88a08d1c673ad27ac494293ac5cac1"
  hb = "{\"outcome\":\"unchanged\",\"head_rev\":\"#{head}\"}"
  n = heartbeat_noop(hb, head, a)
  assert get(n, :action) == :noop
  assert get(n, :desired) == a
  assert heartbeat_noop(hb, "cb22456a00000000000000000000000000000000", a).nil?
  assert heartbeat_noop(
    "{\"outcome\":\"building\",\"head_rev\":\"#{head}\"}",
    head,
    a
  ).nil?
  assert heartbeat_noop("", head, a).nil?
end

test "a plan that evaluated nothing says so without empty counts"
  assert summary({action: :hold, why: "busy"}) == "kirikae: hold — busy\n"
  assert ends_with?(
    summary({action: :noop, why: "same", plan_ms: 5, build: 0, fetch: 0}),
    "0 to fetch)\n"
  ) == true
end

test "an outcome carries the exit status a caller branches on"
  assert exit_status_of(outcome_of(exit_hold, "hold")) == 75
  assert exit_status_of(outcome_of(exit_refused, "refuse")) == 78
  assert exit_status_of(outcome_of(0, "noop")) == 0
  assert exit_status_of("{\"action\":\"noop\"}") == 0
  assert text_of(outcome_of(75, "hold")) == "hold"
  assert text_of("plain") == "plain"
end

test "a command's answer is text it can print, and a wrong verb is a usage error"
  assert error?(
    begin
      answer(["bogus"])
    rescue e
      e
    end
  ) == true
  assert error?(
    begin
      answer(["run"])
    rescue e
      e
    end
  ) == true
end

test "a switch is verified against the system it built, naming both on a mismatch"
  assert get(verify_switch(b, b), :verdict) == :switched
  miss = verify_switch(b, a)
  assert get(miss, :verdict) == :not_switched
  assert get(miss, :step) == :activation
  assert includes(get(miss, :why), b) == true
  assert includes(get(miss, :why), a) == true
  assert get(verify_switch(b, nil), :verdict) == :not_switched
  assert get(verify_switch(nil, a), :verdict) == :unverified
end

test "a command that exits 0 without switching is a failure the history counts"
  dir = path_join(getenv("TMPDIR", "/tmp"), "kirikae-verify-#{to_s(now_ns)}")
  s = {history: path_join(dir, "history.jsonl")}
  p = {desired: b}
  out = settle(s, p, 0, verify_switch(b, a), "rebuild")
  assert exit_status_of(out) == exit_not_switched
  assert text_of(out) == "not-switched"
  assert get(streak(history(get(s, :history)), b), :n) == 1
  ok = settle(s, p, 0, verify_switch(b, b), "rebuild")
  assert exit_status_of(ok) == 0
  assert get(streak(history(get(s, :history)), b), :n) == 0
  assert exit_status_of(settle(s, p, 0, nil, "rebuild")) == 0
  rm_rf(dir)
end

test "the verify switch is 0 or 1 and nothing else"
  assert verify_flag("1") == true
  assert verify_flag("0") == false
  assert error?(
    begin
      verify_flag("yes")
    rescue e
      e
    end
  ) == true
end

test "the toplevel attribute follows the platform"
  assert attr_for("darwin", "ryn") == "darwinConfigurations.ryn.system"
  assert attr_for("nixos", "plo") ==
    "nixosConfigurations.plo.config.system.build.toplevel"
end

test "the narration level is full, brief or off and nothing else"
  assert narrate_level("full") == :full
  assert narrate_level("off") == :off
  assert error?(
    begin
      narrate_level("loud")
    rescue e
      e
    end
  ) == true
end

test "a writer is named by its command and the rev it builds, and by its command alone without one"
  assert writer_of("/run/current-system/sw/bin/darwin-rebuild build --flake github:pleme-io/nix/b548e3a24f88a08d1c673ad27ac494293ac5cac1#ryn -L") ==
    "darwin-rebuild build at b548e3a2"
  assert writer_of("nix build --dry-run .#darwinConfigurations.ryn.system") ==
    "nix build"
  assert writer_of("darwin-rebuild --flake .#ryn") == "darwin-rebuild"
  assert writer_of("") == ""
  assert nth(
    2,
    busy_refusal(
      ["nix eval git+file:///x?rev=b548e3a24f88a08d1c673ad27ac494293ac5cac1#ryn"]
    )
  ) == "nix eval at b548e3a2"
end

test "the expected plan time is the median of the last five timed plans, and nothing without one"
  assert expected_plan([]).nil?
  assert expected_plan([{plan_ms: 0}, {}]).nil?
  hist = map((ms) -> {plan_ms: ms}, [9, 1, 2, 3, 4, 5])
  assert expected_plan(hist) == {ms: 3, n: 5}
  assert expected_plan([{plan_ms: 7}]) == {ms: 7, n: 1}
end

test "a timed plan survives the history file"
  dir = path_join(getenv("TMPDIR", "/tmp"), "kirikae-timed-#{to_s(now_ns)}")
  p = path_join(dir, "history.jsonl")
  record(p, assoc(entry(b, "activated", 1000, "ok"), :plan_ms, 551_000))
  record(p, entry(b, "activated", 2000, "ok"))
  assert map((e) -> get(e, :plan_ms), history(p)) == [551_000, 0]
  assert expected_plan(history(p)) == {ms: 551_000, n: 1}
  rm_rf(dir)
end

test "each phase closes with the state its finding earns"
  busy = busy_hold([:busy, "x", "nix build"], 0)
  assert finding(
    :guard,
    {host: "ryn", result: {verdict: nil, checkout: nil}}
  ) == [:done, "the flake is pinned; no other writer of ryn"]
  assert first(finding(:guard, {result: {verdict: busy}})) == :warn
  assert first(
    finding(:guard, {result: {verdict: refused_plan([:dirty, "dirty"])}})
  ) == :failed
  assert first(finding(:wait, {result: busy})) == :warn
  assert finding(:wait, {host: "ryn", result: nil}) == [:done, "ryn is free"]
  assert first(finding(:plan, {result: {action: :hold, why: "h"}})) == :warn
  assert first(finding(:plan, {result: {action: :refuse, why: "r"}})) == :failed
  assert first(finding(:switch, {ran: "x", result: 1})) == :failed
  assert first(finding(:verify, {result: verify_switch(b, a)})) == :failed
  assert first(finding(:verify, {result: verify_switch(nil, a)})) == :warn
end

test "the demo renders every phase in order, plain when colour is off"
  plain = map((n) -> styled(n, {color: false, theme: nil}), demo_lines)
  assert first(plain) ==
    "kirikae · rebuilding ryn (darwin) from . — guard, wait, plan, switch, verify"
  assert nth(2, plain) ==
    "⚠️ [1/5] guard — held by darwin-rebuild build at b548e3a2 (0.4s)"
  assert nth(5, plain) == "✅ [2/5] wait — ryn is free (2m 15s)"
  assert nth(7, plain) ==
    "✅ [3/5] plan — switch to 8i7qwqja-darwin-system-25.11.ebec37a: 12 to build, 340 to fetch (9m 08s)"
  assert last(plain) ==
    "🟢 kirikae: activated 8i7qwqja-darwin-system-25.11.ebec37a (17m 26s)"
  assert map((l) -> take_chars(l, 1), take_n(rest(plain), 11)) ==
    ["⏳", "⚠", "⏳", "⏳", "✅", "⏳", "✅", "⏳", "✅", "⏳", "✅"]
end
