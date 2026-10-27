#!/usr/bin/env -S blue --allow host
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
    ["json_sum", "records.json"],
    ["wordfreq", "words.txt"],
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
  json_get(json_parse(read_file(out)), "results")[0]
end

def ms(seconds)
  round(seconds * 10000) / 10
end

def measure(command, runs, out)
  r = hyperfine(command, runs, out)
  {
    mean: ms(json_get(r, "mean")),
    sd: ms(json_get(r, "stddev")),
    user: ms(json_get(r, "user"))
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
        ["b", "py", "rb"]
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

def main()
  if argv[0] == "compile"
    write_stdout(compile_rows(argv[1]))
  else
    blue = argv[0]
    langs = [["b", blue], ["py", argv[1]], ["rb", argv[2]]]
    scripts(blue, langs, argv[3], to_int(argv[4] rescue "10"))
  end
end
