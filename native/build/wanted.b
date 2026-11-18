@moduledoc """
The native builder (tier T3, W1 of docs/FACTS.md): it builds what runs asked for. A run whose evaluation took 20 ms or more, with a native tier present, writes `<root>/wanted/<key>`, holding its program's path, where `key` is the content hash of the program's text (`blue_lang_mondou::store::want_native`). For each request this builds every function of the program that chuuzou compiles and that has no artifact yet, into `<root>/v1/<hex>/` as `def`, `def.so` and `def.rs`, runs the program's tests to seed the profile, and writes `<key>.done`. `$NATIVE_ROOT` is the root, else this node's: `$XDG_CACHE_HOME/blue/native`, else `$HOME/.cache/blue/native`. `$DEF_SEAM` holds the seams the definitions link.

    native_root_from("", "/h") #=> "/h/.cache/blue/native"
"""

use("chuuzou", %i[cz_def_image cz_def_native cz_defs])
use("retsu", [:size])

@doc """
native_root_from: This node's native root, from `$XDG_CACHE_HOME` (`xdg`) when it is set, else from `$HOME` (`home`).

    native_root_from("/x", "/h") #=> "/x/blue/native"
"""
def native_root_from(xdg, home)
  if xdg == ""
    path_join(home, ".cache", "blue", "native")
  else
    path_join(xdg, "blue", "native")
  end
end

def native_root()
  given = getenv("NATIVE_ROOT", "")
  if given == ""
    native_root_from(getenv("XDG_CACHE_HOME", ""), getenv("HOME", ""))
  else
    given
  end
end

@doc """
requests: The keys of the requests under `root` that are not done, from the names in its `wanted` directory.

    requests_of(["/r/wanted/ab", "/r/wanted/ab.done", "/r/wanted/cd"]) #=> ["cd"]
"""
def requests_of(names)
  keys = map(path_basename, names)
  filter(
    (k) -> not ends_with?(k, ".done") and not member?("#{k}.done", keys),
    keys
  )
end

@doc """
hex_of: A def_hash without its `b3:` prefix, the name of its directory.

    hex_of("b3:00ff") #=> "00ff"
"""
def hex_of(hash)
  replace(hash, "b3:", "")
end

@doc """
buildable?: Whether a definition gets an artifact: a function chuuzou compiles that has none under `root` yet.

    buildable?({"kind" => "value"}, "/nowhere") #=> false
"""
def buildable?(d, root)
  if d["kind"] != "function"
    false
  elsif is_file?(path_join(root, "v1", hex_of(d["hash"]), "def"))
    false
  else
    cz_def_native(d["slice"], d["entry"]).nil?
  end
end

def build(d, root, seam)
  hex = hex_of(d["hash"])
  work = path_join(root, "building", hex)
  mkdir_p(work)
  slice = path_join(work, "slice")
  write_file(slice, d["slice"])
  cz_def_image(slice, d["entry"], seam, work)
  into = path_join(root, "v1", hex)
  mkdir_p(into)
  rename_file(path_join(work, "def.so"), path_join(into, "def.so"))
  rename_file(path_join(work, "def.rs"), path_join(into, "def.rs"))
  rename_file(path_join(work, "def.elf"), path_join(into, "def"))
  hex
end

@doc """
take: Build what the request `key` under `root` asks for, then mark it done: the hexes it built.
"""
def take(root, key, seam)
  wanted = path_join(root, "wanted")
  program = trim(read_file(path_join(wanted, key)))
  built = if is_file?(program)
    map(
      (d) -> build(d, root, seam),
      filter((d) -> buildable?(d, root), cz_defs(program))
    )
  else
    []
  end
  if built != []
    seed(program)
  end
  write_file(path_join(wanted, "#{key}.done"), unlines(built))
  built
end

@doc """
seed: Run the tests of `program`, its doc examples among them, so the native tier records a profile for each definition they run hot: that one is answered natively from the first real run. Answers whether the tests ran green.
"""
def seed(program)
  exec_capture(self_exe, "test", "--no-cache", program).status == 0
end

def main()
  root = native_root
  wanted = path_join(root, "wanted")
  keys = if is_dir?(wanted)
    requests_of(ls(wanted))
  else
    []
  end
  seam = env_required("DEF_SEAM")
  built = reduce((acc, k) -> append(acc, take(root, k, seam)), [], keys)
  write_stdout(
    unlines(["built #{size(built)} definition(s) for #{size(keys)} request(s)"])
  )
end

test "only the requests with no .done are taken"
  assert requests_of([]) == []
  assert requests_of(%w[/w/a /w/b /w/b.done]) == ["a"]
end

test "the root is the given one, else this node's cache"
  assert native_root_from("", "/home/u") == "/home/u/.cache/blue/native"
  assert native_root_from("/c", "/home/u") == "/c/blue/native"
end

test "a value, or a function already built, is not built again"
  root = temp_dir("native-wanted")
  mkdir_p(path_join(root, "v1", "00aa"))
  write_file(path_join(root, "v1", "00aa", "def"), "")
  f = {
    "kind" => "function",
    "hash" => "b3:00aa",
    "entry" => "%root/f",
    "slice" => "(define-typed (%root/f (x Int)) Int (* x x))"
  }
  assert not buildable?(f, root)
  assert buildable?({**f, "hash" => "b3:00bb"}, root)
  assert not buildable?({**f, "kind" => "value", "hash" => "b3:00bb"}, root)
  assert not buildable?(
    {
      **f,
      "hash" => "b3:00bb",
      "slice" => "(define-typed (%root/f (x Int)) Int (kiban/put_int x))"
    },
    root
  )
end
