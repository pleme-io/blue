use("kazu", [:abs, :max, :min])
use("retsu", [:first, :index_of, :is_empty, :last, :rest, :size, :zip])
use("settei", [:env_of, :no_env, :resolve])

use(
  "shisutemu",
  [:last_nonempty_line, :read_or, :status_of, :stderr_of, :stdout_of]
)

def moving(rate)
  {verdict: "moving", rate:}
end

def stalled(since)
  {verdict: "stalled", since:}
end

def blind(why)
  {verdict: "blind", why:}
end

def queued_behind(generation, observed, phase)
  {verdict: "queued-behind", generation:, observed:, behind: phase}
end

def settled(generation, phase)
  {verdict: "settled", generation:, phase:}
end

def verdict(v)
  get(v, :verdict)
end

def sample(at_ms, value)
  {at_ms:, value:}
end

def failed_sample(at_ms, why)
  {at_ms:, error: why}
end

def failed?(s)
  get(s, :error) != nil or number?(get(s, :value)) == false
end

def trailing_since(samples)
  last_value = get(last(samples), :value)
  reduce(
    fn(acc, s)
      if get(s, :value) == last_value
        if acc.nil?
          get(s, :at_ms)
        else
          acc
        end
      end
    end,
    nil,
    samples
  )
end

def travelled(samples)
  reduce(
    fn(acc, pair)
      acc + abs(get(second(pair), :value) - get(first(pair), :value))
    end,
    0,
    zip(samples, rest(samples))
  )
end

def progress(samples, window_s)
  if size(samples) < 2
    blind("#{size(samples)} sample(s); progress needs two or more")
  elsif any?(failed?, samples)
    s = first(filter(failed?, samples))
    blind(
      "the sample at #{to_s(get(s, :at_ms))} failed: #{to_s(get(s, :error))}"
    )
  else
    span_ms = get(last(samples), :at_ms) - get(first(samples), :at_ms)
    since = trailing_since(samples)
    still_ms = get(last(samples), :at_ms) - since
    if span_ms <= 0
      blind("the samples span no time")
    elsif still_ms >= window_s * 1000
      stalled(since)
    elsif travelled(samples) > 0
      moving(travelled(samples) * 1000 / span_ms)
    else
      blind(
        "no change over #{to_s(span_ms / 1000)}s, under the #{to_s(window_s)}s window"
      )
    end
  end
end

def bucket(resources, name)
  b = get(resources, name)
  if b.nil?
    blind("rate_limit names no #{name} bucket")
  else
    {
      bucket: name,
      limit: get(b, "limit"),
      used: get(b, "used"),
      remaining: get(b, "remaining"),
      reset: get(b, "reset")
    }
  end
end

def budget_of(text)
  doc = json_read(text) rescue nil
  resources = if doc != nil and map?(doc)
    get(doc, "resources")
  end
  if resources.nil?
    blind("gh api rate_limit answered no resources")
  else
    {
      verdict: "found",
      core: bucket(resources, "core"),
      actions: bucket(resources, "actions_runner_registration"),
      graphql: bucket(resources, "graphql")
    }
  end
end

def run_capture(argv)
  cap = exec_capture(*argv) rescue nil
  if cap.nil?
    {ok: false, why: "#{first(argv)} could not be started"}
  elsif status_of(cap) != 0
    {
      ok: false,
      why: "#{first(argv)} exited #{to_s(status_of(cap))}: #{last_nonempty_line(stderr_of(cap))}"
    }
  else
    {ok: true, stdout: stdout_of(cap)}
  end
end

def gh_budget()
  r = run_capture(["gh", "api", "rate_limit"])
  if get(r, :ok)
    budget_of(get(r, :stdout))
  else
    blind(get(r, :why))
  end
end

def defaults()
  {
    "load_factor" => 2,
    "load_per_agent" => 2,
    "gh_floor" => 500,
    "gh_calls_per_agent" => 250,
    "max_agents" => 8
  }
end

def settings_from(lookup)
  resolve("shinchoku", defaults, nil, lookup)
end

def admission(n, why)
  {allowed: max(n, 0), why:}
end

def agents_allowed_with(s, load1, cores, gh_remaining, agents_running)
  ceiling = get(s, "load_factor") * cores
  if load1 > ceiling
    admission(
      0,
      "load #{to_s(load1)} is above #{to_s(get(s, "load_factor"))}x #{to_s(cores)} cores"
    )
  elsif gh_remaining.nil?
    admission(0, "the GitHub budget could not be read")
  elsif gh_remaining < get(s, "gh_floor")
    admission(
      0,
      "#{to_s(gh_remaining)} GitHub calls left, under the floor of #{to_s(get(s, "gh_floor"))}"
    )
  elsif agents_running >= get(s, "max_agents")
    admission(
      0,
      "#{to_s(agents_running)} agents run, the most allowed is #{to_s(get(s, "max_agents"))}"
    )
  else
    by_load = floor((ceiling - load1) / get(s, "load_per_agent"))
    by_gh = floor(
      (gh_remaining - get(s, "gh_floor")) / get(s, "gh_calls_per_agent")
    )
    by_count = get(s, "max_agents") - agents_running
    n = min(by_load, min(by_gh, by_count))
    why = if n == by_load
      "load headroom"
    elsif n == by_gh
      "GitHub budget"
    else
      "agent ceiling"
    end
    admission(
      n,
      if n <= 0
        "no #{why} for one more agent"
      else
        "bounded by #{why}"
      end
    )
  end
end

def agents_allowed(load1, cores, gh_remaining, agents_running)
  agents_allowed_with(defaults, load1, cores, gh_remaining, agents_running)
end

def job_from_cronjob(cronjob_json, name)
  cj = json_read(cronjob_json) rescue nil
  if cj.nil? or map?(cj) == false
    {ok: false, why: "not a JSON object"}
  elsif get(cj, "kind") != "CronJob"
    {ok: false, why: "kind is #{to_s(get(cj, "kind"))}, not CronJob"}
  else
    meta = get(cj, "metadata") or {}
    tmpl = get(get(cj, "spec") or {}, "jobTemplate")
    if tmpl.nil? or get(tmpl, "spec").nil?
      {ok: false, why: "the CronJob has no spec.jobTemplate.spec"}
    else
      tmeta = get(tmpl, "metadata") or {}
      owner = {
        "apiVersion" => get(cj, "apiVersion") or "batch/v1",
        "kind" => "CronJob",
        "name" => get(meta, "name"),
        "uid" => get(meta, "uid"),
        "controller" => true
      }
      job_meta = {
        "name" => name,
        "namespace" => get(meta, "namespace") or "default",
        "labels" => get(tmeta, "labels") or {},
        "annotations" => assoc(
          get(tmeta, "annotations") or {},
          "cronjob.kubernetes.io/instantiate",
          "manual"
        )
      }
      {
        ok: true,
        job: {
          "apiVersion" => "batch/v1",
          "kind" => "Job",
          "metadata" => if get(meta, "uid").nil?
            job_meta
          else
            assoc(job_meta, "ownerReferences", [owner])
          end,
          "spec" => get(tmpl, "spec")
        }
      }
    end
  end
end

def at(doc, path)
  reduce(
    fn(acc, k)
      if acc != nil and map?(acc)
        get(acc, k)
      end
    end,
    doc,
    path
  )
end

def progress_paths()
  [
    ["status", "pass", "heartbeatAt"],
    ["status", "applyCursorCount"],
    ["status", "applyCursorAdvancedAt"]
  ]
end

def motion_paths()
  [
    ["status", "phase"],
    ["status", "phaseEnteredAt"],
    ["status", "observedGeneration"],
    ["status", "cycleCount"],
    ["status", "lastPlannedAt"],
    ["status", "lastAppliedAt"]
  ]
end

def active_phase?(phase)
  member?(
    phase,
    [
      "Pending",
      "Verifying",
      "Verified",
      "Compiling",
      "Initializing",
      "Planning",
      "Applying",
      "Destroying"
    ]
  )
end

def latest(xs)
  reduce(
    fn(acc, x)
      if x.nil?
        acc
      elsif acc.nil? or compare(x, acc) > 0
        x
      else
        acc
      end
    end,
    nil,
    xs
  )
end

def cursor_rate(a, b, window_s)
  ca = at(a, ["status", "applyCursorCount"])
  cb = at(b, ["status", "applyCursorCount"])
  if number?(ca) and number?(cb) and window_s > 0
    abs(cb - ca) / window_s
  end
end

def liveness(a, b, window_s)
  if a.nil? or b.nil?
    blind("a status read failed")
  else
    gen = at(b, ["metadata", "generation"])
    observed = at(b, ["status", "observedGeneration"])
    phase = at(b, ["status", "phase"])
    pass_kind = at(b, ["status", "pass", "kind"])
    present = filter((p) -> at(b, p) != nil, progress_paths)
    progressed = any?((p) -> at(a, p) != at(b, p), present)
    moved = any?((p) -> at(a, p) != at(b, p), motion_paths)
    since = latest(
      [
        at(b, ["status", "phaseEnteredAt"]),
        at(b, ["status", "pass", "heartbeatAt"]),
        at(b, ["status", "applyCursorAdvancedAt"])
      ]
    )
    if pass_kind == "stalled"
      assoc(stalled(since), :reason, at(b, ["status", "pass", "reason"]))
    elsif progressed or moved
      v = assoc(
        moving(cursor_rate(a, b, window_s)),
        :evidence,
        if progressed
          "progress field advanced"
        else
          "status changed"
        end
      )
      if gen != nil and observed != nil and gen > observed
        assoc(v, :queued_generation, gen)
      else
        v
      end
    elsif active_phase?(phase) and is_empty(present)
      blind(
        "phase #{phase} carries no progress field; sample the upstream calls with progress instead"
      )
    elsif active_phase?(phase)
      stalled(since)
    elsif gen != nil and observed != nil and gen > observed
      queued_behind(gen, observed, phase)
    else
      settled(gen, phase)
    end
  end
end

def split_target(template)
  if contains?(template, "/")
    parts = split(template, "/")
    [first(parts), second(parts)]
  else
    ["default", template]
  end
end

def read_template(ns, name)
  r = run_capture(
    ["k-ryn", "get", "infrastructuretemplate", name, "-n", ns, "-o", "json"]
  )
  if get(r, :ok)
    json_read(get(r, :stdout)) rescue nil
  end
end

def reconcile_liveness_over(template, window_s)
  t = split_target(template)
  a = read_template(first(t), second(t))
  sleep(window_s)
  b = read_template(first(t), second(t))
  if a.nil? or b.nil?
    blind("k-ryn could not read infrastructuretemplate #{template}")
  else
    liveness(a, b, window_s)
  end
end

def reconcile_liveness(template)
  reconcile_liveness_over(template, 60)
end

def counter_sample(argv)
  r = run_capture(argv)
  if get(r, :ok) == false
    failed_sample(now_ms, get(r, :why))
  else
    v = to_float(trim(get(r, :stdout))) rescue nil
    if v.nil?
      failed_sample(now_ms, "#{first(argv)} printed no number")
    else
      sample(now_ms, v)
    end
  end
end

def sample_every(argv, count, every_s)
  reduce(
    fn(acc, i)
      if i > 0
        sleep(every_s)
      end
      append(acc, [counter_sample(argv)])
    end,
    [],
    range(0, count)
  )
end

def samples_of(text)
  map(
    fn(s)
      if get(s, "error") != nil
        failed_sample(get(s, "at_ms"), get(s, "error"))
      else
        sample(get(s, "at_ms"), get(s, "value"))
      end
    end,
    json_read(text)
  )
end

def flag(args, name, default)
  i = index_of(args, name)
  if i.nil?
    default
  else
    nth(i + 1, args)
  end
end

def after_dashes(args)
  i = index_of(args, "--")
  if i != nil
    drop(i + 1, args)
  end
end

def load_and_cores()
  la = read_or("/proc/loadavg", "")
  load1 = if la != ""
    to_float(first(split(la, " ")))
  else
    r = run_capture(["sysctl", "-n", "vm.loadavg"])
    if get(r, :ok)
      to_float(nth(1, split(trim(get(r, :stdout)), " ")))
    end
  end
  c = run_capture(["getconf", "_NPROCESSORS_ONLN"])
  cores = if get(c, :ok)
    to_int(trim(get(c, :stdout)))
  end
  [load1, cores]
end

def usage()
  "usage: shinchoku progress --window S [--every S --count N -- CMD ARGS | --samples FILE]\n       shinchoku gh-budget\n       shinchoku agents-allowed [--running N]\n       shinchoku job-from-cronjob CRONJOB.json NAME\n       shinchoku reconcile-liveness [NS/]NAME [--window S]\n"
end

def command(args)
  sub = first(args) rescue nil
  rest_args = drop(1, args)
  if sub == "progress"
    window = to_int(flag(rest_args, "--window", "60"))
    cmd = after_dashes(rest_args)
    samples = if cmd != nil
      sample_every(
        cmd,
        to_int(flag(rest_args, "--count", "3")),
        to_int(flag(rest_args, "--every", "20"))
      )
    else
      samples_of(read_file(flag(rest_args, "--samples", "/dev/stdin")))
    end
    assoc(progress(samples, window), :samples, samples)
  elsif sub == "gh-budget"
    gh_budget
  elsif sub == "agents-allowed"
    lc = load_and_cores
    b = gh_budget
    remaining = if verdict(b) == "found"
      get(get(b, :core), :remaining)
    end
    a = agents_allowed_with(
      settings_from((n) -> getenv(n)),
      first(lc) or 0,
      second(lc) or 1,
      remaining,
      to_int(flag(rest_args, "--running", "0"))
    )
    assoc(
      assoc(assoc(a, :load1, first(lc)), :cores, second(lc)),
      :gh_remaining,
      remaining
    )
  elsif sub == "job-from-cronjob" and size(rest_args) >= 2
    r = job_from_cronjob(read_file(first(rest_args)), second(rest_args))
    if get(r, :ok)
      get(r, :job)
    else
      blind(get(r, :why))
    end
  elsif sub == "reconcile-liveness" and size(rest_args) >= 1
    reconcile_liveness_over(
      first(rest_args),
      to_int(flag(rest_args, "--window", "60"))
    )
  end
end

def main()
  out = command(argv)
  if out.nil?
    write_stderr(usage)
    exit_with(2)
  end
  write_stdout("#{json_stringify(out)}\n")
  out
end

test "progress: the empty case and one sample are blind, never stalled"
  assert verdict(progress([], 60)) == "blind"
  assert verdict(progress([sample(0, 5)], 60)) == "blind"
end

test "progress: a failed sample is blind even when the others stand still"
  s = [
    sample(0, 12494),
    failed_sample(20000, "gh exited 1"),
    sample(90000, 12494)
  ]
  assert verdict(progress(s, 40)) == "blind"
  assert contains?(get(progress(s, 40), :why), "gh exited 1")
end

test "progress: an unchanged counter over the window is stalled since its first equal sample"
  s = [
    sample(0, 10),
    sample(10000, 12494),
    sample(30000, 12494),
    sample(60000, 12494)
  ]
  p = progress(s, 40)
  assert verdict(p) == "stalled"
  assert get(p, :since) == 10000
end

test "progress: a moving counter reports its rate, and a fall counts as movement"
  p = progress([sample(0, 2100), sample(40000, 2140)], 40)
  assert verdict(p) == "moving"
  assert get(p, :rate) == 1
  assert verdict(progress([sample(0, 9), sample(10000, 3)], 60)) == "moving"
end

test "progress: no change inside a short window is blind, not stalled"
  assert verdict(progress([sample(0, 7), sample(10000, 7)], 60)) == "blind"
end

test "gh_budget: the core, Actions and GraphQL buckets read from rate_limit"
  b = budget_of("{\"resources\":{\"core\":{\"limit\":5000,\"used\":2408,\"remaining\":2592,\"reset\":1792613194},\"actions_runner_registration\":{\"limit\":10000,\"used\":0,\"remaining\":10000,\"reset\":1792616487}}}")
  assert verdict(b) == "found"
  assert get(get(b, :core), :remaining) == 2592
  assert get(get(b, :core), :limit) - get(get(b, :core), :used) == 2592
  assert get(get(b, :actions), :remaining) == 10000
  assert verdict(get(b, :graphql)) == "blind"
  assert verdict(budget_of("")) == "blind"
  assert verdict(budget_of("{}")) == "blind"
end

test "agents_allowed: load above twice the cores holds, with the reason"
  a = agents_allowed(29, 14, 4000, 0)
  assert get(a, :allowed) == 0
  assert contains?(get(a, :why), "above 2x 14 cores")
end

test "agents_allowed: under 500 GitHub calls holds, and an unread budget holds"
  assert get(agents_allowed(1, 14, 499, 0), :allowed) == 0
  assert contains?(
    get(agents_allowed(1, 14, 499, 0), :why),
    "under the floor of 500"
  )
  assert get(agents_allowed(1, 14, nil, 0), :allowed) == 0
end

test "agents_allowed: headroom is the tightest of load, budget and the ceiling"
  assert get(agents_allowed(8, 14, 5000, 0), :allowed) == 8
  assert get(agents_allowed(20, 14, 5000, 0), :allowed) == 4
  assert get(agents_allowed(0, 14, 1000, 0), :allowed) == 2
  assert get(agents_allowed(0, 14, 5000, 7), :allowed) == 1
  assert get(agents_allowed(0, 14, 5000, 8), :allowed) == 0
end

test "agents_allowed: the thresholds are settings, overridable by name"
  s = settings_from(env_of({"SHINCHOKU_GH_FLOOR" => "100"}))
  assert get(agents_allowed_with(s, 1, 14, 499, 0), :allowed) == 1
  assert settings_from(no_env) == defaults
end

def cronjob_text()
  "{\"apiVersion\":\"batch/v1\",\"kind\":\"CronJob\",\"metadata\":{\"name\":\"vars\",\"namespace\":\"pangea-system\",\"uid\":\"u-1\"},\"spec\":{\"schedule\":\"0 * * * *\",\"jobTemplate\":{\"metadata\":{\"labels\":{\"app\":\"vars\"}},\"spec\":{\"backoffLimit\":0,\"template\":{\"spec\":{\"restartPolicy\":\"Never\",\"containers\":[{\"name\":\"c\",\"image\":\"x\"}]}}}}}}"
end

test "job_from_cronjob: the Job carries the template spec unchanged and is owned by the CronJob"
  r = job_from_cronjob(cronjob_text, "vars-manual-1")
  assert get(r, :ok)
  j = get(r, :job)
  assert get(j, "kind") == "Job"
  assert get(j, "apiVersion") == "batch/v1"
  assert at(j, ["metadata", "name"]) == "vars-manual-1"
  assert at(j, ["metadata", "namespace"]) == "pangea-system"
  assert at(j, ["metadata", "labels", "app"]) == "vars"
  assert at(
    j,
    ["metadata", "annotations", "cronjob.kubernetes.io/instantiate"]
  ) == "manual"
  assert get(j, "spec") ==
    at(json_read(cronjob_text), ["spec", "jobTemplate", "spec"])
  assert at(first(at(j, ["metadata", "ownerReferences"])), ["uid"]) == "u-1"
  assert json_read(json_stringify(j)) == j
end

test "job_from_cronjob: anything but a CronJob with a jobTemplate is refused"
  assert get(job_from_cronjob("", "x"), :ok) == false
  assert get(job_from_cronjob("{\"kind\":\"Deployment\"}", "x"), :ok) == false
  assert get(
    job_from_cronjob(
      replace(cronjob_text, "\"CronJob\"", "\"Deployment\""),
      "x"
    ),
    :ok
  ) == false
  assert get(
    job_from_cronjob("{\"kind\":\"CronJob\",\"spec\":{}}", "x"),
    :ok
  ) == false
end

def tmpl(gen, observed, phase, entered, extra)
  {
    "metadata" => {"generation" => gen},
    "status" => reduce(
      (acc, e) -> assoc(acc, first(e), second(e)),
      {
        "observedGeneration" => observed,
        "phase" => phase,
        "phaseEnteredAt" => entered
      },
      map_entries(extra)
    )
  }
end

test "reconcile_liveness: a failed read is blind"
  assert verdict(liveness(nil, tmpl(1, 1, "Ready", "t", {}), 60)) == "blind"
end

test "reconcile_liveness: an advancing apply cursor is moving"
  a = tmpl(21, 21, "Applying", "t1", {"applyCursorCount" => 1})
  b = tmpl(21, 21, "Applying", "t1", {"applyCursorCount" => 40})
  v = liveness(a, b, 30)
  assert verdict(v) == "moving"
  assert get(v, :rate) == 1.3
  assert get(
    liveness(a, tmpl(22, 21, "Applying", "t1", {"applyCursorCount" => 40}), 30),
    :queued_generation
  ) == 22
end

test "reconcile_liveness: a still heartbeat in Planning is stalled since the latest evidence"
  p = {
    "pass" => {
      "kind" => "planning",
      "heartbeatAt" => "2026-10-21T19:02:00Z",
      "generation" => 21
    }
  }
  a = tmpl(21, 20, "Planning", "2026-10-21T18:35:05Z", p)
  v = liveness(a, a, 60)
  assert verdict(v) == "stalled"
  assert get(v, :since) == "2026-10-21T19:02:00Z"
end

test "reconcile_liveness: Planning with no progress field is blind, never stalled"
  a = tmpl(21, 20, "Planning", "2026-10-21T18:35:05Z", {})
  assert verdict(liveness(a, a, 60)) == "blind"
  assert verdict(
    liveness(
      tmpl(4, 4, "Compiling", "t", {}),
      tmpl(4, 4, "Compiling", "t", {}),
      60
    )
  ) == "blind"
end

test "reconcile_liveness: a settled pass with a newer generation is queued behind it"
  a = tmpl(21, 20, "Ready", "t", {})
  v = liveness(a, a, 60)
  assert verdict(v) == "queued-behind"
  assert get(v, :generation) == 21
  assert get(v, :observed) == 20
  assert verdict(
    liveness(tmpl(21, 21, "Ready", "t", {}), tmpl(21, 21, "Ready", "t", {}), 60)
  ) == "settled"
end

test "reconcile_liveness: the operator's own stalled pass is stalled, with its reason"
  p = {
    "pass" => {
      "kind" => "stalled",
      "reason" => "silent Planning",
      "generation" => 3
    }
  }
  v = liveness(
    tmpl(3, 2, "Planning", "t", p),
    tmpl(3, 2, "Planning", "t", p),
    60
  )
  assert verdict(v) == "stalled"
  assert get(v, :reason) == "silent Planning"
end

test "the command: an unknown subcommand is a usage error, a known one answers"
  assert command([]).nil?
  assert command(["nope"]).nil?
  assert command(["job-from-cronjob"]).nil?
end
