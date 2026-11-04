@moduledoc """
run: Run every real-kernel suite on this machine and judge what they left
behind. A busy machine is refused before anything loads, because a loaded host
reads as a broken BPF. The build runs at idle priority and the network suite
inside its own namespace.

    blue kernel/run.b

Settings are `kernel-run`'s, through `settei`. `admission.enabled` turns the
refusal off, `build.enabled` the build, `tools.from_nix` the nix lookup of
`ip`, `ping` and the object oracles, and `suite.filter` keeps the tests whose name
holds it.
"""

use("gamen", [:show_step])

use("retsu", %i[enumerate first last rest])

use("settei")

use("shinchoku", [:load_and_cores])

use("shisutemu", %i[blue_exe status_of stderr_of stdout_of])

@doc """
config_defaults: What `kernel-run` does when nothing says otherwise.

    config_defaults[:admission][:max_stalled] #=> 4
"""
def config_defaults()
  {
    admission: {enabled: true, load_per_core: 1, max_stalled: 4},
    build: {enabled: true, jobs: 3},
    tools: {from_nix: true},
    suite: {seconds: 900, net_seconds: 300, filter: ""}
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
build_command: The checkout's blue, built at idle priority so the host stays
responsive.

    last(build_command(3)) #=> "blue-lang-cli"
    first(build_command(3)) #=> "nice"
"""
def build_command(jobs)
  append(
    %w[nice -n 19 ionice -c3 nix develop --accept-flake-config -c env],
    ["CARGO_BUILD_JOBS=#{to_s(jobs)}"],
    %w[cargo build -p blue-lang-cli]
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
not carry. It is a test oracle, and nothing in a build needs it.

    contains?(veristat_expression, "libbpf") #=> true
"""
def veristat_expression()
  join(
    [
      "let pkgs = (builtins.getFlake \"nixpkgs\").legacyPackages.${builtins.currentSystem}; in",
      "pkgs.stdenv.mkDerivation {",
      "pname = \"veristat\"; version = \"0.5.1\";",
      "src = pkgs.fetchFromGitHub { owner = \"libbpf\"; repo = \"veristat\"; rev = \"v0.5.1\"; fetchSubmodules = true;",
      "hash = \"sha256-kYAr40GFAd2fn9zyUayHbfImQHLfjp6SO9rZGDA+rAU=\"; };",
      "nativeBuildInputs = [ pkgs.pkg-config ];",
      "buildInputs = [ pkgs.elfutils pkgs.zlib pkgs.zstd ];",
      "hardeningDisable = [ \"all\" ];",
      "makeFlags = [ \"-C\" \"src\" ];",
      "installPhase = \"mkdir -p $out/bin; cp src/veristat $out/bin/\";",
      "}"
    ],
    " "
  )
end

@doc """
veristat_dir: The directory that holds a built `veristat`.

    string?(veristat_expression) #=> true
"""
def veristat_dir()
  r = exec_capture(
    "nix",
    "build",
    "--impure",
    "--no-link",
    "--print-out-paths",
    "--expr",
    veristat_expression
  )
  if status_of(r) != 0
    raise(:missing_tool, "nix cannot build veristat: #{stderr_of(r)}")
  end
  "#{trim(stdout_of(r))}/bin"
end

@doc """
tool_dirs: The directories that hold `ip`, `ping` and the object suite's oracles:
nix's when `from_nix`, and none when PATH already has them.

    tool_dirs(false) #=> []
"""
def tool_dirs(from_nix)
  if from_nix
    r = exec_capture(
      "nix",
      "build",
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
    append(map((p) -> "#{trim(p)}/bin", rows_of(stdout_of(r))), [veristat_dir])
  else
    []
  end
end

@doc """
run_step: One step of the run, shown as it goes; its verdict and output.

    run_step(1, 1, "true", () -> ["env", "true"])[:green] #=> true
"""
def run_step(at, of, name, argv_of)
  show_step({state: :running, at:, of:, name:}, {})
  t = now_ms
  argv = argv_of()
  r = exec_capture(first(argv), *rest(argv))
  green = status_of(r) == 0
  state = if green
    :done
  else
    :failed
  end
  show_step({state:, at:, of:, name:, ms: now_ms - t}, {})
  {name:, green:, output: "#{stdout_of(r)}#{stderr_of(r)}"}
end

@doc """
refuse_when_busy: Stop here, naming why, when the host cannot carry the run.

    refuse_when_busy({admitted: true, why: ""}) #=> nil
"""
def refuse_when_busy(verdict)
  if not verdict[:admitted]
    write_stderr(unlines(["kernel/run: refused: #{verdict[:why]}"]))
    exit_with(3)
  end
  nil
end

def main()
  config = settei::read("kernel-run", config_defaults)
  lc = load_and_cores
  refuse_when_busy(
    admission(
      config[:admission],
      first(lc) or 0,
      last(lc) or 1,
      stalled_of(stdout_of(exec_capture("ps", "-eo", "state=")))
    )
  )
  dirs = tool_dirs(config[:tools][:from_nix])
  ip = if dirs == []
    "ip"
  else
    "#{first(dirs)}/ip"
  end
  blue = if config[:build][:enabled]
    "#{getenv("PWD")}/target/debug/blue"
  else
    blue_exe
  end
  env = [
    "BLUE_TEST_WRITES=anywhere",
    "BLUE_PATH=#{getenv("PWD")}/bidamas",
    "PATH=#{join(dirs, ":")}:/run/current-system/sw/bin:#{getenv("PATH")}"
  ]
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
    [["build", () -> build_command(config[:build][:jobs])]]
  else
    []
  end
  steps = append(
    build,
    [
      [
        "kernel/suite.b",
        fn()
          append(
            %w[sudo -n],
            suite_command(
              "kernel/suite.b",
              config[:suite][:seconds],
              blue,
              env,
              config[:suite][:filter]
            )
          )
        end
      ],
      [
        "kernel/object_suite.b",
        fn()
          append(
            %w[sudo -n],
            suite_command(
              "kernel/object_suite.b",
              config[:suite][:seconds],
              blue,
              env
            )
          )
        end
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
    (p) -> run_step(first(p) + 1, total, first(last(p)), last(last(p))),
    enumerate(steps)
  )
  map(
    fn(r)
      if r[:green]
        tally = tally_of(r[:output])
        if tally != nil
          write_stdout(unlines(["#{r[:name]}: #{tally}"]))
        end
      else
        write_stderr(r[:output])
      end
    end,
    results
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
    exit_with(1)
  elsif red != []
    write_stderr(unlines(["🔴 kernel/run: red: #{join(red, ", ")}"]))
    exit_with(1)
  else
    write_stdout(
      unlines(["🟢 kernel/run: every suite green, nothing left behind"])
    )
  end
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
  c = build_command(3)
  assert member?("-c3", c)
  assert member?("19", c)
  assert member?("CARGO_BUILD_JOBS=3", c)
end
