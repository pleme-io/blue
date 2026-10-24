use("danpen")
use("jisho", [:has?])
use("kyohi", [:ok, :ok?, :refusal, :refusal_of, :refused, :value, :why])
use("moji", [:starts_with])

use(
  "retsu",
  [
    :contains,
    :count_where,
    :enumerate,
    :find_first,
    :first,
    :flat_map,
    :index_of,
    :is_empty,
    :last,
    :rest,
    :size,
    :update_at
  ]
)

# outou (応答) — a GraphQL request answered: a schema of blue resolvers, execution to {data, errors}, introspection and subscription events, over danpen's documents.
#
# Written to the GraphQL specification, October 2021 edition
# (https://spec.graphql.org/October2021/): the type system of §3,
# introspection of §4, execution of §6 and the response shape of §7.
# danpen parses the document and judges it against this schema's SDL (§2,
# §5); a parse or validation failure is a kyohi refusal whose why is the list
# of GraphQL errors with their locations, refused per document. A schema is
# a value built from type constructors, and a resolver is a blue function of
# (parent, args, context). No I/O happens here: host effects enter only
# through the resolvers a service supplies. `from_model` derives object types
# and the query root from an entity map, as a pure function, so a model
# renders straight into a schema.

def errors_of(result)
  why(refusal_of(result))
end

def type_ref(text)
  op = first(danpen::parse("query ($t: #{text}) { a }").definitions)
  first(op.variables).type
end

def named(name)
  {kind: :named, name:}
end

def list_of(ref)
  {kind: :list_of, of: as_ref(ref)}
end

def non_null(ref)
  {kind: :non_null, of: as_ref(ref)}
end

def as_ref(ref)
  if string?(ref)
    type_ref(ref)
  else
    ref
  end
end

def non_null?(ref)
  ref.kind == :non_null
end

def nullable(ref)
  if non_null?(ref)
    ref.of
  else
    ref
  end
end

def deprecation(d)
  if d == true
    "No longer supported"
  else
    d
  end
end

def field(name, ref, opts?)
  o = opts or {}
  {
    name:,
    type: as_ref(ref),
    args: get(o, :args) or [],
    resolve: get(o, :resolve),
    subscribe: get(o, :subscribe),
    deprecated: deprecation(get(o, :deprecated)),
    description: get(o, :description)
  }
end

def arg(name, ref, opts?)
  o = opts or {}
  {
    name:,
    type: as_ref(ref),
    default: get(o, :default),
    has_default: has?(o, :default),
    deprecated: deprecation(get(o, :deprecated)),
    description: get(o, :description)
  }
end

def enum_value(name, opts?)
  o = opts or {}
  {
    name:,
    deprecated: deprecation(get(o, :deprecated)),
    description: get(o, :description)
  }
end

def as_enum_value(v)
  if string?(v)
    enum_value(v)
  else
    v
  end
end

def indexed(fields)
  zipmap(map((f) -> f.name, fields), fields)
end

def object_type(name, fields, opts?)
  o = opts or {}
  {
    kind: "OBJECT",
    name:,
    fields:,
    field_index: indexed(fields),
    interfaces: get(o, :interfaces) or [],
    description: get(o, :description)
  }
end

def interface_type(name, fields, opts?)
  o = opts or {}
  {
    kind: "INTERFACE",
    name:,
    fields:,
    field_index: indexed(fields),
    interfaces: get(o, :interfaces) or [],
    resolve_type: get(o, :resolve_type),
    description: get(o, :description)
  }
end

def union_type(name, members, opts?)
  o = opts or {}
  {
    kind: "UNION",
    name:,
    members:,
    resolve_type: get(o, :resolve_type),
    description: get(o, :description)
  }
end

def enum_type(name, values, opts?)
  o = opts or {}
  {
    kind: "ENUM",
    name:,
    values: map(as_enum_value, values),
    description: get(o, :description)
  }
end

def input_type(name, fields, opts?)
  o = opts or {}
  {
    kind: "INPUT_OBJECT",
    name:,
    fields:,
    field_index: indexed(fields),
    description: get(o, :description)
  }
end

def scalar_type(name, opts?)
  o = opts or {}
  {
    kind: "SCALAR",
    name:,
    serialize: get(o, :serialize),
    parse: get(o, :parse),
    specified_by: get(o, :specified_by),
    description: get(o, :description)
  }
end

def directive(name, locations, args, opts?)
  o = opts or {}
  {
    name:,
    locations:,
    args:,
    repeatable: get(o, :repeatable) == true,
    description: get(o, :description)
  }
end

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

def builtin_directives()
  [
    directive(
      "skip",
      ["FIELD", "FRAGMENT_SPREAD", "INLINE_FRAGMENT"],
      [arg("if", "Boolean!", {description: "Skipped when true."})],
      {
        description: "Directs the executor to skip this field or fragment when the `if` argument is true."
      }
    ),
    directive(
      "include",
      ["FIELD", "FRAGMENT_SPREAD", "INLINE_FRAGMENT"],
      [arg("if", "Boolean!", {description: "Included when true."})],
      {
        description: "Directs the executor to include this field or fragment only when the `if` argument is true."
      }
    ),
    directive(
      "deprecated",
      ["FIELD_DEFINITION", "ENUM_VALUE"],
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

def output_kind?(k)
  contains(["SCALAR", "OBJECT", "INTERFACE", "UNION", "ENUM"], k)
end

def input_kind?(k)
  contains(["SCALAR", "ENUM", "INPUT_OBJECT"], k)
end

def leaf_kind?(k)
  contains(["SCALAR", "ENUM"], k)
end

def composite_kind?(k)
  contains(["OBJECT", "INTERFACE", "UNION"], k)
end

def kind_named(types, name)
  t = get(types, name)
  if t.nil?
    nil
  else
    t.kind
  end
end

def ref_whys(types, owner, ref, ok_kind)
  k = kind_named(types, danpen::base_name(ref))
  if k.nil?
    ["#{owner} refers to the unknown type #{danpen::base_name(ref)}"]
  elsif not ok_kind(k)
    ["#{owner} cannot have the type #{danpen::base_name(ref)}"]
  else
    []
  end
end

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

def root_or(spec_name, types, fallback)
  if spec_name != nil
    spec_name
  elsif get(types, fallback) != nil
    fallback
  end
end

def schema(spec)
  all = append(builtin_scalars, introspection_types, get(spec, :types) or [])
  names = map((t) -> t.name, all)
  dupes = filter(
    (i) -> index_of(names, nth(i, names)) < i,
    range(0, size(names))
  )
  types = zipmap(names, all)
  query = root_or(get(spec, :query), types, "Query")
  whys = append(
    map((i) -> "the type #{nth(i, names)} is defined twice", dupes),
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
    mutation: root_or(get(spec, :mutation), types, "Mutation"),
    subscription: root_or(get(spec, :subscription), types, "Subscription"),
    directives: append(builtin_directives, get(spec, :directives) or []),
    description: get(spec, :description)
  }
end

def lookup(sc, name)
  get(sc.types, name)
end

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
        fn(e)
          nth(1, e).kind == "OBJECT" and contains(nth(1, e).interfaces, name)
        end,
        map_entries(sc.types)
      )
    )
  else
    []
  end
end

def applies?(sc, object_name, condition)
  t = lookup(sc, condition)
  t != nil and contains(possible_types(sc, condition), object_name)
end

def overlap?(sc, a, b)
  pb = possible_types(sc, b)
  count_where((x) -> contains(pb, x), possible_types(sc, a)) > 0
end

def typename_field()
  field("__typename", "String!")
end

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
        resolve: (_p, a, _c) -> type_view_named(sc, get(a, "name"))
      }
    )
  elsif t.nil? or get(t, :field_index).nil?
    nil
  else
    get(get(t, :field_index), fname)
  end
end

def type_view(sc, ref)
  {sc:, ref:}
end

def type_view_named(sc, name)
  if lookup(sc, name).nil?
    nil
  else
    type_view(sc, named(name))
  end
end

def def_of(p)
  if p.ref.kind == :named
    lookup(p.sc, p.ref.name)
  end
end

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

def kind_in?(p, kinds)
  def_of(p) != nil and contains(kinds, def_of(p).kind)
end

def shown_deprecated(xs, include)
  if include == true
    xs
  else
    filter((x) -> x.deprecated.nil?, xs)
  end
end

def view_fields(p, include)
  if kind_in?(p, ["OBJECT", "INTERFACE"])
    map((f) -> {sc: p.sc, f:}, shown_deprecated(def_of(p).fields, include))
  end
end

def view_interfaces(p)
  if kind_in?(p, ["OBJECT", "INTERFACE"])
    map((i) -> type_view(p.sc, named(i)), def_of(p).interfaces)
  end
end

def view_possible(p)
  if kind_in?(p, ["INTERFACE", "UNION"])
    map((n) -> type_view(p.sc, named(n)), possible_types(p.sc, p.ref.name))
  end
end

def view_enum_values(p, include)
  if kind_in?(p, ["ENUM"])
    map((v) -> {ev: v}, shown_deprecated(def_of(p).values, include))
  end
end

def view_input_fields(p)
  if kind_in?(p, ["INPUT_OBJECT"])
    map((a) -> {sc: p.sc, a:}, def_of(p).fields)
  end
end

def view_of_type(p)
  if p.ref.kind == :named
    nil
  else
    type_view(p.sc, p.ref.of)
  end
end

def view_description(p)
  if def_of(p).nil?
    nil
  else
    def_of(p).description
  end
end

def view_specified_by(p)
  if kind_in?(p, ["SCALAR"])
    def_of(p).specified_by
  end
end

def view_name(p)
  if p.ref.kind == :named
    p.ref.name
  end
end

def default_value_text(p)
  if p.a.has_default
    render_value(p.sc, p.a.type, p.a.default)
  end
end

def include_arg()
  [arg("includeDeprecated", "Boolean", {default: false})]
end

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
            resolve: (p, a, _c) -> view_fields(p, get(a, "includeDeprecated"))
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
            resolve: fn(p, a, _c)
              view_enum_values(p, get(a, "includeDeprecated"))
            end
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
      [
        "SCALAR",
        "OBJECT",
        "INTERFACE",
        "UNION",
        "ENUM",
        "INPUT_OBJECT",
        "LIST",
        "NON_NULL"
      ]
    ),
    enum_type(
      "__DirectiveLocation",
      [
        "QUERY",
        "MUTATION",
        "SUBSCRIPTION",
        "FIELD",
        "FRAGMENT_DEFINITION",
        "FRAGMENT_SPREAD",
        "INLINE_FRAGMENT",
        "VARIABLE_DEFINITION",
        "SCHEMA",
        "SCALAR",
        "OBJECT",
        "FIELD_DEFINITION",
        "ARGUMENT_DEFINITION",
        "INTERFACE",
        "UNION",
        "ENUM",
        "ENUM_VALUE",
        "INPUT_OBJECT",
        "INPUT_FIELD_DEFINITION"
      ]
    )
  ]
end

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
      [true, nth(1, e)]
    end
  end
end

def shown_value(v)
  json_stringify(v) rescue to_s(v)
end

def int_range?(v)
  v >= -2_147_483_648 and v <= 2_147_483_647
end

def enum_names(t)
  map((v) -> v.name, t.values)
end

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

def coerce_input(sc, ref, v)
  if non_null?(ref)
    if v.nil?
      raise(
        :coerce,
        "Expected non-nullable type \"#{danpen::type_text(ref)}\" not to be null."
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

def coerce_input_object(sc, t, v)
  if not map?(v)
    raise(:coerce, "Expected type \"#{t.name}\" to be an object.")
  end
  map(
    fn(e)
      if get(get(t, :field_index), to_s(first(e))).nil?
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
        assoc(acc, f.name, coerce_input(sc, f.type, nth(1, e)))
      elsif f.has_default
        assoc(acc, f.name, f.default)
      elsif non_null?(f.type)
        raise(
          :coerce,
          "Field \"#{t.name}.#{f.name}\" of required type \"#{danpen::type_text(f.type)}\" was not provided."
        )
      else
        acc
      end
    end,
    {},
    t.fields
  )
end

def render_ast(ast)
  danpen::value_text(nil, ast)
end

def ast_value(ast)
  case ast.kind
  when :int
    to_int(ast.text)
  when :float
    to_float(ast.text)
  when :enum
    ast.name
  else
    get(ast, :value)
  end
end

def loc_of(node)
  at = get(node, :at)
  if at.nil?
    []
  else
    [{line: first(at), column: nth(1, at)}]
  end
end

def literal_scalar(t, ast, vars)
  k = ast.kind
  case t.name
  when "Int"
    if k == :int and int_range?(ast_value(ast))
      ast_value(ast)
    else
      raise(
        :coerce,
        "Int cannot represent non-integer value: #{render_ast(ast)}"
      )
    end
  when "Float"
    if k == :int or k == :float
      to_float(ast_value(ast))
    else
      raise(
        :coerce,
        "Float cannot represent non numeric value: #{render_ast(ast)}"
      )
    end
  when "String"
    if k == :string
      ast_value(ast)
    else
      raise(
        :coerce,
        "String cannot represent a non string value: #{render_ast(ast)}"
      )
    end
  when "Boolean"
    if k == :boolean
      ast_value(ast)
    else
      raise(
        :coerce,
        "Boolean cannot represent a non boolean value: #{render_ast(ast)}"
      )
    end
  when "ID"
    if k == :string
      ast_value(ast)
    elsif k == :int
      ast.text
    else
      raise(:coerce, "ID cannot represent value: #{render_ast(ast)}")
    end
  else
    coerce_scalar_input(t, plain_value(ast, vars))
  end
end

def plain_value(ast, vars)
  case ast.kind
  when :var
    nth(1, entry_of(vars, ast.name))
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

def value_from_ast(sc, ref, ast, vars)
  if ast.kind == :var
    v = nth(1, entry_of(vars, ast.name))
    if v.nil? and non_null?(ref)
      raise(
        :coerce,
        "Expected non-nullable type \"#{danpen::type_text(ref)}\" not to be null."
      )
    end
    v
  elsif non_null?(ref)
    if ast.kind == :null
      raise(
        :coerce,
        "Expected value of type \"#{danpen::type_text(ref)}\", found null."
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
        "Enum \"#{t.name}\" cannot represent value: #{render_ast(ast)}"
      )
    end
  else
    object_from_ast(sc, t, ast, vars)
  end
end

def object_from_ast(sc, t, ast, vars)
  if ast.kind != :object
    raise(
      :coerce,
      "Expected value of type \"#{t.name}\", found #{render_ast(ast)}."
    )
  end
  map(
    fn(f)
      if get(get(t, :field_index), f.name).nil?
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
          "Field \"#{t.name}.#{f.name}\" of required type \"#{danpen::type_text(f.type)}\" was not provided."
        )
      else
        acc
      end
    end,
    {},
    t.fields
  )
end

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
      "{#{join(map((f) -> "#{f.name}: #{render_value(sc, f.type, nth(1, entry_of(v, f.name)))}", shown), ", ")}}"
    elsif string?(v)
      json_stringify(v)
    else
      to_s(v)
    end
  end
end

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
              "Argument \"#{d.name}\" of required type \"#{danpen::type_text(d.type)}\" was provided the variable \"$#{node.value.name}\" which was not provided a runtime value."
            else
              "Argument \"#{d.name}\" of required type \"#{danpen::type_text(d.type)}\" was not provided."
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
            "Argument \"#{d.name}\" has invalid value #{render_ast(node.value)}: #{e.message}"
          )
        end
      end
    end,
    {},
    defs
  )
end

def coerce_variables(sc, op, given)
  reduce(
    fn(acc, vd)
      name = vd.name
      e = entry_of(given or {}, name)
      ref = vd.type
      fault = fn(message)
        {**acc, errors: append(acc.errors, [gql_error(message, loc_of(vd))])}
      end
      if lookup(sc, danpen::base_name(ref)).nil? or
          not input_kind?(lookup(sc, danpen::base_name(ref)).kind)
        fault(
          "Variable \"$#{name}\" expected value of type \"#{danpen::type_text(ref)}\" which cannot be used as an input type."
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
          "Variable \"$#{name}\" of required type \"#{danpen::type_text(ref)}\" was not provided."
        )
      elsif non_null?(ref) and nth(1, e).nil?
        fault(
          "Variable \"$#{name}\" of non-null type \"#{danpen::type_text(ref)}\" must not be null."
        )
      elsif not first(e)
        acc
      else
        begin
          {
            **acc,
            values: assoc(acc.values, name, coerce_input(sc, ref, nth(1, e)))
          }
        rescue :coerce as err
          fault(
            "Variable \"$#{name}\" got invalid value #{shown_value(nth(1, e))}; #{err.message}"
          )
        end
      end
    end,
    {values: {}, errors: []},
    op.variables
  )
end

def operations(doc)
  filter((d) -> d.kind == :operation, doc.definitions)
end

def fragment_defs(doc)
  filter((d) -> d.kind == :fragment, doc.definitions)
end

def fragments_of(doc)
  defs = fragment_defs(doc)
  zipmap(map((f) -> f.name, defs), defs)
end

def request_error(message, locations)
  refused(refusal(:request, [gql_error(message, locations)]))
end

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
    op = find_first((o) -> get(o, :name) == name, ops)
    if op.nil?
      request_error("Unknown operation named \"#{name}\".", [])
    else
      ok(op)
    end
  end
end

def response_key(node)
  node.alias or node.name
end

def directive_value(env, dirs, name)
  d = find_first((x) -> x.name == name, dirs)
  if d.nil?
    nil
  else
    a = find_first((x) -> x.name == "if", d.arguments)
    value_from_ast(env.sc, non_null("Boolean"), a.value, env.vars) rescue nil
  end
end

def included?(env, dirs)
  directive_value(env, dirs, "skip") != true and
    directive_value(env, dirs, "include") != false
end

def add_to_group(groups, key, node)
  i = index_of(map(first, groups), key)
  if i < 0
    append(groups, [[key, [node]]])
  else
    update_at(groups, i, [key, append(nth(1, nth(i, groups)), [node])])
  end
end

def collect_fields(env, tname, sels)
  first(collect_into(env, tname, sels, [[], []]))
end

def collect_into(env, tname, sels, st)
  reduce((acc, s) -> collect_one(env, tname, s, acc), st, sels)
end

def collect_one(env, tname, s, st)
  if not included?(env, s.directives)
    st
  elsif s.kind == :field
    [add_to_group(first(st), response_key(s), s), nth(1, st)]
  elsif s.kind == :spread
    if contains(nth(1, st), s.name)
      st
    else
      frag = get(env.frags, s.name)
      seen = [first(st), append(nth(1, st), [s.name])]
      if frag.nil? or not applies?(env.sc, tname, frag.on)
        seen
      else
        collect_into(env, tname, frag.selections, seen)
      end
    end
  elsif get(s, :on) != nil and not applies?(env.sc, tname, get(s, :on))
    st
  else
    collect_into(env, tname, s.selections, st)
  end
end

def done(v)
  {value: v, errs: [], bad: false}
end

def failed(message, node, path)
  {value: nil, errs: [{message:, locations: loc_of(node), path:}], bad: true}
end

def response(data, errs)
  if is_empty(errs)
    {data:}
  else
    {data:, errors: errs}
  end
end

def exec_selection_set(env, tname, sels, parent, path)
  reduce(
    fn(acc, g)
      r = exec_field(env, tname, parent, nth(1, g), append(path, [first(g)]))
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

def default_resolve(parent, name)
  nth(1, entry_of(parent, name))
end

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
          complete(
            env,
            ref.of,
            nodes,
            nth(1, e),
            append(path, [first(e)]),
            owner
          )
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

def resolve_type(env, t, v)
  if t.resolve_type.nil?
    nth(1, entry_of(v, "__typename"))
  else
    pick = t.resolve_type
    pick(v, env.ctx)
  end
end

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

def env_for(sc, doc, values, opts)
  {sc:, frags: fragments_of(doc), vars: values, ctx: get(opts, :context)}
end

def prepared(sc, doc, opts)
  found = operation_of(doc, get(opts, :operation_name))
  if not ok?(found)
    found
  else
    op = value(found)
    cv = coerce_variables(sc, op, get(opts, :variables))
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
      get(o, :root),
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
    node = first(nth(1, g))
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

def gql_error(message, locations)
  {message:, locations:}
end

def parse(text)
  ok(danpen::parse(text, {spans: true}))
rescue :parse_error as e
  refused(
    refusal(:parse_error, [gql_error("Syntax Error: #{e.message}", [e.data])])
  )
end

def user_type?(t)
  not starts_with(t.name, "__") and
    not contains(["Int", "Float", "String", "Boolean", "ID"], t.name)
end

def deprecated_text(d)
  if d.nil?
    ""
  else
    " @deprecated(reason: #{json_stringify(d)})"
  end
end

def arg_text(sc, a)
  default = if a.has_default
    " = #{render_value(sc, a.type, a.default)}"
  else
    ""
  end
  "#{a.name}: #{danpen::type_text(a.type)}#{default}"
end

def args_text(sc, args)
  if is_empty(args)
    ""
  else
    "(#{join(map((a) -> arg_text(sc, a), args), ", ")})"
  end
end

def field_text(sc, f)
  "  #{f.name}#{args_text(sc, f.args)}: #{danpen::type_text(f.type)}#{deprecated_text(f.deprecated)}"
end

def braced_lines(lines)
  if is_empty(lines)
    ""
  else
    " {\n#{join(lines, "\n")}\n}"
  end
end

def implements_text(t)
  if is_empty(t.interfaces)
    ""
  else
    " implements #{join(t.interfaces, " & ")}"
  end
end

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

def roots_sdl(sc)
  roots = filter(
    (r) -> nth(1, r) != nil,
    [
      ["query", sc.query],
      ["mutation", sc.mutation],
      ["subscription", sc.subscription]
    ]
  )
  "schema {\n#{join(map((r) -> "  #{first(r)}: #{nth(1, r)}", roots), "\n")}\n}"
end

def sdl(sc)
  types = filter(user_type?, map((e) -> nth(1, e), map_entries(sc.types)))
  join(append([roots_sdl(sc)], map((t) -> type_sdl(sc, t), types)), "\n\n")
end

def findings(doc, sc)
  map(
    (f) -> {message: f.message, locations: loc_of(f), rule: f.rule},
    danpen::check(doc, sdl(sc))
  )
end

def validate(doc, sc)
  found = findings(doc, sc)
  if is_empty(found)
    ok(doc)
  else
    refused(refusal(:invalid, found))
  end
end

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

def lower_first(s)
  cs = chars(s)
  concat(downcase(first(cs)), join(rest(cs), ""))
end

def model_field(e, f)
  scalar = model_scalar(get(f, :type))
  if get(f, :secret) == true or get(f, :public) == false
    [nil, []]
  elsif scalar.nil?
    [
      nil,
      [
        refusal(
          :unknown_type,
          "#{e.name}.#{get(f, :name)} has the type #{to_s(get(f, :type))}, which has no GraphQL scalar"
        )
      ]
    ]
  else
    ref = if get(f, :optional) == true
      scalar
    else
      "#{scalar}!"
    end
    [
      field(
        get(f, :name),
        ref,
        {deprecated: get(f, :deprecated), description: get(f, :description)}
      ),
      []
    ]
  end
end

def model_relation(e, r, names)
  if not contains(names, get(r, :entity))
    [
      nil,
      [
        refusal(
          :unknown_entity,
          "#{e.name}.#{get(r, :name)} relates to #{get(r, :entity)}, which is not an entity of the model"
        )
      ]
    ]
  else
    ref = if get(r, :many) == true
      "[#{get(r, :entity)}!]!"
    elsif get(r, :optional) == false
      "#{get(r, :entity)}!"
    else
      get(r, :entity)
    end
    [
      field(
        get(r, :name),
        ref,
        {deprecated: get(r, :deprecated), description: get(r, :description)}
      ),
      []
    ]
  end
end

def kept(pairs)
  filter((x) -> x != nil, map(first, pairs))
end

def plural_of(e)
  get(e, :plural) or "#{lower_first(e.name)}s"
end

def root_fields(e)
  key = get(e, :key) or "id"
  [
    field(lower_first(e.name), e.name, {args: [arg(key, "ID!")]}),
    field(plural_of(e), "[#{e.name}!]!")
  ]
end

def from_model(model)
  ents = get(model, :entities) or []
  names = map((e) -> e.name, ents)
  parts = map(
    fn(e)
      fs = map((f) -> model_field(e, f), get(e, :fields) or [])
      rs = map((r) -> model_relation(e, r, names), get(e, :relations) or [])
      [
        object_type(
          e.name,
          append(kept(fs), kept(rs)),
          {description: get(e, :description)}
        ),
        append(flat_map(fs, (x) -> nth(1, x)), flat_map(rs, (x) -> nth(1, x)))
      ]
    end,
    ents
  )
  uses_time = count_where(
    fn(e)
      count_where((f) -> get(f, :type) == :time, get(e, :fields) or []) > 0
    end,
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
            {description: "An RFC 3339 date and time, as a String."}
          )
        ]
      else
        []
      end
    ),
    refusals: flat_map(parts, (p) -> nth(1, p))
  }
end

def with_resolvers(types, table)
  map(
    fn(t)
      if get(t, :field_index).nil? or t.kind == "INPUT_OBJECT"
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

def people()
  [
    {
      kind: "Human",
      id: "1000",
      name: "Luke Skywalker",
      friends: ["1002", "2001"],
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

def person(id)
  find_first((c) -> c.id == id, people)
end

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
        union_type("SearchResult", ["Human", "Droid"]),
        enum_type(
          "Unit",
          ["METER", enum_value("FOOT", {deprecated: "Use METER."})]
        ),
        enum_type("Episode", ["NEWHOPE", "EMPIRE", "JEDI"]),
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
                  if get(a, "episode") == "EMPIRE"
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
                    episode: get(a, "episode"),
                    stars: a.review.stars,
                    commentary: get(a.review, "commentary")
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
    ["Int", "Float", "String", "Boolean", "ID", "__Schema"]
  ) == ["SCALAR", "SCALAR", "SCALAR", "SCALAR", "SCALAR", "OBJECT"]
  assert [sc.query, sc.mutation, sc.subscription] ==
    ["Query", "Mutation", "Subscription"]
  assert field_def(sc, "Droid", "legacyCode").deprecated ==
    "Use primaryFunction."
  assert field_def(sc, "Query", "old").deprecated == "No longer supported"
  assert danpen::type_text(type_ref("[[Int!]]!")) == "[[Int!]]!"
  assert possible_types(sc, "Character") == ["Droid", "Human"]
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
  assert map((t) -> t.name, d.types) ==
    ["Control", "Evidence", "Query", "DateTime"]
  c = first(d.types)
  assert map((f) -> "#{f.name}: #{danpen::type_text(f.type)}", c.fields) ==
    [
      "id: ID!",
      "title: String!",
      "observedAt: DateTime!",
      "score: Float",
      "evidence: [Evidence!]!"
    ]
  assert nth(2, c.fields).deprecated == "Use evidenceTime."
  assert kyohi::kinds(d.refusals) == [:unknown_type, :unknown_entity]
  assert map((f) -> f.name, nth(2, d.types).fields) ==
    [
      "control",
      "controls",
      "evidence_",
      "evidence"
    ] or
    map((f) -> f.name, nth(2, d.types).fields) ==
      ["control", "controls", "evidence", "evidence"]
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
          path: ["outer", "inner"]
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
          path: ["outer", "sealed"]
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
  assert get(over, :data).nil?
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
    (t) -> get(t, "name"),
    get(
      get(request(sc, "{ __schema { types { name } } }").data, "__schema"),
      "types"
    )
  )
  assert contains(names, "Human") and contains(names, "__TypeKind")
  d = request(
    sc,
    "{ __type(name: \"Droid\") { kind fields { name } all: fields(includeDeprecated: true) { name isDeprecated deprecationReason } interfaces { name } } }"
  )
  t = get(d.data, "__type")
  assert get(t, "kind") == "OBJECT"
  assert map((f) -> get(f, "name"), get(t, "fields")) ==
    ["id", "name", "friends", "primaryFunction"]
  assert last(get(t, "all")) ==
    {
      "name" => "legacyCode",
      "isDeprecated" => true,
      "deprecationReason" => "Use primaryFunction."
    }
  assert get(t, "interfaces") == [{"name" => "Character"}]
  e = request(
    sc,
    "{ __type(name: \"Unit\") { enumValues(includeDeprecated: true) { name isDeprecated deprecationReason } } }"
  )
  assert get(get(e.data, "__type"), "enumValues") ==
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
    (f) -> get(f, "name") == "characters",
    get(get(w.data, "__type"), "fields")
  )
  assert get(chars_field, "type") ==
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
  assert get(get(p.data, "__type"), "possibleTypes") ==
    [{"name" => "Droid"}, {"name" => "Human"}]
  height = find_first(
    (f) -> get(f, "name") == "height",
    get(get(p.data, "h"), "fields")
  )
  assert get(height, "args") == [{"name" => "unit", "defaultValue" => "METER"}]
  dirs = request(sc, "{ __schema { directives { name locations } } }")
  assert map(
    (x) -> get(x, "name"),
    get(get(dirs.data, "__schema"), "directives")
  ) == ["skip", "include", "deprecated", "specifiedBy"]
  reason = request(
    sc,
    "{ __schema { directives { args { name defaultValue } } } }"
  )
  assert nth(2, get(get(reason.data, "__schema"), "directives")) ==
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
          path: ["reviewAdded", "stars"]
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
  bad = findings(value(parse("{\n  hero { nope } }")), sc)
  assert size(bad) == 1
  assert first(bad).locations == [{line: 2, column: 10}]
  assert kyohi::kind(refusal_of(validate(value(parse("{ nope }")), sc))) ==
    :invalid
  assert kyohi::kind(refusal_of(parse("{ a "))) == :parse_error
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
  assert danpen::check(text) == []
end
