@moduledoc """
The tier T3 manifest, written to $GEN_OUT: the generator behind
generate("native-defs", …) in ../Bluefile. One JSON line per definition of
each program under $GEN_ROOT/defs: its program, key, def_hash, the name it
has in its slice, the slice (`blue ast --resolved --defs`), and whether
chuuzou compiles it for the native tier (`native`, else `refused` says why).
nix/native-defs.nix reads it and builds one derivation per def_hash.
"""

# waive B0085: the manifest's consumer is nix/native-defs.nix, which checks.native-defs and checks.native-generated-native-defs-fresh build from it; no blue test can feed a nix evaluation
use("chuuzou", %i[cz_def_native cz_defs])

@doc """
row: One definition of `program` as its manifest line.

    row("p", {"key" => "%root/f", "hash" => "b3:0", "entry" => "%root/f", "slice" => "(define-typed (%root/f (x Int)) Int x)"}) |> json_read |> get("native") #=> true
"""
def row(program, d)
  why = cz_def_native(d["slice"], d["entry"])
  json_write(
    {
      program:,
      key: d["key"],
      hash: d["hash"],
      entry: d["entry"],
      native: why.nil?,
      refused: why,
      slice: d["slice"]
    }
  )
end

def rows(path)
  program = replace(path_basename(path), ".b", "")
  map((d) -> row(program, d), cz_defs(path))
end

def main()
  dir = path_join(env_required("GEN_ROOT"), "defs")
  programs = filter((p) -> ends_with?(p, ".b"), ls(dir))
  write_file(
    env_required("GEN_OUT"),
    unlines(reduce((acc, p) -> append(acc, rows(p)), [], programs))
  )
end
