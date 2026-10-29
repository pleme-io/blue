use("moji", %i[present starts_with strip_suffix])

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
