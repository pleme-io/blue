#!/usr/bin/env -S blue --allow host
use(
  "hadome",
  %i[
    failures_within
    judge_within
    measurement
    parse
    receipted
    recorded
    render
    shrunk
  ]
)

use("hikisuu", [:flag])
use("kazu", [:max])
use("kyohi", [:why])
use("moji", %i[after_first before_first includes lines trim])
use("retsu", %i[first is_empty size])
use("shisutemu", %i[read_or status_of stderr_of])

BASELINE = "bench/cost.baseline"

def record(i)
  "{\"id\": #{i}, \"value\": #{i % 1000}, \"name\": \"item-#{i}\", \"tags\": [\"alpha\", \"beta\"]}"
end

def json_text(n)
  unlines(["[#{join(map(record, range(n)), unlines([","]))}]"])
end

def vocabulary()
  map((i) -> "w#{i * 7919 % 1009}x", range(600))
end

def word(words, i)
  words[i * 2_654_435_761 % 4_294_967_296 % length(words)]
end

def text(words, n)
  join(map((i) -> word(words, i), range(n)), " ")
end

def write_data(dir)
  mkdir_p(dir)
  write_file(path_join(dir, "records.json"), json_text(17000))
  write_file(path_join(dir, "words.txt"), unlines([text(vocabulary, 800_000)]))
end

def workloads()
  [
    ["empty", nil],
    ["hello", nil],
    ["fib", nil],
    ["pipeline", nil],
    ["strbuild", nil],
    %w[json_sum records.json],
    %w[wordfreq words.txt],
    ["spawn", nil]
  ]
end

def hyperfine(command, runs, out)
  exec_capture(
    "hyperfine",
    "-N",
    "--warmup",
    "2",
    "--runs",
    to_s(runs),
    "--export-json",
    out,
    command
  )
  json_get(json_parse(read_file(out)), :results)[0]
end

def ms(seconds)
  round(seconds * 10000) / 10
end

def measure(command, runs, out)
  r = hyperfine(command, runs, out)
  {
    mean: ms(json_get(r, :mean)),
    sd: ms(json_get(r, :stddev)),
    user: ms(json_get(r, :user))
  }
end

def command(exe, file, arg, data)
  if arg.nil?
    "#{exe} #{file}"
  else
    "#{exe} #{file} #{path_join(data, arg)}"
  end
end

def cell(m)
  "#{m.mean} ± #{m.sd} (user #{m.user})"
end

def ratio(a, b)
  round(a.mean / max(b.mean, 0.1) * 10) / 10
end

def language_row(langs, w, work, runs)
  name = w[0]
  arg = w[1]
  data = path_join(work, "data")
  timed = map(
    fn(l)
      file = path_join(work, "#{name}.#{l[0]}")
      measure(
        command(l[1], file, arg, data),
        runs,
        path_join(work, "#{name}-#{l[0]}.json")
      )
    end,
    langs
  )
  b = timed[0]
  py = timed[1]
  rb = timed[2]
  unlines(
    [
      "| #{name} | #{cell(b)} | #{cell(py)} | #{cell(rb)} | #{ratio(b, py)}× | #{ratio(b, rb)}× |"
    ]
  )
end

def copy_workloads(src, work, names)
  map(
    fn(n)
      map(
        fn(ext)
          write_file(
            path_join(work, "#{n}.#{ext}"),
            read_file(path_join(src, "#{n}.#{ext}"))
          )
        end,
        %w[b py rb]
      )
    end,
    names
  )
end

def tooling_rows(blue, work)
  files = filter(
    (f) -> f != "",
    split(stdout_of(exec_capture("git", "ls-files", "*.b")), line_break)
  )
  large = "bidamas/kueri/kueri.b"
  one = measure(
    "#{blue} fmt --check #{large}",
    10,
    path_join(work, "fmt-one.json")
  )
  all = measure(
    "#{blue} fmt --check #{join(files, " ")}",
    3,
    path_join(work, "fmt-all.json")
  )
  started = now_ms
  map((f) -> exec_capture(blue, "check", f), files)
  checked = now_ms - started
  join(
    [
      unlines(["| `fmt --check` #{large} | #{cell(one)} |"]),
      unlines(
        ["| `fmt --check` all #{length(files)} tracked files | #{cell(all)} |"]
      ),
      unlines(
        [
          "| `check`, one process per file, #{length(files)} files | #{checked} (one run) |"
        ]
      )
    ],
    ""
  )
end

def stdout_of(cap)
  json_get(cap, :stdout)
end

def timed_build(target, profile)
  started = now_ms
  cap = exec_with_env(
    [
      ["RUSTC_WRAPPER", ""],
      ["CARGO_BUILD_RUSTC_WRAPPER", ""],
      ["CARGO_TARGET_DIR", target]
    ],
    "cargo",
    "build",
    "--profile",
    profile,
    "-p",
    "blue-lang-cli"
  )
  if json_get(cap, :status) != 0
    raise(:build, json_get(cap, :stderr))
  end
  (now_ms - started) / 1000
end

def touched(file)
  write_file(file, read_file(file))
  file
end

def compile_row(target, profile)
  rm_rf(target)
  clean = timed_build(target, profile)
  touched("crates/blue-lang-art/src/lib.rs")
  leaf = timed_build(target, profile)
  touched("crates/blue-lang-runtime/src/lib.rs")
  runtime = timed_build(target, profile)
  rm_rf(target)
  unlines(["| #{profile} | #{clean} | #{leaf} | #{runtime} |"])
end

def compile_rows(target)
  join(
    [
      unlines(
        ["| profile | clean s | leaf crate touched s | blue-lang-runtime touched s |"]
      ),
      unlines(["|---|---|---|---|"]),
      compile_row(target, "dev"),
      compile_row(target, "release")
    ],
    ""
  )
end

def scripts(blue, langs, work, runs)
  names = map((w) -> w[0], workloads)
  write_data(path_join(work, "data"))
  copy_workloads("bench/workloads", work, names)
  write_stdout(
    unlines(
      ["| workload | blue ms | python ms | ruby ms | blue/python | blue/ruby |"]
    )
  )
  write_stdout(unlines(["|---|---|---|---|---|---|"]))
  map((w) -> write_stdout(language_row(langs, w, work, runs)), workloads)
  write_stdout(unlines(["", "| tooling | ms |", "|---|---|"]))
  write_stdout(tooling_rows(blue, work))
end

@doc """
gated: Each cost a workload's run is judged on, its baseline kind and its tolerance in per mille. Steps are the evaluator's and the same on every host; allocations and bytes are keyed by host.

    map((g) -> g[:kind], gated) #=> ["bench-steps", "bench-allocs", "bench-bytes"]
"""
def gated()
  [
    {field: :steps, kind: "bench-steps", permille: 5, hosted: false},
    {field: :allocs, kind: "bench-allocs", permille: 20, hosted: true},
    {field: :bytes, kind: "bench-bytes", permille: 20, hosted: true}
  ]
end

@doc """
quick: The workloads the pre-push gate runs: no data to write, under a second.

    quick #=> ["empty", "hello", "fib"]
"""
def quick()
  %w[empty hello fib]
end

@doc """
timing_rows: A `blue run --timings` report read by its first word, every row's number kept.

    timing_rows(unlines(["total        4.8 ms", "steps    7"])) #=> {"total" => "4.8", "steps" => "7"}
"""
def timing_rows(text)
  reduce(
    fn(acc, l)
      t = trim(l)
      if includes(t, " ")
        assoc(
          acc,
          before_first(t, " "),
          first(split(trim(after_first(t, " ")), " "))
        )
      else
        acc
      end
    end,
    {},
    lines(text)
  )
end

@doc """
cost_of: One workload's run as its costs: steps, allocations and bytes as counts, wall time in ms. A count the report lacks is nil, never zero.

    cost_of("fib", {"steps" => "7", "allocs" => "3", "bytes" => "9", "total" => "4.5"}) #=> {name: "fib", steps: 7, allocs: 3, bytes: 9, ms: 4.5}
"""
def count_of(text)
  if text.nil?
    nil
  else
    to_int(text)
  end
end

def cost_of(name, rows)
  {
    name:,
    steps: count_of(rows["steps"]),
    allocs: count_of(rows["allocs"]),
    bytes: count_of(rows["bytes"]),
    ms: if rows["total"].nil?
      nil
    else
      to_float(rows["total"])
    end
  }
end

def run_cost(blue, w, work)
  name = w[0]
  data = path_join(work, "data")
  file = path_join(work, "#{name}.b")
  write_program(file, read_file("bench/workloads/#{name}.b"))
  args = if w[1].nil?
    [file]
  else
    [file, path_join(data, w[1])]
  end
  cap = exec_capture(
    blue,
    "run",
    "--quiet",
    "--no-memo",
    "--door",
    "walker",
    "--timings",
    "--allow",
    "host",
    *args
  )
  if status_of(cap) != 0
    raise(:bench, "#{name}: #{stderr_of(cap)}")
  end
  cost_of(name, timing_rows(stderr_of(cap)))
end

@doc """
levers: The lever rows of docs/PERFORMANCE.md section 3.0: each a blue program in
bench/levers that does less work by a lever blue's knowledge enables, and a plain
Rust twin in bench/native that does the whole job every run. `memo` answers
repeated pure calls in process; `bake` runs against a store a build already filled
(nothing changed); `incremental` runs after one of the program's 64 inputs changed,
so one chunk is computed and 63 are answered from the store; `hexmsg` is the
hex round trip of a framed message, the hot path a decoder run showed. Each is a
cost row (steps on the walker door) and a ratio row against its twin.

    map((l) -> l.name, levers) #=> ["memo", "bake", "incremental", "hexmsg"]
"""
def levers()
  [
    {
      name: "memo",
      lever: "memo by identity",
      program: "memo",
      memo: "process",
      primed: false,
      edit: nil,
      rust: "fib",
      rust_args: ["38"]
    },
    {
      name: "bake",
      lever: "bake",
      program: "incremental",
      memo: "on",
      primed: true,
      edit: 0,
      rust: "incremental",
      rust_args: ["0"]
    },
    {
      name: "incremental",
      lever: "incremental",
      program: "incremental",
      memo: "on",
      primed: true,
      edit: 1,
      rust: "incremental",
      rust_args: ["1"]
    },
    {
      name: "hexmsg",
      lever: "linear library word",
      program: "hexmsg",
      memo: nil,
      primed: false,
      edit: nil,
      rust: "hexmsg",
      rust_args: []
    }
  ]
end

@doc """
with_line: The text with the line that starts with `prefix` set to `prefix` and `value`.

    with_line(unlines(["EDIT = 0", "f(EDIT)"]), "EDIT = ", 1) #=> unlines(["EDIT = 1", "f(EDIT)"])
"""
def with_line(text, prefix, value)
  unlines(
    map(
      fn(l)
        if starts_with?(l, prefix)
          "#{prefix}#{to_s(value)}"
        else
          l
        end
      end,
      lines(text)
    )
  )
end

def lever_file(spec, work, edit)
  file = path_join(work, "levers", "#{spec.name}-#{to_s(edit)}.b")
  mkdir_p(path_join(work, "levers"))
  text = read_file("bench/levers/#{spec.program}.b")
  write_program(
    file,
    if edit.nil?
      text
    else
      with_line(text, "EDIT = ", edit)
    end
  )
  file
end

def lever_store(spec, work)
  path_join(work, "store-#{spec.name}")
end

@doc """
lever_run: The command that runs a lever's program: its memo mode and store, the walker
door, and `extra` flags before the file.

    lever_run("blue", {memo: nil}, "/w/s", ["--timings"], "/w/p.b") #=> ["env", "BLUE_MEMO=off", "blue", "run", "--quiet", "--door", "walker", "--allow", "host", "--no-memo", "--timings", "/w/p.b"]
"""
def lever_run(blue, spec, store, extra, file)
  memo = if spec.memo.nil?
    ["BLUE_MEMO=off"]
  else
    ["BLUE_MEMO=#{spec.memo}", "XDG_CACHE_HOME=#{store}"]
  end
  off = if spec.memo.nil?
    ["--no-memo"]
  else
    []
  end
  append(
    ["env"],
    memo,
    [blue, "run", "--quiet", "--door", "walker", "--allow", "host"],
    off,
    extra,
    [file]
  )
end

def run_checked(command, what)
  cap = exec_capture(*command)
  if status_of(cap) != 0
    raise(:bench, "#{what}: #{stderr_of(cap)}")
  end
  cap
end

def prime(blue, spec, work)
  store = lever_store(spec, work)
  rm_rf(store)
  if spec.primed
    run_checked(
      lever_run(blue, spec, store, [], lever_file(spec, work, 0)),
      "#{spec.name} (priming the store)"
    )
  end
  store
end

def lever_cost(blue, spec, work)
  store = prime(blue, spec, work)
  cap = run_checked(
    lever_run(
      blue,
      spec,
      store,
      ["--timings"],
      lever_file(spec, work, spec.edit)
    ),
    spec.name
  )
  cost_of(spec.name, timing_rows(stderr_of(cap)))
end

@doc """
row_key: A cost's baseline key: the workload, and the host for a hosted cost.

    row_key({hosted: true}, "fib", "darwin") #=> "fib darwin"
"""
def row_key(g, name, host)
  if g[:hosted]
    "#{name} #{host}"
  else
    name
  end
end

def measures_of(g, costs, host)
  map((c) -> measurement(row_key(g, c[:name], host), get(c, g[:field])), costs)
end

@doc """
hosted_here: Whether a baseline holds any row of a hosted kind for this host. Until it does, that kind is advisory here, never read as held.

    hosted_here([], {kind: "bench-allocs", hosted: true}, "linux") #=> false
"""
def hosted_here(rows, g, host)
  if not g[:hosted]
    true
  else
    not is_empty(
      filter(
        (r) -> r[:kind] == g[:kind] and ends_with?(r[:key], " #{host}"),
        rows
      )
    )
  end
end

@doc """
fell: The measures below their row by more than the tolerance, worth banking; a fall inside it is noise.

    fell([], {kind: "bench-steps", permille: 5}, []) #=> []
"""
def fell(rows, g, ms)
  filter(
    fn(m)
      m[:size] * 1000 <
        recorded(rows, g[:kind], m[:key]) * (1000 - g[:permille])
    end,
    shrunk(rows, g[:kind], ms)
  )
end

@doc """
judged: Every gated cost of every workload against the baseline rows: the refusals, the falls past the tolerance, and the kinds this host has no rows for yet.

    judged([], [], "darwin")[:refusals] #=> []
"""
def judged(rows, costs, host)
  reduce(
    fn(acc, g)
      ms = measures_of(g, costs, host)
      if hosted_here(rows, g, host)
        {
          refusals: append(
            acc[:refusals],
            failures_within(rows, g[:kind], ms, g[:permille])
          ),
          fell: append(acc[:fell], fell(rows, g, ms)),
          unhosted: acc[:unhosted]
        }
      else
        assoc(acc, :unhosted, append(acc[:unhosted], [g[:kind]]))
      end
    end,
    {refusals: [], fell: [], unhosted: []},
    gated
  )
end

@doc """
banked: The size a record writes for one measure: a fall is banked, a rise within the tolerance keeps the old row so the baseline cannot creep, and anything else is the measure.

    banked([], {kind: "bench-steps", permille: 5}, measurement("fib", 9)) #=> {key: "fib", size: 9}
"""
def banked(rows, g, m)
  r = recorded(rows, g[:kind], m[:key])
  held = get(
    judge_within(rows, g[:kind], m[:key], m[:size], g[:permille]),
    :verdict
  ) == :held
  if held and m[:size] > r
    measurement(m[:key], r)
  else
    m
  end
end

@doc """
recorded_rows: The rows a record writes for one kind: this run's measures, banked, and every other host's rows of a hosted kind kept as they were.

    recorded_rows([], {kind: "bench-steps", permille: 5, hosted: false, field: :steps}, [], "darwin") #=> []
"""
def recorded_rows(rows, g, costs, host)
  here = map((m) -> banked(rows, g, m), measures_of(g, costs, host))
  others = if g[:hosted]
    map(
      (r) -> measurement(r[:key], r[:size]),
      filter(
        (r) -> r[:kind] == g[:kind] and not ends_with?(r[:key], " #{host}"),
        rows
      )
    )
  else
    []
  end
  append(here, others)
end

@doc """
raises: Every measure a record would raise or add: new, or past its row's tolerance. A rise within the tolerance keeps the old row, so it needs no reason.

    raises([], [], "darwin") #=> []
"""
def raises(rows, costs, host)
  reduce(
    fn(acc, g)
      append(
        acc,
        failures_within(
          rows,
          g[:kind],
          measures_of(g, costs, host),
          g[:permille]
        )
      )
    end,
    [],
    gated
  )
end

def baseline_text(old, receipt, rows, costs, host)
  receipted(
    old,
    receipt,
    join(
      map((g) -> render(g[:kind], recorded_rows(rows, g, costs, host)), gated),
      ""
    )
  )
end

def cost_line(c)
  "| #{c[:name]} | #{to_s(c[:steps])} | #{to_s(c[:allocs])} | #{to_s(c[:bytes])} | #{to_s(c[:ms])} |"
end

def host_name()
  downcase(trim(json_get(exec_capture("uname", "-s"), :stdout)))
end

def chosen(flags)
  if member?("--quick", flags)
    filter((w) -> member?(w[0], quick), workloads)
  else
    workloads
  end
end

def chosen_levers(flags)
  if member?("--quick", flags)
    []
  else
    levers
  end
end

def needs_data(ws)
  not is_empty(filter((w) -> not w[1].nil?, ws))
end

def cost_command(blue, work, flags)
  ws = chosen(flags)
  data = path_join(work, "data")
  mkdir_p(work)
  if needs_data(ws)
    write_data(data)
  end
  host = host_name
  costs = append(
    map((w) -> run_cost(blue, w, work), ws),
    map((l) -> lever_cost(blue, l, work), chosen_levers(flags))
  )
  write_stdout(
    unlines(
      append(
        [
          "| workload | steps | allocations | bytes | wall ms (not gated) |",
          "|---|---|---|---|---|"
        ],
        map(cost_line, costs)
      )
    )
  )
  old = read_or(BASELINE, "")
  rows = parse(old)
  if member?("--record", flags)
    record_costs(old, rows, costs, host, flags)
  else
    check_costs(rows, costs, host, size(costs))
  end
end

@doc """
receipt_kinds: The kinds of reason a raised row may carry, as `--receipt "<kind>: <why>"`:
the measure itself changed (`measurement`), a fix costs work (`correctness`), new
behaviour costs work (`capability`), or the toolchain or host changed (`platform`).
A slower release with any other reason, or none, is refused.

    receipt_kinds #=> ["measurement", "correctness", "capability", "platform"]
"""
def receipt_kinds()
  %w[measurement correctness capability platform]
end

@doc """
receipt_refusal: Why a receipt is not a typed reason, or nil when it is one: a kind
from receipt_kinds, a colon, and a reason. No receipt is no refusal.

    receipt_refusal(nil) #=> nil
    receipt_refusal("correctness: the overflow check") #=> nil
    receipt_refusal("faster later").nil? #=> false
"""
def receipt_refusal(receipt)
  if receipt.nil?
    nil
  else
    kind = trim(before_first(receipt, ":"))
    why = if includes(receipt, ":")
      trim(after_first(receipt, ":"))
    else
      ""
    end
    if not member?(kind, receipt_kinds) or why == ""
      "bench: a receipt is \"<kind>: <why>\" with a kind of #{join(receipt_kinds, ", ")}; got \"#{receipt}\""
    end
  end
end

def record_costs(old, rows, costs, host, flags)
  receipt = flag(flags, "--receipt")
  up = raises(rows, costs, host)
  refused = receipt_refusal(receipt)
  if not refused.nil?
    write_stdout(unlines([refused]))
    false
  elsif member?("--quick", flags)
    write_stdout(
      unlines(["bench: --record measures every workload; drop --quick"])
    )
    false
  elsif size(up) > 0 and receipt.nil?
    write_stdout(
      unlines(
        append(
          map(why, up),
          ["bench: a raised or new row needs a reason: blue bench/bench.b cost BLUE WORKDIR --record --receipt \"<kind>: <why>\""]
        )
      )
    )
    false
  else
    write_file(BASELINE, baseline_text(old, receipt, rows, costs, host))
    write_stdout(
      unlines(["recorded #{to_s(size(costs))} workload(s) to #{BASELINE}"])
    )
    true
  end
end

def check_costs(rows, costs, host, n)
  j = judged(rows, costs, host)
  bad = j[:refusals]
  write_stdout(
    unlines(
      [
        "ratchet bench (#{host}): #{to_s(n)} workload(s), #{to_s(size(bad))} grew or new, #{to_s(size(j[:fell]))} fell"
      ]
    )
  )
  map(
    fn(k)
      write_stdout(
        unlines(
          [
            "advisory: #{BASELINE} has no #{k} row for #{host}, so #{k} is not judged here; record it: blue bench/bench.b cost BLUE WORKDIR --record --receipt \"first #{host} measure\""
          ]
        )
      )
    end,
    j[:unhosted]
  )
  if size(j[:fell]) > 0
    write_stdout(
      unlines(["bank it: blue bench/bench.b cost BLUE WORKDIR --record"])
    )
  end
  if size(bad) > 0
    write_stdout(
      unlines(
        append(
          map(why, bad),
          [
            "fix: make it cheaper, or raise the row: blue bench/bench.b cost BLUE WORKDIR --record --receipt \"<kind>: <why>\" against #{BASELINE}"
          ]
        )
      )
    )
    false
  else
    true
  end
end

NATIVE_BASELINE = "bench/native.baseline"

@doc """
native_programs: The programs measured on every execution path: each is a corpus program
the interpreter and chuuzou run (native/corpus) with a hand-written Rust twin
(bench/native) that takes the program's `N` as its argument. The interpreter
runs the program at its own `N`; chuuzou and Rust run it at `big`, `work`
times the work, so a native run is long enough to time and not process
start. A program with no `N` runs as written on every path.

    map((p) -> p[:name], native_programs) #=> ["fib", "loop", "mutual", "shapes", "sums"]
"""
def native_programs()
  [
    {name: "fib", n: 30, big: 38, work: 39_088_169 / 832_040},
    {name: "loop", n: 3_000_000, big: 300_000_000, work: 100},
    {name: "mutual", n: nil, big: nil, work: 1},
    {name: "shapes", n: 1_000_000, big: 100_000_000, work: 100},
    {name: "sums", n: 100_000, big: 10_000_000, work: 100}
  ]
end

@doc """
scaled_source: The program's text with its `N = …` line set to `n`.

    scaled_source(unlines(["N = 3", "f(N)"]), 7) #=> unlines(["N = 7", "f(N)"])
"""
def scaled_source(text, n)
  unlines(
    map(
      fn(l)
        if starts_with?(l, "N = ")
          "N = #{to_s(n)}"
        else
          l
        end
      end,
      lines(text)
    )
  )
end

@doc """
native_paths: The execution paths a native row compares with Rust, each gated as its
time over Rust's, in per mille, with a tolerance wide enough for a loaded
machine's noise.

    map((p) -> p[:name], native_paths) #=> ["tree", "vm", "chuuzou"]
"""
def native_paths()
  [
    {name: "tree", field: :tree, permille: 500, scaled: true},
    {name: "vm", field: :vm, permille: 500, scaled: true},
    {name: "chuuzou", field: :chuuzou, permille: 500, scaled: false}
  ]
end

def cpu_ms(r)
  ms(json_get(r, :user) + json_get(r, :system))
end

def timed(command, runs, out)
  r = hyperfine(command, runs, out)
  {wall: ms(json_get(r, :mean)), cpu: cpu_ms(r)}
end

@doc """
per_mille: `a` over `b` in per mille, rounded; a zero `b` counts as 0.1 ms.

    per_mille(5, 2.5) #=> 2000
"""
def per_mille(a, b)
  round(a * 1000 / max(b, 0.1))
end

def output_of(command)
  cap = exec_capture(*command)
  if status_of(cap) != 0
    raise(:bench, "#{join(command, " ")} failed: #{stderr_of(cap)}")
  end
  stdout_of(cap)
end

def native_commands(blue, spec, work)
  name = spec.name
  bidamas = "BLUE_PATH=#{path_join(cwd, "native/bidamas")}"
  program = path_join(cwd, "native/corpus/#{name}.b")
  big_program = if spec.big.nil?
    program
  else
    mkdir_p(path_join(work, "big"))
    p = path_join(work, "big", "#{name}.b")
    write_program(p, scaled_source(read_file(program), spec.big))
    p
  end
  image = trim(
    output_of(
      [
        "env",
        bidamas,
        blue,
        "run",
        "--quiet",
        "native/build/host.b",
        big_program,
        path_join(work, name),
        path_join(cwd, "native/seam")
      ]
    )
  )
  rust = path_join(work, "#{name}-rust")
  output_of(
    [
      "rustc",
      "--edition",
      "2021",
      "-C",
      "opt-level=3",
      "-C",
      "codegen-units=1",
      "-o",
      rust,
      "bench/native/#{name}.rs"
    ]
  )
  arg = fn(n)
    if n.nil?
      []
    else
      [to_s(n)]
    end
  end
  {
    tree: ["env", bidamas, blue, "run", "--quiet", program],
    vm: ["env", bidamas, blue, "run", "--quiet", "--vm", program],
    chuuzou: [image],
    rust: append([rust], arg(spec.big)),
    rust_small: append([rust], arg(spec.n))
  }
end

@doc """
native_row: One program on every path: the three agree on what they print, then each
is timed; wall and CPU (user + system) in ms.
"""
def native_row(blue, spec, work, runs)
  name = spec.name
  c = native_commands(blue, spec, work)
  if output_of(c.tree) != output_of(c.rust_small)
    raise(:bench, "#{name}: the interpreter prints other than the Rust twin")
  end
  if output_of(c.vm) != output_of(c.rust_small)
    raise(:bench, "#{name}: the VM prints other than the Rust twin")
  end
  if output_of(c.chuuzou) != output_of(c.rust)
    raise(:bench, "#{name}: chuuzou's image prints other than the Rust twin")
  end
  out = path_join(work, "#{name}.json")
  {
    name:,
    work: spec.work,
    tree: timed(join(c.tree, " "), runs, out),
    vm: timed(join(c.vm, " "), runs, out),
    chuuzou: timed(join(c.chuuzou, " "), runs, out),
    rust: timed(join(c.rust, " "), runs, out)
  }
end

def native_cell(t)
  "#{t.wall} (cpu #{t.cpu})"
end

def native_line(r)
  "| #{r.name} | #{native_cell(r.tree)} | #{native_cell(r.vm)} | #{native_cell(r.chuuzou)} | #{native_cell(r.rust)} | #{per_mille(r.chuuzou.cpu, r.rust.cpu)} | #{per_mille(r.vm.cpu * r.work, r.rust.cpu)} | #{per_mille(r.tree.cpu * r.work, r.rust.cpu)} |"
end

@doc """
native_measures: A path's rows: each program's CPU time over Rust's, keyed by program,
path and host.

    native_measures([{name: "fib", work: 2, tree: {cpu: 30}, rust: {cpu: 3}}], {name: "tree", field: :tree, scaled: true}, "darwin") #=> [{key: "fib tree darwin", size: 20000}]
"""
def native_measures(results, path, host)
  map(
    fn(r)
      measurement(
        "#{r.name} #{path.name} #{host}",
        per_mille(get(r, path.field).cpu * work_of(r, path), r.rust.cpu)
      )
    end,
    results
  )
end

@doc """
work_of: How many units of the Rust run's work one run on `path` is: the program's
`work` for a path run at the small `N`, else 1.

    work_of({work: 100}, {scaled: true}) #=> 100
    work_of({work: 100}, {scaled: false}) #=> 1
"""
def work_of(r, path)
  if path.scaled
    r.work
  else
    1
  end
end

def native_refusals(rows, results, host)
  reduce(
    fn(acc, p)
      append(
        acc,
        failures_within(
          rows,
          "native-ratio",
          native_measures(results, p, host),
          p.permille
        )
      )
    end,
    [],
    native_paths
  )
end

def native_command(blue, work, flags)
  runs = 3
  results = map((n) -> native_row(blue, n, work, runs), native_programs)
  write_stdout(
    unlines(
      [
        "| program | tree-walker ms (N) | VM ms (N) | chuuzou ms (big N) | Rust ms (big N) | chuuzou/Rust ‰ | VM/Rust ‰ per unit of work | tree/Rust ‰ per unit of work |",
        "|---|---|---|---|---|---|---|---|"
      ]
    )
  )
  map((r) -> write_stdout(unlines([native_line(r)])), results)
  host = host_name
  old = read_or(NATIVE_BASELINE, "")
  rows = parse(old)
  if member?("--record", flags)
    measures = reduce(
      (acc, p) -> append(acc, native_measures(results, p, host)),
      [],
      native_paths
    )
    refused = receipt_refusal(flag(flags, "--receipt"))
    if refused.nil?
      write_file(
        NATIVE_BASELINE,
        receipted(
          old,
          flag(flags, "--receipt"),
          render("native-ratio", measures)
        )
      )
      true
    else
      write_stdout(unlines([refused]))
      false
    end
  else
    bad = native_refusals(rows, results, host)
    map((b) -> write_stdout(unlines([why(b)])), bad)
    is_empty(bad)
  end
end

LEVER_BASELINE = "bench/lever.baseline"

def timed_prepared(command, prepare, runs, out)
  exec_capture(
    "hyperfine",
    "-N",
    "--warmup",
    "1",
    "--runs",
    to_s(runs),
    "--prepare",
    prepare,
    "--export-json",
    out,
    command
  )
  r = json_get(json_parse(read_file(out)), :results)[0]
  {wall: ms(json_get(r, :mean)), cpu: cpu_ms(r)}
end

@doc """
lever_row: One lever on its blue program and its Rust twin: the two print the same,
then each is timed; the blue run starts every time from the store its build left
(a copy restored before each run), so a run never answers from its own last run.
"""
def lever_row(blue, spec, work, runs)
  store = prime(blue, spec, work)
  snapshot = "#{store}-built"
  mkdir_p(store)
  rm_rf(snapshot)
  output_of(["cp", "-R", store, snapshot])
  restore = "rsync -a --delete #{snapshot}/ #{store}/"
  rust = path_join(work, "#{spec.rust}-rust")
  output_of(
    [
      "rustc",
      "--edition",
      "2021",
      "-C",
      "opt-level=3",
      "-C",
      "codegen-units=1",
      "-o",
      rust,
      "bench/native/#{spec.rust}.rs"
    ]
  )
  file = lever_file(spec, work, spec.edit)
  b = lever_run(blue, spec, store, [], file)
  r = append([rust], spec.rust_args)
  if output_of(b) != output_of(r)
    raise(:bench, "#{spec.name}: blue prints other than the Rust twin")
  end
  out = path_join(work, "#{spec.name}.json")
  {
    name: spec.name,
    lever: spec.lever,
    blue: timed_prepared(join(b, " "), restore, runs, out),
    rust: timed(join(r, " "), runs, out)
  }
end

@doc """
lever_measures: Each lever's blue CPU time over its Rust twin's, in per mille, keyed by
lever and host. Below 1000 is faster than Rust.

    lever_measures([{name: "memo", blue: {cpu: 30}, rust: {cpu: 300}}], "darwin") #=> [{key: "memo darwin", size: 100}]
"""
def lever_measures(results, host)
  map(
    (r) -> measurement("#{r.name} #{host}", per_mille(r.blue.cpu, r.rust.cpu)),
    results
  )
end

def lever_line(r)
  "| #{r.name} | #{r.lever} | #{native_cell(r.blue)} | #{native_cell(r.rust)} | #{per_mille(r.blue.cpu, r.rust.cpu)} |"
end

def lever_command(blue, work, flags)
  results = map((l) -> lever_row(blue, l, work, 5), levers)
  write_stdout(
    unlines(
      [
        "| lever row | lever | blue ms | Rust ms | blue/Rust CPU ‰ |",
        "|---|---|---|---|---|"
      ]
    )
  )
  map((r) -> write_stdout(unlines([lever_line(r)])), results)
  host = host_name
  old = read_or(LEVER_BASELINE, "")
  rows = parse(old)
  measures = lever_measures(results, host)
  if member?("--record", flags)
    refused = receipt_refusal(flag(flags, "--receipt"))
    if refused.nil?
      write_file(
        LEVER_BASELINE,
        receipted(
          old,
          flag(flags, "--receipt"),
          render("lever-ratio", measures)
        )
      )
      true
    else
      write_stdout(unlines([refused]))
      false
    end
  else
    bad = failures_within(rows, "lever-ratio", measures, 500)
    map((b) -> write_stdout(unlines([why(b)])), bad)
    is_empty(bad)
  end
end

def main()
  if argv[0] == "lever"
    if not lever_command(argv[1], argv[2], drop(3, argv))
      exit_with(1)
    end
  elsif argv[0] == "compile"
    write_stdout(compile_rows(argv[1]))
  elsif argv[0] == "native"
    if not native_command(argv[1], argv[2], drop(3, argv))
      exit_with(1)
    end
  elsif argv[0] == "cost"
    if not cost_command(argv[1], argv[2], drop(3, argv))
      exit_with(1)
    end
  else
    blue = argv[0]
    langs = [["b", blue], ["py", argv[1]], ["rb", argv[2]]]
    scripts(blue, langs, argv[3], to_int(argv[4] rescue "10"))
  end
end

def example_rows()
  parse(
    unlines(
      [
        "# receipt: first measure",
        "bench-steps: fib 1000",
        "bench-allocs: fib darwin 500",
        "bench-allocs: fib linux 520",
        "bench-bytes: fib darwin 9000"
      ]
    )
  )
end

def example_cost(steps, allocs, bytes)
  {name: "fib", steps:, allocs:, bytes:, ms: 1.0}
end

test "a native path past its ratio to Rust is refused, and one within it holds"
  results = [
    {
      name: "fib",
      work: 1,
      tree: {cpu: 300},
      vm: {cpu: 250},
      chuuzou: {cpu: 11},
      rust: {cpu: 10}
    }
  ]
  rows = parse(
    unlines(
      [
        "native-ratio: fib tree darwin 30000",
        "native-ratio: fib vm darwin 25000",
        "native-ratio: fib chuuzou darwin 1000"
      ]
    )
  )
  assert native_refusals(rows, results, "darwin") == []
  slow = [
    {
      name: "fib",
      work: 1,
      tree: {cpu: 300},
      vm: {cpu: 250},
      chuuzou: {cpu: 16},
      rust: {cpu: 10}
    }
  ]
  assert size(native_refusals(rows, slow, "darwin")) == 1
  assert size(native_refusals([], results, "darwin")) == 3
end

test "a cost within every tolerance holds"
  j = judged(example_rows, [example_cost(1005, 510, 9180)], "darwin")
  assert j[:refusals] == []
  assert j[:fell] == []
  assert get(
    judged(example_rows, [example_cost(996, 499, 8990)], "darwin"),
    :fell
  ) == []
  assert get(
    judged(example_rows, [example_cost(900, 500, 9000)], "darwin"),
    :fell
  ) == [{key: "fib", size: 900}]
  assert j[:unhosted] == []
end

test "steps past their tolerance name the workload and the delta"
  j = judged(example_rows, [example_cost(1200, 500, 9000)], "darwin")
  assert size(j[:refusals]) == 1
  assert why(j[:refusals][0]) ==
    "bench-steps: fib measures 1200, past its recorded 1000 by 200, beyond its 5 per mille tolerance"
end

test "allocations are judged against this host's row only"
  j = judged(example_rows, [example_cost(1000, 530, 9000)], "darwin")
  assert includes(why(j[:refusals][0]), "bench-allocs: fib darwin measures 530")
  held = judged(example_rows, [example_cost(1000, 530, 9000)], "linux")
  assert held[:unhosted] == ["bench-bytes"]
  assert held[:refusals] == []
end

test "a host with no hosted rows is advisory for them, and steps still gate"
  j = judged(example_rows, [example_cost(2000, 1, 1)], "freebsd")
  assert j[:unhosted] == %w[bench-allocs bench-bytes]
  assert size(j[:refusals]) == 1
end

test "a new workload is refused, never read as held"
  j = judged(
    example_rows,
    [
      example_cost(1000, 500, 9000),
      {name: "new", steps: 1, allocs: 1, bytes: 1, ms: 1.0}
    ],
    "darwin"
  )
  assert size(j[:refusals]) == 3
end

test "a record banks a fall, keeps the row for a rise within tolerance, and refuses a raise without a reason"
  assert raises(example_rows, [example_cost(900, 505, 9000)], "darwin") == []
  text = baseline_text(
    unlines(["# receipt: first measure"]),
    nil,
    example_rows,
    [example_cost(900, 505, 9000)],
    "darwin"
  )
  assert text ==
    unlines(
      [
        "# receipt: first measure",
        "bench-steps: fib 900",
        "bench-allocs: fib darwin 500",
        "bench-allocs: fib linux 520",
        "bench-bytes: fib darwin 9000"
      ]
    )
  assert raises(example_rows, [example_cost(1004, 500, 9000)], "darwin") == []
  up = raises(example_rows, [example_cost(1100, 500, 9000)], "darwin")
  assert size(up) == 1
  assert includes(why(up[0]), "past its recorded 1000 by 100")
end

test "a timings report reads by key, so a moved row does not shift a count"
  rows = timing_rows(
    unlines(
      ["eval        1.0 ms", "allocs   12", "steps    7", "total  3.5 ms"]
    )
  )
  assert cost_of("x", rows) ==
    {name: "x", steps: 7, allocs: 12, bytes: nil, ms: 3.5}
end

test "a raised row needs a typed reason, and an untyped one is refused by name"
  assert receipt_refusal(nil).nil?
  assert receipt_refusal("capability: hex words").nil?
  assert includes(receipt_refusal("slower is fine"), "got \"slower is fine\"")
  assert not receipt_refusal("speed: why").nil?
  assert not receipt_refusal("measurement:").nil?
  assert not record_costs(
    "",
    example_rows,
    [example_cost(1100, 500, 9000)],
    "darwin",
    ["--receipt", "faster later"]
  )
end

test "a lever slower than its recorded ratio to Rust is refused"
  rows = parse(unlines(["lever-ratio: memo darwin 100"]))
  fast = [{name: "memo", blue: {cpu: 30}, rust: {cpu: 300}}]
  slow = [{name: "memo", blue: {cpu: 300}, rust: {cpu: 300}}]
  assert failures_within(
    rows,
    "lever-ratio",
    lever_measures(fast, "darwin"),
    500
  ) == []
  assert size(
    failures_within(rows, "lever-ratio", lever_measures(slow, "darwin"), 500)
  ) == 1
end
