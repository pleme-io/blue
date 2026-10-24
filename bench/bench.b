#!/usr/bin/env -S blue --allow host
def record(i)
  "{\"id\": #{i}, \"value\": #{i % 1000}, \"name\": \"item-#{i}\", \"tags\": [\"alpha\", \"beta\"]}"
end

def json_text(n)
  "[#{join(map(record, range(n)), ",\n")}]\n"
end

def vocabulary()
  map((i) -> "w#{i * 7919 % 1009}x", range(600))
end

def word(words, i)
  nth(i * 2_654_435_761 % 4_294_967_296 % length(words), words)
end

def text(words, n)
  join(map((i) -> word(words, i), range(n)), " ")
end

def write_data(dir)
  mkdir_p(dir)
  write_file(path_join(dir, "records.json"), json_text(17000))
  write_file(path_join(dir, "words.txt"), "#{text(vocabulary, 800_000)}\n")
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
  nth(0, json_get(json_parse(read_file(out)), "results"))
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
  name = nth(0, w)
  arg = nth(1, w)
  data = path_join(work, "data")
  timed = map(
    fn(l)
      file = path_join(work, "#{name}.#{nth(0, l)}")
      measure(
        command(nth(1, l), file, arg, data),
        runs,
        path_join(work, "#{name}-#{nth(0, l)}.json")
      )
    end,
    langs
  )
  b = nth(0, timed)
  py = nth(1, timed)
  rb = nth(2, timed)
  "| #{name} | #{cell(b)} | #{cell(py)} | #{cell(rb)} | #{ratio(b, py)}× | #{ratio(b, rb)}× |\n"
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
    split(stdout_of(exec_capture("git", "ls-files", "*.b")), "\n")
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
      "| `fmt --check` #{large} | #{cell(one)} |\n",
      "| `fmt --check` all #{length(files)} tracked files | #{cell(all)} |\n",
      "| `check`, one process per file, #{length(files)} files | #{checked} (one run) |\n"
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
  "| #{profile} | #{clean} | #{leaf} | #{runtime} |\n"
end

def compile_rows(target)
  join(
    [
      "| profile | clean s | leaf crate touched s | blue-lang-runtime touched s |\n",
      "|---|---|---|---|\n",
      compile_row(target, "dev"),
      compile_row(target, "release")
    ],
    ""
  )
end

def scripts(blue, langs, work, runs)
  names = map((w) -> nth(0, w), workloads)
  write_data(path_join(work, "data"))
  copy_workloads("bench/workloads", work, names)
  write_stdout("| workload | blue ms | python ms | ruby ms | blue/python | blue/ruby |\n")
  write_stdout("|---|---|---|---|---|---|\n")
  map((w) -> write_stdout(language_row(langs, w, work, runs)), workloads)
  write_stdout("\n| tooling | ms |\n|---|---|\n")
  write_stdout(tooling_rows(blue, work))
end

def main()
  if nth(0, argv) == "compile"
    write_stdout(compile_rows(nth(1, argv)))
  else
    blue = nth(0, argv)
    langs = [["b", blue], ["py", nth(1, argv)], ["rb", nth(2, argv)]]
    scripts(blue, langs, nth(3, argv), to_int(nth(4, argv) rescue "10"))
  end
end
