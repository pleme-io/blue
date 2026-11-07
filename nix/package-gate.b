@moduledoc """
package-gate: the packaged crate is the distribution the checkout embeds.

    blue run package-gate.b -- files CHECKOUT_WALK CHECKOUT_ROOT TARBALL_WALK TARBALL_ROOT
    blue run package-gate.b -- resolve BLUE PROBE_DIR HOME LEVEL...

`files` reads two outputs of blue-lang-pkg's own build.rs, run once over the
checkout and once over the unpacked `.crate`: every `rerun-if-changed` line
below a root is a file the build embeds. A file the checkout embeds and the
tarball does not is named, one per line, and the gate is red.

`resolve` runs BLUE, the blue built from the unpacked tarballs alone, once per
LEVEL, with an empty environment: `use(LEVEL)` must load from the compiled-in
distribution. A level that does not resolve is named. A level that cannot exist
must fail to resolve, or the probe could not say no.
"""

use("retsu", [:reject])

use("shisutemu", [:status_of])

@doc """
embedded: the files a build.rs walk embeds below root, relative to it.

    embedded(unlines(["cargo:rerun-if-changed=/r", "cargo:rerun-if-changed=/r/a/Bluefile", "cargo:rerun-if-changed=/r/a/a.b"]), "/r") #=> ["a/Bluefile", "a/a.b"]
"""
def embedded(walk, root)
  marker = "cargo:rerun-if-changed=#{root}/"
  map(
    (l) -> replace(l, marker, ""),
    filter((l) -> starts_with?(l, marker), split(walk, line_break))
  )
end

@doc """
missing: what the checkout embeds and the tarball does not.

    missing(["a/a.b", "a/l/l.b"], ["a/a.b"]) #=> ["a/l/l.b"]
"""
def missing(checkout, tarball)
  reject((f) -> member?(f, tarball), checkout)
end

@doc """
files: the file-set gate over two build.rs walks; red names each missing file.

    embedded("", "/r") #=> []
"""
def files(checkout_walk, checkout_root, tarball_walk, tarball_root)
  checkout = embedded(read_file(checkout_walk), checkout_root)
  tarball = embedded(read_file(tarball_walk), tarball_root)
  if checkout == []
    raise(:gate, "#{checkout_walk} embeds nothing below #{checkout_root}")
  end
  gone = missing(checkout, tarball)
  if gone != []
    raise(
      :gate,
      join_lines(
        [
          "the packaged crate is missing #{to_s(count(gone))} of #{to_s(count(checkout))} embedded file(s):",
          join(gone, line_break)
        ]
      )
    )
  end
  write_stdout(
    unlines(["files: #{to_s(count(checkout))} embedded, all in the tarball"])
  )
end

@doc """
probe: the source that resolves one level.

    probe("todokede/motenashi") #=> unlines(["use(\"todokede/motenashi\")"])
"""
def probe(level)
  unlines(["use(\"#{level}\")"])
end

@doc """
resolves?: whether BLUE, with nothing in its environment but HOME, loads level.

    contains?(probe("a"), "use(") #=> true
"""
def resolves?(blue, dir, home, level)
  file = path_join(dir, "#{replace(level, "/", "-")}.b")
  write_program(file, probe(level))
  cap = exec_capture("env", "-i", "HOME=#{home}", blue, file)
  status_of(cap) == 0
end

@doc """
resolve: the resolution gate; red names each level that does not load.

    contains?(probe("okite/rung/deep"), "okite/rung/deep") #=> true
"""
def resolve(blue, dir, home, levels)
  if resolves?(blue, dir, home, "todokede/no-such-level")
    raise(:gate, "#{blue} resolved a level that does not exist")
  end
  failed = reject((l) -> resolves?(blue, dir, home, l), levels)
  if failed != []
    raise(
      :gate,
      join_lines(
        [
          "the blue built from the packaged crates does not resolve:",
          join(failed, line_break)
        ]
      )
    )
  end
  write_stdout(
    unlines(["resolve: #{to_s(count(levels))} level(s) from the tarball"])
  )
end

@doc """
main: dispatch on the verb.

    missing([], []) #=> []
"""
def main()
  if argv[0] == "files"
    files(argv[1], argv[2], argv[3], argv[4])
  elsif argv[0] == "resolve"
    resolve(argv[1], argv[2], argv[3], drop(4, argv))
  else
    raise(:usage, "package-gate.b files … | resolve …")
  end
end
