use("deeta", [:get_int, :get_str])

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

use("moji", [:drop_chars, :includes, :lines, :take_chars])

use(
  "retsu",
  [
    :concat_lists,
    :drop_n,
    :drop_while,
    :first,
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
  {out: out, outcome: outcome, at_ms: at_ms, why: why}
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
  reduce(
    (acc, e) -> streak_step(acc, e),
    {out: out, n: 0, last_ms: nil},
    history
  )
end

def decide(desired, current, history, now_ms, pol)
  if store_path?(desired) == false
    {action: :refuse, why: "no system to switch to: #{to_s(desired)}"}
  elsif desired == current
    {action: :noop, why: "the system already runs #{store_name(desired)}"}
  else
    h = hold_for(desired, history, now_ms, pol)
    if h == nil
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
      key: key
    }
  end
end

def hex40?(t)
  length(t) == 40 and every?((c) -> includes("0123456789abcdef", c), chars(t))
end

def pinned?(flake)
  any?((t) -> hex40?(t), split(flake, "/")) or includes(flake, "rev=")
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
  if d == nil
    nil
  else
    entry(
      get_str(d, "out", ""),
      get_str(d, "outcome", ""),
      get_int(d, "at_ms", 0),
      get_str(d, "why", "")
    )
  end
end

def history(path)
  filter(
    (e) -> e != nil,
    map(
      (l) -> parse_entry(l),
      filter((l) -> trim(l) != "", lines(read_or(path, "")))
    )
  )
end

def entry_line(e)
  json_stringify(
    {
      out: get(e, :out),
      outcome: get(e, :outcome),
      at_ms: get(e, :at_ms),
      why: get(e, :why)
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

def record(path, e)
  kept = keep_last(concat_lists(history(path), [e]), 200)
  mkdir_p(path_dirname(path))
  tmp = "#{path}.kirikae-tmp"
  write_file(tmp, concat(join(map((x) -> entry_line(x), kept), "\n"), "\n"))
  rename_file(tmp, path)
  e
end

def plan(flake, host, kind, current_link, hist, now_ms, pol)
  inst = installable(flake, attr_for(kind, host))
  early = if pinned?(flake)
    hold_for(inst, hist, now_ms, pol)
  end
  if early == nil
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
    history: getenv(
      "KIRIKAE_HISTORY",
      path_join(getenv("HOME", "/tmp"), ".local/state/kirikae/history.jsonl")
    ),
    policy: policy(
      to_int(getenv("KIRIKAE_BACKOFF_BASE_S", "0")),
      to_int(getenv("KIRIKAE_BACKOFF_CAP_S", "21600"))
    )
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
  if cap == nil or shisutemu::status_of(cap) != 0
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
    remote: if remote == nil
      nil
    else
      first(split(remote, "\t"))
    end,
    branch: branch
  }
end

def checkout_refusal(c)
  if get(c, :head) == nil
    [:not_a_checkout, "the flake is not a git checkout kirikae can read"]
  elsif get(c, :dirty) != nil and get(c, :dirty) != ""
    [:dirty, "the checkout has uncommitted changes; plan a committed rev"]
  elsif get(c, :remote) == nil or get(c, :remote) == ""
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
  heads = map((w) -> base_name(w), take_n(ws, 2))
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
      "another evaluation or rebuild of this machine is running: #{take_chars(trim(first(ws)), 160)}"
    ]
  end
end

def heartbeat_noop(hb_text, head, current)
  d = json_parse(hb_text) rescue nil
  if d == nil or head == nil
    nil
  elsif get_str(d, "outcome", "") == "unchanged" and
    get_str(d, "head_rev", "") == head
    {
      action: :noop,
      why: "the gitops loop already runs #{take_chars(head, 8)} (#{label(current)}); nothing evaluated",
      desired: current,
      current: current,
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

def guard(s)
  dir = checkout_path(get(s, :flake))
  c = if dir == nil
    nil
  else
    checkout_of(dir, getenv("KIRIKAE_BRANCH", "main"))
  end
  stale = if c == nil or getenv("KIRIKAE_ALLOW_UNPUBLISHED", "") != ""
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
  if stale != nil
    refused_plan(stale)
  elsif busy != nil
    busy_hold(busy, now_ms)
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

def plan_now(s)
  g = guard(s)
  if g != nil
    g
  else
    plan_unguarded(s)
  end
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
  work = if get(p, :build) == nil
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
  get(
    reduce((acc, a) -> node_step(acc, a), {skip: 0, node: nil}, rest(after)),
    :node
  )
end

def settings_for(cmd)
  n = node_arg(cmd)
  if n == nil
    settings
  else
    assoc(settings, :host, n)
  end
end

def run(cmd)
  s = settings_for(cmd)
  p = plan_now(s)
  write_stderr(summary(p))
  a = get(p, :action)
  if a == :noop and getenv("KIRIKAE_FORCE", "") == ""
    outcome_of(0, "noop")
  elsif a == :hold and getenv("KIRIKAE_FORCE", "") == ""
    outcome_of(exit_hold, "hold")
  elsif a == :refuse
    if get(p, :key) != nil
      record(
        get(s, :history),
        entry(get(p, :key), "failed", now_ms, get(p, :why))
      )
    end
    outcome_of(exit_refused, "refuse")
  else
    status = exec_check(*cmd)
    outcome = if status == 0
      "activated"
    else
      "failed"
    end
    record(
      get(s, :history),
      entry(
        get(p, :desired),
        outcome,
        now_ms,
        "#{last(cmd)} exited #{to_s(status)}"
      )
    )
    outcome_of(status, outcome)
  end
end

def exit_hold()
  75
end

def exit_refused()
  78
end

def outcome_of(status, text)
  {status: status, text: text}
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
    json_stringify(plan_now(settings))
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
      "kirikae plan | run <command> [args...] | record <store-path> <outcome> [why]"
    )
  end
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
  ) ==
    :switch
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
  ) ==
    :switch
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
  assert node_arg(["fleet", "rebuild"]) == nil
  assert node_arg(["/x/bin/fleet", "rebuild", "--show-trace", "plo"]) == "plo"
  assert node_arg(["fleet", "rebuild", "--nix-option", "cores", "8", "rio"]) ==
    "rio"
  assert node_arg(["fleet", "rebuild", "--nix-option", "cores", "8"]) == nil
  assert node_arg(["darwin-rebuild"]) == nil
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
  assert hold_for(inst, h, 2000 + 600_000, pol) == nil
  assert hold_for(inst, [], 3000, pol) == nil
end

test "only a clean checkout at origin's rev is planned"
  pub = "b548e3a24f88a08d1c673ad27ac494293ac5cac1"
  old = "cb22456a00000000000000000000000000000000"
  assert checkout_refusal(
    {head: pub, dirty: "", remote: pub, branch: "main"}
  ) ==
    nil
  assert first(
    checkout_refusal({head: old, dirty: "", remote: pub, branch: "main"})
  ) ==
    :unpublished
  assert first(
    checkout_refusal(
      {head: pub, dirty: " M flake.nix", remote: pub, branch: "main"}
    )
  ) ==
    :dirty
  assert first(
    checkout_refusal({head: pub, dirty: "", remote: nil, branch: "main"})
  ) ==
    :remote_unknown
  assert first(
    checkout_refusal({head: nil, dirty: nil, remote: pub, branch: "main"})
  ) ==
    :not_a_checkout
  assert checkout_path(".") == "."
  assert checkout_path("/x/nix") == "/x/nix"
  assert checkout_path("git+file:///x/nix?ref=main") == "/x/nix"
  assert checkout_path("github:pleme-io/nix/#{pub}") == nil
  assert checkout_path("github:pleme-io/nix") == nil
end

test "a running evaluation or rebuild of this machine refuses the plan; others do not"
  ps = "/usr/sbin/cron\n/run/current-system/sw/bin/darwin-rebuild build --flake github:pleme-io/nix/abc#ryn -L\nnix build --no-link .#checks.aarch64-darwin.promotion-gate\n"
  assert size(writers(ps, "ryn")) == 1
  assert first(busy_refusal(writers(ps, "ryn"))) == :busy
  assert writers(
    "nix build --dry-run --json .#nixosConfigurations.rio.config.system.build.toplevel\n",
    "rio"
  ) !=
    []
  assert writers(
    "nix build --dry-run --json .#nixosConfigurations.rio.config.system.build.toplevel\n",
    "plo"
  ) ==
    []
  assert writers("blue run kirikae plan darwin-rebuild switch\n", "ryn") == []
  assert writers(
    "zsh -c pgrep -lf 'darwin-rebuild ' ; nix build #ryn\n",
    "ryn"
  ) ==
    []
  assert size(
    writers(
      "/nix/store/x-nix-2.31.5/bin/nix build --no-link github:o/r/abc#ryn\n",
      "ryn"
    )
  ) ==
    1
  assert busy_refusal([]) == nil
  h = busy_hold([:busy, "x"], 1000)
  assert get(h, :action) == :hold
  assert get(h, :until_ms) == 61000
end

test "a loop that already runs the checkout's rev answers the plan without evaluating"
  head = "b548e3a24f88a08d1c673ad27ac494293ac5cac1"
  hb = "{\"outcome\":\"unchanged\",\"head_rev\":\"#{head}\"}"
  n = heartbeat_noop(hb, head, a)
  assert get(n, :action) == :noop
  assert get(n, :desired) == a
  assert heartbeat_noop(hb, "cb22456a00000000000000000000000000000000", a) ==
    nil
  assert heartbeat_noop(
    "{\"outcome\":\"building\",\"head_rev\":\"#{head}\"}",
    head,
    a
  ) ==
    nil
  assert heartbeat_noop("", head, a) == nil
end

test "a plan that evaluated nothing says so without empty counts"
  assert summary({action: :hold, why: "busy"}) == "kirikae: hold — busy\n"
  assert ends_with?(
    summary({action: :noop, why: "same", plan_ms: 5, build: 0, fetch: 0}),
    "0 to fetch)\n"
  ) ==
    true
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
  ) ==
    true
  assert error?(
    begin
      answer(["run"])
    rescue e
      e
    end
  ) ==
    true
end

test "the toplevel attribute follows the platform"
  assert attr_for("darwin", "ryn") == "darwinConfigurations.ryn.system"
  assert attr_for("nixos", "plo") ==
    "nixosConfigurations.plo.config.system.build.toplevel"
end
