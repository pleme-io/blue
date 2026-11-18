@moduledoc """
bounds: the execution bounds a program's run measures to (W5.2 of
docs/FACTS.md). `blue bounds FILE` runs FILE once on the tree-walker, which
counts every step, reads the steps and the bytes it allocated from
`--timings`, and proposes `bounds({steps:, alloc_bytes:})` at ten times each,
rounded up to a power of ten. The allocated bytes are a total, never less
than the live bytes the bound holds, so the proposal has room. `--accept`
writes the proposal into the nearest Bluefile above FILE and locks it; a
Bluefile that already declares bounds is left to its author, since a
proposal never widens one. Nothing is written without `--accept`.

    proposed(1234) #=> 100000
"""

use("moji", [:lines])
use("retsu", %i[first is_empty rest])

ACCEPT = "--accept"

@doc """
proposed: the bound for a measured `n`: ten times it, rounded up to a power of ten,
at least 1000.

    proposed(0) #=> 1000
    proposed(99) #=> 1000
    proposed(1001) #=> 100000
"""
def proposed(n)
  reduce(
    fn(b, _)
      if b < n * 10
        b * 10
      else
        b
      end
    end,
    1000,
    range(19)
  )
end

@doc """
measured: the number a `--timings` report gives a row, or nil when it has none.

    measured(unlines(["steps    534", "bytes    27921"]), "bytes") #=> 27921
    measured("", "steps") #=> nil
"""
def measured(report, row)
  hit = find(lines(report), (l) -> starts_with?(l, "#{row} "))
  if hit.nil?
    nil
  else
    to_int(trim(drop_prefix(hit, row)))
  end
end

@doc """
drop_prefix: `text` without its first `n` characters, `n` the length of `prefix`.

    drop_prefix("steps 5", "steps") #=> " 5"
"""
def drop_prefix(text, prefix)
  join(drop(length(prefix), chars(text)), "")
end

@doc """
line_of: the Bluefile line a proposal is written as.

    line_of(1000, 100000) #=> "bounds({steps: 1000, alloc_bytes: 100000})"
"""
def line_of(steps, bytes)
  "bounds({steps: #{steps}, alloc_bytes: #{bytes}})"
end

@doc """
bluefile_of: the nearest Bluefile at or above `dir`, or nil.

    bluefile_of("/") #=> nil
"""
def bluefile_of(dir)
  here = path_join(dir, "Bluefile")
  if path_exists(here)
    here
  elsif dir == "/" or dir == "" or dir == "."
    nil
  else
    bluefile_of(path_dirname(dir))
  end
end

@doc """
absolute: `file` as a path from the root: as it is when it starts at `/`, else
from the working directory.

    absolute("/a/b.b") #=> "/a/b.b"
"""
def absolute(file)
  if starts_with?(file, "/")
    file
  else
    path_join(cwd, file)
  end
end

def accept(file, line)
  bluefile = bluefile_of(path_dirname(absolute(file)))
  if bluefile.nil?
    write_stderr(
      unlines(
        [
          "blue bounds: #{file} is in no project; there is no Bluefile to hold bounds"
        ]
      )
    )
    false
  elsif contains?(read_file(bluefile), "bounds(")
    write_stderr(
      unlines(
        [
          "blue bounds: #{bluefile} already declares bounds; a proposal never widens them, so its author edits that line"
        ]
      )
    )
    false
  else
    write_file(bluefile, concat(read_file(bluefile), unlines([line])))
    locked = exec_capture(self_exe, "lock", path_dirname(bluefile))
    write_stdout(unlines(["wrote #{line} to #{bluefile}"]))
    locked.status == 0
  end
end

def main(args)
  if is_empty(args)
    write_stderr(unlines(["usage: blue bounds FILE [--accept]"]))
    false
  else
    file = first(args)
    ran = exec_with_env(
      [%w[BLUE_DOOR walker], %w[BLUE_MEMO off], %w[BLUE_NATIVE off]],
      self_exe,
      "run",
      "--quiet",
      "--timings",
      file
    )
    steps = measured(ran.stderr, "steps")
    bytes = measured(ran.stderr, "bytes")
    if ran.status != 0 or steps.nil? or bytes.nil?
      write_stderr(
        unlines(
          [
            "blue bounds: #{file} did not run to its end; nothing to measure",
            ran.stderr
          ]
        )
      )
      false
    else
      line = line_of(proposed(steps), proposed(bytes))
      write_stdout(
        unlines(
          [
            "#{file} ran in #{steps} steps and allocated #{bytes} bytes",
            "proposed: #{line}"
          ]
        )
      )
      if member?(ACCEPT, rest(args))
        accept(file, line)
      else
        true
      end
    end
  end
end

test "a measured run is proposed at ten times, rounded up to a power of ten"
  assert proposed(534) == 10000
  assert proposed(27921) == 1_000_000
  assert line_of(proposed(534), proposed(27921)) ==
    "bounds({steps: 10000, alloc_bytes: 1000000})"
end

main(argv)
