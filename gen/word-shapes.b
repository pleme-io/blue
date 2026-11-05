use("retsu", %i[first size])
use("sabi")
use("shisutemu", %i[blue_exe status_of stderr_of stdout_of])

FOUNDATION = %w[kazu kansuu deeta retsu moji kyohi kousei jisho junjo shuugou]

def foundation?(scope)
  member?(scope, FOUNDATION)
end

def rank(fact)
  if foundation?(fact["scope"])
    "0/#{fact["scope"]}/#{fact["name"]}"
  else
    "1/#{fact["scope"]}/#{fact["name"]}"
  end
end

def home_of(facts)
  first(sort_keyed(rank, facts))
end

def row_of(fact)
  [
    take_chars(fact["shape"]),
    "#{fact["scope"]}::#{fact["name"]}",
    foundation?(fact["scope"])
  ]
end

def take_chars(shape)
  join(take(16, chars(shape)), "")
end

def rows_of(facts)
  homes = map(
    (e) -> home_of(e[1]),
    map_entries(group_by(facts, (f) -> f["shape"]))
  )
  sort_keyed((r) -> r[0], map(row_of, homes))
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
    rendered(rows_of(facts_under(root)))
  )
end

def fact(scope, name, shape)
  {"scope" => scope, "name" => name, "shape" => shape}
end

test "no definition is no row"
  assert rows_of([]) == []
end

test "one shape is one row, its home the foundation bidama"
  rows = rows_of([fact("souji", "sum", "aa"), fact("kazu", "sum", "aa")])
  assert size(rows) == 1
  assert first(rows) == ["aa", "kazu::sum", true]
end

test "a shape only domain bidamas hold has the first as its home, marked domain"
  rows = rows_of([fact("shomei", "side", "bb"), fact("empresa", "pair", "bb")])
  assert first(rows) == ["bb", "todokede::empresa::pair", false]
end

test "rows are sorted by shape, and a shape is cut to sixteen digits"
  long = "0123456789abcdef0123"
  rows = rows_of([fact("a", "x", "ff"), fact("a", "y", long)])
  assert map((r) -> r[0], rows) == %w[0123456789abcdef ff]
end
