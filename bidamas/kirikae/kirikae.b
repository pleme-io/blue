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

use("moji", [:lines, :take_chars])

use(
  "retsu",
  [:concat_lists, :drop_n, :drop_while, :first, :is_empty, :last, :rest, :size]
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
  if failures < 1 || get(pol, :base_ms) < 1
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
  foldl(
    fn(acc, e) streak_step(acc, e) end,
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
    s = streak(history, desired)
    wait = backoff_ms(get(s, :n), pol)
    if wait > 0 && now_ms < get(s, :last_ms) + wait
      {
        action: :hold,
        why: "#{to_s(get(s, :n))} failed activation(s) of #{store_name(desired)}; next try in #{to_s(floor((get(s, :last_ms) + wait - now_ms) / 1000))}s",
        until_ms: get(s, :last_ms) + wait
      }
    else
      {action: :switch, why: "#{label(desired)} differs from #{label(current)}"}
    end
  end
end

def label(p)
  if store_path?(p)
    "#{take_chars(store_hash(p), 8)}-#{store_name(p)}"
  else
    to_s(p)
  end
end

def parse_entry(line)
  d = try(json_parse(line), catch(_e(), nil))
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
    fn(e) e != nil end,
    map(
      fn(l) parse_entry(l) end,
      filter(fn(l) trim(l) != "" end, lines(read_or(path, "")))
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
  write_file(tmp, concat(join(map(fn(x) entry_line(x) end, kept), "\n"), "\n"))
  rename_file(tmp, path)
  e
end

def plan(flake, host, kind, current_link, hist, now_ms, pol)
  started = now_ns()
  b = plan_build(installable(flake, attr_for(kind, host)), [])
  if ok?(b)
    p = value(b)
    desired = first_out(p)
    current = resolve(current_link)
    d = decide(desired, current, hist, now_ms, pol)
    assoc(
      assoc(
        assoc(
          assoc(assoc(d, :desired, desired), :current, current),
          :build,
          size(get(p, :build))
        ),
        :fetch,
        size(get(p, :fetch))
      ),
      :plan_ms,
      floor(elapsed_since(started) / 1000000)
    )
  else
    {
      action: :refuse,
      why: "the system did not evaluate: #{to_s(refusal_of(b))}",
      refusal: refusal_of(b),
      plan_ms: floor(elapsed_since(started) / 1000000)
    }
  end
end

def settings()
  {
    flake: getenv("KIRIKAE_FLAKE", "."),
    host: getenv("KIRIKAE_HOST", trim(stdout_of_host())),
    kind: getenv("KIRIKAE_KIND", kind_of_host()),
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
  stdout_of(try(exec_capture("hostname", "-s"), catch(_e(), nil)))
end

def kind_of_host()
  if trim(stdout_of(try(exec_capture("uname", "-s"), catch(_e(), nil)))) ==
    "Linux"
    "nixos"
  else
    "darwin"
  end
end

def plan_now(s)
  plan(
    get(s, :flake),
    get(s, :host),
    get(s, :kind),
    get(s, :current),
    history(get(s, :history)),
    now_ms(),
    get(s, :policy)
  )
end

def summary(p)
  "kirikae: #{to_s(get(p, :action))} — #{get(p, :why)} (planned in #{to_s(get(p, :plan_ms))} ms; #{to_s(get(p, :build))} to build, #{to_s(get(p, :fetch))} to fetch)\n"
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
  after = drop_while(fn(a) a != "rebuild" end, cmd)
  get(
    foldl(fn(acc, a) node_step(acc, a) end, {skip: 0, node: nil}, rest(after)),
    :node
  )
end

def settings_for(cmd)
  n = node_arg(cmd)
  if n == nil
    settings()
  else
    assoc(settings(), :host, n)
  end
end

def run(cmd)
  s = settings_for(cmd)
  p = plan_now(s)
  write_stderr(summary(p))
  a = get(p, :action)
  if a == :noop && getenv("KIRIKAE_FORCE", "") == ""
    "noop"
  elsif a == :hold && getenv("KIRIKAE_FORCE", "") == ""
    throw(error(:hold, get(p, :why)))
  elsif a == :refuse
    throw(error(:refuse, get(p, :why)))
  else
    status = apply(exec_check, cmd)
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
        now_ms(),
        "#{last(cmd)} exited #{to_s(status)}"
      )
    )
    if status != 0
      throw(error(:switch_failed, "#{join(cmd, " ")} exited #{to_s(status)}"))
    end
    outcome
  end
end

def main()
  args = argv()
  verb = if is_empty(args)
    "plan"
  else
    first(args)
  end
  if verb == "plan"
    json_stringify(plan_now(settings()))
  elsif verb == "run"
    if size(args) < 2
      throw(error(:usage, "kirikae run <command> [args...]"))
    end
    run(rest(args))
  elsif verb == "record"
    if size(args) < 3
      throw(
        error(:usage, "kirikae record <store-path> <activated|failed> [why]")
      )
    end
    json_stringify(
      record(
        get(settings(), :history),
        entry(
          nth(1, args),
          nth(2, args),
          now_ms(),
          if size(args) > 3
            nth(3, args)
          else
            ""
          end
        )
      )
    )
  else
    throw(
      error(
        :usage,
        "kirikae plan | run <command> [args...] | record <store-path> <outcome> [why]"
      )
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
  assert get(decide(a(), a(), [], 0, pol), :action) == :noop
  assert get(decide(b(), a(), [], 0, pol), :action) == :switch
  assert get(decide(b(), nil, [], 0, pol), :action) == :switch
  assert get(decide(nil, a(), [], 0, pol), :action) == :refuse
  assert get(decide("/run/current-system", a(), [], 0, pol), :action) == :refuse
end

test "an exact system that keeps failing waits longer each time, and only that system"
  pol = policy(300, 3600)
  h = [entry(b(), "failed", 1000, "x"), entry(b(), "failed", 2000, "x")]
  d = decide(b(), a(), h, 3000, pol)
  assert get(d, :action) == :hold
  assert get(d, :until_ms) == 2000 + 600000
  assert get(decide(b(), a(), h, 2000 + 600000, pol), :action) == :switch
  assert get(
    decide(sys("00000000000000000000000000000000"), a(), h, 3000, pol),
    :action
  ) ==
    :switch
  assert backoff_ms(0, pol) == 0
  assert backoff_ms(1, pol) == 300000
  assert backoff_ms(5, pol) == 3600000
end

test "a success clears the streak, and a zero base never holds"
  pol = policy(300, 3600)
  h = [entry(b(), "failed", 1000, "x"), entry(b(), "activated", 2000, "ok")]
  assert get(streak(h, b()), :n) == 0
  assert get(decide(b(), a(), h, 2001, pol), :action) == :switch
  off = policy(0, 3600)
  assert get(
    decide(b(), a(), [entry(b(), "failed", 1000, "x")], 1001, off),
    :action
  ) ==
    :switch
  assert get(streak([], b()), :n) == 0
end

test "the history file round-trips and keeps only its tail"
  dir = path_join(getenv("TMPDIR", "/tmp"), "kirikae-test-#{to_s(now_ns())}")
  p = path_join(dir, "history.jsonl")
  assert history(p) == []
  record(p, entry(b(), "failed", 1000, "first"))
  record(p, entry(b(), "failed", 2000, "second"))
  h = history(p)
  assert size(h) == 2
  assert get(last(h), :why) == "second"
  assert get(streak(h, b()), :n) == 2
  write_file(p, "not json\n#{entry_line(entry(a(), "activated", 5, ""))}\n")
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
  d = decide(b(), a(), [], 0, policy(0, 0))
  assert label(b()) == "8i7qwqja-darwin-system-25.11.ebec37a"
  assert get(d, :why) ==
    "8i7qwqja-darwin-system-25.11.ebec37a differs from f97whj20-darwin-system-25.11.ebec37a"
  assert label(nil) == ""
end

test "the toplevel attribute follows the platform"
  assert attr_for("darwin", "ryn") == "darwinConfigurations.ryn.system"
  assert attr_for("nixos", "plo") ==
    "nixosConfigurations.plo.config.system.build.toplevel"
end
