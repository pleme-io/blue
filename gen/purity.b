use("hadome", %i[failures measurement parse])
use("junjo", [:sort_by])
use("moji", [:includes])
use("retsu", %i[is_empty size])
use("shisutemu", [:read_or])

KIND = "purity-bytes"

BASELINE = "gen/purity.baseline"

@doc """
root: the tree the ledger reads: $GEN_ROOT, where a nix check places its inputs, or the working directory.

    string?(root) #=> true
"""
def root()
  getenv("GEN_ROOT", ".")
end

RECORD = "blue gen/purity.b record"

@doc """
crate_of: the crate a Rust source path belongs to, or nil for a path outside crates/*/src.

    crate_of("crates/blue-lang-fmt/src/lib.rs") #=> "blue-lang-fmt"
    crate_of("crates/blue-lang-fmt/tests/laws.rs") #=> nil
    crate_of("bidamas/kazu/kazu.b") #=> nil
"""
def crate_of(path)
  if starts_with?(path, "crates/") and
      includes(path, "/src/") and
      ends_with?(path, ".rs")
    moji::before_first(replace(path, "crates/", ""), "/src/")
  end
end

@doc """
rust_files: every Rust source path under crates, sorted.

    is_empty(rust_files("no/such/root")) #=> true
"""
def rust_files(root)
  if path_exists(path_join(root, "crates"))
    sort_by(
      (p) -> p,
      filter(
        (p) -> crate_of(p) != nil,
        map(
          (p) -> replace(p, "#{root}/crates/", "crates/"),
          walk_dir(path_join(root, "crates"))
        )
      )
    )
  else
    []
  end
end

@doc """
totals: the Rust source bytes of each crate, as measurements keyed crates/NAME.

    totals([], []) #=> []
"""
def totals(paths, sizes)
  names = distinct(sort_by((n) -> n, map(crate_of, paths)))
  map(
    fn(n)
      measurement(
        "crates/#{n}",
        reduce(
          fn(acc, i)
            if crate_of(paths[i]) == n
              acc + sizes[i]
            else
              acc
            end
          end,
          0,
          range(0, size(paths))
        )
      )
    end,
    names
  )
end

def measured(root)
  paths = rust_files(root)
  totals(paths, map((p) -> file_size(path_join(root, p)), paths))
end

@doc """
rows_text: a baseline file's text for these measurements, one row each.

    rows_text([measurement("crates/a", 3)]) #=> "purity-bytes: crates/a 3\n"
"""
def rows_text(ms)
  join(map((m) -> unlines(["#{KIND}: #{m[:key]} #{to_s(m[:size])}"]), ms), "")
end

def record()
  text = rows_text(measured(root))
  write_file(path_join(root, BASELINE), text)
  write_stdout(
    unlines(["recorded #{to_s(size(measured(root)))} crate(s) in #{BASELINE}"])
  )
end

def main()
  if argv_get(0) == "record"
    record
  else
    write_stderr(unlines(["usage: #{RECORD}"]))
    exit_with(64)
  end
end

test "no crate grows past its recorded Rust bytes, and a new crate must be recorded"
  rows = parse(read_or(path_join(root, BASELINE), ""))
  ms = measured(root)
  assert size(ms) >= 20
  bad = map((f) -> f[1], failures(rows, KIND, ms))
  if not is_empty(bad)
    write_stderr(unlines(bad))
    write_stderr(unlines(["record a shrink with: #{RECORD}"]))
  end
  assert is_empty(bad)
end

test "a crate whose source grew is refused, one that shrank or held is not"
  rows = parse(unlines(["purity-bytes: crates/a 100"]))
  assert is_empty(failures(rows, KIND, [measurement("crates/a", 100)]))
  assert is_empty(failures(rows, KIND, [measurement("crates/a", 40)]))
  assert size(failures(rows, KIND, [measurement("crates/a", 101)])) == 1
  assert size(failures(rows, KIND, [measurement("crates/b", 1)])) == 1
end

test "totals sums each crate's files under its own key"
  ps = %w[crates/a/src/x.rs crates/a/src/y.rs crates/b/src/z.rs]
  assert totals(ps, [10, 5, 7]) ==
    [measurement("crates/a", 15), measurement("crates/b", 7)]
end

test "only a crate's src files count"
  assert crate_of("crates/k/src/m/n.rs") == "k"
  assert crate_of("crates/k/build.rs").nil?
  assert crate_of("crates/k/src/data.json").nil?
end

test "a growth is reported as its message"
  rows = parse(unlines(["purity-bytes: crates/a 100"]))
  bad = map((f) -> f[1], failures(rows, KIND, [measurement("crates/a", 101)]))
  assert bad ==
    ["purity-bytes: crates/a measures 101, past its recorded 100 by 1"]
end

test "the ledger measures a tree it is not standing in"
  away = temp_dir("purity-away")
  mkdir_p(path_join(away, "crates/tiny/src"))
  write_file(path_join(away, "crates/tiny/src/lib.rs"), unlines(["fn a() {}"]))
  ms = measured(away)
  assert size(ms) == 1
  assert ms[0][:size] == 10
  rm_rf(away)
end
