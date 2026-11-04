@moduledoc """
run: Run every real-kernel suite on this machine and judge what they left
behind. A busy machine is refused before anything loads, because a loaded host
reads as a broken BPF. The build runs at idle priority and the network suite
inside its own namespace.

    blue kernel/run.b

Settings are `kernel-run`'s, through `settei`. `admission.enabled` turns the
refusal off, `build.enabled` the build, `tools.from_nix` the nix lookup of
`ip`, `ping` and the object oracles, `build.private_cache` the run's own nix
cache, and `suite.filter` keeps the tests whose name holds it.

    blue kernel/run.b on HOST [REF]

runs REF (HEAD by default, which needs no push) on HOST from this
machine: its own directory under `on.root`, `on.lock` held for the whole of it,
detached so a dropped session loses nothing, its log followed here, and the
directory removed by the runner on the host once this side has read it.
`on.cleanup` turns that removal off.
"""

use("gamen", [:show_step])

use("retsu", %i[enumerate first last rest])

use("settei")

use("shinchoku", [:load_and_cores])

use("shisutemu", %i[blue_exe read_or status_of stderr_of stdout_of])

@doc """
config_defaults: What `kernel-run` does when nothing says otherwise.

    config_defaults[:admission][:max_stalled] #=> 4
"""
def config_defaults()
  {
    admission: {enabled: true, load_per_core: 1, max_stalled: 4},
    build: {enabled: true, jobs: 3, private_cache: true},
    tools: {from_nix: true},
    suite: {seconds: 900, net_seconds: 300, filter: ""},
    on: {
      root: "/tmp/blue-kernel-runs",
      lock: "/tmp/blue-kernel.lock",
      poll_seconds: 15,
      deadline_seconds: 14400,
      linger_seconds: 900,
      stale_seconds: 3600,
      cleanup: true,
      transport: "auto",
      origin: "https://github.com/pleme-io/blue"
    }
  }
end

@doc """
admission: Whether this host can carry the suites. Tasks stalled in D state or a
load over the limit refuse the run and name why.

    admission({enabled: true, load_per_core: 1, max_stalled: 4}, 2, 8, 0)[:admitted] #=> true
    admission({enabled: true, load_per_core: 1, max_stalled: 4}, 20, 8, 0)[:why] #=> "load 20 is over 8"
    admission({enabled: false, load_per_core: 1, max_stalled: 4}, 20, 8, 9)[:admitted] #=> true
"""
def admission(s, load1, cores, stalled)
  limit = s[:load_per_core] * cores
  if not s[:enabled]
    {admitted: true, why: "admission is off"}
  elsif stalled > s[:max_stalled]
    {
      admitted: false,
      why: "#{to_s(stalled)} tasks are stalled in D state; read them first"
    }
  elsif load1 > limit
    {admitted: false, why: "load #{to_s(load1)} is over #{to_s(limit)}"}
  else
    {admitted: true, why: ""}
  end
end

@doc """
rows_of: The lines of a command's output that say anything.

    rows_of("a\n\n b\n") #=> ["a", " b"]
"""
def rows_of(text)
  retsu::reject((l) -> trim(l) == "", split(text, line_break))
end

@doc """
stalled_of: How many tasks `ps -eo state=` shows in D state.

    stalled_of("S\nD\nR\nDs\n") #=> 2
"""
def stalled_of(states)
  count(filter((l) -> starts_with?(trim(l), "D"), rows_of(states)))
end

@doc """
footprint: What the suites can leave behind, as counts. A test cgroup is one the
suites name, since the host makes its own.

    footprint("lo\neth0\n", "", "x\n", "blue_suite_a\ninit.scope\n") #=> {links: 2, netns: 0, pins: 1, cgroups: 1}
"""
def footprint(links, netns, pins, cgroups)
  {
    links: count(rows_of(links)),
    netns: count(rows_of(netns)),
    pins: count(rows_of(pins)),
    cgroups: count(
      filter((l) -> starts_with?(l, "blue_suite"), rows_of(cgroups))
    )
  }
end

@doc """
left_behind: The kinds a run added to the host.

    left_behind({links: 4, netns: 0, pins: 0, cgroups: 0}, {links: 4, netns: 0, pins: 0, cgroups: 0}) #=> []
    left_behind({links: 4, netns: 0, pins: 0, cgroups: 0}, {links: 5, netns: 0, pins: 1, cgroups: 1}) #=> [:links, :pins, :cgroups]
"""
def left_behind(before, after)
  filter((k) -> get(after, k) > get(before, k), %i[links netns pins cgroups])
end

@doc """
tally_of: The summary line a `blue test` run ends with, or nil.

    tally_of("noise\n22 test(s): 22 passed, 0 failed\n") #=> "22 test(s): 22 passed, 0 failed"
    tally_of("") #=> nil
"""
def tally_of(text)
  tallies = filter((l) -> contains?(l, " test(s): "), rows_of(text))
  if tallies != []
    last(tallies)
  end
end

@doc """
private_cache: The nix cache a run reads, or nil for the host's. A damaged `~/.cache/nix/tarball-cache` stops every `nix develop` that reads it, so a run reads its own, under the checkout's `target`.

    private_cache({private_cache: true}, "/r") #=> "/r/target/kernel-run/cache"
    private_cache({private_cache: false}, "/r") #=> nil
"""
def private_cache(build, root)
  if build[:private_cache]
    "#{root}/target/kernel-run/cache"
  end
end

@doc """
cache_env: That cache as the environment `exec_with_env` takes.

    cache_env(nil) #=> []
    cache_env("/c") #=> [["XDG_CACHE_HOME", "/c"]]
"""
def cache_env(cache)
  if cache.nil?
    []
  else
    [["XDG_CACHE_HOME", cache]]
  end
end

@doc """
build_command: The checkout's blue, built at idle priority so the host stays
responsive, reading the run's own nix cache when it has one.

    last(build_command(3, nil)) #=> "blue-lang-cli"
    first(build_command(3, nil)) #=> "nice"
    first(build_command(3, "/c")) #=> "env"
"""
def build_command(jobs, cache)
  append(
    if cache.nil?
      []
    else
      ["env", "XDG_CACHE_HOME=#{cache}"]
    end,
    %w[nice -n 19 ionice -c3 nix develop --accept-flake-config -c env],
    ["CARGO_BUILD_JOBS=#{to_s(jobs)}"],
    %w[cargo build -p blue-lang-cli]
  )
end

@doc """
suite_words: The `KERNEL_SUITE_*` settings to hand a suite by name. `sudo` drops every other variable, and a suite expectation that never arrives lets a kernel answer anything.

    suite_words((n) -> get({"KERNEL_SUITE_KPROBE_MULTI" => "attached"}, n)) #=> ["KERNEL_SUITE_KPROBE_MULTI=attached"]
    suite_words((_n) -> nil) #=> []
"""
def suite_words(read)
  retsu::reject(
    (w) -> w.nil?,
    map(
      fn(n)
        v = read(n)
        if v != nil
          "#{n}=#{v}"
        end
      end,
      %w[KERNEL_SUITE_KPROBE_MULTI KERNEL_SUITE_DIVISION_GUARD]
    )
  )
end

@doc """
suite_command: One suite under `blue test`, bounded, at low priority, in the
environment given, with the tests a filter keeps.

    last(suite_command("kernel/suite.b", 900, "blue", ["A=1"], "")) #=> "kernel/suite.b"
    first(suite_command("x.b", 9, "blue", ["A=1"], "")) #=> "env"
    member?("--filter", suite_command("x.b", 9, "blue", [], "fexit")) #=> true
"""
def suite_command(file, seconds, blue, env, wanted)
  keep = if wanted == ""
    []
  else
    ["--filter", wanted]
  end
  append(
    *[
      ["env"],
      env,
      %w[nice -n 10 timeout],
      [to_s(seconds), blue],
      %w[test --allow host],
      keep,
      [file]
    ]
  )
end

@doc """
veristat_expression: The nix expression that builds `veristat`, which nixpkgs does
not carry, from this checkout's `nix/veristat.nix`. It is a test oracle, and
nothing in a build needs it.

    contains?(veristat_expression("/r"), "/r/nix/veristat.nix") #=> true
"""
def veristat_expression(root)
  "(builtins.getFlake \"nixpkgs\").legacyPackages.${builtins.currentSystem}.callPackage #{root}/nix/veristat.nix { }"
end

@doc """
veristat_dir: The directory that holds a built `veristat`.

    string?(veristat_expression("/r")) #=> true
"""
def veristat_dir(cache)
  r = exec_with_env(
    cache_env(cache),
    "nix",
    "build",
    "--impure",
    "--no-link",
    "--print-out-paths",
    "--inputs-from",
    ".",
    "--expr",
    veristat_expression(cwd)
  )
  if status_of(r) != 0
    raise(:missing_tool, "nix cannot build veristat: #{stderr_of(r)}")
  end
  "#{trim(stdout_of(r))}/bin"
end

@doc """
tool_dirs: The directories that hold `ip`, `ping` and the object suite's oracles:
nix's when `from_nix`, and none when PATH already has them.

    tool_dirs(false, nil) #=> []
"""
def tool_dirs(from_nix, cache)
  if from_nix
    r = exec_with_env(
      cache_env(cache),
      "nix",
      "build",
      "--inputs-from",
      ".",
      "--no-link",
      "--print-out-paths",
      "nixpkgs#iproute2",
      "nixpkgs#iputils",
      "nixpkgs#bpftools",
      "nixpkgs#llvmPackages.clang-unwrapped",
      "nixpkgs#llvmPackages.llvm.out",
      "nixpkgs#binutils-unwrapped.out"
    )
    if status_of(r) != 0
      raise(:missing_tool, "nix cannot supply ip and ping: #{stderr_of(r)}")
    end
    append(
      map((p) -> "#{trim(p)}/bin", rows_of(stdout_of(r))),
      [veristat_dir(cache)]
    )
  else
    []
  end
end

@doc """
filtered_out?: Whether a suite said it holds no test the filter keeps.

    filtered_out?("x.b: no test name contains \"f\"", "f") #=> true
    filtered_out?("x.b: no test name contains \"f\"", "") #=> false
    filtered_out?("boom", "f") #=> false
"""
def filtered_out?(output, wanted)
  wanted != "" and contains?(output, "no test name contains")
end

@doc """
run_step: One step of the run, shown as it goes; its verdict and output. A suite with no test the filter keeps ran nothing wrong, so it is green.

    run_step(1, 1, "true", () -> ["env", "true"], "")[:green] #=> true
"""
def run_step(at, of, name, argv_of, wanted)
  show_step({state: :running, at:, of:, name:}, {})
  t = now_ms
  argv = argv_of()
  r = exec_capture(first(argv), *rest(argv))
  output = "#{stdout_of(r)}#{stderr_of(r)}"
  green = status_of(r) == 0 or filtered_out?(output, wanted)
  state = if green
    :done
  else
    :failed
  end
  show_step({state:, at:, of:, name:, ms: now_ms - t}, {})
  {name:, green:, output:}
end

@doc """
step_report: What a finished step tells a reader: its tally and what it skipped by name when green, and the whole of its output when red.

    step_report({name: "s", green: true, output: "1 test(s): 1 passed, 0 failed"}) #=> "s: 1 test(s): 1 passed, 0 failed\n"
    step_report({name: "s", green: true, output: "skipped on 6.6.1: x"}) #=> "s: skipped on 6.6.1: x\n"
    step_report({name: "s", green: true, output: "quiet"}) #=> ""
    step_report({name: "s", green: false, output: "why"}) #=> "why"
"""
def step_report(r)
  if not r[:green]
    r[:output]
  else
    said = filter(
      (l) -> starts_with?(l, "skipped on ") or contains?(l, " test(s): "),
      rows_of(r[:output])
    )
    join(map((l) -> unlines(["#{r[:name]}: #{l}"]), said), "")
  end
end

@doc """
run_suites: Admission, the build, every suite and the judgement of what they left behind, on this machine, each tally written as its suite ends. The status the run exits with: 0 green, 1 red, 3 refused.

    string?(run_suites) #=> false
"""
def run_suites(config)
  lc = load_and_cores
  verdict = admission(
    config[:admission],
    first(lc) or 0,
    last(lc) or 1,
    stalled_of(stdout_of(exec_capture("ps", "-eo", "state=")))
  )
  if verdict[:admitted]
    suites_on(config)
  else
    write_stderr(unlines(["kernel/run: refused: #{verdict[:why]}"]))
    3
  end
end

def suites_on(config)
  root = cwd
  cache = private_cache(config[:build], root)
  dirs = tool_dirs(config[:tools][:from_nix], cache)
  ip = if dirs == []
    "ip"
  else
    "#{first(dirs)}/ip"
  end
  blue = if config[:build][:enabled]
    "#{root}/target/debug/blue"
  else
    blue_exe
  end
  env = append(
    [
      "BLUE_TEST_WRITES=anywhere",
      "BLUE_PATH=#{root}/bidamas",
      "PATH=#{join(dirs, ":")}:/run/current-system/sw/bin:#{getenv("PATH")}"
    ],
    suite_words(getenv)
  )
  ns = "blue_suite"
  measure = fn()
    footprint(
      stdout_of(exec_capture(ip, "-br", "link")),
      stdout_of(exec_capture(ip, "netns", "list")),
      stdout_of(exec_capture("sudo", "-n", "ls", "/sys/fs/bpf")),
      stdout_of(exec_capture("ls", "/sys/fs/cgroup"))
    )
  end
  before = measure()
  build = if config[:build][:enabled]
    [["build", () -> build_command(config[:build][:jobs], cache)]]
  else
    []
  end
  suite = fn(file, seconds)
    append(
      %w[sudo -n],
      suite_command(file, seconds, blue, env, config[:suite][:filter])
    )
  end
  steps = append(
    build,
    [
      [
        "kernel/suite.b",
        () -> suite("kernel/suite.b", config[:suite][:seconds])
      ],
      [
        "kernel/object_suite.b",
        () -> suite("kernel/object_suite.b", config[:suite][:seconds])
      ],
      [
        "kernel/object_llvm.b",
        fn()
          append(
            ["env"],
            env,
            [blue, "run", "--quiet", "--allow", "host", "kernel/object_llvm.b"],
            %w[clang llvm-objdump llvm-readobj readelf]
          )
        end
      ],
      ["netns add", () -> ["sudo", "-n", ip, "netns", "add", ns]],
      [
        "kernel/net_suite.b",
        fn()
          append(
            ["sudo", "-n", ip, "netns", "exec", ns],
            suite_command(
              "kernel/net_suite.b",
              config[:suite][:net_seconds],
              blue,
              env,
              config[:suite][:filter]
            )
          )
        end
      ],
      ["netns del", () -> ["sudo", "-n", ip, "netns", "del", ns]]
    ]
  )
  total = count(steps)
  results = map(
    fn(p)
      r = run_step(
        first(p) + 1,
        total,
        first(last(p)),
        last(last(p)),
        config[:suite][:filter]
      )
      write_stdout(step_report(r))
      r
    end,
    enumerate(steps)
  )
  after = measure()
  left = left_behind(before, after)
  write_stdout(
    unlines(
      [
        "links #{to_s(after[:links])} netns #{to_s(after[:netns])} pins #{to_s(after[:pins])} cgroups #{to_s(after[:cgroups])}"
      ]
    )
  )
  red = map((r) -> r[:name], retsu::reject((r) -> r[:green], results))
  if left != []
    write_stderr(unlines(["🔴 kernel/run: left behind #{to_s(left)}"]))
    1
  elsif red != []
    write_stderr(unlines(["🔴 kernel/run: red: #{join(red, ", ")}"]))
    1
  else
    write_stdout(
      unlines(["🟢 kernel/run: every suite green, nothing left behind"])
    )
    0
  end
end

@doc """
shell_word: A value as one word of a POSIX shell line.

    shell_word("a b") #=> "'a b'"
    shell_word("it's") #=> "'it'\\''s'"
"""
def shell_word(s)
  "'#{replace(s, "'", "'\\''")}'"
end

@doc """
ssh_argv: POSIX sh on a host, reading its script from stdin. A login shell that is not POSIX never parses the script: frost split a quoted word at its escaped quote and sh saw the pieces as arguments. No prompt can wedge it.

    last(ssh_argv("h")) #=> "/bin/sh -s"
    member?("BatchMode=yes", ssh_argv("h")) #=> true
"""
def ssh_argv(host)
  ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=20", host, "/bin/sh -s"]
end

def on_host_sh(host, script)
  exec_with_stdin(unlines([script]), *ssh_argv(host))
end

@doc """
probe_of: What `cat /proc/loadavg; nproc; ps -eo state=` says of a host, as `admission` reads it.

    probe_of("4.5 1 1 1/9 2\n16\nS\nD\n") #=> {load: 4.5, cores: 16, stalled: 1}
"""
def probe_of(text)
  rows = rows_of(text)
  {
    load: to_float(first(split(first(rows), " "))),
    cores: to_int(trim(rows[1])),
    stalled: stalled_of(unlines(drop(2, rows)))
  }
end

@doc """
settings_words: The settings a run on a host takes from the laptop's, as `NAME=value` words. The host's blue is the checkout's, built before the run, so its build is off.

    member?("KERNEL_RUN_SUITE__FILTER='x'", settings_words(assoc(config_defaults, :suite, {filter: "x", seconds: 1, net_seconds: 2}))) #=> true
    member?("KERNEL_RUN_BUILD__ENABLED='false'", settings_words(config_defaults)) #=> true
"""
def settings_words(config)
  map(
    (p) -> "#{first(p)}=#{shell_word(to_s(last(p)))}",
    [
      ["KERNEL_RUN_ADMISSION__ENABLED", config[:admission][:enabled]],
      [
        "KERNEL_RUN_ADMISSION__LOAD_PER_CORE",
        config[:admission][:load_per_core]
      ],
      ["KERNEL_RUN_ADMISSION__MAX_STALLED", config[:admission][:max_stalled]],
      ["KERNEL_RUN_BUILD__ENABLED", false],
      ["KERNEL_RUN_BUILD__PRIVATE_CACHE", config[:build][:private_cache]],
      ["KERNEL_RUN_TOOLS__FROM_NIX", config[:tools][:from_nix]],
      ["KERNEL_RUN_SUITE__SECONDS", config[:suite][:seconds]],
      ["KERNEL_RUN_SUITE__NET_SECONDS", config[:suite][:net_seconds]],
      ["KERNEL_RUN_SUITE__FILTER", config[:suite][:filter]],
      ["KERNEL_RUN_ON__ROOT", config[:on][:root]],
      ["KERNEL_RUN_ON__LINGER_SECONDS", config[:on][:linger_seconds]],
      ["KERNEL_RUN_ON__STALE_SECONDS", config[:on][:stale_seconds]],
      ["KERNEL_RUN_ON__CLEANUP", config[:on][:cleanup]]
    ]
  )
end

@doc """
exit_line: The line that ends a run's log, whatever the run answered.

    exit_line(3) #=> "kernel/run: exit 3"
"""
def exit_line(code)
  "kernel/run: exit #{to_s(code)}"
end

@doc """
exit_of: The status a log's end line names, or nil while the run goes on.

    exit_of(["a", "kernel/run: exit 3"]) #=> 3
    exit_of(["a"]) #=> nil
"""
def exit_of(rows)
  found = find(rows, (l) -> starts_with?(l, "kernel/run: exit "))
  if found != nil
    to_int(replace(found, "kernel/run: exit ", ""))
  end
end

@doc """
hold_line: What a run does under the lock, in its own directory: build the checkout's blue at idle priority with a private nix cache, and hand the rest to it. A build that fails has no blue to go on with, so this line ends the log itself.

    contains?(hold_line("/r/a", 3, ["A='1'"], true), "kernel/run.b host /r/a") #=> true
    contains?(hold_line("/r/a", 3, [], true), "XDG_CACHE_HOME=/r/a/src/target/kernel-run/cache") #=> true
    contains?(hold_line("/r/a", 3, [], false), "XDG_CACHE_HOME") #=> false
    contains?(hold_line("/r/a", 3, [], true), "rm ") #=> false
"""
def hold_line(dir, jobs, settings, private)
  src = "#{dir}/src"
  cache = if private
    "XDG_CACHE_HOME=#{src}/target/kernel-run/cache "
  else
    ""
  end
  join(
    [
      "cd #{src} && export PWD=#{src} BLUE_PATH=#{src}/bidamas #{cache}#{join(settings, " ")};",
      "nice -n 19 ionice -c3 nix build --accept-flake-config --cores #{to_s(jobs)} -o #{dir}/built path:#{src}#default",
      "&& #{dir}/built/bin/blue kernel/run.b host #{dir}",
      "|| echo '#{exit_line(1)}'"
    ],
    " "
  )
end

@doc """
detach_line: The one line that starts a run on a host and returns at once: its own session, its pid written down, the lock held for the whole of it, every word of output in the run's log.

    contains?(detach_line("/r/a", "/l", 3, [], true), "setsid -f") #=> true
    contains?(detach_line("/r/a", "/l", 3, [], true), "flock /l") #=> true
"""
def detach_line(dir, lock, jobs, settings, private)
  body = "echo $$ > #{dir}/pid; exec flock #{lock} /bin/sh -c #{shell_word(hold_line(dir, jobs, settings, private))}"
  "setsid -f /bin/sh -c #{shell_word(body)} > #{dir}/log 2>&1 < /dev/null"
end

@doc """
stale_run?: Whether a run's directory has no runner left. One with a pid is stale when that process is gone; one with no pid yet is stale when its name's time is older than the bound, since a laptop may still be filling it.

    stale_run?("run-100", "7", false, 200, 1000) #=> true
    stale_run?("run-100", "7", true, 999999, 1000) #=> false
    stale_run?("run-100", nil, false, 200, 1000) #=> false
    stale_run?("run-100", nil, false, 1200, 1000) #=> true
    stale_run?("probe", nil, false, 1200, 1000) #=> true
"""
def stale_run?(name, pid, alive, now, bound_ms)
  if pid != nil
    not alive
  else
    born = if starts_with?(name, "run-")
      to_int(replace(name, "run-", "")) rescue 0
    else
      0
    end
    now - born > bound_ms
  end
end

@doc """
remove_run: Remove a run's directory, as root when a suite left a file only root can remove, and say whether it is gone.

    remove_run("/no/such/kernel-run") #=> true
"""
def remove_run(dir)
  rm_rf(dir) rescue nil
  if path_exists(dir)
    exec_capture("sudo", "-n", "rm", "-rf", dir)
  end
  not path_exists(dir)
end

@doc """
sweep_runs: Remove the directories under `root` whose runner died before its own cleanup: a build that failed, a host that rebooted. Each named on stdout.

    sweep_runs("/no/such/kernel-run", "", 1000) #=> []
"""
def sweep_runs(root, mine, bound_ms)
  entries = if path_exists(root)
    ls(root)
  else
    []
  end
  dead = filter(
    fn(d)
      written = trim(read_or("#{d}/pid", ""))
      pid = if written != ""
        written
      end
      alive = pid != nil and path_exists("/proc/#{pid}")
      d != mine and
        stale_run?(last(split(d, "/")), pid, alive, now_ms, bound_ms)
    end,
    entries
  )
  map(
    fn(d)
      remove_run(d)
      write_stdout(unlines(["kernel/run: swept #{d}"]))
      d
    end,
    dead
  )
end

@doc """
linger: Hold a finished run's log until the laptop says it has read it, or the bound passes with the laptop gone.

    linger("/no/such/kernel-run", 0) #=> nil
"""
def linger(dir, seconds)
  find(
    range(0, floor(seconds / 5)),
    fn(_at)
      collected = path_exists("#{dir}/collected")
      if not collected
        sleep(5)
      end
      collected
    end
  )
  nil
end

@doc """
host_run: A run inside its own directory on the host, under the lock. Whatever the suites answer, the log ends with its exit line, and this runner removes its directory.

    contains?(hold_line("/r/a", 3, [], true), "kernel/run.b host") #=> true
"""
def host_run(dir, config)
  sweep_runs(config[:on][:root], dir, config[:on][:stale_seconds] * 1000)
  code = begin
    run_suites(config)
  rescue e
    write_stderr(unlines(["🔴 kernel/run: #{to_s(e.message)}"]))
    1
  end
  write_stdout(unlines([exit_line(code)]))
  linger(dir, config[:on][:linger_seconds])
  if config[:on][:cleanup]
    if not remove_run(dir)
      write_stderr(unlines(["🔴 kernel/run: #{dir} is still here"]))
      exit_with(1)
    end
  end
  exit_with(code)
end

@doc """
follow_step: One read of a run's log from a laptop: `state` {seen:, code:, misses:} and what `tail -n +N` answered. It prints each whole line once, and a session that dropped costs only a miss.

    follow_step({seen: 0, code: nil, misses: 0}, 0, "a\nkernel/run: exit 0\n", (_) -> nil) #=> {seen: 2, code: 0, misses: 0}
    follow_step({seen: 2, code: nil, misses: 0}, 255, "", (_) -> nil) #=> {seen: 2, code: nil, misses: 1}
    follow_step({seen: 2, code: nil, misses: 0}, 1, "", (_) -> nil) #=> {seen: 2, code: :gone, misses: 0}
"""
def follow_step(state, status, text, print)
  if status == 255
    assoc(state, :misses, state[:misses] + 1)
  elsif status != 0
    assoc(state, :code, :gone)
  else
    rows = split(text, line_break)
    whole = take(count(rows) - 1, rows)
    print(whole)
    {
      seen: state[:seen] + count(whole),
      code: exit_of(whole),
      misses: state[:misses]
    }
  end
end

def follow(host, dir, poll_seconds, deadline_seconds)
  reduce(
    fn(state, _at)
      if state[:code] != nil
        state
      else
        r = on_host_sh(host, "tail -n +#{to_s(state[:seen] + 1)} #{dir}/log")
        next = follow_step(
          state,
          status_of(r),
          stdout_of(r),
          (rows) -> write_stdout(unlines(rows))
        )
        if next[:code].nil?
          sleep(poll_seconds)
        end
        next
      end
    end,
    {seen: 0, code: nil, misses: 0},
    range(0, floor(deadline_seconds / poll_seconds))
  )
end

def gone_on_host?(host, dir)
  status_of(on_host_sh(host, "test ! -e #{dir}")) == 0
end

def settled(step, run)
  write_stdout(unlines(["kernel/run: #{step}"]))
  r = run()
  if status_of(r) != 0
    raise(:on_host, "#{step}: #{stderr_of(r)}")
  end
  stdout_of(r)
end

def must(step, argv)
  settled(step, () -> exec_capture(first(argv), *rest(argv)))
end

def must_on(step, host, script)
  settled(step, () -> on_host_sh(host, script))
end

@doc """
transport_of: How REF reaches the host: fetched there from origin when origin holds it, since a host often has a faster road to origin than to this machine (20 MB took over 2 hours from a laptop, and a fetch takes seconds), and sent as a tree when it does not. `on.transport` holds it to :fetch or :send.

    transport_of("auto", "  origin/main\n") #=> :fetch
    transport_of("auto", "") #=> :send
    transport_of("send", "  origin/main\n") #=> :send
    transport_of("fetch", "") #=> :fetch
"""
def transport_of(setting, pushed)
  if setting == "send"
    :send
  elsif setting == "fetch" or trim(pushed) != ""
    :fetch
  else
    :send
  end
end

@doc """
fetch_line: The tree at one commit, fetched by the host itself with no history.

    contains?(fetch_line("/r/a", "https://o/x", "abc"), "--depth 1 https://o/x abc") #=> true
"""
def fetch_line(dir, origin, sha)
  join(
    [
      "git init -q #{dir}/src",
      "git -C #{dir}/src fetch -q --depth 1 #{origin} #{sha}",
      "git -C #{dir}/src -c advice.detachedHead=false checkout -q FETCH_HEAD"
    ],
    " && "
  )
end

def send_tree(host, dir, sha, id)
  tree = "#{getenv("TMPDIR") or "/tmp"}/blue-kernel-#{id}.tar"
  must("archive #{sha}", ["git", "archive", "--format=tar", "-o", tree, sha])
  must(
    "send",
    ["scp", "-q", "-o", "BatchMode=yes", tree, "#{host}:#{dir}/src.tar"]
  )
  rm(tree)
  must_on("unpack", host, "tar -xf #{dir}/src.tar -C #{dir}/src")
end

@doc """
on_host: A whole run on another machine, from this one, in one command: admission read from the host, REF fetched there or sent as a tree (`transport_of`), a directory only this run owns, the shared lock, a detached run that outlives this session, its log followed, and the host's runner removing the directory when this side has read it.

    last(ssh_argv("plo")) #=> "/bin/sh -s"
"""
def on_host(host, ref, config)
  on = config[:on]
  id = "run-#{to_s(now_ms)}"
  dir = "#{on[:root]}/#{id}"
  probe = probe_of(
    must_on(
      "admission on #{host}",
      host,
      "cat /proc/loadavg; nproc; ps -eo state="
    )
  )
  verdict = admission(
    config[:admission],
    probe[:load],
    probe[:cores],
    probe[:stalled]
  )
  if not verdict[:admitted]
    write_stderr(unlines(["kernel/run: refused: #{verdict[:why]}"]))
    exit_with(3)
  end
  must_on("directory #{dir}", host, "mkdir -p #{dir}/src")
  sha = trim(must("resolve #{ref}", ["git", "rev-parse", "#{ref}^{commit}"]))
  pushed = stdout_of(exec_capture("git", "branch", "-r", "--contains", sha))
  if transport_of(on[:transport], pushed) == :fetch
    must_on("fetch #{sha} on #{host}", host, fetch_line(dir, on[:origin], sha))
  else
    send_tree(host, dir, sha, id)
  end
  must_on(
    "detach under #{on[:lock]}",
    host,
    detach_line(
      dir,
      on[:lock],
      config[:build][:jobs],
      settings_words(config),
      config[:build][:private_cache]
    )
  )
  final = follow(host, dir, on[:poll_seconds], on[:deadline_seconds])
  if final[:code].nil?
    write_stderr(
      unlines(
        [
          "🔴 kernel/run: no exit line after #{to_s(on[:deadline_seconds])}s; the run stays detached in #{dir}, and it removes that directory itself"
        ]
      )
    )
    exit_with(1)
  elsif final[:code] == :gone
    write_stderr(
      unlines(
        [
          "🔴 kernel/run: #{dir} went before its exit line was read: the run ended past its linger, and it cleaned up"
        ]
      )
    )
    exit_with(1)
  end
  must_on("collected", host, "touch #{dir}/collected")
  if not on[:cleanup]
    write_stdout(unlines(["kernel/run: #{dir} stays on #{host}, as asked"]))
    exit_with(final[:code])
  end
  gone = find(
    range(0, 12),
    fn(_at)
      here = gone_on_host?(host, dir)
      if not here
        sleep(5)
      end
      here
    end
  )
  if gone.nil?
    write_stderr(
      unlines(
        [
          "🔴 kernel/run: #{dir} is still on #{host}; the next run there sweeps it"
        ]
      )
    )
    exit_with(
      if final[:code] == 0
        1
      else
        final[:code]
      end
    )
  end
  write_stdout(unlines(["kernel/run: nothing left on #{host}"]))
  exit_with(final[:code])
end

def main()
  config = settei::read("kernel-run", config_defaults)
  args = argv
  if first(args) == "on" and count(args) >= 2
    on_host(args[1], args[2] or "HEAD", config)
  elsif first(args) == "host" and count(args) == 2
    host_run(args[1], config)
  elsif args != []
    write_stderr(
      unlines(["usage: blue kernel/run.b [on HOST [REF]] | host RUN_DIRECTORY"])
    )
    exit_with(2)
  else
    code = run_suites(config)
    if code != 0
      exit_with(code)
    end
  end
end

test "a run's nix reads a cache of its own, and the off switch hands it back the host's"
  assert private_cache({private_cache: true}, "/r") ==
    "/r/target/kernel-run/cache"
  assert private_cache({private_cache: false}, "/r").nil?
  c = build_command(3, "/r/c")
  assert first(c) == "env"
  assert member?("XDG_CACHE_HOME=/r/c", c)
  assert not member?("XDG_CACHE_HOME=/r/c", build_command(3, nil))
  assert first(build_command(3, nil)) == "nice"
  assert cache_env("/r/c") == [%w[XDG_CACHE_HOME /r/c]]
  assert cache_env(nil) == []
  assert tool_dirs(false, "/r/c") == []
end

test "a filter that keeps no test of a suite does not turn that suite red"
  assert filtered_out?("no test name contains \"x\"", "x")
  assert not filtered_out?("no test name contains \"x\"", "")
  assert not filtered_out?("1 failed", "x")
  assert run_step(1, 1, "f", () -> %w[env false], "")[:green] == false
  assert run_step(1, 1, "f", () -> %w[env false], "x")[:green] == false
end

test "a finished suite says its tally at once, and a red one says all it said"
  green = {
    name: "s",
    green: true,
    output: unlines(["x", "2 test(s): 2 passed, 0 failed"])
  }
  assert step_report(green) == unlines(["s: 2 test(s): 2 passed, 0 failed"])
  skipped = assoc(
    green,
    :output,
    unlines(["skipped on 6.6.1: x", "1 test(s): 1 passed, 0 failed"])
  )
  assert contains?(step_report(skipped), "s: skipped on 6.6.1: x")
  assert step_report({name: "s", green: false, output: "boom"}) == "boom"
end

test "a host line survives its shell, and every word of a value stays one word"
  assert shell_word("") == "''"
  assert contains?(shell_word("a'b"), "\\''")
  line = detach_line("/r/a", "/tmp/l", 3, ["A='1'"], true)
  assert contains?(line, "setsid -f")
  assert contains?(line, "flock /tmp/l")
  assert contains?(line, "/r/a/log")
  assert contains?(line, "/r/a/pid")
end

test "the host's build is at idle priority, under a private cache, and a failed one still ends the log"
  h = hold_line("/r/a", 3, ["K='v'"], true)
  assert not contains?(hold_line("/r/a", 3, [], false), "XDG_CACHE_HOME")
  assert contains?(h, "nice -n 19 ionice -c3 nix build")
  assert contains?(h, "XDG_CACHE_HOME=/r/a/src/target/kernel-run/cache")
  assert contains?(h, "K='v'")
  assert contains?(h, "kernel/run.b host /r/a")
  assert contains?(h, "|| echo")
  assert contains?(h, exit_line(1))
  assert not contains?(h, "~")
end

test "a commit origin holds is fetched by the host, and one it does not is sent"
  assert transport_of("auto", "  origin/x") == :fetch
  assert transport_of("auto", " ") == :send
  assert transport_of("send", "  origin/x") == :send
  assert transport_of("fetch", "") == :fetch
  assert contains?(
    fetch_line("/r", "https://o/x", "abc"),
    "/r/src fetch -q --depth 1 https://o/x abc"
  )
end

test "a filter and an off switch on the laptop reach the host's run"
  words = settings_words(
    assoc(
      assoc(
        config_defaults,
        :suite,
        {seconds: 1, net_seconds: 2, filter: "fexit"}
      ),
      :admission,
      {enabled: false, load_per_core: 1, max_stalled: 4}
    )
  )
  assert member?("KERNEL_RUN_SUITE__FILTER='fexit'", words)
  assert member?("KERNEL_RUN_ADMISSION__ENABLED='false'", words)
  assert member?("KERNEL_RUN_BUILD__ENABLED='false'", words)
end

test "a host's probe reads as admission reads it, and a busy one is refused"
  p = probe_of(unlines(["20.0 1 1 1/9 2", "8", "S", "D", "R"]))
  assert p == {load: 20.0, cores: 8, stalled: 1}
  assert not get(
    admission(config_defaults[:admission], p[:load], p[:cores], p[:stalled]),
    :admitted
  )
end

test "a log is read whole lines at a time, each once, and a dropped session costs only a miss"
  seen = fn(state, status, text)
    follow_step(state, status, text, (_rows) -> nil)
  end
  start = {seen: 0, code: nil, misses: 0}
  assert seen(start, 0, "half") == start
  assert seen(start, 0, "") == start
  one = seen(start, 0, unlines(%w[a b]))
  assert one[:seen] == 2
  assert one[:code].nil?
  assert seen(one, 255, "")[:misses] == 1
  assert seen(one, 1, "")[:code] == :gone
  assert seen(one, 0, unlines([exit_line(1)]))[:code] == 1
  assert seen(one, 0, unlines([exit_line(0)]))[:code] == 0
end

test "only a run whose runner has gone is swept"
  assert stale_run?("run-5", "1", false, 6, 1000)
  assert not stale_run?("run-5", "1", true, 99999, 1000)
  assert not stale_run?("run-5", nil, false, 6, 1000)
  assert stale_run?("run-5", nil, false, 99999, 1000)
  assert stale_run?("other", nil, false, 99999, 1000)
end

test "this runner removes what it made, and only that"
  root = "#{getenv("TMPDIR") or "/tmp"}/kernel-run-sweep-#{to_s(now_ms)}"
  mine = "#{root}/run-1"
  dead = "#{root}/run-2"
  mkdir_p("#{mine}/src")
  mkdir_p("#{dead}/src")
  write_file("#{mine}/pid", "1")
  write_file("#{dead}/pid", "999999999")
  blank = "#{root}/run-3"
  mkdir_p(blank)
  write_file("#{blank}/pid", "")
  assert sweep_runs(root, mine, 1000) == [dead, blank]
  assert path_exists(mine)
  assert not path_exists(dead)
  assert remove_run(root)
  assert not path_exists(root)
end

test "a busy host is refused and names why, and the off switch lets it through"
  s = config_defaults[:admission]
  assert admission(s, 1, 8, 0)[:admitted]
  assert not admission(s, 9, 8, 0)[:admitted]
  assert not admission(s, 1, 8, 5)[:admitted]
  assert contains?(admission(s, 1, 8, 5)[:why], "D state")
  assert admission(assoc(s, :enabled, false), 99, 8, 99)[:admitted]
end

test "no tasks stalled and an empty listing count nothing"
  assert stalled_of("") == 0
  assert stalled_of(unlines(%w[S R])) == 0
  assert stalled_of(unlines([" D", "DN"])) == 2
end

test "what a run adds is named, and what it removes is not"
  was = {links: 4, netns: 1, pins: 2, cgroups: 0}
  assert left_behind(was, was) == []
  assert left_behind(was, {links: 3, netns: 0, pins: 0, cgroups: 0}) == []
  assert left_behind(was, {links: 4, netns: 2, pins: 2, cgroups: 0}) == [:netns]
  assert left_behind(was, assoc(was, :cgroups, 1)) == [:cgroups]
end

test "a suite's tally is its last, and a log with none has none"
  assert tally_of(
    unlines(["1 test(s): 1 passed, 0 failed", "2 test(s): 2 passed, 0 failed"])
  ) == "2 test(s): 2 passed, 0 failed"
  assert tally_of("no tally").nil?
end

test "a suite is told what its kernel must answer, through sudo"
  assert suite_words((n) -> get({"KERNEL_SUITE_DIVISION_GUARD" => "off"}, n)) ==
    ["KERNEL_SUITE_DIVISION_GUARD=off"]
  assert suite_words((_n) -> nil) == []
end

test "a suite runs bounded, at low priority, in the environment it was given"
  assert not member?("--filter", suite_command("x.b", 9, "b", [], ""))
  assert member?("fexit", suite_command("x.b", 9, "b", [], "fexit"))
  c = suite_command("kernel/suite.b", 900, "/b/blue", %w[A=1 B=2], "")
  assert first(c) == "env"
  assert member?("A=1", c)
  assert member?("900", c)
  assert member?("timeout", c)
  assert member?("nice", c)
  assert last(c) == "kernel/suite.b"
end

test "the build is held to idle priority and few jobs"
  c = build_command(3, nil)
  assert member?("-c3", c)
  assert member?("19", c)
  assert member?("CARGO_BUILD_JOBS=3", c)
end
