use("junjo", [:sort])
use("retsu", %i[first size])
use("sabi")
use("shisutemu", %i[blue_exe status_of stderr_of stdout_of])

@doc """
foundation_of: The names of the bidamas whose lock records `tier(:foundation)`,
sorted. A lock with no tier is an extension, outside the foundation.

    foundation_of([{"manifest" => {"name" => "kazu", "tier" => "foundation"}}, {"manifest" => {"name" => "fairu", "tier" => "system"}}]) #=> ["kazu"]
    foundation_of([{"manifest" => {"name" => "gamen"}}]) #=> []
"""
def foundation_of(locks)
  sort(
    map(
      (l) -> l["manifest"]["name"],
      filter((l) -> l["manifest"]["tier"] == "foundation", locks)
    )
  )
end

def locks_under(root)
  depth = size(split(root, "/")) + 2
  paths = filter(
    (p) -> ends_with?(p, "/Bluefile.lock") and size(split(p, "/")) == depth,
    walk_dir(root)
  )
  map((p) -> json_read(read_file(p)), paths)
end

def rank(fact, foundation)
  if member?(fact["scope"], foundation)
    "0/#{fact["scope"]}/#{fact["name"]}"
  else
    "1/#{fact["scope"]}/#{fact["name"]}"
  end
end

def home_of(facts, foundation)
  first(sort_keyed((f) -> rank(f, foundation), facts))
end

def row_of(fact, foundation)
  [
    take_chars(fact["shape"]),
    "#{fact["scope"]}::#{fact["name"]}",
    member?(fact["scope"], foundation)
  ]
end

def take_chars(shape)
  join(take(16, chars(shape)), "")
end

def rows_of(facts, foundation)
  homes = map(
    (e) -> home_of(e[1], foundation),
    map_entries(group_by(facts, (f) -> f["shape"]))
  )
  sort_keyed((r) -> r[0], map((h) -> row_of(h, foundation), homes))
end

def facts_under(root)
  r = exec_capture(blue_exe, "census", "--reuse", "--facts", root)
  if status_of(r) != 0
    raise(:word_shapes, stderr_of(r))
  end
  map(json_read, filter((l) -> l != "", split(stdout_of(r), line_break)))
end

def rendered(rows)
  str_ref = sabi::ty_ref(sabi::ty("str"))
  sabi::render_rust(
    sabi::file(
      "gen/word-shapes.b",
      [
        sabi::rs_const(
          "WORD_SHAPES",
          sabi::ty_ref(
            sabi::ty_slice(sabi::ty_tuple([str_ref, str_ref, sabi::ty("bool")]))
          ),
          sabi::slice(
            map(
              fn(r)
                sabi::tuple(
                  [sabi::str(r[0]), sabi::str(r[1]), sabi::bool(r[2])]
                )
              end,
              rows
            )
          ),
          []
        )
      ]
    )
  )
end

def main()
  root = path_join(getenv("GEN_ROOT", "."), "bidamas")
  write_file(
    getenv("GEN_OUT", "crates/blue-lang-runtime/src/word_shapes/tables.rs"),
    rendered(rows_of(facts_under(root), foundation_of(locks_under(root))))
  )
end

def fact(scope, name, shape)
  {"scope" => scope, "name" => name, "shape" => shape}
end

FOUNDATION = %w[kazu retsu]

test "no definition is no row"
  assert rows_of([], FOUNDATION) == []
end

test "one shape is one row, its home the foundation bidama"
  rows = rows_of(
    [fact("souji", "sum", "aa"), fact("kazu", "sum", "aa")],
    FOUNDATION
  )
  assert size(rows) == 1
  assert first(rows) == ["aa", "kazu::sum", true]
end

test "a shape only domain bidamas hold has the first as its home, marked domain"
  rows = rows_of(
    [fact("shomei", "side", "bb"), fact("empresa", "pair", "bb")],
    FOUNDATION
  )
  assert first(rows) == ["bb", "empresa::pair", false]
end

test "rows are sorted by shape, and a shape is cut to sixteen digits"
  long = "0123456789abcdef0123"
  rows = rows_of([fact("a", "x", "ff"), fact("a", "y", long)], FOUNDATION)
  assert map((r) -> r[0], rows) == %w[0123456789abcdef ff]
end

test "the foundation is what the locks declare, and only that"
  locks = [
    {"manifest" => {"name" => "ronri", "tier" => "foundation"}},
    {"manifest" => {"name" => "kazu", "tier" => "foundation"}},
    {"manifest" => {"name" => "shisutemu", "tier" => "system"}},
    {"manifest" => {"name" => "gamen"}}
  ]
  assert foundation_of(locks) == %w[kazu ronri]
  assert foundation_of([]) == []
end

test "the distribution's foundation holds ronri, which shuugou and junjo use"
  root = path_join(getenv("GEN_ROOT", "."), "bidamas")
  found = foundation_of(locks_under(root))
  assert member?("ronri", found)
  assert member?("kazu", found)
  assert not member?("shisutemu", found)
end
