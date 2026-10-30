@moduledoc """
fairu (ファイル) — files: paths and the files they name.

fairu holds the properties of a path (`absolute`, `parts`, `stem`) and the
home directory of the user. The verbs that read and write files are runtime
primitives, and the verb graph names them in this space.

    stem("/x/archive.tar.gz") #=> "archive.tar"
"""

use("moji", %i[present starts_with strip_suffix])
use("retsu", %i[concat_lists last push take_while])

@doc """
absolute: the path made absolute against the current directory.

    absolute("/a/b") #=> "/a/b"
"""
def absolute(path)
  if starts_with(path, "/")
    path
  else
    path_join(cwd, path)
  end
end

@doc """
home: the home directory of the user.

    home #=> getenv("HOME")
"""
def home()
  dir = getenv("HOME")
  if dir.nil? or dir == ""
    error(:not_found, "fairu::home: HOME is not set")
  else
    dir
  end
end

@doc """
parts: the path split into its parts.

    parts("") #=> []
"""
def parts(path)
  names = filter((s) -> present(s), split(path, "/"))
  if starts_with(path, "/")
    cons("/", names)
  else
    names
  end
end

@doc """
stem: the name without its final extension.

    stem("dir/") #=> "dir"
"""
def stem(path)
  name = path_basename(path)
  ext = path_extension(path)
  if ext == ""
    name
  else
    strip_suffix(name, ".#{ext}")
  end
end

@doc """
normalize: the path with each `.` part, each empty part and each `dir/..` pair removed; a `..` that climbs above where the path starts is kept, and a leading `/` stays.

    normalize("docs/howto/../SAFETY.md") #=> "docs/SAFETY.md"
"""
def normalize(path)
  kept = reduce(
    fn(acc, part)
      if part == "" or part == "."
        acc
      elsif part == ".." and acc != [] and last(acc) != ".."
        take(length(acc) - 1, acc)
      else
        push(acc, part)
      end
    end,
    [],
    split(path, "/")
  )
  body = join(kept, "/")
  if starts_with(path, "/")
    concat("/", body)
  else
    body
  end
end

@doc """
relative: the path to `path` as a file in the directory `base` writes it, both paths relative to one root.

    relative("bidamas/CATALOG.md", "docs") #=> "../bidamas/CATALOG.md"
"""
def relative(path, base)
  from = filter((s) -> s != "", split(normalize(base), "/"))
  to = split(normalize(path), "/")
  shared = length(
    take_while(
      (i) -> i < length(from) and i < length(to) and from[i] == to[i],
      range(0, length(from))
    )
  )
  join(
    concat_lists(map((_s) -> "..", drop(shared, from)), drop(shared, to)),
    "/"
  )
end

test "normalize removes dot parts, empty parts and each pair that climbs back"
  assert normalize("a/./b//c/../d") == "a/b/d"
  assert normalize("/a/../b") == "/b"
  assert normalize("../x") == "../x"
  assert normalize("a/../..") == ".."
  assert normalize("") == ""
end

test "relative climbs out of the base only as far as the two paths differ"
  assert relative("docs/a.md", "") == "docs/a.md"
  assert relative("docs/a.md", "docs") == "a.md"
  assert relative("docs/a.md", "docs/howto") == "../a.md"
  assert relative("README.md", "docs/howto") == "../../README.md"
  assert relative("docs/x/../a.md", "./docs") == "a.md"
end

test "a relative path is placed under the current directory and an absolute one is kept"
  assert absolute("a/b") == path_join(cwd, "a/b")
  assert absolute("/a/b") == "/a/b"
end

test "absolute of absolute is a fixed point"
  assert absolute(absolute("x.txt")) == absolute("x.txt")
end

test "home is the HOME of the process and raises when it is empty"
  if getenv("HOME").nil? or getenv("HOME") == ""
    assert (home rescue :refused) == :refused
  else
    assert home == getenv("HOME")
  end
end

test "parts keeps the root as its own part and drops empty segments"
  assert parts("/a/b/c") == %w[/ a b c]
  assert parts("a/b") == %w[a b]
  assert parts("a//b/") == %w[a b]
  assert parts("/") == ["/"]
  assert parts("") == []
end

test "stem drops only the final extension"
  assert stem("/x/archive.tar.gz") == "archive.tar"
  assert stem("notes.txt") == "notes"
  assert stem("Makefile") == "Makefile"
  assert stem("/x/.bashrc") == ".bashrc"
  assert stem("dir/") == "dir"
end
