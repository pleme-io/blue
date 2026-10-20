def quoted(ident)
  "\"#{replace(ident, "\"", "\"\"")}\""
end

def enabled?(settings)
  db = get(settings, "database")
  db != nil and get(db, "url") != nil and get(db, "url") != ""
end

def open(settings)
  if not enabled?(settings)
    raise(:no_database, "the settings name no database.url")
  end
  db = get(settings, "database")
  c = pg_connect(get(db, "url"))
  pg_execute(c, "SET search_path TO #{quoted(get(db, "schema"))}")
  c
end

def insert_statement(table, row)
  es = map_entries(row)
  cols = join(map((e) -> quoted(to_s(first(e))), es), ", ")
  marks = join(map((i) -> "$#{to_s(i + 1)}", range(count(es))), ", ")
  [
    "INSERT INTO #{quoted(table)} (#{cols}) VALUES (#{marks}) RETURNING *",
    map((e) -> second(e), es)
  ]
end

def insert(conn, table, row)
  st = insert_statement(table, row)
  first(get(pg_query(conn, first(st), second(st)), :rows))
end

def rows(conn, sql, params)
  get(pg_query(conn, sql, params), :rows)
end

def latest_statement(table, n)
  "SELECT * FROM #{quoted(table)} ORDER BY \"id\" DESC LIMIT #{to_s(n)}"
end

def latest(conn, table, n)
  rows(conn, latest_statement(table, n), [])
end

test "an insert is parameterised, its columns quoted and ordered"
  st = insert_statement("greetings", {"text" => "it's", "loud" => true})
  assert st ==
    [
      "INSERT INTO \"greetings\" (\"loud\", \"text\") VALUES ($1, $2) RETURNING *",
      [true, "it's"]
    ]
  assert first(insert_statement("t", {})) ==
    "INSERT INTO \"t\" () VALUES () RETURNING *"
end

test "identifiers escape their own quotes"
  assert quoted("a\"b") == "\"a\"\"b\""
  assert latest_statement("greetings", 3) ==
    "SELECT * FROM \"greetings\" ORDER BY \"id\" DESC LIMIT 3"
end

test "a database is configured only when its url is set"
  assert enabled?({}) == false
  assert enabled?({"database" => {"url" => "", "schema" => "s"}}) == false
  assert enabled?(
    {"database" => {"url" => "postgres://u@h/d", "schema" => "s"}}
  ) ==
    true
  assert error?(
    begin
      open({})
    rescue e
      e
    end
  ) ==
    true
end
