@moduledoc """
teeburu (テーブル) — a service's tables: rows over the runtime's pg_ words, and versioned data models that evolve in pure blue.

open connects from settei's settings (database.url and database.schema) and scopes the search path to the service's schema; insert writes one parameterised row and returns it, rows runs a query, latest reads the newest rows of a table.

model declares a versioned model (entities, keys, typed fields, indexes, relations, and the intent a diff cannot see). evolve gives the typed steps between two versions, judge refuses each unsafe step alone, postgres renders the steps that stand to Postgres's native safe forms, and keifu renders those changes as the changelog shinka applies. kv_model is the strict Valkey form of a model, checked by kv_check and upgraded by kv_upgrade; kiibariu's check uses it.

    enabled?({}) #=> false
"""

use("kueri")
use("maakuappu")
use("moji", [:checked])
use("retsu", %i[find_first first is_empty last size])
use("tesuto", %i[caught raises?])

@doc """
quoted: an identifier as a Postgres quoted identifier, each inner double quote doubled.

    quoted("orders") #=> "\"orders\""
"""
def quoted(ident)
  "\"#{replace(ident, "\"", "\"\"")}\""
end

@doc """
enabled?: whether the settings name a database, that is a database.url that is set and not empty.

    enabled?({"database" => {"url" => ""}}) #=> false
"""
def enabled?(settings)
  db = settings["database"]
  db != nil and db["url"] != nil and db["url"] != ""
end

@doc """
open: a Postgres connection from the settings' database.url, its search path set to database.schema; settings with no database raise :no_database.

    raises?(:no_database, () -> open({"database" => {"url" => ""}})) #=> true
"""
def open(settings)
  if not enabled?(settings)
    raise(:no_database, "the settings name no database.url")
  end
  db = settings["database"]
  c = pg_connect(db["url"])
  pg_execute(c, "SET search_path TO #{quoted(db["schema"])}")
  c
end

@doc """
insert_statement: the parameterised INSERT for one row, as the SQL and its parameters in column order; the statement returns the row it writes.

    first(insert_statement("orders", {"sku" => "a"})) #=> "INSERT INTO \"orders\" (\"sku\") VALUES ($1) RETURNING *"
"""
def insert_statement(table, row)
  es = map_entries(row)
  cols = join(map((e) -> quoted(to_s(first(e))), es), ", ")
  marks = join(map((i) -> "$#{to_s(i + 1)}", range(count(es))), ", ")
  [
    "INSERT INTO #{quoted(table)} (#{cols}) VALUES (#{marks}) RETURNING *",
    map((e) -> second(e), es)
  ]
end

@doc """
insert: write one row into a table over a connection and return the row as stored; with no connection the runtime refuses it.

    contains?(to_s(caught(() -> insert(nil, "orders", {"sku" => "a"}))), "a Postgres connection") #=> true
"""
def insert(conn, table, row)
  st = insert_statement(table, row)
  first(pg_query(conn, first(st), second(st))[:rows])
end

@doc """
rows: the rows a parameterised query returns over a connection; with no connection the runtime refuses it.

    contains?(to_s(caught(() -> rows(nil, "SELECT 1", []))), "a Postgres connection") #=> true
"""
def rows(conn, sql, params)
  pg_query(conn, sql, params)[:rows]
end

@doc """
latest_statement: the SELECT for the n newest rows of a table, newest id first.

    latest_statement("orders", 5) #=> "SELECT * FROM \"orders\" ORDER BY \"id\" DESC LIMIT 5"
"""
def latest_statement(table, n)
  "SELECT * FROM #{quoted(table)} ORDER BY \"id\" DESC LIMIT #{to_s(n)}"
end

@doc """
latest: the n newest rows of a table over a connection, newest id first; with no connection the runtime refuses it.

    contains?(to_s(caught(() -> latest(nil, "orders", 5))), "a Postgres connection") #=> true
"""
def latest(conn, table, n)
  rows(conn, latest_statement(table, n), [])
end

@doc """
types lists what a model field may be declared as.

    first(types) #=> :uuid
"""
def types()
  %i[
    uuid
    text
    int
    bigint
    decimal
    float
    bool
    timestamp
    json
    bytes
    list
    record
    any
  ]
end

@doc """
pg_type: the Postgres column type a field type is stored as.

    pg_type(:decimal) #=> "numeric"
"""
def pg_type(t)
  rows = {
    uuid: "uuid",
    text: "text",
    int: "integer",
    bigint: "bigint",
    decimal: "numeric",
    float: "double precision",
    bool: "boolean",
    timestamp: "timestamptz",
    json: "jsonb",
    bytes: "bytea",
    list: "jsonb",
    record: "jsonb",
    any: "jsonb"
  }
  found = get(rows, t)
  if found.nil?
    raise(:bad_option, "no field type #{to_s(t)}")
  end
  found
end

@doc """
widening?: whether a retype keeps every value: a whole number into a wider number or into text, a uuid into text.

    widening?(:int, :bigint) #=> true
"""
def widening?(from, to)
  member?(
    [from, to],
    [
      %i[int bigint],
      %i[int decimal],
      %i[bigint decimal],
      %i[int float],
      %i[int text],
      %i[bigint text],
      %i[uuid text]
    ]
  )
end

@doc """
field_of: a field declaration as a record: a bare type becomes `{type:}`, and nullable unless `null: false`.

    field_of(:int) #=> {type: :int, null: true}
"""
def field_of(spec)
  rec = if keyword?(spec)
    {type: spec}
  else
    checked(spec, %i[type renamed_from allow default null backfill])
  end
  assoc(rec, :null, rec[:null] != false)
end

@doc """
entity_whys: why one entity declaration cannot stand: a key that is not a field, an unknown type, an allow other than :destructive.

    entity_whys(:order, {key: :id, fields: {id: :blob}}) #=> ["order: field id has no type blob"]
"""
def entity_whys(name, e)
  fields = e[:fields] or {}
  key_why = if get(fields, e[:key]).nil?
    ["#{to_s(name)}: its key #{to_s(e[:key])} is not a field"]
  else
    []
  end
  field_whys = retsu::flat_map(
    map_entries(fields),
    fn(f)
      rec = field_of(f[1])
      append(
        if member?(rec[:type], types)
          []
        else
          [
            "#{to_s(name)}: field #{to_s(first(f))} has no type #{to_s(rec[:type])}"
          ]
        end,
        if rec[:allow].nil? or rec[:allow] == :destructive
          []
        else
          ["#{to_s(name)}: field #{to_s(first(f))} allows only :destructive"]
        end
      )
    end
  )
  append(key_why, field_whys)
end

@doc """
model: a data model as a versioned value: entities with a key, typed fields, indexes and relations, and the intent a diff cannot see (`renamed_from`, `split_from`, `merged_from`, and `drop` entries with `allow: :destructive`); its hash names the version.

    model("orders", {version: 1, entities: {order: {key: :id, fields: {id: :uuid}}}})[:version] #=> 1
"""
def model(name, spec)
  checked(spec, %i[version entities drop])
  v = spec[:version]
  if not integer?(v) or v < 1
    raise(:bad_option, "a model version is a whole number from 1")
  end
  declared = map_entries(spec[:entities] or {})
  map(
    fn(e)
      checked(
        e[1],
        %i[
          key
          fields
          indexes
          relations
          renamed_from
          split_from
          merged_from
          cache
          events
        ]
      )
    end,
    declared
  )
  whys = retsu::flat_map(declared, (e) -> entity_whys(first(e), e[1]))
  if not is_empty(whys)
    raise(:refused, join(whys, "; "), {data: whys})
  end
  entities = reduce(
    fn(acc, e)
      fields = reduce(
        (fs, f) -> assoc(fs, first(f), field_of(f[1])),
        {},
        map_entries(e[1][:fields] or {})
      )
      assoc(acc, first(e), assoc(e[1], :fields, fields))
    end,
    {},
    declared
  )
  m = {name:, version: v, entities:, drop: spec[:drop] or []}
  assoc(m, :hash, version_hash(m))
end

@doc """
version_hash: sixteen hex characters of the BLAKE3 of a model's canonical JSON, the hash a cache key and a lock pin carry.

    size(chars(version_hash({version: 1}))) #=> 16
"""
def version_hash(m)
  join(take(16, chars(blake3_hex(json_stringify(dissoc(m, :hash))))), "")
end

@doc """
declared_drop: the drop entry the new model declares for what a step removes, or nil.

    declared_drop({drop: [{entity: :order, field: :note, allow: :destructive}]}, {entity: :order, field: :note}) #=> {entity: :order, field: :note, allow: :destructive}
"""
def declared_drop(to, what)
  find_first(
    fn(d)
      d[:entity] == what[:entity] and
        d[:field] == what[:field] and
        d[:index] == what[:index] and
        d[:relation] == what[:relation]
    end,
    to[:drop]
  )
end

@doc """
drop_step: a drop of what a new version removes, carrying the allow its drop entry declares.

    drop_step({drop: []}, {entity: :order, field: :note}) #=> {step: :drop, entity: :order, field: :note, allow: nil}
"""
def drop_step(to, what)
  d = declared_drop(to, what)
  allow = if d.nil?
    nil
  else
    d[:allow]
  end
  assoc(assoc(what, :step, :drop), :allow, allow)
end

@doc """
key_type: the type of an entity's key in a model, which a relation's column takes.

    key_type(model("m", {version: 1, entities: {c: {key: :id, fields: {id: :uuid}}}}), :c) #=> :uuid
"""
def key_type(m, entity)
  e = get(m[:entities], entity)
  if e.nil?
    raise(
      :bad_option,
      "a relation names #{to_s(entity)}, which the model does not hold"
    )
  end
  get(e[:fields], e[:key])[:type]
end

@doc """
relation_column: the column a relation is stored in.

    relation_column(:customer) #=> "customer_id"
"""
def relation_column(rel)
  join([to_s(rel), "id"], "_")
end

@doc """
field_steps: the steps between one entity's old and new declaration: renames, retypes, added and dropped fields, indexes and relations.

    field_steps(:e, {fields: {a: {type: :int}}}, {fields: {a: {type: :bigint}}}, {drop: [], entities: {}}) #=> [{step: :retype, entity: :e, field: :a, from: :int, to: :bigint, widening: true, allow: nil}]
"""
def field_steps(name, old, new, to)
  of = old[:fields] or {}
  nf = new[:fields] or {}
  claimed = map((f) -> f[1][:renamed_from] or first(f), map_entries(nf))
  per_field = retsu::flat_map(
    map_entries(nf),
    fn(f)
      fname = first(f)
      rec = f[1]
      src = rec[:renamed_from] or fname
      was = get(of, src)
      if was.nil?
        [
          {
            step: :add_field,
            entity: name,
            field: fname,
            type: rec[:type],
            null: rec[:null],
            default: rec[:default],
            backfill: rec[:backfill]
          }
        ]
      else
        renamed = if src != fname
          [{step: :rename, entity: name, field: fname, renamed_from: src}]
        else
          []
        end
        retyped = if was[:type] != rec[:type]
          [
            {
              step: :retype,
              entity: name,
              field: fname,
              from: was[:type],
              to: rec[:type],
              widening: widening?(was[:type], rec[:type]),
              allow: rec[:allow]
            }
          ]
        else
          []
        end
        append(renamed, retyped)
      end
    end
  )
  dropped = map(
    (f) -> drop_step(to, {entity: name, field: first(f)}),
    filter((f) -> not member?(first(f), claimed), map_entries(of))
  )
  oi = old[:indexes] or []
  ni = new[:indexes] or []
  orl = map_entries(old[:relations] or {})
  nrl = map_entries(new[:relations] or {})
  added_indexes = map(
    (cols) -> {step: :add_index, entity: name, columns: cols},
    filter((cols) -> not member?(cols, oi), ni)
  )
  added_relations = map(
    fn(r)
      {
        step: :add_field,
        entity: name,
        field: relation_column(first(r)),
        type: key_type(to, r[1]),
        null: true,
        default: nil,
        backfill: nil,
        references: r[1],
        relation: first(r)
      }
    end,
    filter((r) -> not member?(r, orl), nrl)
  )
  dropped_indexes = map(
    (cols) -> drop_step(to, {entity: name, index: cols}),
    filter((cols) -> not member?(cols, ni), oi)
  )
  dropped_relations = map(
    (r) -> drop_step(to, {entity: name, relation: first(r)}),
    filter((r) -> not member?(r, nrl), orl)
  )
  append(
    per_field,
    added_indexes,
    added_relations,
    dropped,
    dropped_indexes,
    dropped_relations
  )
end

@doc """
sources_of: the entities a new entity takes its data from: what it was renamed, split or merged from.

    sources_of({merged_from: [:a, :b]}) #=> [:a, :b]
"""
def sources_of(spec)
  filter(
    (x) -> x != nil,
    append([spec[:renamed_from], spec[:split_from]], spec[:merged_from] or [])
  )
end

@doc """
evolve: the typed steps from one model version to the next: add_entity, add_field, rename, retype, add_index, split, merge and drop, entities in name order; a version that does not move forward is refused.

    map((s) -> s[:step], evolve(model("m", {version: 1, entities: {}}), model("m", {version: 2, entities: {t: {key: :id, fields: {id: :int}}}}))) #=> [:add_entity]
"""
def evolve(from, to)
  if to[:name] != from[:name]
    raise(
      :refused,
      "model #{to_s(to[:name])} does not evolve #{to_s(from[:name])}"
    )
  end
  if to[:version] <= from[:version]
    raise(
      :refused,
      "#{to_s(to[:name])} version #{to_s(to[:version])} does not follow version #{to_s(from[:version])}"
    )
  end
  olds = from[:entities]
  news = map_entries(to[:entities])
  renamed_away = filter((x) -> x != nil, map((e) -> e[1][:renamed_from], news))
  per_entity = retsu::flat_map(
    news,
    fn(e)
      name = first(e)
      spec = e[1]
      renamed = spec[:renamed_from]
      if renamed != nil and get(olds, renamed) != nil
        append(
          [{step: :rename, entity: name, renamed_from: renamed}],
          field_steps(name, get(olds, renamed), spec, to)
        )
      elsif spec[:split_from] != nil
        [{step: :split, entity: name, from: [spec[:split_from]]}]
      elsif spec[:merged_from] != nil
        [{step: :merge, entity: name, from: spec[:merged_from]}]
      elsif get(olds, name) != nil
        field_steps(name, get(olds, name), spec, to)
      else
        [{step: :add_entity, entity: name}]
      end
    end
  )
  gone = filter(
    fn(e)
      get(to[:entities], first(e)).nil? and not member?(first(e), renamed_away)
    end,
    map_entries(olds)
  )
  append(per_entity, map((e) -> drop_step(to, {entity: first(e)}), gone))
end

@doc """
destructive?: whether a step can lose data: every drop, and a retype that narrows.

    destructive?({step: :retype, widening: false}) #=> true
"""
def destructive?(s)
  s[:step] == :drop or s[:step] == :retype and not s[:widening]
end

@doc """
where_of: the place a step acts on, as text.

    where_of({entity: :order, field: :note}) #=> "order.note"
"""
def where_of(s)
  tail = if s[:field] != nil
    ".#{to_s(s[:field])}"
  elsif s[:index] != nil
    " index #{join(map(to_s, s[:index]), "+")}"
  elsif s[:relation] != nil
    " relation #{to_s(s[:relation])}"
  else
    ""
  end
  "#{to_s(s[:entity])}#{tail}"
end

@doc """
data_add?: whether a step adds a field or an entity that a dropped one might really be, renamed.

    data_add?({step: :add_field, field: :b}) #=> true
"""
def data_add?(s)
  s[:step] == :add_field and s[:references].nil? or s[:step] == :add_entity
end

@doc """
meets?: whether an undeclared drop and an add stand in the same place: a field dropped and one added in the same entity, or an entity dropped while another is added.

    meets?({step: :drop, entity: :o, field: :a}, {step: :add_field, entity: :o, field: :b}) #=> true
"""
def meets?(drop, add)
  if drop[:field] != nil
    add[:step] == :add_field and add[:entity] == drop[:entity]
  else
    drop[:index].nil? and drop[:relation].nil? and add[:step] == :add_entity
  end
end

@doc """
judge: the steps that stand and the refusals, each scoped to its step: a drop with no allow met by an add with no declared rename refuses both, and any other destructive step without `allow: :destructive` is refused alone.

    judge([{step: :drop, entity: :o, field: :a, allow: nil}])[:refusals] #=> [[:destructive, "o.a: drop loses data; declare allow: :destructive on this one step"]]
"""
def judge(steps)
  open_drops = filter((s) -> s[:step] == :drop and s[:allow].nil?, steps)
  adds = filter(data_add?, steps)
  paired_drops = filter((d) -> any?((a) -> meets?(d, a), adds), open_drops)
  paired_adds = filter((a) -> any?((d) -> meets?(d, a), open_drops), adds)
  marks = map(
    fn(s)
      if member?(s, paired_drops)
        [
          [
            :rename_undeclared,
            "#{where_of(s)}: dropped while another is added; declare renamed_from: on the new one, or allow: :destructive on this drop"
          ]
        ]
      elsif member?(s, paired_adds)
        [
          [
            :rename_undeclared,
            "#{where_of(s)}: added while another is dropped; declare renamed_from: if it holds the same data"
          ]
        ]
      elsif destructive?(s) and s[:allow] != :destructive
        [
          [
            :destructive,
            "#{where_of(s)}: #{to_s(s[:step])} loses data; declare allow: :destructive on this one step"
          ]
        ]
      else
        []
      end
    end,
    steps
  )
  {
    steps: map(
      (i) -> steps[i],
      filter((i) -> is_empty(marks[i]), range(size(steps)))
    ),
    refusals: retsu::flat_map(marks, (m) -> m)
  }
end

@doc """
ident: a Postgres identifier, quoted.

    ident(:order) #=> "\"order\""
"""
def ident(x)
  quoted(to_s(x))
end

@doc """
sql_value: a value as a Postgres literal, through kueri's expression renderer.

    sql_value("it's") #=> "'it''s'"
"""
def sql_value(v)
  kueri::render_expr(kueri::expr(v), :core)
end

@doc """
column_sql: one column's definition: its name, its Postgres type, NOT NULL unless nullable, and a constant default.

    column_sql(:total, {type: :int, null: false, default: 0}) #=> "\"total\" integer NOT NULL DEFAULT 0"
"""
def column_sql(name, rec)
  nn = if rec[:null] == false
    ["NOT NULL"]
  else
    []
  end
  dv = if rec[:default].nil?
    []
  else
    ["DEFAULT #{sql_value(rec[:default])}"]
  end
  join(append([ident(name), pg_type(rec[:type])], nn, dv), " ")
end

@doc """
index_name: the name an index on some columns of an entity takes.

    index_name(:order, [:state]) #=> "order_state_idx"
"""
def index_name(entity, cols)
  "#{to_s(entity)}_#{join(map(to_s, cols), "_")}_idx"
end

@doc """
change: one migration change: its id, the step it lowers, whether it runs inside a transaction, and its statements, the lock timeout first.

    change("c1", {step: :rename}, true, ["SELECT 1"], "5s")[:sql] #=> ["SET LOCAL lock_timeout = '5s'", "SELECT 1"]
"""
def change(id, step, transaction, statements, lock_timeout)
  set = if transaction
    "SET LOCAL lock_timeout = '#{lock_timeout}'"
  else
    "SET lock_timeout = '#{lock_timeout}'"
  end
  {id:, step:, transaction:, sql: append([set], statements)}
end

@doc """
keyset_loop: a batched keyset walk over a table in key order, each batch committed on its own, running a statement over that batch's keys.

    contains?(keyset_loop("t", "id", "uuid", 500, "SELECT 1"), "LIMIT 500") #=> true
"""
def keyset_loop(table, key, key_sql_type, batch, statement)
  join_lines(
    [
      "DO $$",
      "DECLARE",
      "  last_key #{key_sql_type};",
      "  keys #{key_sql_type}[];",
      "BEGIN",
      "  LOOP",
      "    SELECT array_agg(k ORDER BY k) INTO keys FROM (SELECT #{key} AS k FROM #{table} WHERE last_key IS NULL OR #{key} > last_key ORDER BY #{key} LIMIT #{to_s(batch)}) AS b;",
      "    EXIT WHEN keys IS NULL;",
      "    #{statement};",
      "    last_key := keys[array_length(keys, 1)];",
      "    COMMIT;",
      "  END LOOP;",
      "END $$"
    ]
  )
end

@doc """
pg_options: the lowering's options with their defaults: a five-second lock timeout and batches of a thousand rows.

    pg_options({})[:batch] #=> 1000
"""
def pg_options(opts)
  checked(opts, %i[lock_timeout batch])
  {lock_timeout: opts[:lock_timeout] or "5s", batch: opts[:batch] or 1000}
end

@doc """
step_id: the changeset id of a step: model, version, position, step and place.

    step_id({name: "m", version: 2}, {step: :rename, entity: :o, field: :b}, 3) #=> "m-v2-3-rename-o.b"
"""
def step_id(to, s, n)
  "#{to[:name]}-v#{to_s(to[:version])}-#{to_s(n)}-#{to_s(s[:step])}-#{replace(where_of(s), " ", "-")}"
end

@doc """
pg_create: the changes that create a new entity's table with its indexes and foreign keys, then copy each source's rows in keyset batches when the entity is split or merged from others.

    size(pg_create({step: :add_entity, entity: :t}, nil, model("m", {version: 1, entities: {t: {key: :id, fields: {id: :int}}}}), pg_options({}), "c")) #=> 1
"""
def pg_create(s, from, to, o, base)
  t = ident(s[:entity])
  lt = o[:lock_timeout]
  e = get(to[:entities], s[:entity])
  rels = map_entries(e[:relations] or {})
  cols = append(
    map((f) -> column_sql(first(f), f[1]), map_entries(e[:fields])),
    map(
      (r) -> column_sql(relation_column(first(r)), {type: key_type(to, r[1])}),
      rels
    )
  )
  create = "CREATE TABLE #{t} (#{join(append(cols, ["PRIMARY KEY (#{ident(e[:key])})"]), ", ")})"
  idx = map(
    fn(cols)
      "CREATE INDEX #{ident(index_name(s[:entity], cols))} ON #{t} (#{join(map(ident, cols), ", ")})"
    end,
    e[:indexes] or []
  )
  fks = map(
    fn(r)
      "ALTER TABLE #{t} ADD CONSTRAINT #{ident("#{to_s(s[:entity])}_#{to_s(first(r))}_fkey")} FOREIGN KEY (#{ident(relation_column(first(r)))}) REFERENCES #{ident(r[1])} (#{ident(get(to[:entities], r[1])[:key])})"
    end,
    rels
  )
  copies = map(
    fn(src)
      old = get(from[:entities], src)
      shared = filter(
        (f) -> get(old[:fields], first(f)) != nil,
        map_entries(e[:fields])
      )
      names = join(map((f) -> ident(first(f)), shared), ", ")
      change(
        "#{base}-copy-#{to_s(src)}",
        s,
        false,
        [
          keyset_loop(
            ident(src),
            ident(old[:key]),
            pg_type(get(old[:fields], old[:key])[:type]),
            o[:batch],
            "INSERT INTO #{t} (#{names}) SELECT #{names} FROM #{ident(src)} WHERE #{ident(old[:key])} = ANY(keys) ON CONFLICT DO NOTHING"
          )
        ],
        lt
      )
    end,
    s[:from] or []
  )
  append(
    [change("#{base}-create", s, true, append([create], idx, fks), lt)],
    copies
  )
end

@doc """
pg_add_field: the changes that add a column: one instant ADD COLUMN for a constant default; for a relation the foreign key NOT VALID then VALIDATE; for a backfill the column, a keyset backfill and, when NOT NULL, a CHECK NOT VALID, VALIDATE, SET NOT NULL; a NOT NULL column with neither default nor backfill is refused.

    size(pg_add_field({step: :add_field, entity: :t, field: :n, type: :int, null: true}, model("m", {version: 1, entities: {}}), pg_options({}), "c")) #=> 1
"""
def pg_add_field(s, to, o, base)
  t = ident(s[:entity])
  lt = o[:lock_timeout]
  c = ident(s[:field])
  rec = {type: s[:type], null: s[:null], default: s[:default]}
  if s[:references] != nil
    fk = ident("#{to_s(s[:entity])}_#{to_s(s[:relation])}_fkey")
    target = get(to[:entities], s[:references])
    [
      change(
        "#{base}-add",
        s,
        true,
        [
          "ALTER TABLE #{t} ADD COLUMN #{column_sql(s[:field], {type: s[:type]})}",
          "ALTER TABLE #{t} ADD CONSTRAINT #{fk} FOREIGN KEY (#{c}) REFERENCES #{ident(s[:references])} (#{ident(target[:key])}) NOT VALID"
        ],
        lt
      ),
      change(
        "#{base}-validate",
        s,
        true,
        ["ALTER TABLE #{t} VALIDATE CONSTRAINT #{fk}"],
        lt
      )
    ]
  elsif s[:backfill] != nil
    e = get(to[:entities], s[:entity])
    key = e[:key]
    check = ident("#{to_s(s[:entity])}_#{to_s(s[:field])}_not_null")
    fill = keyset_loop(
      t,
      ident(key),
      pg_type(get(e[:fields], key)[:type]),
      o[:batch],
      "UPDATE #{t} SET #{c} = #{kueri::render_expr(kueri::expr(s[:backfill]), :core)} WHERE #{ident(key)} = ANY(keys)"
    )
    tighten = if s[:null] == false
      [
        change(
          "#{base}-check",
          s,
          true,
          [
            "ALTER TABLE #{t} ADD CONSTRAINT #{check} CHECK (#{c} IS NOT NULL) NOT VALID"
          ],
          lt
        ),
        change(
          "#{base}-validate",
          s,
          true,
          ["ALTER TABLE #{t} VALIDATE CONSTRAINT #{check}"],
          lt
        ),
        change(
          "#{base}-not-null",
          s,
          true,
          [
            "ALTER TABLE #{t} ALTER COLUMN #{c} SET NOT NULL",
            "ALTER TABLE #{t} DROP CONSTRAINT #{check}"
          ],
          lt
        )
      ]
    else
      []
    end
    append(
      [
        change(
          "#{base}-add",
          s,
          true,
          [
            "ALTER TABLE #{t} ADD COLUMN #{column_sql(s[:field], {type: s[:type]})}"
          ],
          lt
        ),
        change("#{base}-backfill", s, false, [fill], lt)
      ],
      tighten
    )
  elsif s[:null] == false and s[:default].nil?
    raise(
      :refused,
      "#{where_of(s)}: NOT NULL with no default and no backfill leaves existing rows without a value"
    )
  else
    [
      change(
        base,
        s,
        true,
        ["ALTER TABLE #{t} ADD COLUMN #{column_sql(s[:field], rec)}"],
        lt
      )
    ]
  end
end

@doc """
pg_step: one judged step lowered to its Postgres changes, the fastest safe form for each: CONCURRENTLY outside a transaction, NOT VALID then VALIDATE, a constant default with no rewrite, a batched keyset backfill, lock_timeout on every change; a step Postgres cannot carry safely is refused by name.

    map((c) -> c[:transaction], pg_step({step: :add_index, entity: :o, columns: [:s]}, nil, {name: "m", version: 2}, pg_options({}), 1)) #=> [false]
"""
def pg_step(s, from, to, o, n)
  base = step_id(to, s, n)
  t = ident(s[:entity])
  lt = o[:lock_timeout]
  one = (sql, tx) -> [change(base, s, tx, [sql], lt)]
  st = s[:step]
  if member?(st, %i[add_entity split merge])
    pg_create(s, from, to, o, base)
  elsif st == :add_field
    pg_add_field(s, to, o, base)
  elsif st == :rename and s[:field].nil?
    one("ALTER TABLE #{ident(s[:renamed_from])} RENAME TO #{t}", true)
  elsif st == :rename
    one(
      "ALTER TABLE #{t} RENAME COLUMN #{ident(s[:renamed_from])} TO #{ident(s[:field])}",
      true
    )
  elsif st == :retype
    c = ident(s[:field])
    one(
      "ALTER TABLE #{t} ALTER COLUMN #{c} TYPE #{pg_type(s[:to])} USING #{c}::#{pg_type(s[:to])}",
      true
    )
  elsif st == :add_index
    one(
      "CREATE INDEX CONCURRENTLY IF NOT EXISTS #{ident(index_name(s[:entity], s[:columns]))} ON #{t} (#{join(map(ident, s[:columns]), ", ")})",
      false
    )
  elsif st == :drop and s[:field] != nil
    one("ALTER TABLE #{t} DROP COLUMN #{ident(s[:field])}", true)
  elsif st == :drop and s[:index] != nil
    one(
      "DROP INDEX CONCURRENTLY IF EXISTS #{ident(index_name(s[:entity], s[:index]))}",
      false
    )
  elsif st == :drop and s[:relation] != nil
    one(
      "ALTER TABLE #{t} DROP CONSTRAINT #{ident("#{to_s(s[:entity])}_#{to_s(s[:relation])}_fkey")}",
      true
    )
  elsif st == :drop
    one("DROP TABLE #{t}", true)
  else
    raise(:bad_option, "no Postgres lowering for step #{to_s(st)}")
  end
end

@doc """
postgres: the Postgres changes for the steps the judge lets stand between two versions, in step order, with the judge's refusals beside them; a refused step never reaches the database.

    postgres(model("m", {version: 1, entities: {}}), model("m", {version: 2, entities: {}}), {}) #=> {changes: [], refusals: []}
"""
def postgres(from, to, opts)
  o = pg_options(opts)
  j = judge(evolve(from, to))
  {
    changes: retsu::flat_map(
      range(size(j[:steps])),
      (i) -> pg_step(j[:steps][i], from, to, o, i + 1)
    ),
    refusals: j[:refusals]
  }
end

@doc """
keifu: changes as a keifu changelog, the Liquibase XML shinka applies in process: one changeSet per change, each statement its own sql element, and runInTransaction false where a change must run outside a transaction.

    contains?(keifu([{id: "m-v2-1", step: {step: :add_index}, transaction: false, sql: ["SELECT 1"]}]), "runInTransaction=\"false\"") #=> true
"""
def keifu(changes)
  sets = retsu::flat_map(
    changes,
    fn(c)
      tx = if c[:transaction]
        ""
      else
        " runInTransaction=\"false\""
      end
      append(
        [
          "  <changeSet id=\"#{maakuappu::escape(c[:id])}\" author=\"blue\"#{tx}>",
          "    <comment>#{maakuappu::escape(to_s(c[:step][:step]))}</comment>"
        ],
        map(
          fn(q)
            "    <sql splitStatements=\"false\">#{maakuappu::escape(q)}</sql>"
          end,
          c[:sql]
        ),
        ["  </changeSet>"]
      )
    end
  )
  unlines(
    append(
      [
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
        "<databaseChangeLog xmlns=\"http://www.liquibase.org/xml/ns/dbchangelog\">"
      ],
      sets,
      ["</databaseChangeLog>"]
    )
  )
end

@doc """
kv_entity: one strict Valkey entity checked and given its defaults: JSON encoding, upgrade on read, strict; indexes, relations and an encoding not rendered yet are refused by name.

    kv_entity(:s, {key: :id, fields: {id: :text}})[:upgrade] #=> :on_read
"""
def kv_entity(name, ent)
  checked(
    ent,
    %i[key fields encoding ttl_ms upgrade strict indexes relations renamed_from]
  )
  if ent[:indexes] != nil
    raise(:refused, "kv entity #{to_s(name)}: indexes have no Valkey form")
  end
  if ent[:relations] != nil
    raise(:refused, "kv entity #{to_s(name)}: relations have no Valkey form")
  end
  enc = ent[:encoding] or :json
  if enc != :json
    raise(
      :refused,
      "kv entity #{to_s(name)}: the #{to_s(enc)} encoding is not rendered yet (pending-kv-encodings); :json is"
    )
  end
  up = ent[:upgrade] or :on_read
  if not member?(up, %i[on_read eager])
    raise(:bad_option, "kv entity #{to_s(name)}: upgrade is :on_read or :eager")
  end
  assoc(
    assoc(
      assoc(dissoc(dissoc(ent, :indexes), :relations), :encoding, enc),
      :upgrade,
      up
    ),
    :strict,
    ent[:strict] != false
  )
end

@doc """
kv_model: a strict Valkey model: a versioned model whose entities each carry an encoding, a TTL, an upgrade mode and strictness, evolved by the same steps as a table.

    kv_model("sessions", {version: 1, entities: {session: {key: :id, fields: {id: :text}}}})[:entities][:session][:encoding] #=> :json
"""
def kv_model(name, spec)
  checked(spec, %i[version entities])
  shaped = map(
    (e) -> [first(e), kv_entity(first(e), e[1])],
    map_entries(spec[:entities] or {})
  )
  plain = reduce(
    fn(acc, e)
      assoc(
        acc,
        first(e),
        {
          key: e[1][:key],
          fields: e[1][:fields],
          renamed_from: e[1][:renamed_from]
        }
      )
    end,
    {},
    shaped
  )
  m = model(name, {version: spec[:version], entities: plain})
  kept = reduce(
    fn(acc, e)
      k = e[1]
      typed = get(m[:entities], first(e))
      assoc(
        acc,
        first(e),
        assoc(
          assoc(
            assoc(assoc(typed, :encoding, k[:encoding]), :upgrade, k[:upgrade]),
            :strict,
            k[:strict]
          ),
          :ttl_ms,
          k[:ttl_ms]
        )
      )
    end,
    {},
    shaped
  )
  out = assoc(m, :entities, kept)
  assoc(out, :hash, version_hash(out))
end

@doc """
holds?: whether a stored value is of a field type, as JSON carries it.

    holds?(:int, "1") #=> false
"""
def holds?(type, v)
  if member?(type, %i[uuid text timestamp bytes])
    string?(v)
  elsif member?(type, %i[int bigint])
    integer?(v)
  elsif member?(type, %i[decimal float])
    number?(v)
  elsif type == :bool
    boolean?(v)
  elsif type == :list
    v != nil and list?(v)
  elsif type == :record
    map?(v)
  elsif member?(type, %i[json any])
    true
  else
    raise(:bad_option, "no field type #{to_s(type)}")
  end
end

@doc """
kv_findings: every way a stored record breaks a strict entity: not a record, a missing field, a value of the wrong type, and, unless the entity is loose, a field it does not declare.

    kv_findings({fields: {"n" => :int}}, {"n" => 1, "x" => 2}) #=> [[:bad_value, "the record has a field x the model does not declare"]]
"""
def kv_findings(entity, rec)
  if not map?(rec)
    [[:bad_value, "a stored value is a record, got #{to_s(rec)}"]]
  else
    fields = map_entries(entity[:fields] or {})
    declared = map((f) -> to_s(first(f)), fields)
    per_field = retsu::flat_map(
      fields,
      fn(f)
        name = to_s(first(f))
        t = field_of(f[1])[:type]
        v = get(rec, name)
        if v.nil? and
            not member?(name, map((e) -> to_s(first(e)), map_entries(rec)))
          [[:bad_value, "the record has no field #{name}"]]
        elsif not holds?(t, v)
          [[:bad_value, "field #{name} is not #{to_s(t)}"]]
        else
          []
        end
      end
    )
    extra = if entity[:strict] == false
      []
    else
      map(
        fn(e)
          [
            :bad_value,
            "the record has a field #{to_s(first(e))} the model does not declare"
          ]
        end,
        filter((e) -> not member?(to_s(first(e)), declared), map_entries(rec))
      )
    end
    append(per_field, extra)
  end
end

@doc """
kv_check: the record when it holds to a strict entity, else one :bad_value raise naming every finding.

    kv_check({fields: {"n" => :int}}, {"n" => 1}) #=> {"n" => 1}
"""
def kv_check(entity, rec)
  found = kv_findings(entity, rec)
  if not is_empty(found)
    raise(:bad_value, join(map((f) -> f[1], found), "; "), {data: found})
  end
  rec
end

@doc """
kv_upgrade: what an old stored record of an entity becomes under the next version, from the judged steps: renamed fields moved, added fields given their default, fields widened to text converted, dropped fields removed; a step Valkey cannot carry is refused by name.

    kv_upgrade([{step: :add_field, entity: :s, field: :n, default: 0}], :s)({}) #=> {"n" => 0}
"""
def kv_upgrade(steps, entity)
  own = filter((s) -> s[:entity] == entity, steps)
  bad = filter(
    fn(s)
      member?(s[:step], %i[add_index split merge]) or s[:references] != nil
    end,
    own
  )
  if not is_empty(bad)
    raise(
      :refused,
      "#{to_s(first(bad)[:step])} on #{where_of(first(bad))} has no Valkey form"
    )
  end
  fn(rec)
    reduce(
      fn(r, s)
        st = s[:step]
        if st == :rename and s[:field] != nil
          was = to_s(s[:renamed_from])
          assoc(dissoc(r, was), to_s(s[:field]), get(r, was))
        elsif st == :add_field
          assoc(r, to_s(s[:field]), s[:default])
        elsif st == :retype and s[:to] == :text
          assoc(r, to_s(s[:field]), to_s(get(r, to_s(s[:field]))))
        elsif st == :drop and s[:field] != nil
          dissoc(r, to_s(s[:field]))
        else
          r
        end
      end,
      rec,
      own
    )
  end
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
  ) == true
  assert error?(
    begin
      open({})
    rescue e
      e
    end
  ) == true
end

test "an unchanged model evolves to no steps, and a version must move forward"
  m1 = model(
    "orders",
    {version: 1, entities: {order: {key: :id, fields: {id: :uuid}}}}
  )
  m2 = model(
    "orders",
    {version: 2, entities: {order: {key: :id, fields: {id: :uuid}}}}
  )
  assert evolve(m1, m2) == []
  assert judge([]) == {steps: [], refusals: []}
  assert raises?(:refused, () -> evolve(m2, m1))
  assert raises?(:refused, () -> evolve(m1, m1))
  assert raises?(
    :refused,
    () -> evolve(m1, model("other", {version: 2, entities: {}}))
  )
  assert m1[:hash] != m2[:hash]
  assert m1[:hash] ==
    get(
      model(
        "orders",
        {version: 1, entities: {order: {key: :id, fields: {id: :uuid}}}}
      ),
      :hash
    )
end

test "a model refuses a key that is no field, an unknown type and a bad version"
  assert raises?(
    :refused,
    () -> model("m", {version: 1, entities: {t: {key: :id, fields: {x: :int}}}})
  )
  assert raises?(
    :refused,
    fn()
      model("m", {version: 1, entities: {t: {key: :id, fields: {id: :blob}}}})
    end
  )
  assert raises?(:bad_option, () -> model("m", {version: 0, entities: {}}))
  assert raises?(
    :bad_option,
    fn()
      model(
        "m",
        {version: 1, entities: {t: {key: :id, fields: {id: :int}, color: :red}}}
      )
    end
  )
end

test "evolve names all eight steps, each in its place"
  v1 = model(
    "shop",
    {
      version: 1,
      entities: {
        customer: {key: :id, fields: {id: :uuid, name: :text}},
        order: {
          key: :id,
          fields: {id: :uuid, total: :int, note: :text, state: :text},
          indexes: [[:note]]
        },
        parts: {key: :id, fields: {id: :int, a: :text, b: :text}},
        legacy: {key: :id, fields: {id: :int}}
      }
    }
  )
  v2 = model(
    "shop",
    {
      version: 2,
      entities: {
        customer: {key: :id, fields: {id: :uuid, name: :text}},
        order: {
          key: :id,
          fields: {
            id: :uuid,
            amount: {type: :bigint, renamed_from: :total},
            state: :text
          },
          indexes: [[:state]],
          relations: {customer: :customer}
        },
        part_a: {key: :id, fields: {id: :int, a: :text}, split_from: :parts},
        ledger: {key: :id, fields: {id: :int}, merged_from: %i[legacy parts]},
        invoice: {key: :id, fields: {id: :uuid}}
      },
      drop: [{entity: :order, field: :note, allow: :destructive}]
    }
  )
  steps = evolve(v1, v2)
  assert map((s) -> [s[:step], where_of(s)], steps) ==
    [
      [:add_entity, "invoice"],
      [:merge, "ledger"],
      [:rename, "order.amount"],
      [:retype, "order.amount"],
      [:add_index, "order"],
      [:add_field, "order.customer_id"],
      [:drop, "order.note"],
      [:drop, "order index note"],
      [:split, "part_a"],
      [:drop, "legacy"],
      [:drop, "parts"]
    ]
  j = judge(steps)
  assert map((r) -> first(r), j[:refusals]) ==
    %i[rename_undeclared destructive rename_undeclared rename_undeclared]
  assert size(j[:steps]) == 7
end

test "a drop met by an add with no declared rename is refused as a pair, and a declared rename passes"
  v1 = model(
    "m",
    {
      version: 1,
      entities: {
        o: {key: :id, fields: {id: :int, note: :text}},
        keep: {key: :id, fields: {id: :int}}
      }
    }
  )
  bare = model(
    "m",
    {
      version: 2,
      entities: {
        o: {key: :id, fields: {id: :int, memo: :text}},
        keep: {key: :id, fields: {id: :int, extra: {type: :int, default: 0}}}
      }
    }
  )
  j = judge(evolve(v1, bare))
  assert map(first, j[:refusals]) == %i[rename_undeclared rename_undeclared]
  assert map(where_of, j[:steps]) == ["keep.extra"]
  named = model(
    "m",
    {
      version: 2,
      entities: {
        o: {
          key: :id,
          fields: {id: :int, memo: {type: :text, renamed_from: :note}}
        },
        keep: {key: :id, fields: {id: :int}}
      }
    }
  )
  assert judge(evolve(v1, named))[:refusals] == []
  assert map((s) -> s[:step], judge(evolve(v1, named))[:steps]) == [:rename]
  allowed = model(
    "m",
    {
      version: 2,
      entities: {
        o: {key: :id, fields: {id: :int, memo: :text}},
        keep: {key: :id, fields: {id: :int}}
      },
      drop: [{entity: :o, field: :note, allow: :destructive}]
    }
  )
  assert judge(evolve(v1, allowed))[:refusals] == []
end

test "a narrowing retype needs allow: :destructive on its own field, and a widening one does not"
  v1 = model(
    "m",
    {
      version: 1,
      entities: {o: {key: :id, fields: {id: :int, n: :bigint, w: :int}}}
    }
  )
  v2 = model(
    "m",
    {
      version: 2,
      entities: {o: {key: :id, fields: {id: :int, n: :int, w: :bigint}}}
    }
  )
  j = judge(evolve(v1, v2))
  assert j[:refusals] ==
    [
      [
        :destructive,
        "o.n: retype loses data; declare allow: :destructive on this one step"
      ]
    ]
  assert map((s) -> s[:to], j[:steps]) == [:bigint]
  v3 = model(
    "m",
    {
      version: 2,
      entities: {
        o: {
          key: :id,
          fields: {id: :int, n: {type: :int, allow: :destructive}, w: :bigint}
        }
      }
    }
  )
  assert judge(evolve(v1, v3))[:refusals] == []
end

test "Postgres gets its native safe forms, each change led by its lock timeout"
  v1 = model(
    "shop",
    {
      version: 1,
      entities: {
        customer: {key: :id, fields: {id: :uuid}},
        order: {key: :id, fields: {id: :uuid, price: :int, qty: :int}}
      }
    }
  )
  v2 = model(
    "shop",
    {
      version: 2,
      entities: {
        customer: {key: :id, fields: {id: :uuid}},
        order: {
          key: :id,
          fields: {
            id: :uuid,
            price: :int,
            qty: :int,
            currency: {type: :text, null: false, default: "BRL"},
            total: {type: :int, null: false, backfill: kueri::mul(:price, :qty)}
          },
          indexes: [[:currency]],
          relations: {customer: :customer}
        }
      }
    }
  )
  out = postgres(v1, v2, {lock_timeout: "3s", batch: 500})
  cs = out[:changes]
  assert out[:refusals] == []
  assert every?(
    fn(c)
      starts_with?(first(c[:sql]), "SET") and
        contains?(first(c[:sql]), "lock_timeout = '3s'")
    end,
    cs
  )
  sqls = map((c) -> last(c[:sql]), cs)
  assert sqls[0] ==
    "ALTER TABLE \"order\" ADD COLUMN \"currency\" text NOT NULL DEFAULT 'BRL'"
  assert sqls[1] == "ALTER TABLE \"order\" ADD COLUMN \"total\" integer"
  assert contains?(
    sqls[2],
    "UPDATE \"order\" SET \"total\" = price * qty WHERE \"id\" = ANY(keys)"
  )
  assert contains?(sqls[2], "LIMIT 500")
  assert contains?(sqls[2], "last_key := keys[array_length(keys, 1)];")
  assert contains?(sqls[2], "    COMMIT;")
  assert cs[2][:transaction] == false
  assert sqls[3] ==
    "ALTER TABLE \"order\" ADD CONSTRAINT \"order_total_not_null\" CHECK (\"total\" IS NOT NULL) NOT VALID"
  assert sqls[4] ==
    "ALTER TABLE \"order\" VALIDATE CONSTRAINT \"order_total_not_null\""
  assert sqls[5] ==
    "ALTER TABLE \"order\" DROP CONSTRAINT \"order_total_not_null\""
  assert sqls[6] ==
    "CREATE INDEX CONCURRENTLY IF NOT EXISTS \"order_currency_idx\" ON \"order\" (\"currency\")"
  assert cs[6][:transaction] == false
  assert contains?(
    last(cs[7][:sql]),
    "REFERENCES \"customer\" (\"id\") NOT VALID"
  )
  assert sqls[8] ==
    "ALTER TABLE \"order\" VALIDATE CONSTRAINT \"order_customer_fkey\""
  assert size(distinct(map((c) -> c[:id], cs))) == size(cs)
end

test "a NOT NULL column with neither default nor backfill is refused for Postgres by name"
  v1 = model("m", {version: 1, entities: {o: {key: :id, fields: {id: :int}}}})
  v2 = model(
    "m",
    {
      version: 2,
      entities: {
        o: {key: :id, fields: {id: :int, n: {type: :int, null: false}}}
      }
    }
  )
  assert raises?(:refused, () -> postgres(v1, v2, {}))
end

test "a refused step never reaches the changes, and its siblings still do"
  v1 = model(
    "m",
    {version: 1, entities: {o: {key: :id, fields: {id: :int, gone: :text}}}}
  )
  v2 = model(
    "m",
    {
      version: 2,
      entities: {o: {key: :id, fields: {id: :int}, indexes: [[:id]]}}
    }
  )
  out = postgres(v1, v2, {})
  assert map(first, out[:refusals]) == [:destructive]
  assert map((c) -> c[:step][:step], out[:changes]) == [:add_index]
end

test "split and merge copy rows in keyset batches into the new table"
  v1 = model(
    "m",
    {
      version: 1,
      entities: {
        a: {key: :id, fields: {id: :int, x: :text}},
        b: {key: :id, fields: {id: :int, y: :text}}
      }
    }
  )
  v2 = model(
    "m",
    {
      version: 2,
      entities: {
        a: {key: :id, fields: {id: :int, x: :text}},
        b: {key: :id, fields: {id: :int, y: :text}},
        ab: {
          key: :id,
          fields: {id: :int, x: :text, y: :text},
          merged_from: %i[a b]
        }
      }
    }
  )
  cs = postgres(v1, v2, {})[:changes]
  assert size(cs) == 3
  assert starts_with?(last(first(cs)[:sql]), "CREATE TABLE \"ab\"")
  assert contains?(
    last(cs[1][:sql]),
    "INSERT INTO \"ab\" (\"id\", \"x\") SELECT \"id\", \"x\" FROM \"a\""
  )
  assert contains?(
    last(cs[2][:sql]),
    "FROM \"b\" WHERE \"id\" = ANY(keys) ON CONFLICT DO NOTHING"
  )
end

test "keifu renders one changeSet per change, escaped, outside a transaction where it must be"
  cs = [
    {
      id: "m-v2-1",
      step: {step: :add_index},
      transaction: false,
      sql: ["SET lock_timeout = '5s'", "SELECT 1 < 2 & 3"]
    },
    {id: "m-v2-2", step: {step: :rename}, transaction: true, sql: ["SELECT 2"]}
  ]
  x = keifu(cs)
  assert starts_with?(x, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
  assert size(split(x, "<changeSet ")) == 3
  assert contains?(
    x,
    "<changeSet id=\"m-v2-1\" author=\"blue\" runInTransaction=\"false\">"
  )
  assert contains?(x, "<changeSet id=\"m-v2-2\" author=\"blue\">")
  assert contains?(x, "SELECT 1 &lt; 2 &amp; 3")
  assert keifu([]) ==
    join_lines(
      [
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
        "<databaseChangeLog xmlns=\"http://www.liquibase.org/xml/ns/dbchangelog\">",
        "</databaseChangeLog>",
        ""
      ]
    )
end

test "a strict kv model refuses what Valkey cannot carry, and checks every field both ways"
  assert raises?(
    :refused,
    fn()
      kv_model(
        "s",
        {
          version: 1,
          entities: {s: {key: :id, fields: {id: :text}, indexes: [[:id]]}}
        }
      )
    end
  )
  assert raises?(
    :refused,
    fn()
      kv_model(
        "s",
        {
          version: 1,
          entities: {s: {key: :id, fields: {id: :text}, relations: {u: :u}}}
        }
      )
    end
  )
  assert raises?(
    :refused,
    fn()
      kv_model(
        "s",
        {
          version: 1,
          entities: {s: {key: :id, fields: {id: :text}, encoding: :hash}}
        }
      )
    end
  )
  m = kv_model(
    "s",
    {
      version: 1,
      entities: {s: {key: :id, fields: {id: :text, n: :int}, ttl_ms: 60000}}
    }
  )
  e = m[:entities][:s]
  assert e[:ttl_ms] == 60000
  assert kv_check(e, {"id" => "a", "n" => 1}) == {"id" => "a", "n" => 1}
  assert map(last, kv_findings(e, {"n" => "1", "extra" => true})) ==
    [
      "the record has no field id",
      "field n is not int",
      "the record has a field extra the model does not declare"
    ]
  assert kv_findings(
    assoc(e, :strict, false),
    {"id" => "a", "n" => 1, "extra" => true}
  ) == []
  assert raises?(:bad_value, () -> kv_check(e, "text"))
end

test "a kv record upgrades through the same steps, and an index has no Valkey form"
  v1 = kv_model(
    "s",
    {
      version: 1,
      entities: {s: {key: :id, fields: {id: :text, n: :int, old: :text}}}
    }
  )
  v2 = kv_model(
    "s",
    {
      version: 2,
      entities: {
        s: {
          key: :id,
          fields: {
            id: :text,
            count: {type: :int, renamed_from: :n},
            unit: {type: :text, default: "ms"}
          }
        }
      }
    }
  )
  steps = evolve(v1, v2)
  allowed = judge(
    evolve(
      v1,
      assoc(v2, :drop, [{entity: :s, field: :old, allow: :destructive}])
    )
  )
  assert map(first, judge(steps)[:refusals]) ==
    %i[rename_undeclared rename_undeclared]
  up = kv_upgrade(allowed[:steps], :s)
  assert up({"id" => "a", "n" => 3, "old" => "x"}) ==
    {"id" => "a", "count" => 3, "unit" => "ms"}
  assert kv_check(
    v2[:entities][:s],
    up({"id" => "a", "n" => 3, "old" => "x"})
  ) == {"id" => "a", "count" => 3, "unit" => "ms"}
  assert raises?(
    :refused,
    () -> kv_upgrade([{step: :add_index, entity: :s, columns: [:id]}], :s)
  )
end
