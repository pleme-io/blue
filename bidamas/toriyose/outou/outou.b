@moduledoc """
outou (応答) — a GraphQL request answered: a schema of blue resolvers, execution to {data, errors}, introspection and subscription events, over danpen's documents.

Written to the GraphQL specification, October 2021 edition
(https://spec.graphql.org/October2021/): the type system of §3,
introspection of §4, execution of §6 and the response shape of §7.
danpen parses the document and judges it against this schema's SDL (§2,
§5); a parse or validation failure is a kyohi refusal whose why is the list
of GraphQL errors with their locations, refused per document. A schema is
a value built from type constructors, and a resolver is a blue function of
(parent, args, context). No I/O happens here: host effects enter only
through the resolvers a service supplies. `from_model` derives object types
and the query root from an entity map, as a pure function, so a model
renders straight into a schema; `from_teeburu` reads a chozou/teeburu data
model as that map, so one declaration names a service's storage and its
GraphQL types. `http_routes` serves a schema as kyuuji routes, GET and POST
at one path, answered by `http_answer` with a typed error for a request
that cannot be read.

    as_ref("Int") #=> type_ref("Int")
"""

use("eigyou/kyuuji")
use("hizuke", [:rfc3339_of_ms])
use("jisho", [:has?])
use("kansuu", [:apply_when])
use("kyohi", %i[kind ok ok? refusal refusal_of refused value why])

use("moji", %i[camel_case pascal_case starts_with])

use(
  "retsu",
  %i[
    contains
    count_where
    enumerate
    find_first
    first
    flat_map
    index_of
    is_empty
    last
    rest
    size
    update_at
  ]
)

use("toriyose/danpen")

legacy_names("0.1.2", [%w[render_ast toriyose::danpen::render_value]])

@doc """
errors_of: the GraphQL errors a refused parse, validation or request carries, ready to answer as `errors`.

    errors_of(request_error("Must provide an operation.", [])) #=> [{message: "Must provide an operation.", locations: []}]
"""
def errors_of(result)
  why(refusal_of(result))
end

@doc """
type_ref: a type reference read from its GraphQL text, so a schema can name a type the way SDL writes it.

    toriyose::danpen::type_text(type_ref("[Int!]")) #=> "[Int!]"
"""
def type_ref(text)
  op = first(toriyose::danpen::parse("query ($t: #{text}) { a }").definitions)
  first(op.variables).type
end

@doc """
named: a reference to the type called `name`, with no list or non-null wrapper.

    named("Int") #=> {kind: :named, name: "Int"}
"""
def named(name)
  {kind: :named, name:}
end

@doc """
list_of: a list of the type `ref`, given as a reference or as its text.

    toriyose::danpen::type_text(list_of("Int")) #=> "[Int]"
"""
def list_of(ref)
  {kind: :list_of, of: as_ref(ref)}
end

@doc """
non_null: the type `ref` made non-null, so a value of it can never be null.

    toriyose::danpen::type_text(non_null("String")) #=> "String!"
"""
def non_null(ref)
  {kind: :non_null, of: as_ref(ref)}
end

@doc """
as_ref: a type reference from either its text or a reference already built, so every constructor takes both.

    as_ref(named("Int")) #=> {kind: :named, name: "Int"}
"""
def as_ref(ref)
  apply_when(string?, type_ref)(ref)
end

@doc """
non_null? tells whether the reference `ref` forbids null.

    non_null?(type_ref("Int!")) #=> true
"""
def non_null?(ref)
  ref.kind == :non_null
end

@doc """
nullable: the reference `ref` with its outer non-null wrapper taken off; a nullable reference stays as it is.

    toriyose::danpen::type_text(nullable(type_ref("Int!"))) #=> "Int"
"""
def nullable(ref)
  if non_null?(ref)
    ref.of
  else
    ref
  end
end

@doc """
deprecation: the deprecation reason a `deprecated` option gives: true reads as the specification's default reason, a text stays itself, and nil means not deprecated.

    deprecation(true) #=> "No longer supported"
"""
def deprecation(d)
  if d == true
    "No longer supported"
  else
    d
  end
end

@doc """
field: one field of an object or interface type, with the arguments it takes, the resolver that answers it, the subscribe function of a subscription root and its deprecation.

    field("id", "ID!").name #=> "id"
    field("old", "String", {deprecated: true}).deprecated #=> "No longer supported"
"""
def field(name, ref, opts?)
  o = opts or {}
  {
    name:,
    type: as_ref(ref),
    args: o[:args] or [],
    resolve: o[:resolve],
    subscribe: o[:subscribe],
    deprecated: deprecation(o[:deprecated]),
    description: o[:description]
  }
end

@doc """
arg: one argument of a field or directive, or one field of an input type, with the default it falls back to when the request leaves it out.

    arg("unit", "Unit", {default: "METER"}).has_default #=> true
    arg("id", "ID!").has_default #=> false
"""
def arg(name, ref, opts?)
  o = opts or {}
  {
    name:,
    type: as_ref(ref),
    default: o[:default],
    has_default: has?(o, :default),
    deprecated: deprecation(o[:deprecated]),
    description: o[:description]
  }
end

@doc """
enum_value: one value of an enum type, with its deprecation and description.

    enum_value("FOOT", {deprecated: "Use METER."}).deprecated #=> "Use METER."
"""
def enum_value(name, opts?)
  o = opts or {}
  {name:, deprecated: deprecation(o[:deprecated]), description: o[:description]}
end

@doc """
as_enum_value: an enum value from either its bare name or a value already built, so enum_type takes both.

    as_enum_value("RED")[:name] #=> "RED"
"""
def as_enum_value(v)
  apply_when(string?, enum_value)(v)
end

@doc """
indexed: a list of named members keyed by their names, so execution finds a field without a scan.

    indexed([field("a", "Int")])["a"].name #=> "a"
"""
def indexed(fields)
  zipmap(map((f) -> f.name, fields), fields)
end

@doc """
object_type: an object type of a schema, with its fields and the interfaces it implements.

    object_type("Review", [field("stars", "Int!")]).kind #=> "OBJECT"
"""
def object_type(name, fields, opts?)
  o = opts or {}
  {
    kind: "OBJECT",
    name:,
    fields:,
    field_index: indexed(fields),
    interfaces: o[:interfaces] or [],
    description: o[:description]
  }
end

@doc """
interface_type: an interface type of a schema, with its fields and the resolve_type function that names the object type of a value at runtime.

    interface_type("Character", [field("id", "ID!")]).kind #=> "INTERFACE"
"""
def interface_type(name, fields, opts?)
  o = opts or {}
  {
    kind: "INTERFACE",
    name:,
    fields:,
    field_index: indexed(fields),
    interfaces: o[:interfaces] or [],
    resolve_type: o[:resolve_type],
    description: o[:description]
  }
end

@doc """
union_type: a union type of a schema over the object types it may hold.

    union_type("SearchResult", %w[Human Droid]).members #=> ["Human", "Droid"]
"""
def union_type(name, members, opts?)
  o = opts or {}
  {
    kind: "UNION",
    name:,
    members:,
    resolve_type: o[:resolve_type],
    description: o[:description]
  }
end

@doc """
enum_type: an enum type of a schema; each value is a bare name or an enum_value.

    enum_names(enum_type("Episode", %w[NEWHOPE JEDI])) #=> ["NEWHOPE", "JEDI"]
"""
def enum_type(name, values, opts?)
  o = opts or {}
  {
    kind: "ENUM",
    name:,
    values: map(as_enum_value, values),
    description: o[:description]
  }
end

@doc """
input_type: an input object type of a schema, whose fields are built with arg.

    input_type("ReviewInput", [arg("stars", "Int!")]).kind #=> "INPUT_OBJECT"
"""
def input_type(name, fields, opts?)
  o = opts or {}
  {
    kind: "INPUT_OBJECT",
    name:,
    fields:,
    field_index: indexed(fields),
    description: o[:description]
  }
end

@doc """
scalar_type: a custom scalar type of a schema, with the functions that serialize its values out and parse them in.

    scalar_type("DateTime").kind #=> "SCALAR"
"""
def scalar_type(name, opts?)
  o = opts or {}
  {
    kind: "SCALAR",
    name:,
    serialize: o[:serialize],
    parse: o[:parse],
    specified_by: o[:specified_by],
    description: o[:description]
  }
end

@doc """
directive: a directive a schema declares, with the locations it may appear at and whether it may repeat there.

    directive("cached", ["FIELD"], []).repeatable #=> false
"""
def directive(name, locations, args, opts?)
  o = opts or {}
  {
    name:,
    locations:,
    args:,
    repeatable: o[:repeatable] == true,
    description: o[:description]
  }
end

@doc """
builtin_scalars: the five scalar types every schema holds, as the specification describes them.

    map((t) -> t.name, builtin_scalars) #=> ["Int", "Float", "String", "Boolean", "ID"]
"""
def builtin_scalars()
  [
    scalar_type("Int", {description: "A signed 32-bit integer."}),
    scalar_type(
      "Float",
      {description: "A signed double-precision floating-point value."}
    ),
    scalar_type("String", {description: "A UTF-8 character sequence."}),
    scalar_type("Boolean", {description: "true or false."}),
    scalar_type(
      "ID",
      {description: "A unique identifier, serialized as a String."}
    )
  ]
end

@doc """
builtin_directives: the four directives every schema declares, skip, include, deprecated and specifiedBy.

    map((d) -> d.name, builtin_directives) #=> ["skip", "include", "deprecated", "specifiedBy"]
"""
def builtin_directives()
  [
    directive(
      "skip",
      %w[FIELD FRAGMENT_SPREAD INLINE_FRAGMENT],
      [arg("if", "Boolean!", {description: "Skipped when true."})],
      {
        description: "Directs the executor to skip this field or fragment when the `if` argument is true."
      }
    ),
    directive(
      "include",
      %w[FIELD FRAGMENT_SPREAD INLINE_FRAGMENT],
      [arg("if", "Boolean!", {description: "Included when true."})],
      {
        description: "Directs the executor to include this field or fragment only when the `if` argument is true."
      }
    ),
    directive(
      "deprecated",
      %w[FIELD_DEFINITION ENUM_VALUE],
      [arg("reason", "String", {default: "No longer supported"})],
      {
        description: "Marks an element of a GraphQL schema as no longer supported."
      }
    ),
    directive(
      "specifiedBy",
      ["SCALAR"],
      [arg("url", "String!")],
      {
        description: "Exposes a URL that specifies the behaviour of this scalar."
      }
    )
  ]
end

@doc """
output_kind? tells whether a type of kind `k` may be a field's type.

    output_kind?("INPUT_OBJECT") #=> false
"""
def output_kind?(k)
  contains(%w[SCALAR OBJECT INTERFACE UNION ENUM], k)
end

@doc """
input_kind? tells whether a type of kind `k` may be an argument's or a variable's type.

    input_kind?("OBJECT") #=> false
"""
def input_kind?(k)
  contains(%w[SCALAR ENUM INPUT_OBJECT], k)
end

@doc """
leaf_kind? tells whether a value of a type of kind `k` is answered whole, with no selection set below it.

    leaf_kind?("ENUM") #=> true
"""
def leaf_kind?(k)
  contains(%w[SCALAR ENUM], k)
end

@doc """
composite_kind? tells whether a type of kind `k` is answered through a selection set.

    composite_kind?("UNION") #=> true
"""
def composite_kind?(k)
  contains(%w[OBJECT INTERFACE UNION], k)
end

@doc """
kind_named: the kind of the type called `name` in the type map `types`, or nil when no type has that name.

    kind_named(fixture.types, "Human") #=> "OBJECT"
"""
def kind_named(types, name)
  toriyose::danpen::kind_in(types, name)
end

@doc """
ref_whys: why the reference `ref` that `owner` holds is wrong, an unknown type or a kind `ok_kind` refuses; empty when it is sound.

    ref_whys(fixture.types, "Query.a", type_ref("Nope"), output_kind?) #=> ["Query.a refers to the unknown type Nope"]
"""
def ref_whys(types, owner, ref, ok_kind)
  k = kind_named(types, toriyose::danpen::base_name(ref))
  if k.nil?
    ["#{owner} refers to the unknown type #{toriyose::danpen::base_name(ref)}"]
  elsif not ok_kind(k)
    ["#{owner} cannot have the type #{toriyose::danpen::base_name(ref)}"]
  else
    []
  end
end

@doc """
type_whys: every reason the type `t` cannot stand in a schema of `types`: a field or argument of an unknown or wrong kind, an implemented name that is no interface, a union member that is no object.

    type_whys(fixture.types, union_type("U", ["Unit"])) #=> ["U has the member Unit, which is not an object type"]
"""
def type_whys(types, t)
  if t.kind == "OBJECT" or t.kind == "INTERFACE"
    append(
      flat_map(
        t.fields,
        fn(f)
          append(
            ref_whys(types, "#{t.name}.#{f.name}", f.type, output_kind?),
            flat_map(
              f.args,
              fn(a)
                ref_whys(
                  types,
                  "#{t.name}.#{f.name}(#{a.name})",
                  a.type,
                  input_kind?
                )
              end
            )
          )
        end
      ),
      flat_map(
        t.interfaces,
        fn(i)
          if kind_named(types, i) == "INTERFACE"
            []
          else
            ["#{t.name} implements #{i}, which is not an interface"]
          end
        end
      )
    )
  elsif t.kind == "INPUT_OBJECT"
    flat_map(
      t.fields,
      (f) -> ref_whys(types, "#{t.name}.#{f.name}", f.type, input_kind?)
    )
  elsif t.kind == "UNION"
    flat_map(
      t.members,
      fn(m)
        if kind_named(types, m) == "OBJECT"
          []
        else
          ["#{t.name} has the member #{m}, which is not an object type"]
        end
      end
    )
  else
    []
  end
end

@doc """
root_or: the root type of an operation: the name a spec gives, else `fallback` when `types` defines it, else nil.

    root_or(nil, {"Query" => 1}, "Query") #=> "Query"
    root_or(nil, {}, "Mutation") #=> nil
"""
def root_or(spec_name, types, fallback)
  if spec_name != nil
    spec_name
  elsif get(types, fallback) != nil
    fallback
  end
end

@doc """
schema: a schema from a spec of types and root names, joined with the built-in scalars, directives and introspection types; a broken reference raises :invalid_schema with every reason at once.

    schema({types: [object_type("Query", [field("a", "Int")])]}).query #=> "Query"
"""
def schema(spec)
  all = append(builtin_scalars, introspection_types, spec[:types] or [])
  names = map((t) -> t.name, all)
  dupes = filter((i) -> index_of(names, names[i]) < i, range(0, size(names)))
  types = zipmap(names, all)
  query = root_or(spec[:query], types, "Query")
  whys = append(
    map((i) -> "the type #{names[i]} is defined twice", dupes),
    flat_map(all, (t) -> type_whys(types, t)),
    if kind_named(types, query) == "OBJECT"
      []
    else
      ["the query root type #{query} is not an object type"]
    end
  )
  if not is_empty(whys)
    raise(:invalid_schema, join(whys, "; "), {data: whys})
  end
  {
    kind: :schema,
    types:,
    query:,
    mutation: root_or(spec[:mutation], types, "Mutation"),
    subscription: root_or(spec[:subscription], types, "Subscription"),
    directives: append(builtin_directives, spec[:directives] or []),
    description: spec[:description]
  }
end

@doc """
lookup: the type called `name` in the schema `sc`, or nil when the schema has none.

    lookup(fixture, "Droid").kind #=> "OBJECT"
"""
def lookup(sc, name)
  get(sc.types, name)
end

@doc """
root_name: the root type that answers an operation of the kind `operation`, or nil when the schema has none.

    root_name(fixture, :mutation) #=> "Mutation"
"""
def root_name(sc, operation)
  case operation
  when :query
    sc.query
  when :mutation
    sc.mutation
  else
    sc.subscription
  end
end

@doc """
possible_types: the object types a value of the type `name` may be at runtime: itself for an object, its members for a union, its implementers for an interface.

    possible_types(fixture, "Character") #=> ["Droid", "Human"]
"""
def possible_types(sc, name)
  t = lookup(sc, name)
  case t.kind
  when "OBJECT"
    [name]
  when "UNION"
    t.members
  when "INTERFACE"
    map(
      (e) -> first(e),
      filter(
        (e) -> e[1].kind == "OBJECT" and contains(e[1].interfaces, name),
        map_entries(sc.types)
      )
    )
  else
    []
  end
end

@doc """
applies? tells whether a fragment on the type `condition` applies to an object of the type `object_name`.

    applies?(fixture, "Human", "Character") #=> true
    applies?(fixture, "Human", "Droid") #=> false
"""
def applies?(sc, object_name, condition)
  t = lookup(sc, condition)
  t != nil and contains(possible_types(sc, condition), object_name)
end

@doc """
overlap? tells whether one runtime object type could be both of the types `a` and `b`.

    overlap?(fixture, "SearchResult", "Character") #=> true
"""
def overlap?(sc, a, b)
  pb = possible_types(sc, b)
  count_where((x) -> contains(pb, x), possible_types(sc, a)) > 0
end

@doc """
typename_field: the `__typename` meta-field every object answers with its own type name.

    typename_field.name #=> "__typename"
"""
def typename_field()
  field("__typename", "String!")
end

@doc """
field_def: the field `fname` of the type `tname`, the meta-fields `__typename`, and `__schema` and `__type` on the query root, included; nil when the type has no such field.

    field_def(fixture, "Droid", "legacyCode").deprecated #=> "Use primaryFunction."
    field_def(fixture, "Droid", "nope") #=> nil
"""
def field_def(sc, tname, fname)
  t = lookup(sc, tname)
  if fname == "__typename"
    typename_field
  elsif fname == "__schema" and tname == sc.query
    field("__schema", "__Schema!", {resolve: (_p, _a, _c) -> {sc:}})
  elsif fname == "__type" and tname == sc.query
    field(
      "__type",
      "__Type",
      {
        args: [arg("name", "String!")],
        resolve: (_p, a, _c) -> type_view_named(sc, a["name"])
      }
    )
  elsif t.nil? or t[:field_index].nil?
    nil
  else
    get(t[:field_index], fname)
  end
end

@doc """
type_view: the introspection parent of a `__Type`: the reference `ref` seen in the schema `sc`.

    type_view(fixture, named("Int")).ref #=> {kind: :named, name: "Int"}
"""
def type_view(sc, ref)
  {sc:, ref:}
end

@doc """
type_view_named: the introspection view of the type called `name`, or nil when the schema has none, as `__type(name:)` answers.

    type_view_named(fixture, "Nope") #=> nil
"""
def type_view_named(sc, name)
  if lookup(sc, name).nil?
    nil
  else
    type_view(sc, named(name))
  end
end

@doc """
def_of: the type definition a named type view stands for; nil for a list or non-null view.

    def_of(type_view(fixture, named("Human"))).kind #=> "OBJECT"
"""
def def_of(p)
  if p.ref.kind == :named
    lookup(p.sc, p.ref.name)
  end
end

@doc """
kind_of_view: the `__TypeKind` a type view answers: its definition's kind, or LIST or NON_NULL for a wrapper.

    kind_of_view(type_view(fixture, list_of("Int"))) #=> "LIST"
"""
def kind_of_view(p)
  case p.ref.kind
  when :named
    def_of(p).kind
  when :list_of
    "LIST"
  else
    "NON_NULL"
  end
end

@doc """
kind_in? tells whether a type view names a definition of one of `kinds`, which decides the introspection fields it answers.

    kind_in?(type_view(fixture, named("Unit")), ["ENUM"]) #=> true
"""
def kind_in?(p, kinds)
  def_of(p) != nil and contains(kinds, def_of(p).kind)
end

@doc """
shown_deprecated: the members of `xs` introspection shows: all of them when `include` is true, else only those not deprecated.

    size(shown_deprecated([enum_value("A"), enum_value("B", {deprecated: true})], false)) #=> 1
"""
def shown_deprecated(xs, include)
  if include == true
    xs
  else
    filter((x) -> x.deprecated.nil?, xs)
  end
end

@doc """
view_fields: the `__Field` parents of an object or interface view, deprecated ones only when `include` is true; nil for any other kind.

    map((x) -> x.f.name, view_fields(type_view(fixture, named("Review")), false)) #=> ["episode", "stars", "commentary"]
"""
def view_fields(p, include)
  if kind_in?(p, %w[OBJECT INTERFACE])
    map((f) -> {sc: p.sc, f:}, shown_deprecated(def_of(p).fields, include))
  end
end

@doc """
view_interfaces: the views of the interfaces an object or interface view implements; nil for any other kind.

    map((v) -> v.ref.name, view_interfaces(type_view(fixture, named("Droid")))) #=> ["Character"]
"""
def view_interfaces(p)
  if kind_in?(p, %w[OBJECT INTERFACE])
    map((i) -> type_view(p.sc, named(i)), def_of(p).interfaces)
  end
end

@doc """
view_possible: the views of the object types an interface or union view may be at runtime; nil for any other kind.

    map((v) -> v.ref.name, view_possible(type_view(fixture, named("SearchResult")))) #=> ["Human", "Droid"]
"""
def view_possible(p)
  if kind_in?(p, %w[INTERFACE UNION])
    map((n) -> type_view(p.sc, named(n)), possible_types(p.sc, p.ref.name))
  end
end

@doc """
view_enum_values: the `__EnumValue` parents of an enum view, deprecated ones only when `include` is true; nil for any other kind.

    map((v) -> v.ev.name, view_enum_values(type_view(fixture, named("Unit")), true)) #=> ["METER", "FOOT"]
"""
def view_enum_values(p, include)
  if kind_in?(p, ["ENUM"])
    map((v) -> {ev: v}, shown_deprecated(def_of(p).values, include))
  end
end

@doc """
view_input_fields: the `__InputValue` parents of an input object view; nil for any other kind.

    map((x) -> x.a.name, view_input_fields(type_view(fixture, named("ReviewInput")))) #=> ["stars", "commentary"]
"""
def view_input_fields(p)
  if kind_in?(p, ["INPUT_OBJECT"])
    map((a) -> {sc: p.sc, a:}, def_of(p).fields)
  end
end

@doc """
view_of_type: the view of the type a list or non-null view wraps, as `ofType` answers; nil for a named view.

    view_of_type(type_view(fixture, list_of("Int"))).ref.name #=> "Int"
"""
def view_of_type(p)
  if p.ref.kind == :named
    nil
  else
    type_view(p.sc, p.ref.of)
  end
end

@doc """
view_description: the description of the type a view names; nil for a wrapper view.

    view_description(type_view(fixture, named("Int"))) #=> "A signed 32-bit integer."
"""
def view_description(p)
  if def_of(p).nil?
    nil
  else
    def_of(p).description
  end
end

@doc """
view_specified_by: the URL that specifies a scalar view's behaviour, as `specifiedByURL` answers; nil for any other kind.

    sc = schema({types: [scalar_type("URL", {specified_by: "https://url.spec.whatwg.org"}), object_type("Query", [field("u", "URL")])]})
    view_specified_by(type_view(sc, named("URL"))) #=> "https://url.spec.whatwg.org"
"""
def view_specified_by(p)
  if kind_in?(p, ["SCALAR"])
    def_of(p).specified_by
  end
end

@doc """
view_name: the name a type view answers; nil for a list or non-null view, which has none.

    view_name(type_view(fixture, named("Human"))) #=> "Human"
"""
def view_name(p)
  if p.ref.kind == :named
    p.ref.name
  end
end

@doc """
default_value_text: an argument's default written as GraphQL text, as `defaultValue` answers; nil when it has none.

    default_value_text({sc: fixture, a: arg("unit", "Unit", {default: "METER"})}) #=> "METER"
"""
def default_value_text(p)
  if p.a.has_default
    render_value(p.sc, p.a.type, p.a.default)
  end
end

@doc """
include_arg: the `includeDeprecated` argument the introspection fields and enumValues take, false unless given.

    first(include_arg).name #=> "includeDeprecated"
"""
def include_arg()
  [arg("includeDeprecated", "Boolean", {default: false})]
end

@doc """
introspection_types: the types of the introspection system every schema holds, each resolved over the schema itself.

    map((t) -> t.name, introspection_types) #=> ["__Schema", "__Type", "__Field", "__InputValue", "__EnumValue", "__Directive", "__TypeKind", "__DirectiveLocation"]
"""
def introspection_types()
  [
    object_type(
      "__Schema",
      [
        field(
          "description",
          "String",
          {resolve: (p, _a, _c) -> p.sc.description}
        ),
        field(
          "types",
          "[__Type!]!",
          {
            resolve: fn(p, _a, _c)
              map(
                (e) -> type_view(p.sc, named(first(e))),
                map_entries(p.sc.types)
              )
            end
          }
        ),
        field(
          "queryType",
          "__Type!",
          {resolve: (p, _a, _c) -> type_view(p.sc, named(p.sc.query))}
        ),
        field(
          "mutationType",
          "__Type",
          {resolve: (p, _a, _c) -> type_view_named(p.sc, p.sc.mutation)}
        ),
        field(
          "subscriptionType",
          "__Type",
          {resolve: (p, _a, _c) -> type_view_named(p.sc, p.sc.subscription)}
        ),
        field(
          "directives",
          "[__Directive!]!",
          {resolve: (p, _a, _c) -> map((d) -> {sc: p.sc, d:}, p.sc.directives)}
        )
      ]
    ),
    object_type(
      "__Type",
      [
        field("kind", "__TypeKind!", {resolve: (p, _a, _c) -> kind_of_view(p)}),
        field("name", "String", {resolve: (p, _a, _c) -> view_name(p)}),
        field(
          "description",
          "String",
          {resolve: (p, _a, _c) -> view_description(p)}
        ),
        field(
          "specifiedByURL",
          "String",
          {resolve: (p, _a, _c) -> view_specified_by(p)}
        ),
        field(
          "fields",
          "[__Field!]",
          {
            args: include_arg,
            resolve: (p, a, _c) -> view_fields(p, a["includeDeprecated"])
          }
        ),
        field(
          "interfaces",
          "[__Type!]",
          {resolve: (p, _a, _c) -> view_interfaces(p)}
        ),
        field(
          "possibleTypes",
          "[__Type!]",
          {resolve: (p, _a, _c) -> view_possible(p)}
        ),
        field(
          "enumValues",
          "[__EnumValue!]",
          {
            args: include_arg,
            resolve: (p, a, _c) -> view_enum_values(p, a["includeDeprecated"])
          }
        ),
        field(
          "inputFields",
          "[__InputValue!]",
          {resolve: (p, _a, _c) -> view_input_fields(p)}
        ),
        field("ofType", "__Type", {resolve: (p, _a, _c) -> view_of_type(p)})
      ]
    ),
    object_type(
      "__Field",
      [
        field("name", "String!", {resolve: (p, _a, _c) -> p.f.name}),
        field(
          "description",
          "String",
          {resolve: (p, _a, _c) -> p.f.description}
        ),
        field(
          "args",
          "[__InputValue!]!",
          {resolve: (p, _a, _c) -> map((a) -> {sc: p.sc, a:}, p.f.args)}
        ),
        field(
          "type",
          "__Type!",
          {resolve: (p, _a, _c) -> type_view(p.sc, p.f.type)}
        ),
        field(
          "isDeprecated",
          "Boolean!",
          {resolve: (p, _a, _c) -> p.f.deprecated != nil}
        ),
        field(
          "deprecationReason",
          "String",
          {resolve: (p, _a, _c) -> p.f.deprecated}
        )
      ]
    ),
    object_type(
      "__InputValue",
      [
        field("name", "String!", {resolve: (p, _a, _c) -> p.a.name}),
        field(
          "description",
          "String",
          {resolve: (p, _a, _c) -> p.a.description}
        ),
        field(
          "type",
          "__Type!",
          {resolve: (p, _a, _c) -> type_view(p.sc, p.a.type)}
        ),
        field(
          "defaultValue",
          "String",
          {resolve: (p, _a, _c) -> default_value_text(p)}
        )
      ]
    ),
    object_type(
      "__EnumValue",
      [
        field("name", "String!", {resolve: (p, _a, _c) -> p.ev.name}),
        field(
          "description",
          "String",
          {resolve: (p, _a, _c) -> p.ev.description}
        ),
        field(
          "isDeprecated",
          "Boolean!",
          {resolve: (p, _a, _c) -> p.ev.deprecated != nil}
        ),
        field(
          "deprecationReason",
          "String",
          {resolve: (p, _a, _c) -> p.ev.deprecated}
        )
      ]
    ),
    object_type(
      "__Directive",
      [
        field("name", "String!", {resolve: (p, _a, _c) -> p.d.name}),
        field(
          "description",
          "String",
          {resolve: (p, _a, _c) -> p.d.description}
        ),
        field(
          "locations",
          "[__DirectiveLocation!]!",
          {resolve: (p, _a, _c) -> p.d.locations}
        ),
        field(
          "args",
          "[__InputValue!]!",
          {resolve: (p, _a, _c) -> map((a) -> {sc: p.sc, a:}, p.d.args)}
        ),
        field(
          "isRepeatable",
          "Boolean!",
          {resolve: (p, _a, _c) -> p.d.repeatable}
        )
      ]
    ),
    enum_type(
      "__TypeKind",
      %w[SCALAR OBJECT INTERFACE UNION ENUM INPUT_OBJECT LIST NON_NULL]
    ),
    enum_type(
      "__DirectiveLocation",
      %w[
        QUERY
        MUTATION
        SUBSCRIPTION
        FIELD
        FRAGMENT_DEFINITION
        FRAGMENT_SPREAD
        INLINE_FRAGMENT
        VARIABLE_DEFINITION
        SCHEMA
        SCALAR
        OBJECT
        FIELD_DEFINITION
        ARGUMENT_DEFINITION
        INTERFACE
        UNION
        ENUM
        ENUM_VALUE
        INPUT_OBJECT
        INPUT_FIELD_DEFINITION
      ]
    )
  ]
end

@doc """
entry_of: whether the map `m` holds the key `name`, and its value, as a pair, so a present null is told apart from an absent key; a keyword key answers to its text.

    entry_of({id: 7}, "id") #=> [true, 7]
    entry_of({}, "id") #=> [false, nil]
"""
def entry_of(m, name)
  if not map?(m)
    [false, nil]
  elsif get(m, name) != nil
    [true, get(m, name)]
  else
    e = find_first((p) -> to_s(first(p)) == name, map_entries(m)) rescue nil
    if e.nil?
      [false, nil]
    else
      [true, e[1]]
    end
  end
end

@doc """
shown_value: a value as an error message quotes it, as JSON when it has a JSON form.

    shown_value([1, 2]) #=> "[1,2]"
"""
def shown_value(v)
  json_stringify(v) rescue to_s(v)
end

@doc """
int_range? tells whether a number fits GraphQL's Int, a signed 32-bit integer.

    int_range?(2_147_483_647) #=> true
    int_range?(2_147_483_648) #=> false
"""
def int_range?(v)
  v >= -2_147_483_648 and v <= 2_147_483_647
end

@doc """
enum_names: the names of the values of the enum type `t`, which bound what it accepts and answers.

    enum_names(lookup(fixture, "Episode")) #=> ["NEWHOPE", "EMPIRE", "JEDI"]
"""
def enum_names(t)
  map((v) -> v.name, t.values)
end

@doc """
coerce_scalar_input: a variable's value read as the scalar type `t`, by the specification's input coercion; a value it cannot represent raises :coerce.

    coerce_scalar_input(lookup(fixture, "ID"), 1000) #=> "1000"
"""
def coerce_scalar_input(t, v)
  case t.name
  when "Int"
    if integer?(v) and int_range?(v)
      v
    elsif float?(v) and floor(v) == v and int_range?(v)
      to_int(v)
    else
      raise(
        :coerce,
        "Int cannot represent non-integer value: #{shown_value(v)}"
      )
    end
  when "Float"
    if number?(v)
      to_float(v)
    else
      raise(
        :coerce,
        "Float cannot represent non numeric value: #{shown_value(v)}"
      )
    end
  when "String"
    if string?(v)
      v
    else
      raise(
        :coerce,
        "String cannot represent a non string value: #{shown_value(v)}"
      )
    end
  when "Boolean"
    if v == true or v == false
      v
    else
      raise(
        :coerce,
        "Boolean cannot represent a non boolean value: #{shown_value(v)}"
      )
    end
  when "ID"
    if string?(v)
      v
    elsif integer?(v)
      to_s(v)
    else
      raise(:coerce, "ID cannot represent value: #{shown_value(v)}")
    end
  else
    if t.parse.nil?
      v
    else
      parse_with = t.parse
      parse_with(v)
    end
  end
end

@doc """
coerce_input: a variable's value read as the type `ref`: null refused where non-null, a single value lifted into a list, and each named type coerced by its kind.

    coerce_input(fixture, type_ref("[Int]"), 5) #=> [5]
"""
def coerce_input(sc, ref, v)
  if non_null?(ref)
    if v.nil?
      raise(
        :coerce,
        "Expected non-nullable type \"#{toriyose::danpen::type_text(ref)}\" not to be null."
      )
    end
    coerce_input(sc, ref.of, v)
  elsif v.nil?
    nil
  elsif ref.kind == :list_of
    if list?(v)
      map((x) -> coerce_input(sc, ref.of, x), v)
    else
      [coerce_input(sc, ref.of, v)]
    end
  else
    coerce_named_input(sc, lookup(sc, ref.name), v)
  end
end

@doc """
coerce_named_input: a variable's value read as the named type `t`, a scalar, an enum or an input object.

    coerce_named_input(fixture, lookup(fixture, "Episode"), "JEDI") #=> "JEDI"
"""
def coerce_named_input(sc, t, v)
  case t.kind
  when "SCALAR"
    coerce_scalar_input(t, v)
  when "ENUM"
    if string?(v) and contains(enum_names(t), v)
      v
    else
      raise(
        :coerce,
        "Value #{shown_value(v)} does not exist in \"#{t.name}\" enum."
      )
    end
  else
    coerce_input_object(sc, t, v)
  end
end

@doc """
coerce_input_object: a variable's map read as the input object type `t`: an unknown field refused, a missing one given its default, a missing required one refused.

    coerce_input_object(fixture, lookup(fixture, "ReviewInput"), {"stars" => 5}) #=> {"stars" => 5}
"""
def coerce_input_object(sc, t, v)
  if not map?(v)
    raise(:coerce, "Expected type \"#{t.name}\" to be an object.")
  end
  map(
    fn(e)
      if get(t[:field_index], to_s(first(e))).nil?
        raise(
          :coerce,
          "Field \"#{to_s(first(e))}\" is not defined by type \"#{t.name}\"."
        )
      end
    end,
    map_entries(v)
  )
  reduce(
    fn(acc, f)
      e = entry_of(v, f.name)
      if first(e)
        assoc(acc, f.name, coerce_input(sc, f.type, e[1]))
      elsif f.has_default
        assoc(acc, f.name, f.default)
      elsif non_null?(f.type)
        raise(
          :coerce,
          "Field \"#{t.name}.#{f.name}\" of required type \"#{toriyose::danpen::type_text(f.type)}\" was not provided."
        )
      else
        acc
      end
    end,
    {},
    t.fields
  )
end

@doc """
ast_value: the plain value a literal node of a document holds, a number read from its text.

    ast_value({kind: :int, text: "42"}) #=> 42
"""
def ast_value(ast)
  case ast.kind
  when :int
    to_int(ast.text)
  when :float
    to_float(ast.text)
  when :enum
    ast.name
  else
    ast[:value]
  end
end

@doc """
loc_of: the `locations` of an error about a document node: its line and column, or none when the node has no span.

    loc_of({at: [2, 10]}) #=> [{line: 2, column: 10}]
"""
def loc_of(node)
  at = node[:at]
  if at.nil?
    []
  else
    [{line: first(at), column: at[1]}]
  end
end

@doc """
literal_scalar: a literal written in a document read as the scalar type `t`, by the specification's literal coercion; a literal it cannot represent raises :coerce.

    literal_scalar(lookup(fixture, "ID"), {kind: :int, text: "1000"}, {}) #=> "1000"
"""
def literal_scalar(t, ast, vars)
  k = ast.kind
  case t.name
  when "Int"
    if k == :int and int_range?(ast_value(ast))
      ast_value(ast)
    else
      raise(
        :coerce,
        "Int cannot represent non-integer value: #{toriyose::danpen::render_value(ast)}"
      )
    end
  when "Float"
    if k == :int or k == :float
      to_float(ast_value(ast))
    else
      raise(
        :coerce,
        "Float cannot represent non numeric value: #{toriyose::danpen::render_value(ast)}"
      )
    end
  when "String"
    if k == :string
      ast_value(ast)
    else
      raise(
        :coerce,
        "String cannot represent a non string value: #{toriyose::danpen::render_value(ast)}"
      )
    end
  when "Boolean"
    if k == :boolean
      ast_value(ast)
    else
      raise(
        :coerce,
        "Boolean cannot represent a non boolean value: #{toriyose::danpen::render_value(ast)}"
      )
    end
  when "ID"
    if k == :string
      ast_value(ast)
    elsif k == :int
      ast.text
    else
      raise(
        :coerce,
        "ID cannot represent value: #{toriyose::danpen::render_value(ast)}"
      )
    end
  else
    coerce_scalar_input(t, plain_value(ast, vars))
  end
end

@doc """
plain_value: a value node of a document as a plain value, its variables read from `vars`, for a custom scalar to parse.

    plain_value({kind: :var, name: "n"}, {"n" => 3}) #=> 3
"""
def plain_value(ast, vars)
  case ast.kind
  when :var
    entry_of(vars, ast.name)[1]
  when :list
    map((x) -> plain_value(x, vars), ast.items)
  when :object
    zipmap(
      map((f) -> f.name, ast.fields),
      map((f) -> plain_value(f.value, vars), ast.fields)
    )
  when :null
    nil
  else
    ast_value(ast)
  end
end

@doc """
value_from_ast: a value node of a document read as the type `ref`, variables taken from the coerced `vars`; a value the type refuses raises :coerce.

    value_from_ast(fixture, type_ref("[Int]"), {kind: :int, text: "4"}, {}) #=> [4]
"""
def value_from_ast(sc, ref, ast, vars)
  if ast.kind == :var
    v = entry_of(vars, ast.name)[1]
    if v.nil? and non_null?(ref)
      raise(
        :coerce,
        "Expected non-nullable type \"#{toriyose::danpen::type_text(ref)}\" not to be null."
      )
    end
    v
  elsif non_null?(ref)
    if ast.kind == :null
      raise(
        :coerce,
        "Expected value of type \"#{toriyose::danpen::type_text(ref)}\", found null."
      )
    end
    value_from_ast(sc, ref.of, ast, vars)
  elsif ast.kind == :null
    nil
  elsif ref.kind == :list_of
    if ast.kind == :list
      map((x) -> value_from_ast(sc, ref.of, x, vars), ast.items)
    else
      [value_from_ast(sc, ref.of, ast, vars)]
    end
  else
    named_from_ast(sc, lookup(sc, ref.name), ast, vars)
  end
end

@doc """
named_from_ast: a value node of a document read as the named type `t`, a scalar, an enum or an input object.

    named_from_ast(fixture, lookup(fixture, "Episode"), {kind: :enum, name: "JEDI"}, {}) #=> "JEDI"
"""
def named_from_ast(sc, t, ast, vars)
  case t.kind
  when "SCALAR"
    literal_scalar(t, ast, vars)
  when "ENUM"
    if ast.kind == :enum and contains(enum_names(t), ast_value(ast))
      ast_value(ast)
    else
      raise(
        :coerce,
        "Enum \"#{t.name}\" cannot represent value: #{toriyose::danpen::render_value(ast)}"
      )
    end
  else
    object_from_ast(sc, t, ast, vars)
  end
end

@doc """
object_from_ast: an object literal of a document read as the input object type `t`: an unknown field refused, a missing one given its default, a missing required one refused.

    object_from_ast(fixture, lookup(fixture, "ReviewInput"), {kind: :object, fields: [{name: "stars", value: {kind: :int, text: "5"}}]}, {}) #=> {"stars" => 5}
"""
def object_from_ast(sc, t, ast, vars)
  if ast.kind != :object
    raise(
      :coerce,
      "Expected value of type \"#{t.name}\", found #{toriyose::danpen::render_value(ast)}."
    )
  end
  map(
    fn(f)
      if get(t[:field_index], f.name).nil?
        raise(
          :coerce,
          "Field \"#{f.name}\" is not defined by type \"#{t.name}\"."
        )
      end
    end,
    ast.fields
  )
  reduce(
    fn(acc, f)
      node = find_first((n) -> n.name == f.name, ast.fields)
      if node != nil and
          not (
            node.value.kind == :var and
            not first(entry_of(vars, node.value.name))
          )
        assoc(acc, f.name, value_from_ast(sc, f.type, node.value, vars))
      elsif f.has_default
        assoc(acc, f.name, f.default)
      elsif non_null?(f.type)
        raise(
          :coerce,
          "Field \"#{t.name}.#{f.name}\" of required type \"#{toriyose::danpen::type_text(f.type)}\" was not provided."
        )
      else
        acc
      end
    end,
    {},
    t.fields
  )
end

@doc """
render_value: a value of the type `ref` written as a GraphQL literal, as a default value is shown in introspection and SDL.

    render_value(fixture, type_ref("[Episode]"), ["JEDI", "EMPIRE"]) #=> "[JEDI, EMPIRE]"
"""
def render_value(sc, ref, v)
  if v.nil?
    "null"
  elsif non_null?(ref)
    render_value(sc, ref.of, v)
  elsif ref.kind == :list_of
    if list?(v)
      "[#{join(map((x) -> render_value(sc, ref.of, x), v), ", ")}]"
    else
      render_value(sc, ref.of, v)
    end
  else
    t = lookup(sc, ref.name)
    if t.kind == "ENUM"
      to_s(v)
    elsif t.kind == "INPUT_OBJECT"
      shown = filter((f) -> first(entry_of(v, f.name)), t.fields)
      "{#{join(map((f) -> "#{f.name}: #{render_value(sc, f.type, entry_of(v, f.name)[1])}", shown), ", ")}}"
    elsif string?(v)
      json_stringify(v)
    else
      to_s(v)
    end
  end
end

@doc """
coerce_arguments: the argument values a field is resolved with, from the argument nodes written and the definitions `defs`: defaults filled, a missing required argument or an invalid value raised as :coerce.

    coerce_arguments(fixture, [arg("unit", "Unit", {default: "METER"})], [], {}) #=> {"unit" => "METER"}
"""
def coerce_arguments(sc, defs, nodes, vars)
  reduce(
    fn(acc, d)
      node = find_first((n) -> n.name == d.name, nodes)
      missing_var = node != nil and
        node.value.kind == :var and
        not first(entry_of(vars, node.value.name))
      if node.nil? or missing_var
        if d.has_default
          assoc(acc, d.name, d.default)
        elsif non_null?(d.type)
          raise(
            :coerce,
            if missing_var
              "Argument \"#{d.name}\" of required type \"#{toriyose::danpen::type_text(d.type)}\" was provided the variable \"$#{node.value.name}\" which was not provided a runtime value."
            else
              "Argument \"#{d.name}\" of required type \"#{toriyose::danpen::type_text(d.type)}\" was not provided."
            end
          )
        else
          acc
        end
      else
        begin
          assoc(acc, d.name, value_from_ast(sc, d.type, node.value, vars))
        rescue :coerce as e
          raise(
            :coerce,
            "Argument \"#{d.name}\" has invalid value #{toriyose::danpen::render_value(node.value)}: #{e.message}"
          )
        end
      end
    end,
    {},
    defs
  )
end

@doc """
coerce_variables: the variables of the operation `op` coerced from the values `given`, with an error for each variable that cannot be, so a request with a bad variable answers every fault and no data.

    op = first(operations(value(parse("query ($id: ID!) { human(id: $id) { name } }"))))
    coerce_variables(fixture, op, {"id" => 1000}).values #=> {"id" => "1000"}
"""
def coerce_variables(sc, op, given)
  reduce(
    fn(acc, vd)
      name = vd.name
      e = entry_of(given or {}, name)
      ref = vd.type
      fault = fn(message)
        {**acc, errors: append(acc.errors, [gql_error(message, loc_of(vd))])}
      end
      if lookup(sc, toriyose::danpen::base_name(ref)).nil? or
          not input_kind?(lookup(sc, toriyose::danpen::base_name(ref)).kind)
        fault(
          "Variable \"$#{name}\" expected value of type \"#{toriyose::danpen::type_text(ref)}\" which cannot be used as an input type."
        )
      elsif not first(e) and vd.default != nil
        {
          **acc,
          values: assoc(
            acc.values,
            name,
            value_from_ast(sc, ref, vd.default, {})
          )
        }
      elsif non_null?(ref) and not first(e)
        fault(
          "Variable \"$#{name}\" of required type \"#{toriyose::danpen::type_text(ref)}\" was not provided."
        )
      elsif non_null?(ref) and e[1].nil?
        fault(
          "Variable \"$#{name}\" of non-null type \"#{toriyose::danpen::type_text(ref)}\" must not be null."
        )
      elsif not first(e)
        acc
      else
        begin
          {**acc, values: assoc(acc.values, name, coerce_input(sc, ref, e[1]))}
        rescue :coerce as err
          fault(
            "Variable \"$#{name}\" got invalid value #{shown_value(e[1])}; #{err.message}"
          )
        end
      end
    end,
    {values: {}, errors: []},
    op.variables
  )
end

@doc """
operations: the operations a document defines, in order.

    size(operations(value(parse("query A { a } query B { b }")))) #=> 2
"""
def operations(doc)
  toriyose::danpen::definitions_of_kind(doc, :operation)
end

@doc """
fragment_defs: the fragments a document defines, in order.

    map((f) -> f.name, fragment_defs(value(parse("{ ...F } fragment F on Query { a }")))) #=> ["F"]
"""
def fragment_defs(doc)
  toriyose::danpen::definitions_of_kind(doc, :fragment)
end

@doc """
fragments_of: a document's fragments keyed by name, so a spread finds the fragment it names.

    fragments_of(value(parse("{ ...F } fragment F on Query { a }")))["F"].on #=> "Query"
"""
def fragments_of(doc)
  defs = fragment_defs(doc)
  zipmap(map((f) -> f.name, defs), defs)
end

@doc """
request_error: a request refused with one GraphQL error, before any field runs.

    errors_of(request_error("Must provide an operation.", [])) #=> [{message: "Must provide an operation.", locations: []}]
"""
def request_error(message, locations)
  refused(refusal(:request, [gql_error(message, locations)]))
end

@doc """
operation_of: the operation of a document a request runs: the one called `name`, or the only one when no name is given; any other case is refused with the specification's error.

    value(operation_of(value(parse("query A { a } query B { b }")), "B")).name #=> "B"
    ok?(operation_of(value(parse("query A { a } query B { b }")), nil)) #=> false
"""
def operation_of(doc, name)
  ops = operations(doc)
  if name.nil?
    if size(ops) == 1
      ok(first(ops))
    elsif is_empty(ops)
      request_error("Must provide an operation.", [])
    else
      request_error(
        "Must provide operation name if query contains multiple operations.",
        []
      )
    end
  else
    op = find_first((o) -> o[:name] == name, ops)
    if op.nil?
      request_error("Unknown operation named \"#{name}\".", [])
    else
      ok(op)
    end
  end
end

@doc """
response_key: the key a field node answers under in the response, its alias when it has one, else its name.

    response_key(first(first(operations(value(parse("{ luke: hero { id } }")))).selections)) #=> "luke"
"""
def response_key(node)
  toriyose::danpen::response_key(node)
end

@doc """
directive_value: the `if` argument of the directive `name` among `dirs`, read with the request's variables; nil when the directive is absent.

    dirs = first(first(operations(value(parse("{ a @skip(if: true) }")))).selections).directives
    directive_value({sc: fixture, vars: {}}, dirs, "skip") #=> true
"""
def directive_value(env, dirs, name)
  d = find_first((x) -> x.name == name, dirs)
  if d.nil?
    nil
  else
    a = find_first((x) -> x.name == "if", d.arguments)
    value_from_ast(env.sc, non_null("Boolean"), a.value, env.vars) rescue nil
  end
end

@doc """
included? tells whether a selection carrying the directives `dirs` runs: not skipped, and not left out by include.

    dirs = first(first(operations(value(parse("{ a @skip(if: true) }")))).selections).directives
    included?({sc: fixture, vars: {}}, dirs) #=> false
"""
def included?(env, dirs)
  directive_value(env, dirs, "skip") != true and
    directive_value(env, dirs, "include") != false
end

@doc """
add_to_group: the ordered field groups with `node` added under the response key `key`, so fields of one key merge and keep their first position.

    add_to_group([["a", [1]]], "a", 2) #=> [["a", [1, 2]]]
"""
def add_to_group(groups, key, node)
  i = index_of(map(first, groups), key)
  if i < 0
    append(groups, [[key, [node]]])
  else
    update_at(groups, i, [key, append(groups[i][1], [node])])
  end
end

@doc """
collect_fields: the fields a selection set asks of an object of the type `tname`, grouped by response key in order, with fragments that apply expanded and skipped selections left out.

    doc = value(parse("{ hero { id } h: hero { name } }"))
    map(first, collect_fields(env_for(fixture, doc, {}, {}), "Query", first(operations(doc)).selections)) #=> ["hero", "h"]
"""
def collect_fields(env, tname, sels)
  first(collect_into(env, tname, sels, [[], []]))
end

@doc """
collect_into: the collection state `st`, field groups and fragments already visited, carried through every selection of `sels`.

    doc = value(parse("{ hero { id } }"))
    map(first, first(collect_into(env_for(fixture, doc, {}, {}), "Query", first(operations(doc)).selections, [[], []]))) #=> ["hero"]
"""
def collect_into(env, tname, sels, st)
  reduce((acc, s) -> collect_one(env, tname, s, acc), st, sels)
end

@doc """
collect_one: the collection state `st` after the one selection `s`, a field, a fragment spread visited once, or an inline fragment that applies.

    doc = value(parse("{ hero { id } }"))
    map(first, first(collect_one(env_for(fixture, doc, {}, {}), "Query", first(first(operations(doc)).selections), [[], []]))) #=> ["hero"]
"""
def collect_one(env, tname, s, st)
  if not included?(env, s.directives)
    st
  elsif s.kind == :field
    [add_to_group(first(st), response_key(s), s), st[1]]
  elsif s.kind == :spread
    if contains(st[1], s.name)
      st
    else
      frag = get(env.frags, s.name)
      seen = [first(st), append(st[1], [s.name])]
      if frag.nil? or not applies?(env.sc, tname, frag.on)
        seen
      else
        collect_into(env, tname, frag.selections, seen)
      end
    end
  elsif s[:on] != nil and not applies?(env.sc, tname, s[:on])
    st
  else
    collect_into(env, tname, s.selections, st)
  end
end

@doc """
done: the outcome of a field that completed with the value `v` and no error.

    done(1) #=> {value: 1, errs: [], bad: false}
"""
def done(v)
  {value: v, errs: [], bad: false}
end

@doc """
failed: the outcome of a field that raised a field error at `path`, located at its node, so null propagates from it.

    failed("no", {at: [1, 3]}, ["a"]).errs #=> [{message: "no", locations: [{line: 1, column: 3}], path: ["a"]}]
"""
def failed(message, node, path)
  {value: nil, errs: [{message:, locations: loc_of(node), path:}], bad: true}
end

@doc """
response: an executed operation as the response shape of the specification: data, with errors only when there are some.

    response({"a" => 1}, []) #=> {data: {"a" => 1}}
"""
def response(data, errs)
  if is_empty(errs)
    {data:}
  else
    {data:, errors: errs}
  end
end

@doc """
exec_selection_set: a selection set run against the value `parent` of the type `tname`: each field group resolved and completed into one map, its errors gathered.

    doc = value(parse("{ hero { id } }"))
    exec_selection_set(env_for(fixture, doc, {}, {}), "Query", first(operations(doc)).selections, nil, []).value #=> {"hero" => {"id" => "2001"}}
"""
def exec_selection_set(env, tname, sels, parent, path)
  reduce(
    fn(acc, g)
      r = exec_field(env, tname, parent, g[1], append(path, [first(g)]))
      if r.nil?
        acc
      else
        {
          value: assoc(acc.value, first(g), r.value),
          errs: append(acc.errs, r.errs),
          bad: acc.bad or r.bad
        }
      end
    end,
    done({}),
    collect_fields(env, tname, sels)
  )
end

@doc """
default_resolve: the value of a field that has no resolver, read from its parent under the field's name.

    default_resolve({name: "R2-D2"}, "name") #=> "R2-D2"
"""
def default_resolve(parent, name)
  entry_of(parent, name)[1]
end

@doc """
exec_field: one field group of the type `tname` run: arguments coerced, the resolver called, the value completed; a raised error becomes a field error at `path`, and an unknown field answers nil.

    doc = value(parse("{ hero { id } }"))
    exec_field(env_for(fixture, doc, {}, {}), "Query", nil, first(operations(doc)).selections, ["hero"]).value #=> {"id" => "2001"}
"""
def exec_field(env, tname, parent, nodes, path)
  node = first(nodes)
  if node.name == "__typename"
    done(tname)
  else
    fdef = field_def(env.sc, tname, node.name)
    if fdef.nil?
      nil
    else
      resolved = begin
        args = coerce_arguments(env.sc, fdef.args, node.arguments, env.vars)
        if fdef.resolve.nil?
          ok(default_resolve(parent, fdef.name))
        else
          resolver = fdef.resolve
          ok(resolver(parent, args, env.ctx))
        end
      rescue e
        failed(e.message, node, path)
      end
      if ok?(resolved)
        complete(
          env,
          fdef.type,
          nodes,
          value(resolved),
          path,
          "#{tname}.#{fdef.name}"
        )
      else
        {**resolved, bad: non_null?(fdef.type)}
      end
    end
  end
end

@doc """
complete: a resolved value completed as the type `ref`: a null in a non-null place is a field error that propagates, and a nullable place absorbs an error below it as null.

    complete({sc: fixture}, type_ref("Int!"), [{at: [1, 3]}], nil, ["n"], "Query.n").bad #=> true
    complete({sc: fixture}, type_ref("Int"), [{at: [1, 3]}], nil, ["n"], "Query.n").bad #=> false
"""
def complete(env, ref, nodes, v, path, owner)
  if non_null?(ref)
    r = complete_raw(env, ref.of, nodes, v, path, owner)
    if r.bad
      r
    elsif r.value.nil?
      f = failed(
        "Cannot return null for non-nullable field #{owner}.",
        first(nodes),
        path
      )
      {**f, errs: append(r.errs, f.errs)}
    else
      r
    end
  else
    r = complete_raw(env, ref, nodes, v, path, owner)
    if r.bad
      {value: nil, errs: r.errs, bad: false}
    else
      r
    end
  end
end

@doc """
complete_raw: a resolved value completed as the nullable type `ref`: a list item by item, a leaf serialized, an object or abstract type run through its selection set.

    complete_raw({sc: fixture}, type_ref("[Int]"), [{at: [1, 3]}], [1, 2], ["n"], "Query.n").value #=> [1, 2]
"""
def complete_raw(env, ref, nodes, v, path, owner)
  if v.nil?
    done(nil)
  elsif ref.kind == :list_of
    if not list?(v)
      failed(
        "Expected Iterable, but did not find one for field \"#{owner}\".",
        first(nodes),
        path
      )
    else
      items = map(
        fn(e)
          complete(env, ref.of, nodes, e[1], append(path, [first(e)]), owner)
        end,
        enumerate(v)
      )
      bad = count_where((r) -> r.bad, items) > 0
      {
        value: if bad
          nil
        else
          map((r) -> r.value, items)
        end,
        errs: flat_map(items, (r) -> r.errs),
        bad:
      }
    end
  else
    t = lookup(env.sc, ref.name)
    if leaf_kind?(t.kind)
      begin
        done(serialize(t, v))
      rescue e
        failed(e.message, first(nodes), path)
      end
    elsif t.kind == "OBJECT"
      complete_object(env, t.name, nodes, v, path)
    else
      runtime = resolve_type(env, t, v)
      if runtime.nil? or not contains(possible_types(env.sc, t.name), runtime)
        failed(
          "Abstract type \"#{t.name}\" must resolve to an Object type at runtime for field \"#{owner}\". Either the \"#{t.name}\" type should provide a resolve_type function or each value should carry its __typename.",
          first(nodes),
          path
        )
      else
        complete_object(env, runtime, nodes, v, path)
      end
    end
  end
end

@doc """
complete_object: the value `v` completed as the object type `tname`, through the merged selection sets of its field nodes.

    doc = value(parse("{ hero { name } }"))
    complete_object(env_for(fixture, doc, {}, {}), "Droid", first(operations(doc)).selections, person("2001"), []).value #=> {"name" => "R2-D2"}
"""
def complete_object(env, tname, nodes, v, path)
  r = exec_selection_set(
    env,
    tname,
    flat_map(nodes, (n) -> n.selections),
    v,
    path
  )
  if r.bad
    {**r, value: nil}
  else
    r
  end
end

@doc """
resolve_type: the object type a value of the abstract type `t` is at runtime, from the type's resolve_type function or else the value's own `__typename`.

    resolve_type({ctx: nil}, lookup(fixture, "Character"), person("1000")) #=> "Human"
"""
def resolve_type(env, t, v)
  if t.resolve_type.nil?
    entry_of(v, "__typename")[1]
  else
    pick = t.resolve_type
    pick(v, env.ctx)
  end
end

@doc """
serialize: a resolved value answered as the leaf type `t`, by the specification's result coercion; a value it cannot represent raises :coerce.

    serialize(lookup(fixture, "String"), 7) #=> "7"
"""
def serialize(t, v)
  case t.name
  when "Int"
    if integer?(v) and int_range?(v)
      v
    elsif float?(v) and floor(v) == v and int_range?(v)
      to_int(v)
    else
      raise(
        :coerce,
        "Int cannot represent non-integer value: #{shown_value(v)}"
      )
    end
  when "Float"
    if number?(v)
      to_float(v)
    else
      raise(
        :coerce,
        "Float cannot represent non numeric value: #{shown_value(v)}"
      )
    end
  when "String"
    if string?(v)
      v
    elsif number?(v) or v == true or v == false or keyword?(v)
      to_s(v)
    else
      raise(:coerce, "String cannot represent value: #{shown_value(v)}")
    end
  when "Boolean"
    if v == true or v == false
      v
    else
      raise(
        :coerce,
        "Boolean cannot represent a non boolean value: #{shown_value(v)}"
      )
    end
  when "ID"
    if string?(v)
      v
    elsif integer?(v)
      to_s(v)
    else
      raise(:coerce, "ID cannot represent value: #{shown_value(v)}")
    end
  else
    serialize_other(t, v)
  end
end

@doc """
serialize_other: a resolved value answered as an enum or a custom scalar: an enum name checked against its values, a scalar through its serialize function.

    serialize_other(lookup(fixture, "Episode"), "JEDI") #=> "JEDI"
"""
def serialize_other(t, v)
  if t.kind == "ENUM"
    name = to_s(v)
    if contains(enum_names(t), name)
      name
    else
      raise(
        :coerce,
        "Enum \"#{t.name}\" cannot represent value: #{shown_value(v)}"
      )
    end
  elsif t.serialize.nil?
    v
  else
    out = t.serialize
    out(v)
  end
end

@doc """
env_for: what every field of one execution reads: the schema, the document's fragments, the coerced variables and the resolvers' context.

    env_for(fixture, value(parse("{ a }")), {}, {context: 1}).ctx #=> 1
"""
def env_for(sc, doc, values, opts)
  {sc:, frags: fragments_of(doc), vars: values, ctx: opts[:context]}
end

@doc """
prepared: the operation a request runs and its environment, or the refusal that stops it first: no such operation, a bad variable, or a root the schema lacks.

    ok?(prepared(fixture, value(parse("{ hero { id } }")), {})) #=> true
"""
def prepared(sc, doc, opts)
  found = operation_of(doc, opts[:operation_name])
  if not ok?(found)
    found
  else
    op = value(found)
    cv = coerce_variables(sc, op, opts[:variables])
    if not is_empty(cv.errors)
      refused(refusal(:request, cv.errors))
    elsif root_name(sc, op.operation).nil?
      request_error(
        "Schema is not configured to execute #{to_s(op.operation)} operation.",
        loc_of(op)
      )
    else
      ok({op:, env: env_for(sc, doc, cv.values, opts)})
    end
  end
end

@doc """
execute: a parsed document run against the schema `sc` to a response, with the operation name, variables, root value and context `opts` gives; it does not validate.

    execute(fixture, value(parse("{ hero { id } }"))) #=> {data: {"hero" => {"id" => "2001"}}}
"""
def execute(sc, doc, opts?)
  o = opts or {}
  p = prepared(sc, doc, o)
  if not ok?(p)
    {errors: errors_of(p)}
  else
    op = value(p).op
    env = value(p).env
    r = exec_selection_set(
      env,
      root_name(sc, op.operation),
      op.selections,
      o[:root],
      []
    )
    response(
      if r.bad
        nil
      else
        r.value
      end,
      r.errs
    )
  end
end

@doc """
event_response: the response a subscription sends for one source event, the event run as the root value of the operation's selection set.

    doc = value(parse("subscription { reviewAdded { stars } }"))
    event_response(env_for(fixture, doc, {}, {}), "Subscription", first(operations(doc)), {reviewAdded: {stars: 4}}) #=> {data: {"reviewAdded" => {"stars" => 4}}}
"""
def event_response(env, root, op, event)
  r = exec_selection_set(env, root, op.selections, event, [])
  response(
    if r.bad
      nil
    else
      r.value
    end,
    r.errs
  )
end

@doc """
subscribe: a subscription made ready: the source the root field's subscribe function names, and a function from each event to its response; a document that is no subscription, or a field with no subscribe function, is refused.

    doc = value(parse("subscription ($e: Episode) { reviewAdded(episode: $e) { stars } }"))
    value(subscribe(fixture, doc, {variables: {"e" => "JEDI"}, context: {user: "leia"}})).source #=> {topic: "reviews", episode: "JEDI", by: "leia"}
"""
def subscribe(sc, doc, opts?)
  o = opts or {}
  p = prepared(sc, doc, o)
  if not ok?(p)
    p
  elsif value(p).op.operation != :subscription
    request_error("The operation is not a subscription.", loc_of(value(p).op))
  else
    op = value(p).op
    env = value(p).env
    root = sc.subscription
    g = first(collect_fields(env, root, op.selections))
    node = first(g[1])
    fdef = field_def(sc, root, node.name)
    begin
      args = coerce_arguments(sc, fdef.args, node.arguments, env.vars)
      if fdef.subscribe.nil?
        raise(
          :request,
          "Subscription field \"#{root}.#{fdef.name}\" has no subscribe function."
        )
      end
      source_of = fdef.subscribe
      source = source_of(args, env.ctx)
      ok({source:, respond: (event) -> event_response(env, root, op, event)})
    rescue e
      refused(
        refusal(
          :request,
          [{message: e.message, locations: loc_of(node), path: [first(g)]}]
        )
      )
    end
  end
end

@doc """
gql_error: one GraphQL error of a request, its message and where in the document it points.

    gql_error("no", []) #=> {message: "no", locations: []}
"""
def gql_error(message, locations)
  {message:, locations:}
end

@doc """
parse: a request's text read as a document with spans, or refused with the syntax error and its location.

    ok?(parse("{ hero { id } }")) #=> true
    kind(refusal_of(parse("{ a "))) #=> :parse_error
"""
def parse(text)
  ok(toriyose::danpen::parse(text, {spans: true}))
rescue :parse_error as e
  refused(
    refusal(:parse_error, [gql_error("Syntax Error: #{e.message}", [e.data])])
  )
end

@doc """
user_type? tells whether the type `t` is one a service declared, not a built-in scalar or an introspection type, so SDL writes it out.

    user_type?(lookup(fixture, "Human")) #=> true
    user_type?(lookup(fixture, "Int")) #=> false
"""
def user_type?(t)
  not starts_with(t.name, "__") and
    not contains(%w[Int Float String Boolean ID], t.name)
end

@doc """
deprecated_text: the `@deprecated` directive SDL writes after a member with the reason `d`; empty when it is not deprecated.

    deprecated_text(nil) #=> ""
    starts_with(deprecated_text("Use METER."), " @deprecated(reason: ") #=> true
"""
def deprecated_text(d)
  if d.nil?
    ""
  else
    " @deprecated(reason: #{json_stringify(d)})"
  end
end

@doc """
arg_text: one argument or input field written as SDL, with its default when it has one.

    arg_text(fixture, arg("unit", "Unit", {default: "METER"})) #=> "unit: Unit = METER"
"""
def arg_text(sc, a)
  default = if a.has_default
    " = #{render_value(sc, a.type, a.default)}"
  else
    ""
  end
  "#{a.name}: #{toriyose::danpen::type_text(a.type)}#{default}"
end

@doc """
args_text: a field's argument list written as SDL; empty when it takes none.

    args_text(fixture, [arg("id", "ID!")]) #=> "(id: ID!)"
"""
def args_text(sc, args)
  if is_empty(args)
    ""
  else
    "(#{join(map((a) -> arg_text(sc, a), args), ", ")})"
  end
end

@doc """
field_text: one field written as an indented SDL line, with its arguments and deprecation.

    field_text(fixture, field("id", "ID!")) #=> "  id: ID!"
"""
def field_text(sc, f)
  "  #{f.name}#{args_text(sc, f.args)}: #{toriyose::danpen::type_text(f.type)}#{deprecated_text(f.deprecated)}"
end

@doc """
braced_lines: the member lines of an SDL definition inside braces; empty when there are none, so an empty type writes no braces.

    braced_lines([]) #=> ""
    braced_lines(["  a"]) == join_lines([" {", "  a", "}"]) #=> true
"""
def braced_lines(lines)
  if is_empty(lines)
    ""
  else
    join_lines([" {", join(lines, line_break), "}"])
  end
end

@doc """
implements_text: the `implements` clause SDL writes for the interfaces of the type `t`; empty when it implements none.

    implements_text(lookup(fixture, "Human")) #=> " implements Character"
"""
def implements_text(t)
  if is_empty(t.interfaces)
    ""
  else
    " implements #{join(t.interfaces, " & ")}"
  end
end

@doc """
type_sdl: one type of a schema written as its SDL definition.

    type_sdl(fixture, lookup(fixture, "SearchResult")) #=> "union SearchResult = Human | Droid"
"""
def type_sdl(sc, t)
  case t.kind
  when "OBJECT"
    "type #{t.name}#{implements_text(t)}#{braced_lines(map((f) -> field_text(sc, f), t.fields))}"
  when "INTERFACE"
    "interface #{t.name}#{implements_text(t)}#{braced_lines(map((f) -> field_text(sc, f), t.fields))}"
  when "UNION"
    "union #{t.name} = #{join(t.members, " | ")}"
  when "ENUM"
    "enum #{t.name}#{braced_lines(map((v) -> "  #{v.name}#{deprecated_text(v.deprecated)}", t.values))}"
  when "INPUT_OBJECT"
    "input #{t.name}#{braced_lines(map((a) -> "  #{arg_text(sc, a)}", t.fields))}"
  else
    "scalar #{t.name}"
  end
end

@doc """
roots_sdl: the `schema` block of SDL naming each root type the schema has.

    roots_sdl(schema({types: [object_type("Query", [field("a", "Int")])]})) == join_lines(["schema {", "  query: Query", "}"]) #=> true
"""
def roots_sdl(sc)
  roots = filter(
    (r) -> r[1] != nil,
    [
      ["query", sc.query],
      ["mutation", sc.mutation],
      ["subscription", sc.subscription]
    ]
  )
  join_lines(
    [
      "schema {",
      join(map((r) -> "  #{first(r)}: #{r[1]}", roots), line_break),
      "}"
    ]
  )
end

@doc """
sdl: the schema `sc` written as SDL, the text danpen validates a document against.

    contains?(sdl(fixture), "union SearchResult = Human | Droid") #=> true
"""
def sdl(sc)
  types = filter(user_type?, map((e) -> e[1], map_entries(sc.types)))
  join(
    append([roots_sdl(sc)], map((t) -> type_sdl(sc, t), types)),
    unlines(["", ""])
  )
end

@doc """
findings: every validation error of the document `doc` against the schema `sc`, each with its locations and the rule it breaks; empty for a valid document.

    findings(value(parse("{ hero { id } }")), fixture) #=> []
    size(findings(value(parse("{ nope }")), fixture)) #=> 1
"""
def findings(doc, sc)
  map(
    (f) -> {message: f.message, locations: loc_of(f), rule: f.rule},
    toriyose::danpen::check(doc, sdl(sc))
  )
end

@doc """
validate: the document `doc` accepted when it is valid against the schema `sc`, else refused with all of its findings.

    ok?(validate(value(parse("{ hero { id } }")), fixture)) #=> true
"""
def validate(doc, sc)
  found = findings(doc, sc)
  if is_empty(found)
    ok(doc)
  else
    refused(refusal(:invalid, found))
  end
end

@doc """
request: a GraphQL request answered end to end: the text parsed, validated against the schema and executed, a parse or validation failure answered as errors with no data.

    request(fixture, "{ hero { id } }") #=> {data: {"hero" => {"id" => "2001"}}}
"""
def request(sc, text, opts?)
  p = parse(text)
  if not ok?(p)
    {errors: errors_of(p)}
  else
    v = validate(value(p), sc)
    if not ok?(v)
      {errors: map((f) -> dissoc(f, :rule), errors_of(v))}
    else
      execute(sc, value(p), opts)
    end
  end
end

@doc """
model_scalar: the GraphQL scalar a model field kind is served as; nil for a kind with none.

    model_scalar(:time) #=> "DateTime"
    model_scalar(:bytes) #=> nil
"""
def model_scalar(k)
  case k
  when :string
    "String"
  when :text
    "String"
  when :int
    "Int"
  when :float
    "Float"
  when :bool
    "Boolean"
  when :id
    "ID"
  when :time
    "DateTime"
  end
end

@doc """
lower_first: a type name with its first letter lowered, the name of the query field that fetches one of it.

    lower_first("Team") #=> "team"
"""
def lower_first(s)
  cs = chars(s)
  concat(downcase(first(cs)), join(rest(cs), ""))
end

@doc """
model_field: a model field of the entity `e` as a GraphQL field and its refusals: kept out when secret or not public, refused alone when its kind has no scalar.

    toriyose::danpen::type_text(first(model_field({name: "Team"}, {name: "score", type: :float, optional: true})).type) #=> "Float"
"""
def model_field(e, f)
  scalar = model_scalar(f[:type])
  if f[:secret] == true or f[:public] == false
    [nil, []]
  elsif scalar.nil?
    [
      nil,
      [
        refusal(
          :unknown_type,
          "#{e.name}.#{f[:name]} has the type #{to_s(f[:type])}, which has no GraphQL scalar"
        )
      ]
    ]
  else
    ref = if f[:optional] == true
      scalar
    else
      "#{scalar}!"
    end
    [
      field(
        f[:name],
        ref,
        {deprecated: f[:deprecated], description: f[:description]}
      ),
      []
    ]
  end
end

@doc """
model_relation: a model relation of the entity `e` as a GraphQL field and its refusals, refused alone when it names an entity not in `names`.

    toriyose::danpen::type_text(first(model_relation({name: "Control"}, {name: "evidence", entity: "Evidence", many: true}, ["Evidence"])).type) #=> "[Evidence!]!"
"""
def model_relation(e, r, names)
  if not contains(names, r[:entity])
    [
      nil,
      [
        refusal(
          :unknown_entity,
          "#{e.name}.#{r[:name]} relates to #{r[:entity]}, which is not an entity of the model"
        )
      ]
    ]
  else
    ref = if r[:many] == true
      "[#{r[:entity]}!]!"
    elsif r[:optional] == false
      "#{r[:entity]}!"
    else
      r[:entity]
    end
    [
      field(
        r[:name],
        ref,
        {deprecated: r[:deprecated], description: r[:description]}
      ),
      []
    ]
  end
end

@doc """
kept: the fields of the field-and-refusals pairs that were not left out.

    kept([[1, []], [nil, [2]]]) #=> [1]
"""
def kept(pairs)
  filter((x) -> x != nil, map(first, pairs))
end

@doc """
plural_of: the name of the query field that lists an entity: its declared plural, else its lowered name with an s.

    plural_of({name: "Team"}) #=> "teams"
    plural_of({name: "Evidence", plural: "evidence"}) #=> "evidence"
"""
def plural_of(e)
  e[:plural] or "#{lower_first(e.name)}s"
end

@doc """
root_fields: the two query fields an entity adds to the root, one by its key and one listing all of it.

    map((f) -> f.name, root_fields({name: "Team"})) #=> ["team", "teams"]
"""
def root_fields(e)
  key = e[:key] or "id"
  [
    field(lower_first(e.name), e.name, {args: [arg(key, "ID!")]}),
    field(plural_of(e), "[#{e.name}!]!")
  ]
end

@doc """
from_model: the object types and query root an entity model derives, with a DateTime scalar when a field is a time, and each field or relation that cannot be served refused alone.

    map((t) -> t.name, from_model({entities: [{name: "Team", fields: [{name: "id", type: :id}]}]}).types) #=> ["Team", "Query"]
"""
def from_model(model)
  ents = model[:entities] or []
  names = map((e) -> e.name, ents)
  parts = map(
    fn(e)
      fs = map((f) -> model_field(e, f), e[:fields] or [])
      rs = map((r) -> model_relation(e, r, names), e[:relations] or [])
      [
        object_type(
          e.name,
          append(kept(fs), kept(rs)),
          {description: e[:description]}
        ),
        append(flat_map(fs, (x) -> x[1]), flat_map(rs, (x) -> x[1]))
      ]
    end,
    ents
  )
  uses_time = count_where(
    (e) -> count_where((f) -> f[:type] == :time, e[:fields] or []) > 0,
    ents
  ) > 0
  {
    types: append(
      map(first, parts),
      [object_type("Query", flat_map(ents, root_fields))],
      if uses_time
        [
          scalar_type(
            "DateTime",
            {
              description: "An RFC 3339 date and time, as a String.",
              serialize: datetime_text
            }
          )
        ]
      else
        []
      end
    ),
    refusals: append(model[:refusals] or [], flat_map(parts, (p) -> p[1]))
  }
end

@doc """
datetime_text: a DateTime as it is answered: text passes through, and a whole number is read as Unix milliseconds and written in RFC 3339.

    datetime_text(0) #=> "1970-01-01T00:00:00.000Z"
"""
def datetime_text(v)
  if string?(v)
    v
  elsif integer?(v)
    rfc3339_of_ms(v)
  else
    raise(:coerce, "DateTime cannot represent value: #{shown_value(v)}")
  end
end

@doc """
teeburu_scalars: the model kind each teeburu field type is served as; a type absent here has no GraphQL scalar, and from_model refuses its field by name.

    teeburu_scalars[:timestamp] #=> :time
"""
def teeburu_scalars()
  {
    uuid: :id,
    text: :string,
    int: :int,
    float: :float,
    bool: :bool,
    timestamp: :time
  }
end

@doc """
teeburu_field: one teeburu field as a model field: its name in camelCase, its type through teeburu_scalars, optional unless declared `null: false`, and public unless `omit` names it as `entity.field`.

    teeburu_field(:order, :placed_at, {type: :timestamp, null: false}, []) #=> {name: "placedAt", type: :time, optional: false, public: true}
"""
def teeburu_field(ename, fname, rec, omit)
  {
    name: camel_case(to_s(fname)),
    type: get(teeburu_scalars, rec[:type]) or rec[:type],
    optional: rec[:null] != false,
    public: not contains(omit, "#{to_s(ename)}.#{to_s(fname)}")
  }
end

@doc """
teeburu_relations: the relations a teeburu entity declares, each with its name in camelCase and the entity it names in PascalCase.

    teeburu_relations({relations: {customer: :customer}}) #=> [{name: "customer", entity: "Customer"}]
"""
def teeburu_relations(ent)
  map(
    (r) -> {name: camel_case(to_s(first(r))), entity: pascal_case(to_s(r[1]))},
    map_entries(ent[:relations] or {})
  )
end

@doc """
teeburu_reverse: the reverse relations of the entity `target`: for each relation in `declared` that names `target`, a many relation to the owner, named with the owner's plural.

    teeburu_reverse([[:order, {relations: {customer: :customer}}]], :customer) #=> [{name: "orders", entity: "Order", many: true}]
"""
def teeburu_reverse(declared, target)
  flat_map(
    declared,
    fn(e)
      owner = pascal_case(to_s(first(e)))
      map(
        (_r) -> {name: plural_of({name: owner}), entity: owner, many: true},
        filter((r) -> r[1] == target, map_entries(e[1][:relations] or {}))
      )
    end
  )
end

@doc """
distinct_members: the members of the type `ename` with each name kept once. The first member with a name stays; each later one is left out and refused as a name clash.

    size(get(distinct_members("Order", [{member: {name: "id"}}, {member: {name: "id"}}]), :refusals)) #=> 1
"""
def distinct_members(ename, members)
  reduce(
    fn(acc, m)
      if contains(acc.names, m.member.name)
        {
          **acc,
          refusals: append(
            acc.refusals,
            [
              refusal(
                :name_clash,
                "#{ename}.#{m.member.name} is named twice; the later one is left out"
              )
            ]
          )
        }
      else
        {
          **acc,
          names: append(acc.names, [m.member.name]),
          kept: append(acc.kept, [m])
        }
      end
    end,
    {names: [], kept: [], refusals: []},
    members
  )
end

@doc """
from_teeburu: a teeburu model as the model from_model reads: each entity a type named in PascalCase, each field and relation in camelCase, each field typed through teeburu_scalars and nullable unless declared `null: false`, and every relation also answered from the entity it names as the list of its owners. `omit` lists `entity.field` names kept out of GraphQL; a name used twice on one type is refused alone.

    from_teeburu({entities: {}}) #=> {entities: [], refusals: []}
"""
def from_teeburu(model, opts?)
  omit = (opts or {})[:omit] or []
  declared = map_entries(model[:entities] or {})
  parts = map(
    fn(e)
      ename = pascal_case(to_s(first(e)))
      key = e[1][:key] or :id
      all = map_entries(e[1][:fields] or {})
      fields = map(
        fn(f)
          {kind: :field, member: teeburu_field(first(e), first(f), f[1], omit)}
        end,
        append(
          filter((f) -> first(f) == key, all),
          filter((f) -> first(f) != key, all)
        )
      )
      rels = map(
        (r) -> {kind: :relation, member: r},
        append(teeburu_relations(e[1]), teeburu_reverse(declared, first(e)))
      )
      d = distinct_members(ename, append(fields, rels))
      pick = (k) -> map((m) -> m.member, filter((m) -> m.kind == k, d.kept))
      [
        {
          name: ename,
          key: camel_case(to_s(key)),
          fields: pick(:field),
          relations: pick(:relation)
        },
        d.refusals
      ]
    end,
    declared
  )
  {entities: map(first, parts), refusals: flat_map(parts, (p) -> p[1])}
end

@doc """
http_params: the query, variables and operation name a GraphQL-over-HTTP request carries, from a GET's query string or a POST's JSON body; a POST of any other content type, a body that is not a JSON object, no query, or variables that are not an object is refused by name.

    ok?(http_params({method: "GET", path: "/graphql", query: "query=%7Ba%7D"})) #=> true
"""
def http_params(req)
  bad = (text) -> refused(refusal(:bad_request, text))
  if req[:method] == "GET"
    q = eigyou::kyuuji::query_params(req)
    at = fn(k)
      v = get(q, k)
      if v != nil
        eigyou::kyuuji::form_decoded(v)
      end
    end
    vars = at("variables")
    parsed = if vars.nil?
      ok(nil)
    else
      ok(json_read(vars)) rescue bad("the variables are not JSON")
    end
    if not ok?(parsed)
      parsed
    else
      params_of(
        {
          "query" => at("query"),
          "variables" => value(parsed),
          "operationName" => at("operationName")
        },
        bad
      )
    end
  elsif not starts_with(
    downcase(eigyou::kyuuji::header(req, "content-type") or ""),
    "application/json"
  )
    refused(
      refusal(:unsupported_media_type, "a POST to GraphQL is application/json")
    )
  else
    body = json_read(req[:body] or "") rescue nil
    if not map?(body)
      bad("the body is not a JSON object")
    else
      params_of(body, bad)
    end
  end
end

@doc """
params_of: the query, variables and operation name of a decoded request `b`, or the result of `bad` with the reason. A request with no query, variables that are not an object, or an operation name that is not a string is bad.

    value(params_of({"query" => "{ a }"}, (t) -> t)) #=> {query: "{ a }", variables: {}, operation_name: nil}
    params_of({}, (t) -> t) #=> "the request carries no query"
"""
def params_of(b, bad)
  q = b["query"]
  v = b["variables"]
  name = b["operationName"]
  if not string?(q) or q == ""
    bad("the request carries no query")
  elsif v != nil and not map?(v)
    bad("the variables are not a JSON object")
  elsif name != nil and not string?(name)
    bad("the operationName is not a string")
  else
    ok({query: q, variables: v or {}, operation_name: name})
  end
end

@doc """
http_error: a JSON response with the HTTP `status` and one GraphQL error that carries `message` and the extension `code`.

    http_error(400, "BAD_REQUEST", "no query")[:status] #=> 400
"""
def http_error(status, code, message)
  eigyou::kyuuji::json(status, {errors: [{message:, extensions: {code:}}]})
end

@doc """
query_only?: whether the operation `name` in `text` is a query. Text that does not parse, or names no operation it holds, is true here, so the request reports its own error.

    query_only?("{ a }", nil) #=> true
    query_only?("mutation { a }", nil) #=> false
"""
def query_only?(text, name)
  p = parse(text)
  if not ok?(p)
    true
  else
    op = operation_of(value(p), name)
    not ok?(op) or value(op).operation == :query
  end
end

@doc """
http_answer: a GraphQL-over-HTTP request answered through request as application/json: 200 when the answer carries data, 400 when it carries only errors, 405 for a GET that is not a query, 415 for a POST that is not JSON. `context` is a function of the HTTP request giving the resolvers' context; with none, the context is the request.

    http_answer(fixture, {method: "GET", path: "/graphql", query: "query=%7Bhero%7Bid%7D%7D"})[:status] #=> 200
"""
def http_answer(sc, req, opts?)
  o = opts or {}
  p = http_params(req)
  if not ok?(p)
    r = refusal_of(p)
    if kind(r) == :unsupported_media_type
      http_error(415, "UNSUPPORTED_MEDIA_TYPE", why(r))
    else
      http_error(400, "BAD_REQUEST", why(r))
    end
  else
    g = value(p)
    if req[:method] == "GET" and not query_only?(g.query, g.operation_name)
      r = http_error(405, "METHOD_NOT_ALLOWED", "a GET answers only a query")
      assoc(r, :headers, assoc(r[:headers], "Allow", "POST"))
    else
      ctx = if o[:context].nil?
        req
      else
        f = o[:context]
        f(req)
      end
      out = request(
        sc,
        g.query,
        {variables: g.variables, operation_name: g.operation_name, context: ctx}
      )
      eigyou::kyuuji::json(
        if has?(out, :data)
          200
        else
          400
        end,
        out
      )
    end
  end
end

@doc """
http_routes: the kyuuji routes that serve a schema at one path, GET for a query string and POST for a JSON body, each answered by http_answer.

    size(http_routes("/graphql", fixture)) #=> 2
"""
def http_routes(path, sc, opts?)
  h = (req) -> http_answer(sc, req, opts)
  [
    eigyou::kyuuji::route("GET", path, h),
    eigyou::kyuuji::route("POST", path, h)
  ]
end

@doc """
with_resolvers: the types `types` with the resolvers of `table`, keyed `Type.field`, laid over their fields, so a derived schema answers.

    t = with_resolvers([object_type("Query", [field("a", "Int")])], {"Query.a" => (_p, _a, _c) -> 1})
    request(schema({types: t}), "{ a }") #=> {data: {"a" => 1}}
"""
def with_resolvers(types, table)
  map(
    fn(t)
      if t[:field_index].nil? or t.kind == "INPUT_OBJECT"
        t
      else
        fs = map(
          fn(f)
            r = get(table, "#{t.name}.#{f.name}")
            if r.nil?
              f
            else
              assoc(f, :resolve, r)
            end
          end,
          t.fields
        )
        {**t, fields: fs, field_index: indexed(fs)}
      end
    end,
    types
  )
end

@doc """
people: the characters the test fixture serves, two humans and a droid.

    size(people) #=> 3
"""
def people()
  [
    {
      kind: "Human",
      id: "1000",
      name: "Luke Skywalker",
      friends: %w[1002 2001],
      homePlanet: "Tatooine",
      height: 1.72
    },
    {
      kind: "Human",
      id: "1002",
      name: "Han Solo",
      friends: ["1000"],
      homePlanet: nil,
      height: 1.8
    },
    {
      kind: "Droid",
      id: "2001",
      name: "R2-D2",
      friends: ["1000"],
      primaryFunction: "Astromech",
      legacyCode: "R2"
    }
  ]
end

@doc """
person: the fixture character with the id `id`, or nil.

    person("1000").name #=> "Luke Skywalker"
"""
def person(id)
  find_first((c) -> c.id == id, people)
end

@doc """
fixture: the schema the tests and examples run against, a Star Wars graph with an interface, a union, enums, an input type, a mutation, a subscription and fields that fail on purpose.

    request(fixture, "{ hero { name } }") #=> {data: {"hero" => {"name" => "R2-D2"}}}
"""
def fixture()
  friends = field(
    "friends",
    "[Character]",
    {resolve: (p, _a, _c) -> map(person, p.friends)}
  )
  schema(
    {
      types: [
        interface_type(
          "Character",
          [
            field("id", "ID!"),
            field("name", "String"),
            field("friends", "[Character]")
          ],
          {resolve_type: (v, _c) -> v.kind}
        ),
        object_type(
          "Human",
          [
            field("id", "ID!"),
            field("name", "String"),
            friends,
            field("homePlanet", "String"),
            field(
              "height",
              "Float",
              {
                args: [arg("unit", "Unit", {default: "METER"})],
                resolve: fn(p, a, _c)
                  if a.unit == "FOOT"
                    round(p.height * 3.28084 * 100) / 100
                  else
                    p.height
                  end
                end
              }
            )
          ],
          {interfaces: ["Character"]}
        ),
        object_type(
          "Droid",
          [
            field("id", "ID!"),
            field("name", "String"),
            friends,
            field("primaryFunction", "String"),
            field("legacyCode", "String", {deprecated: "Use primaryFunction."})
          ],
          {interfaces: ["Character"]}
        ),
        union_type("SearchResult", %w[Human Droid]),
        enum_type(
          "Unit",
          ["METER", enum_value("FOOT", {deprecated: "Use METER."})]
        ),
        enum_type("Episode", %w[NEWHOPE EMPIRE JEDI]),
        input_type(
          "ReviewInput",
          [arg("stars", "Int!"), arg("commentary", "String")]
        ),
        object_type(
          "Review",
          [
            field("episode", "Episode"),
            field("stars", "Int!"),
            field("commentary", "String")
          ]
        ),
        object_type(
          "Outer",
          [
            field("ok", "String", {resolve: (_p, _a, _c) -> "fine"}),
            field("inner", "String!", {resolve: (_p, _a, _c) -> nil}),
            field(
              "sealed",
              "String!",
              {
                resolve: fn(_p, _a, _c)
                  raise(:unavailable, "the vault is sealed")
                end
              }
            )
          ]
        ),
        object_type(
          "Query",
          [
            field(
              "hero",
              "Character",
              {
                args: [arg("episode", "Episode")],
                resolve: fn(_p, a, _c)
                  if a["episode"] == "EMPIRE"
                    person("1000")
                  else
                    person("2001")
                  end
                end
              }
            ),
            field(
              "human",
              "Human",
              {args: [arg("id", "ID!")], resolve: (_p, a, _c) -> person(a.id)}
            ),
            field(
              "characters",
              "[Character!]!",
              {resolve: (_p, _a, _c) -> people}
            ),
            field(
              "search",
              "[SearchResult]",
              {
                args: [arg("text", "String!")],
                resolve: fn(_p, a, _c)
                  filter(
                    (c) -> contains?(c.name, a.text),
                    map((c) -> {**c, __typename: c.kind}, people)
                  )
                end
              }
            ),
            field("strict", "String!", {resolve: (_p, _a, _c) -> nil}),
            field("outer", "Outer", {resolve: (_p, _a, _c) -> {}}),
            field(
              "broken",
              "String",
              {
                resolve: fn(_p, _a, _c)
                  raise(:unavailable, "the archive is closed")
                end
              }
            ),
            field("whoami", "String", {resolve: (_p, _a, c) -> c.user}),
            field("old", "String", {deprecated: true})
          ]
        ),
        object_type(
          "Mutation",
          [
            field(
              "createReview",
              "Review",
              {
                args: [
                  arg("episode", "Episode"),
                  arg("review", "ReviewInput!")
                ],
                resolve: fn(_p, a, _c)
                  {
                    episode: a["episode"],
                    stars: a.review.stars,
                    commentary: a.review["commentary"]
                  }
                end
              }
            )
          ]
        ),
        object_type(
          "Subscription",
          [
            field(
              "reviewAdded",
              "Review",
              {
                args: [arg("episode", "Episode")],
                subscribe: fn(a, c)
                  {topic: "reviews", episode: a.episode, by: c.user}
                end
              }
            ),
            field("other", "String")
          ]
        )
      ]
    }
  )
end

test "a schema is a value: built-ins joined, references checked, deprecations kept"
  sc = fixture
  assert map(
    (n) -> lookup(sc, n).kind,
    %w[Int Float String Boolean ID __Schema]
  ) == %w[SCALAR SCALAR SCALAR SCALAR SCALAR OBJECT]
  assert [sc.query, sc.mutation, sc.subscription] ==
    %w[Query Mutation Subscription]
  assert field_def(sc, "Droid", "legacyCode").deprecated ==
    "Use primaryFunction."
  assert field_def(sc, "Query", "old").deprecated == "No longer supported"
  assert toriyose::danpen::type_text(type_ref("[[Int!]]!")) == "[[Int!]]!"
  assert possible_types(sc, "Character") == %w[Droid Human]
  bad = begin
    schema(
      {
        types: [
          object_type(
            "Query",
            [
              field("a", "Nope"),
              field("b", "Query", {args: [arg("x", "Query")]})
            ]
          )
        ]
      }
    )
  rescue :invalid_schema as e
    e.message
  end
  assert bad ==
    "Query.a refers to the unknown type Nope; Query.b(x) cannot have the type Query"
end

test "a schema derives from a model's entities, pure, refusing a bad field alone"
  m = {
    entities: [
      {
        name: "Control",
        fields: [
          {name: "id", type: :id},
          {name: "title", type: :string},
          {name: "observedAt", type: :time, deprecated: "Use evidenceTime."},
          {name: "secretNote", type: :string, secret: true},
          {name: "blob", type: :bytes},
          {name: "score", type: :float, optional: true}
        ],
        relations: [
          {name: "evidence", entity: "Evidence", many: true},
          {name: "owner", entity: "Team"}
        ]
      },
      {name: "Evidence", plural: "evidence", fields: [{name: "id", type: :id}]}
    ]
  }
  d = from_model(m)
  assert from_model(m) == d
  assert map((t) -> t.name, d.types) == %w[Control Evidence Query DateTime]
  c = first(d.types)
  assert map(
    (f) -> "#{f.name}: #{toriyose::danpen::type_text(f.type)}",
    c.fields
  ) ==
    [
      "id: ID!",
      "title: String!",
      "observedAt: DateTime!",
      "score: Float",
      "evidence: [Evidence!]!"
    ]
  assert c.fields[2].deprecated == "Use evidenceTime."
  assert kyohi::kinds(d.refusals) == %i[unknown_type unknown_entity]
  assert map((f) -> f.name, d.types[2].fields) ==
    %w[
      control
      controls
      evidence_
      evidence
    ] or
    map((f) -> f.name, d.types[2].fields) ==
      %w[control controls evidence evidence]
  assert from_model({entities: []}).types == [object_type("Query", [])]
end

test "a derived schema answers once resolvers are laid over it"
  m = {
    entities: [
      {
        name: "Team",
        fields: [{name: "id", type: :id}, {name: "name", type: :string}]
      }
    ]
  }
  teams = [{id: "t1", name: "Red"}, {id: "t2", name: "Blue"}]
  types = with_resolvers(
    from_model(m).types,
    {
      "Query.teams" => (_p, _a, _c) -> teams,
      "Query.team" => (_p, a, _c) -> find_first((t) -> t.id == a.id, teams)
    }
  )
  sc = schema({types:})
  assert request(sc, "{ teams { name } team(id: \"t2\") { id } }") ==
    {
      data: {
        "teams" => [{"name" => "Red"}, {"name" => "Blue"}],
        "team" => {"id" => "t2"}
      }
    }
  assert request(sc, "{ team(id: \"zz\") { id } }") == {data: {"team" => nil}}
end

@doc """
shop_model: a teeburu model for tests: a customer and an order that names it, with one field of a type that has no GraphQL scalar.

    shop_model[:name] #=> "shop"
"""
def shop_model()
  {
    name: "shop",
    version: 1,
    entities: {
      customer: {
        key: :id,
        fields: {
          id: {type: :uuid, null: false},
          full_name: {type: :text, null: false},
          orders: {type: :int, null: true}
        }
      },
      order: {
        key: :id,
        fields: {
          id: {type: :uuid, null: false},
          placed_at: {type: :timestamp, null: true},
          total: {type: :decimal, null: false},
          note: {type: :text, null: true},
          secret_code: {type: :text, null: true}
        },
        relations: {customer: :customer}
      }
    }
  }
end

@doc """
field_texts: each field of the type `t` as `name: Type` text, in order.

    d = from_model(from_teeburu(shop_model))
    field_texts(first(d.types)) #=> ["id: ID!", "fullName: String!", "orders: Int"]
"""
def field_texts(t)
  map((f) -> "#{f.name}: #{toriyose::danpen::type_text(f.type)}", t.fields)
end

test "a teeburu model derives a schema: names cased, types mapped as data, an unmapped type and a clash refused alone"
  t = from_teeburu(shop_model, {omit: ["order.secret_code"]})
  d = from_model(t)
  assert map((x) -> x.name, d.types) == %w[Customer Order Query DateTime]
  assert field_texts(first(d.types)) ==
    ["id: ID!", "fullName: String!", "orders: Int"]
  assert field_texts(d.types[1]) ==
    ["id: ID!", "note: String", "placedAt: DateTime", "customer: Customer"]
  assert kyohi::kinds(d.refusals) == %i[name_clash unknown_type]
  assert map(why, d.refusals) ==
    [
      "Customer.orders is named twice; the later one is left out",
      "Order.total has the type decimal, which has no GraphQL scalar"
    ]
  assert map((f) -> f.name, d.types[2].fields) ==
    %w[customer customers order orders]
  assert from_teeburu({entities: {}}) == {entities: [], refusals: []}
end

test "a relation is answered both ways, and a stored millisecond instant reads as RFC 3339"
  m = {
    entities: {
      team: {key: :id, fields: {id: {type: :uuid, null: false}}},
      player: {
        key: :id,
        fields: {
          id: {type: :uuid, null: false},
          joined_at: {type: :timestamp, null: false}
        },
        relations: {team: :team}
      }
    }
  }
  t = from_teeburu(m)
  assert t.refusals == []
  players = [
    {id: "p1", joinedAt: 1_762_259_696_789, team: "t1"},
    {id: "p2", joinedAt: "2020-01-01T00:00:00Z", team: "t1"}
  ]
  sc = schema(
    {
      types: with_resolvers(
        from_model(t).types,
        {
          "Query.team" => (_p, a, _c) -> {id: a.id},
          "Team.players" => fn(p, _a, _c)
            filter((x) -> x.team == p.id, players)
          end,
          "Player.team" => (p, _a, _c) -> {id: p.team}
        }
      )
    }
  )
  assert request(
    sc,
    "{ team(id: \"t1\") { players { id joinedAt team { id } } } }"
  ) ==
    {
      data: {
        "team" => {
          "players" => [
            {
              "id" => "p1",
              "joinedAt" => "2025-11-04T12:34:56.789Z",
              "team" => {"id" => "t1"}
            },
            {
              "id" => "p2",
              "joinedAt" => "2020-01-01T00:00:00Z",
              "team" => {"id" => "t1"}
            }
          ]
        }
      }
    }
end

@doc """
http_get: a GET request to `/graphql` with the query string `qs`.

    http_get("query=%7Ba%7D")[:method] #=> "GET"
"""
def http_get(qs)
  eigyou::kyuuji::request("GET", "/graphql", qs)
end

@doc """
http_post: a POST request to `/graphql` with the content type `content_type` and the body `body`.

    http_post("application/json", "{}")[:body] #=> "{}"
"""
def http_post(content_type, body)
  assoc(
    eigyou::kyuuji::with_headers(
      eigyou::kyuuji::request("POST", "/graphql", ""),
      [["Content-Type", content_type]]
    ),
    :body,
    body
  )
end

@doc """
answered: the answer of http_answer to `req` as its status, its content type and its body read as JSON.

    answered(fixture, http_get("query=%7Bhero%7Bid%7D%7D"))[:status] #=> 200
"""
def answered(sc, req, opts?)
  r = http_answer(sc, req, opts)
  {
    status: r[:status],
    type: r[:headers]["Content-Type"],
    body: json_read(r[:body])
  }
end

test "a GraphQL request is answered over HTTP by GET and POST, and a bad one with a typed error"
  sc = fixture
  got = answered(sc, http_get("query=%7B+hero+%7B+id+%7D+%7D"))
  assert got ==
    {
      status: 200,
      type: "application/json",
      body: {"data" => {"hero" => {"id" => "2001"}}}
    }
  posted = answered(
    sc,
    http_post(
      "application/json; charset=utf-8",
      "{\"query\": \"query ($id: ID!) { human(id: $id) { name } }\", \"variables\": {\"id\": \"1000\"}}"
    )
  )
  assert posted.status == 200
  assert posted.body == {"data" => {"human" => {"name" => "Luke Skywalker"}}}
  unknown = answered(
    sc,
    http_post("application/json", "{\"query\": \"{ nope }\"}")
  )
  assert unknown.status == 400
  assert not has?(unknown.body, "data")
  assert contains?(
    first(unknown.body["errors"])["message"],
    "Query has no field nope"
  )
  form = answered(
    sc,
    http_post("text/plain", "{\"query\": \"{ hero { id } }\"}")
  )
  assert form.status == 415
  assert first(form.body["errors"])["extensions"] ==
    {"code" => "UNSUPPORTED_MEDIA_TYPE"}
  bad = map(
    (b) -> answered(sc, http_post("application/json", b)),
    [
      "not json",
      "[1]",
      "{\"query\": \"\"}",
      "{\"query\": \"{ hero { id } }\", \"variables\": [1]}"
    ]
  )
  assert map((r) -> r.status, bad) == [400, 400, 400, 400]
  assert map((r) -> first(r.body["errors"])["message"], bad) ==
    [
      "the body is not a JSON object",
      "the body is not a JSON object",
      "the request carries no query",
      "the variables are not a JSON object"
    ]
  mutation = http_answer(
    sc,
    http_get("query=mutation+%7B+createReview(review%3A+%7Bstars%3A+5%7D)+%7B+stars+%7D+%7D")
  )
  by_get = answered(
    sc,
    http_get("query=query+A+%7Bhero%7Bid%7D%7D+query+B(%24id%3A+ID!)+%7Bhuman(id%3A+%24id)%7Bname%7D%7D&operationName=B&variables=%7B%22id%22%3A%221002%22%7D")
  )
  assert by_get.body == {"data" => {"human" => {"name" => "Han Solo"}}}
  assert answered(
    sc,
    http_get("query=%7Bhero%7Bid%7D%7D&variables=%7Bno")
  ).body ==
    {
      "errors" => [
        {
          "message" => "the variables are not JSON",
          "extensions" => {"code" => "BAD_REQUEST"}
        }
      ]
    }
  assert mutation[:status] == 405
  assert mutation[:headers]["Allow"] == "POST"
  assert answered(
    sc,
    http_get("query=%7Bwhoami%7D"),
    {context: (req) -> {user: req[:method]}}
  ).body == {"data" => {"whoami" => "GET"}}
end

test "http_routes serve a schema at one path through a kyuuji router"
  app = eigyou::kyuuji::router(http_routes("/graphql", fixture))
  assert app[:refusals] == []
  r = eigyou::kyuuji::dispatch(app, http_get("query=%7Bhero%7Bid%7D%7D"))
  assert r[:status] == 200
  put = eigyou::kyuuji::dispatch(
    app,
    eigyou::kyuuji::request("PUT", "/graphql", "")
  )
  assert put[:status] == 405
end

test "execution resolves aliases, arguments, variables, fragments and abstract types"
  sc = fixture
  r = request(
    sc,
    "query ($u: Unit) { luke: human(id: \"1000\") { name height h2: height(unit: $u) } hero { __typename name ... on Droid { primaryFunction } } }",
    {variables: {"u" => "FOOT"}}
  )
  assert r ==
    {
      data: {
        "luke" => {"name" => "Luke Skywalker", "height" => 1.72, "h2" => 5.64},
        "hero" => {
          "__typename" => "Droid",
          "name" => "R2-D2",
          "primaryFunction" => "Astromech"
        }
      }
    }
  r2 = request(
    sc,
    "{ hero(episode: EMPIRE) { ...Who friends { name ... on Human { homePlanet } } } } fragment Who on Character { id name }"
  )
  assert r2 ==
    {
      data: {
        "hero" => {
          "id" => "1000",
          "name" => "Luke Skywalker",
          "friends" => [
            {"name" => "Han Solo", "homePlanet" => nil},
            {"name" => "R2-D2"}
          ]
        }
      }
    }
  r3 = request(
    sc,
    "{ search(text: \"a\") { __typename ... on Human { name } ... on Droid { id } } d: search(text: \"-\") { ... on Droid { id } } }"
  )
  assert r3 ==
    {
      data: {
        "search" => [
          {"__typename" => "Human", "name" => "Luke Skywalker"},
          {"__typename" => "Human", "name" => "Han Solo"}
        ],
        "d" => [{"id" => "2001"}]
      }
    }
  assert request(
    sc,
    "{ hero(episode: EMPIRE) { name ...D } } fragment D on Droid { id }"
  ) == {data: {"hero" => {"name" => "Luke Skywalker"}}}
  assert request(sc, "{ characters { id } }") ==
    {
      data: {
        "characters" => [{"id" => "1000"}, {"id" => "1002"}, {"id" => "2001"}]
      }
    }
end

test "skip and include decide with the variables they are given"
  sc = fixture
  q = "query ($s: Boolean!) { hero { name @skip(if: $s) id @include(if: $s) ... on Droid @skip(if: $s) { primaryFunction } } }"
  assert request(sc, q, {variables: {"s" => true}}) ==
    {data: {"hero" => {"id" => "2001"}}}
  assert request(sc, q, {variables: {"s" => false}}) ==
    {data: {"hero" => {"name" => "R2-D2", "primaryFunction" => "Astromech"}}}
end

test "a null in a non-null place propagates to the nearest nullable field"
  sc = fixture
  assert request(sc, "{ strict hero { id } }") ==
    {
      data: nil,
      errors: [
        {
          message: "Cannot return null for non-nullable field Query.strict.",
          locations: [{line: 1, column: 3}],
          path: ["strict"]
        }
      ]
    }
  assert request(sc, "{ outer { ok inner } }") ==
    {
      data: {"outer" => nil},
      errors: [
        {
          message: "Cannot return null for non-nullable field Outer.inner.",
          locations: [{line: 1, column: 14}],
          path: %w[outer inner]
        }
      ]
    }
  assert request(sc, "{ broken hero { id } }") ==
    {
      data: {"broken" => nil, "hero" => {"id" => "2001"}},
      errors: [
        {
          message: "the archive is closed",
          locations: [{line: 1, column: 3}],
          path: ["broken"]
        }
      ]
    }
  assert request(sc, "{ outer { ok sealed } }") ==
    {
      data: {"outer" => nil},
      errors: [
        {
          message: "the vault is sealed",
          locations: [{line: 1, column: 14}],
          path: %w[outer sealed]
        }
      ]
    }
  assert request(sc, "{ outer { ok } }") ==
    {data: {"outer" => {"ok" => "fine"}}}
end

test "variables are coerced before execution and a bad one answers errors with no data"
  sc = fixture
  q = "query ($id: ID!) { human(id: $id) { name } }"
  assert request(sc, q, {variables: {"id" => 1000}}) ==
    {data: {"human" => {"name" => "Luke Skywalker"}}}
  assert request(sc, q) ==
    {
      errors: [
        {
          message: "Variable \"$id\" of required type \"ID!\" was not provided.",
          locations: [{line: 1, column: 8}]
        }
      ]
    }
  assert request(sc, q, {variables: {"id" => nil}}).errors ==
    [
      {
        message: "Variable \"$id\" of non-null type \"ID!\" must not be null.",
        locations: [{line: 1, column: 8}]
      }
    ]
  bad = request(
    sc,
    "query ($e: Episode) { hero(episode: $e) { id } }",
    {variables: {"e" => "SITH"}}
  )
  assert bad ==
    {
      errors: [
        {
          message: "Variable \"$e\" got invalid value \"SITH\"; Value \"SITH\" does not exist in \"Episode\" enum.",
          locations: [{line: 1, column: 8}]
        }
      ]
    }
  stars = "mutation ($r: ReviewInput!) { createReview(review: $r) { stars } }"
  assert request(sc, stars, {variables: {"r" => {"stars" => 2_147_483_647}}}) ==
    {data: {"createReview" => {"stars" => 2_147_483_647}}}
  over = request(sc, stars, {variables: {"r" => {"stars" => 2_147_483_648}}})
  assert over[:data].nil?
  assert size(over.errors) == 1
  assert request(
    sc,
    "query ($u: Unit = FOOT) { human(id: \"1000\") { height(unit: $u) } }"
  ) == {data: {"human" => {"height" => 5.64}}}
end

test "a mutation coerces its input object and resolvers see the context"
  sc = fixture
  m = "mutation ($r: ReviewInput!) { createReview(episode: JEDI, review: $r) { episode stars commentary } }"
  assert request(sc, m, {variables: {"r" => {"stars" => 5}}}) ==
    {
      data: {
        "createReview" => {
          "episode" => "JEDI",
          "stars" => 5,
          "commentary" => nil
        }
      }
    }
  assert request(
    sc,
    m,
    {variables: {"r" => {"stars" => 5, "x" => 1}}}
  ).errors ==
    [
      {
        message: "Variable \"$r\" got invalid value {\"stars\":5,\"x\":1}; Field \"x\" is not defined by type \"ReviewInput\".",
        locations: [{line: 1, column: 11}]
      }
    ]
  assert request(sc, "{ whoami }", {context: {user: "leia"}}) ==
    {data: {"whoami" => "leia"}}
end

test "introspection reads the schema, its deprecations included on request"
  sc = fixture
  r = request(
    sc,
    "{ __schema { queryType { name } mutationType { name } subscriptionType { name } } }"
  )
  assert r ==
    {
      data: {
        "__schema" => {
          "queryType" => {"name" => "Query"},
          "mutationType" => {"name" => "Mutation"},
          "subscriptionType" => {"name" => "Subscription"}
        }
      }
    }
  names = map(
    (t) -> t["name"],
    request(sc, "{ __schema { types { name } } }").data["__schema"]["types"]
  )
  assert contains(names, "Human") and contains(names, "__TypeKind")
  d = request(
    sc,
    "{ __type(name: \"Droid\") { kind fields { name } all: fields(includeDeprecated: true) { name isDeprecated deprecationReason } interfaces { name } } }"
  )
  t = d.data["__type"]
  assert t["kind"] == "OBJECT"
  assert map((f) -> f["name"], t["fields"]) ==
    %w[id name friends primaryFunction]
  assert last(t["all"]) ==
    {
      "name" => "legacyCode",
      "isDeprecated" => true,
      "deprecationReason" => "Use primaryFunction."
    }
  assert t["interfaces"] == [{"name" => "Character"}]
  e = request(
    sc,
    "{ __type(name: \"Unit\") { enumValues(includeDeprecated: true) { name isDeprecated deprecationReason } } }"
  )
  assert e.data["__type"]["enumValues"] ==
    [
      {"name" => "METER", "isDeprecated" => false, "deprecationReason" => nil},
      {
        "name" => "FOOT",
        "isDeprecated" => true,
        "deprecationReason" => "Use METER."
      }
    ]
  w = request(
    sc,
    "{ __type(name: \"Query\") { fields { name type { kind name ofType { kind name ofType { kind name } } } } } }"
  )
  chars_field = find_first(
    (f) -> f["name"] == "characters",
    w.data["__type"]["fields"]
  )
  assert chars_field["type"] ==
    {
      "kind" => "NON_NULL",
      "name" => nil,
      "ofType" => {
        "kind" => "LIST",
        "name" => nil,
        "ofType" => {"kind" => "NON_NULL", "name" => nil}
      }
    }
  assert request(sc, "{ __type(name: \"Nope\") { name } }") ==
    {data: {"__type" => nil}}
  p = request(
    sc,
    "{ __type(name: \"Character\") { possibleTypes { name } } h: __type(name: \"Human\") { fields { name args { name defaultValue } } } }"
  )
  assert p.data["__type"]["possibleTypes"] ==
    [{"name" => "Droid"}, {"name" => "Human"}]
  height = find_first((f) -> f["name"] == "height", p.data["h"]["fields"])
  assert height["args"] == [{"name" => "unit", "defaultValue" => "METER"}]
  dirs = request(sc, "{ __schema { directives { name locations } } }")
  assert map((x) -> x["name"], dirs.data["__schema"]["directives"]) ==
    %w[skip include deprecated specifiedBy]
  reason = request(
    sc,
    "{ __schema { directives { args { name defaultValue } } } }"
  )
  assert reason.data["__schema"]["directives"][2] ==
    {
      "args" => [
        {"name" => "reason", "defaultValue" => "\"No longer supported\""}
      ]
    }
end

test "a subscription is a source stream and a function from event to response"
  sc = fixture
  doc = value(
    parse("subscription ($e: Episode) { reviewAdded(episode: $e) { stars episode } }")
  )
  s = subscribe(sc, doc, {variables: {"e" => "JEDI"}, context: {user: "leia"}})
  assert ok?(s)
  assert value(s).source == {topic: "reviews", episode: "JEDI", by: "leia"}
  respond = value(s).respond
  assert respond({reviewAdded: {stars: 4, episode: "JEDI"}}) ==
    {data: {"reviewAdded" => {"stars" => 4, "episode" => "JEDI"}}}
  assert respond({reviewAdded: {episode: "JEDI"}}) ==
    {
      data: {"reviewAdded" => nil},
      errors: [
        {
          message: "Cannot return null for non-nullable field Review.stars.",
          locations: [{line: 1, column: 57}],
          path: %w[reviewAdded stars]
        }
      ]
    }
  q = subscribe(sc, value(parse("{ hero { id } }")))
  assert errors_of(q) ==
    [
      {
        message: "The operation is not a subscription.",
        locations: [{line: 1, column: 1}]
      }
    ]
  n = subscribe(sc, value(parse("subscription { other }")))
  assert errors_of(n) ==
    [
      {
        message: "Subscription field \"Subscription.other\" has no subscribe function.",
        locations: [{line: 1, column: 16}],
        path: ["other"]
      }
    ]
end

test "a request refused at parse or validation answers errors and no data"
  sc = fixture
  assert request(sc, "{ hero {") ==
    {
      errors: [
        {
          message: "Syntax Error: 1:9: expected \"}\", found end of input",
          locations: [{line: 1, column: 9}]
        }
      ]
    }
  assert request(sc, "{ nope }") ==
    {
      errors: [
        {message: "Query has no field nope", locations: [{line: 1, column: 3}]}
      ]
    }
  assert execute(sc, value(parse("{ nope hero { id } }"))) ==
    {data: {"hero" => {"id" => "2001"}}}
  assert execute(
    sc,
    value(parse("query A { hero { id } } query B { strict }")),
    {operation_name: "A"}
  ) == {data: {"hero" => {"id" => "2001"}}}
  assert execute(
    sc,
    value(parse("query A { hero { id } } query B { strict }"))
  ).errors ==
    [
      {
        message: "Must provide operation name if query contains multiple operations.",
        locations: []
      }
    ]
end

test "a valid document has no findings, and a bad one is refused with its locations"
  sc = fixture
  ok_doc = value(
    parse("query Q($e: Episode, $u: Unit = FOOT) { hero(episode: $e) { name ...F ... on Droid { primaryFunction } } human(id: \"1\") { height(unit: $u) } } fragment F on Character { id friends { name } }")
  )
  assert findings(ok_doc, sc) == []
  bad = findings(value(parse(join_lines(["{", "  hero { nope } }"]))), sc)
  assert size(bad) == 1
  assert first(bad).locations == [{line: 2, column: 10}]
  assert kind(refusal_of(validate(value(parse("{ nope }")), sc))) == :invalid
  assert kind(refusal_of(parse("{ a "))) == :parse_error
end

test "the schema renders as SDL that danpen reads back"
  text = sdl(fixture)
  assert contains?(
    text,
    "legacyCode: String @deprecated(reason: \"Use primaryFunction.\")"
  )
  assert contains?(text, "height(unit: Unit = METER): Float")
  assert contains?(text, "type Human implements Character {")
  assert contains?(text, "union SearchResult = Human | Droid")
  assert toriyose::danpen::check(text) == []
end

test "as_enum_value and as_ref read text and keep built values"
  assert as_enum_value("RED")[:name] == "RED"
  assert as_enum_value({name: "RED"}) == {name: "RED"}
  assert as_ref("Int") == type_ref("Int")
  assert as_ref(nil).nil?
end
