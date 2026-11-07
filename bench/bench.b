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

use("kazu", [:max])
use("kyohi", [:why])
use("moji", %i[after_first before_first includes lines trim])
use("retsu", %i[first is_empty size])
use("shinsatsu", [:flag])
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
  costs = map((w) -> run_cost(blue, w, work), ws)
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
    check_costs(rows, costs, host, size(ws))
  end
end

def record_costs(old, rows, costs, host, flags)
  receipt = flag(flags, "--receipt")
  up = raises(rows, costs, host)
  if member?("--quick", flags)
    write_stdout(
      unlines(["bench: --record measures every workload; drop --quick"])
    )
    false
  elsif size(up) > 0 and receipt.nil?
    write_stdout(
      unlines(
        append(
          map(why, up),
          ["bench: a raised or new row needs a reason: blue bench/bench.b cost BLUE WORKDIR --record --receipt \"<why>\""]
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
            "fix: make it cheaper, or raise the row: blue bench/bench.b cost BLUE WORKDIR --record --receipt \"<why>\" against #{BASELINE}"
          ]
        )
      )
    )
    false
  else
    true
  end
end

def main()
  if argv[0] == "compile"
    write_stdout(compile_rows(argv[1]))
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
