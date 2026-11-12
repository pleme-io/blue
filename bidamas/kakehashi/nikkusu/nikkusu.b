@moduledoc """
nikkusu (ニックス) — Nix source as data: rnix's lossless tree from nix_parse, and the queries a linter asks of it (attrpath bindings, calls by head, with scopes, angle paths, option declarations).

    withs(get(read("{ a = 1; }"), :root)) #=> []
"""

use("junjo", [:upper_bound])
use("kansuu", [:maybe])
use("retsu", %i[first flat_map is_empty last rest running_sum size])

@doc """
read: Nix source parsed into a document: the source, rnix's lossless tree as `root`, its parse errors, and where each line starts.

    read("{ a = 1; }")[:errors] #=> []
    kind(read("")[:root]) #=> "NODE_ROOT"
"""
def read(source)
  t = nix_parse(source)
  {
    source:,
    root: t[:root],
    errors: t[:errors],
    line_starts: cons(
      0,
      running_sum(map((l) -> length(l) + 1, split(source, line_break)))
    )
  }
end

@doc """
kind: the rnix kind of a node or token, nil for nothing.

    kind(read("{ }")[:root]) #=> "NODE_ROOT"
    kind(nil) #=> nil
"""
def kind(n)
  maybe(n, nil, (m) -> m[:kind])
end

@doc """
token?: the element is a token, a leaf holding text, not a node.

    token?(read("{ }")[:root]) #=> false
"""
def token?(n)
  n[:text] != nil
end

@doc """
kids: every child of a node, tokens and trivia included; none for a token.

    size(kids(read("x")[:root])) #=> 1
"""
def kids(n)
  cs = n[:children]
  if cs.nil?
    []
  else
    cs
  end
end

@doc """
nodes_of: the child nodes of a node, without its tokens.

    map(kind, nodes_of(read("{ }")[:root])) #=> ["NODE_ATTR_SET"]
"""
def nodes_of(n)
  filter((c) -> c[:children] != nil, kids(n))
end

@doc """
trivia?: the element is whitespace or a comment, which carries no meaning.

    map(trivia?, kids(read("# c\nx")[:root])) #=> [true, true, false]
"""
def trivia?(n)
  kind(n) == "TOKEN_WHITESPACE" or kind(n) == "TOKEN_COMMENT"
end

@doc """
significant: the children of a node that are not trivia.

    map(kind, significant(read("# c\nx")[:root])) #=> ["NODE_IDENT"]
"""
def significant(n)
  filter((c) -> not trivia?(c), kids(n))
end

@doc """
text: the exact source a node covers, trivia included, so the tree reads back losslessly.

    text(read("{ a = 1; } # c")[:root]) #=> "{ a = 1; } # c"
"""
def text(n)
  if token?(n)
    n[:text]
  else
    join(map(text, kids(n)), "")
  end
end

@doc """
code: the source a node covers with its whitespace and comments dropped, for comparing code by meaning.

    code(read("{ a = 1; } # c")[:root]) #=> "{a=1;}"
"""
def code(n)
  if token?(n)
    if trivia?(n)
      ""
    else
      n[:text]
    end
  else
    join(map(code, kids(n)), "")
  end
end

@doc """
line_of: the line, counted from one, that a byte offset of the document falls on.

    line_of(read(sample), 22) #=> 2
"""
def line_of(doc, offset)
  upper_bound(doc[:line_starts], offset)
end

@doc """
line_count: how many lines a node's source spans.

    line_count(read(join_lines(["{", "}"]))[:root]) #=> 2
"""
def line_count(n)
  size(split(text(n), line_break))
end

@doc """
nodes_where: every node under and including `n` for which `f` holds, in source order.

    size(nodes_where((x) -> kind(x) == "NODE_IDENT", read("f a b")[:root])) #=> 3
"""
def nodes_where(f, n)
  below = append(*map((c) -> nodes_where(f, c), nodes_of(n)))
  if f(n)
    cons(n, below)
  else
    below
  end
end

@doc """
of_kind: every node of one kind under and including `n`.

    map(code, of_kind("NODE_WITH", read("with pkgs; [ ]")[:root])) #=> ["withpkgs;[]"]
"""
def of_kind(k, n)
  nodes_where((x) -> kind(x) == k, n)
end

@doc """
string_content: the body of a string node between its quotes, interpolations kept as written; nil for any other node.

    string_content(first(nodes_of(read("\"x${y}z\"")[:root]))) #=> "x${y}z"
"""
def string_content(n)
  if kind(n) == "NODE_STRING"
    join(
      map(
        text,
        filter(
          fn(c)
            kind(c) == "TOKEN_STRING_CONTENT" or kind(c) == "NODE_INTERPOL"
          end,
          kids(n)
        )
      ),
      ""
    )
  end
end

@doc """
literal_string?: the node is a string with no interpolation, so its content is a fixed value.

    literal_string?(first(nodes_of(read("\"x\"")[:root]))) #=> true
    literal_string?(first(nodes_of(read("\"x${y}\"")[:root]))) #=> false
"""
def literal_string?(n)
  kind(n) == "NODE_STRING" and
    is_empty(filter((c) -> kind(c) == "NODE_INTERPOL", kids(n)))
end

@doc """
segment: one part of an attribute path as a name: an identifier, or a literal string's content without its quotes.

    dotted_of(read("{ a.\"b c\" = 1; }")) #=> ["a.b c"]
"""
def segment(n)
  k = kind(n)
  if k == "NODE_IDENT"
    code(n)
  elsif k == "NODE_STRING" and literal_string?(n)
    string_content(n)
  else
    code(n)
  end
end

@doc """
attrpath: the names of an attribute path node, one per segment.

    map((b) -> b[:path], bindings(read("{ a.b = 1; }")[:root])) #=> [["a", "b"]]
"""
def attrpath(n)
  map(segment, nodes_of(n))
end

@doc """
passes_path?: a node of this kind passes its enclosing attribute path on to the sets inside it, as a function application or an `if` does.

    passes_path?("NODE_APPLY") #=> true
    passes_path?("NODE_STRING") #=> false
"""
def passes_path?(k)
  member?(
    k,
    %w[
      NODE_ROOT
      NODE_APPLY
      NODE_PAREN
      NODE_LIST
      NODE_IF_ELSE
      NODE_WITH
      NODE_BIN_OP
      NODE_LAMBDA
      NODE_ASSERT
    ]
  )
end

@doc """
binding: one binding as data: its path, dotted path, node, value, scope, enclosing path and start.

    binding({start: 3}, ["a", "b"], :attrs, nil, nil)[:dotted] #=> "a.b"
"""
def binding(n, path, scope, value, outer)
  {
    path:,
    dotted: join(path, "."),
    node: n,
    value:,
    scope:,
    outer:,
    start: n[:start]
  }
end

@doc """
bindings: every binding of a source tree with its full attribute path; nested sets and wrappers extend the path, `let` and `inherit` bindings carry their own scope.

    dotted_of(read("{ a = { b = 1; }; }")) #=> ["a", "a.b"]
"""
def bindings(root)
  bindings_in(root, [], :attrs, nil)
end

@doc """
bindings_in: the bindings under a node, given the path, scope and enclosing path it sits in.

    map((b) -> b[:scope], bindings_in(read("let x = 1; in { }")[:root], [], :attrs, nil)) #=> [:let]
"""
def bindings_in(n, prefix, scope, outer)
  k = kind(n)
  if k == "NODE_ATTRPATH_VALUE"
    parts = nodes_of(n)
    path = append(prefix, attrpath(first(parts)))
    value = parts[1]
    if value.nil?
      [binding(n, path, scope, nil, outer)]
    else
      cons(
        binding(n, path, scope, value, outer),
        bindings_in(value, path, :attrs, path)
      )
    end
  elsif k == "NODE_INHERIT"
    names = filter((c) -> kind(c) == "NODE_IDENT", nodes_of(n))
    from = filter((c) -> kind(c) == "NODE_INHERIT_FROM", nodes_of(n))
    map(
      (i) -> binding(n, append(prefix, [code(i)]), scope, first(from), outer),
      names
    )
  elsif k == "NODE_LET_IN"
    parts = nodes_of(n)
    lets = filter(
      (c) -> kind(c) == "NODE_ATTRPATH_VALUE" or kind(c) == "NODE_INHERIT",
      parts
    )
    body = last(parts)
    append(
      flat_map(lets, (c) -> bindings_in(c, [], :let, nil)),
      bindings_in(body, prefix, scope, outer)
    )
  elsif k == "NODE_ATTR_SET"
    flat_map(nodes_of(n), (c) -> bindings_in(c, prefix, :attrs, outer))
  elsif passes_path?(k)
    flat_map(nodes_of(n), (c) -> bindings_in(c, prefix, scope, outer))
  else
    flat_map(nodes_of(n), (c) -> bindings_in(c, [], :nested, outer))
  end
end

@doc """
under?: the binding's path starts with the prefix.

    under?({path: ["config", "a"]}, ["config"]) #=> true
    under?({path: ["a"]}, ["config"]) #=> false
"""
def under?(b, prefix)
  p = b[:path]
  size(p) >= size(prefix) and take(size(prefix), p) == prefix
end

@doc """
module_path: the option path a module binding sets, without a leading `config`.

    module_path({path: ["config", "systemd", "services"]}) #=> ["systemd", "services"]
"""
def module_path(b)
  config_relative(b[:path])
end

@doc """
config_relative: a path without its leading `config`, so `config.a.b` and `a.b` name the same option.

    config_relative(["config", "a"]) #=> ["a"]
    config_relative(["a"]) #=> ["a"]
"""
def config_relative(p)
  if first(p) == "config"
    rest(p)
  else
    p
  end
end

@doc """
head_of: the function a curried application calls, under every argument.

    code(head_of(first(nodes_of(read("f a b")[:root])))) #=> "f"
"""
def head_of(n)
  if kind(n) == "NODE_APPLY"
    head_of(first(nodes_of(n)))
  else
    n
  end
end

@doc """
args_of: the arguments of a curried application, in order; none for a node that is not one.

    map(code, args_of(first(nodes_of(read("f a b")[:root])))) #=> ["a", "b"]
"""
def args_of(n)
  if kind(n) == "NODE_APPLY"
    parts = nodes_of(n)
    append(args_of(first(parts)), [parts[1]])
  else
    []
  end
end

@doc """
call: one application as data: its head's code and node, its arguments, the node and its start.

    call(first(nodes_of(read("lib.mkIf c x")[:root])))[:head] #=> "lib.mkIf"
"""
def call(n)
  h = head_of(n)
  {head: code(h), head_node: h, args: args_of(n), node: n, start: n[:start]}
end

@doc """
calls: every call in a source tree, a curried call counted once with all its arguments.

    map((c) -> c[:head], calls(read("f a (g b)")[:root])) #=> ["f", "g"]
"""
def calls(root)
  calls_in(root, false)
end

@doc """
calls_in: the calls under a node; `as_head` marks a node that is itself the head of an outer application, so it is not counted twice.

    size(calls_in(read("f a b")[:root], false)) #=> 1
"""
def calls_in(n, as_head)
  if kind(n) == "NODE_APPLY"
    parts = nodes_of(n)
    inner = append(
      calls_in(first(parts), true),
      flat_map(rest(parts), (c) -> calls_in(c, false))
    )
    if as_head
      inner
    else
      cons(call(n), inner)
    end
  else
    flat_map(nodes_of(n), (c) -> calls_in(c, false))
  end
end

@doc """
head_name: the last name of a call's head, so `lib.mkIf` and `mkIf` match the same word.

    head_name({head: "lib.nixosSystem"}) #=> "nixosSystem"
"""
def head_name(c)
  last(split(c[:head], "."))
end

@doc """
called?: the call's head name is one of the names.

    called?({head: "lib.mkIf"}, ["mkIf"]) #=> true
"""
def called?(c, names)
  member?(head_name(c), names)
end

@doc """
named: the calls whose head name is one of the names.

    named([{head: "lib.mkIf"}, {head: "f"}], ["mkIf"]) #=> [{head: "lib.mkIf"}]
"""
def named(cs, names)
  filter((c) -> called?(c, names), cs)
end

@doc """
calls_named: every call in a source tree whose head name is one of the names.

    map((c) -> c[:head], calls_named(read("lib.nixosSystem { } // f a")[:root], ["nixosSystem"])) #=> ["lib.nixosSystem"]
"""
def calls_named(root, names)
  named(calls(root), names)
end

@doc """
withs: every `with` scope in a source tree and the namespace it opens.

    map((w) -> w[:namespace], withs(read("with pkgs; [ ]")[:root])) #=> ["pkgs"]
"""
def withs(root)
  map(
    (w) -> {namespace: code(first(nodes_of(w))), node: w, start: w[:start]},
    of_kind("NODE_WITH", root)
  )
end

@doc """
angle_paths: every `<...>` search path in a source tree, which depends on NIX_PATH.

    map((p) -> p[:path], angle_paths(read("import <nixpkgs> { }")[:root])) #=> ["<nixpkgs>"]
"""
def angle_paths(root)
  map(
    (p) -> {path: code(p), node: p, start: p[:start]},
    of_kind("NODE_PATH_SEARCH", root)
  )
end

@doc """
option_calls: the library functions that declare a module option.

    member?("mkEnableOption", option_calls) #=> true
"""
def option_calls()
  %w[mkOption mkEnableOption mkPackageOption mkSinkUndeclaredOptions]
end

@doc """
options_roots: the bindings that declare options under a module's `options`, the outermost one of each.

    map((b) -> b[:dotted], options_roots(read(sample)[:root])) #=> ["options.pleme.x.enable"]
"""
def options_roots(root)
  filter(
    fn(b)
      o = b[:outer]
      b[:scope] == :attrs and
        first(b[:path]) == "options" and
        (o.nil? or first(o) != "options") and
        (size(b[:path]) > 1 or kind(b[:value]) == "NODE_ATTR_SET")
    end,
    bindings(root)
  )
end

@doc """
option_declarations: everywhere a source tree declares an option: each `options` binding and each option function call.

    map((o) -> o[:at], option_declarations(read(sample)[:root])) #=> ["options.pleme.x.enable", "lib.mkEnableOption"]
"""
def option_declarations(root)
  append(
    map(
      (b) -> {at: b[:dotted], node: b[:node], start: b[:start]},
      options_roots(root)
    ),
    map(
      (c) -> {at: c[:head], node: c[:node], start: c[:start]},
      calls_named(root, option_calls)
    )
  )
end

@doc """
attr: the value node of one attribute of a set literal, nil when the set does not bind it.

    string_content(attr(first(nodes_of(read("{ url = \"u\"; }")[:root])), "url")) #=> "u"
    attr(first(nodes_of(read("{ }")[:root])), "url") #=> nil
"""
def attr(set, name)
  hit = filter(
    (b) -> b[:path] == [name],
    flat_map(nodes_of(set), (c) -> bindings_in(c, [], :attrs, nil))
  )
  if is_empty(hit)
    nil
  else
    first(hit)[:value]
  end
end

@doc """
module_function?: the node is a module written as a function that takes `config`.

    module_function?(first(nodes_of(read(sample)[:root]))) #=> true
    module_function?(first(nodes_of(read("{ lib }: { }")[:root]))) #=> false
"""
def module_function?(n)
  kind(n) == "NODE_LAMBDA" and
    member?(
      "config",
      map(
        (e) -> code(first(nodes_of(e))),
        of_kind("NODE_PAT_ENTRY", first(nodes_of(n)))
      )
    )
end

@doc """
sample: a small NixOS module with options, a `let`, a quoted name and an `inherit`, for tests and examples.

    read(sample)[:errors] #=> []
"""
def sample()
  unlines(
    [
      "{ config, lib, ... }:",
      "let cfg = config.pleme.x; in {",
      "  options.pleme.x.enable = lib.mkEnableOption \"x\";",
      "  config = lib.mkIf cfg.enable {",
      "    systemd.services.x = { };",
      "    environment.etc.\"a b\".text = \"hi\";",
      "    inherit (cfg) port;",
      "  };",
      "}"
    ]
  )
end

@doc """
dotted_of: the dotted path of every binding in a document.

    dotted_of(read("{ a.b = 1; }")) #=> ["a.b"]
"""
def dotted_of(doc)
  map((b) -> b[:dotted], bindings(doc[:root]))
end

@doc """
nix_keywords: the words Nix reserves, which an attribute name or a reference may not be bare.

    member?("inherit", nix_keywords) #=> true
"""
def nix_keywords()
  %w[assert else if in inherit let or rec then with]
end

@doc """
nix_identifier?: whether `name` is a bare Nix identifier: a letter or `_`, then letters, digits, `_`, `'` or `-`, and no keyword.

    nix_identifier?("hostName") #=> true
    nix_identifier?("x-y'") #=> true
    nix_identifier?("2fa") #=> false
    nix_identifier?("/") #=> false
    nix_identifier?("rec") #=> false
"""
def nix_identifier?(name)
  letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"
  cs = chars(name)
  not is_empty(cs) and
    contains?(letters, first(cs)) and
    every?((c) -> contains?("#{letters}0123456789'-", c), rest(cs)) and
    not member?(name, nix_keywords)
end

@doc """
nix_ref: a Nix expression named by a dotted path of identifiers, for `render`: a package, a library function, an argument. Anything else raises :bad_option.

    render(nix_ref("pkgs.git")) #=> "pkgs.git"
    (nix_ref("pkgs.git; x") rescue :refused) #=> :refused
"""
def nix_ref(path)
  if not string?(path) or not every?(nix_identifier?, split(path, "."))
    raise(:bad_option, "a Nix reference is a dotted path of identifiers")
  end
  {nix_ref: path}
end

@doc """
nix_apply: a Nix function, named by `nix_ref`, applied to one argument, for `render`.

    render(nix_apply(nix_ref("lib.mkDefault"), 3)) #=> "(lib.mkDefault 3)"
"""
def nix_apply(f, arg)
  if not nix_ref?(f)
    raise(:bad_option, "a Nix application names its function with nix_ref")
  end
  {nix_apply: f, arg:}
end

@doc """
nix_ref?: whether a value is a reference `nix_ref` made.

    nix_ref?(nix_ref("pkgs.git")) #=> true
    nix_ref?({a: 1}) #=> false
"""
def nix_ref?(v)
  map?(v) and size(map_entries(v)) == 1 and string?(v[:nix_ref])
end

@doc """
nix_apply?: whether a value is an application `nix_apply` made.

    nix_apply?(nix_apply(nix_ref("lib.mkForce"), 1)) #=> true
    nix_apply?(nix_ref("lib.mkForce")) #=> false
"""
def nix_apply?(v)
  map?(v) and size(map_entries(v)) == 2 and nix_ref?(v[:nix_apply])
end

@doc """
nix_string: a string as a Nix string literal, escaped so it reads back as the same text and interpolates nothing.

    nix_string("a\"b") #=> "\"a\\\"b\""
    nix_string("${x}") #=> "\"\\${x}\""
"""
def nix_string(s)
  out = map(
    fn(c)
      if c == "\\"
        "\\\\"
      elsif c == "\""
        "\\\""
      elsif c == "$"
        "\\$"
      elsif c == line_break
        "\\n"
      elsif c == "\t"
        "\\t"
      elsif c == "\r"
        "\\r"
      else
        c
      end
    end,
    chars(s)
  )
  "\"#{join(out, "")}\""
end

@doc """
nix_key: an attribute name, bare when it is an identifier and quoted when not.

    nix_key(:hostName) #=> "hostName"
    nix_key("/") #=> "\"/\""
"""
def nix_key(k)
  name = if string?(k)
    k
  elsif symbol?(k) or keyword?(k)
    to_s(k)
  else
    raise(:bad_option, "an attribute name is a string or a symbol")
  end
  if nix_identifier?(name)
    name
  else
    nix_string(name)
  end
end

@doc """
scalar?: whether a value renders on one line with nothing nested: what keeps a list on one line.

    scalar?("a") #=> true
    scalar?([1]) #=> false
"""
def scalar?(v)
  v.nil? or boolean?(v) or integer?(v) or float?(v) or string?(v) or nix_ref?(v)
end

@doc """
pad: the indent of a nesting depth, two spaces a level.

    pad(2) #=> "    "
"""
def pad(depth)
  join(map((_i) -> "  ", range(0, depth)), "")
end

@doc """
render: blue data as Nix source: nil, booleans, numbers, strings, lists and maps, with `nix_ref` and `nix_apply` for expressions. A symbol value or any other value raises :bad_option, since it has no one Nix reading.

    render({a: [1, -2], b: nil}) #=> "{\n  a = [ 1 (-2) ];\n  b = null;\n}"
    (render({a: :b}) rescue :refused) #=> :refused
"""
def render(v)
  render_at(v, 0)
end

@doc """
render_at: `render` at a nesting depth, which indents what it nests.

    render_at([{a: 1}], 1) #=> "[\n    {\n      a = 1;\n    }\n  ]"
"""
def render_at(v, depth)
  if v.nil?
    "null"
  elsif boolean?(v)
    to_s(v)
  elsif integer?(v)
    if v < 0
      "(#{to_s(v)})"
    else
      to_s(v)
    end
  elsif float?(v)
    to_s(v)
  elsif string?(v)
    nix_string(v)
  elsif nix_ref?(v)
    v[:nix_ref]
  elsif nix_apply?(v)
    "(#{v[:nix_apply][:nix_ref]} #{render_at(v[:arg], depth)})"
  elsif list?(v)
    render_list(v, depth)
  elsif map?(v)
    render_set(v, depth)
  else
    raise(
      :bad_option,
      "render takes nil, booleans, numbers, strings, lists, maps and Nix references, not #{to_s(v)}"
    )
  end
end

@doc """
render_list: a list as Nix source: on one line when every element is a scalar, one element a line when not.

    render_list([1, 2], 0) #=> "[ 1 2 ]"
"""
def render_list(xs, depth)
  if is_empty(xs)
    "[ ]"
  elsif every?(scalar?, xs)
    "[ #{join(map((x) -> render_at(x, depth), xs), " ")} ]"
  else
    inner = map((x) -> "#{pad(depth + 1)}#{render_at(x, depth + 1)}", xs)
    join(append(["["], inner, ["#{pad(depth)}]"]), line_break)
  end
end

@doc """
render_set: a map as a Nix attribute set, one binding a line.

    render_set({a: true}, 0) #=> "{\n  a = true;\n}"
"""
def render_set(m, depth)
  entries = map_entries(m)
  if is_empty(entries)
    "{ }"
  else
    inner = map(
      fn(e)
        "#{pad(depth + 1)}#{nix_key(first(e))} = #{render_at(e[1], depth + 1)};"
      end,
      entries
    )
    join(append(["{"], inner, ["#{pad(depth)}}"]), line_break)
  end
end

@doc """
module: a NixOS module as Nix source: a function of `args` (and `...`) returning `config` rendered.

    module(["pkgs"], {a: 1}) #=> "{ pkgs, ... }:\n{\n  a = 1;\n}\n"
"""
def module(args, config)
  head = join(append(args, ["..."]), ", ")
  "{ #{head} }:#{line_break}#{render(config)}#{line_break}"
end

test "read: the tree is lossless, error-free, and lines count from one"
  d = read(sample)
  assert text(d[:root]) == sample
  assert d[:errors] == []
  assert line_of(d, 0) == 1
  assert line_of(d, 22) == 2
  assert line_of(d, length(sample) - 1) == 9
end

test "read on empty source is a root with one error and no bindings"
  assert kind(nil).nil?
  d = read("")
  assert kind(d[:root]) == "NODE_ROOT"
  assert size(d[:errors]) == 1
  assert bindings(d[:root]) == []
  assert calls(d[:root]) == []
end

test "bindings: nested sets and wrappers give dotted paths, let and inherit are scoped"
  d = read(sample)
  ds = dotted_of(d)
  assert member?("options.pleme.x.enable", ds) == true
  assert member?("config.systemd.services.x", ds) == true
  assert member?("config.environment.etc.a b.text", ds) == true
  assert member?("config.port", ds) == true
  lets = filter((b) -> b[:scope] == :let, bindings(d[:root]))
  assert map((b) -> b[:dotted], lets) == ["cfg"]
  assert member?("cfg", filter((x) -> x != "cfg", ds)) == false
end

test "module_path drops a leading config, and under? reads a prefix"
  d = read(sample)
  b = first(
    filter((b) -> b[:dotted] == "config.systemd.services.x", bindings(d[:root]))
  )
  assert module_path(b) == %w[systemd services x]
  assert under?(b, %w[config systemd]) == true
  assert under?(b, ["systemd"]) == false
end

test "calls: a curried call is one call with its head and every argument"
  d = read("lib.nixosSystem { system = \"x\"; } // f a (g b)")
  cs = calls(d[:root])
  assert map((c) -> c[:head], cs) == %w[lib.nixosSystem f g]
  assert size(cs[1][:args]) == 2
  assert head_name(first(cs)) == "nixosSystem"
  assert map(
    (c) -> c[:head],
    calls_named(d[:root], %w[nixosSystem darwinSystem])
  ) == ["lib.nixosSystem"]
  assert calls_named(d[:root], ["darwinSystem"]) == []
end

test "with scopes and angle paths are found, and comments never are"
  d = read(
    join_lines(
      ["# with pkgs; <nixpkgs>", "with pkgs; [ (import <nixpkgs> { }) ]"]
    )
  )
  assert map((w) -> w[:namespace], withs(d[:root])) == ["pkgs"]
  assert map((p) -> p[:path], angle_paths(d[:root])) == ["<nixpkgs>"]
  assert withs(read("{ a = 1; }")[:root]) == []
end

test "option declarations come from options bindings and mkOption calls"
  d = read(sample)
  os = option_declarations(d[:root])
  assert map((o) -> o[:at], os) == %w[options.pleme.x.enable lib.mkEnableOption]
  assert option_declarations(read("{ a.options = 1; }")[:root]) == []
  assert option_declarations(read("{ options = [ 1 ]; }")[:root]) == []
  assert size(option_declarations(read("{ options = { }; }")[:root])) == 1
end

test "attr reads one attribute of a set literal, and module_function? a module"
  d = read("{ url = \"u\"; sha256 = \"h\"; }")
  set = first(nodes_of(d[:root]))
  assert string_content(attr(set, "url")) == "u"
  assert attr(set, "hash").nil?
  m = first(nodes_of(read(sample)[:root]))
  assert module_function?(m) == true
  assert module_function?(first(nodes_of(read("{ lib }: { }")[:root]))) == false
end

test "string_content and line_count read a string's body"
  d = read(join_lines(["''", "  a", "  b", "''"]))
  s = first(nodes_of(d[:root]))
  assert line_count(s) == 4
  assert string_content(first(nodes_of(read("\"x${y}z\"")[:root]))) == "x${y}z"
  assert literal_string?(first(nodes_of(read("\"x${y}\"")[:root]))) == false
end

test "render reads back through Nix's own parser with no error, for every shape"
  shapes = [
    nil,
    true,
    0,
    -7,
    "a \"quoted\" ${x} \\ line",
    [],
    {},
    [1, "two", nix_ref("pkgs.git")],
    [{a: 1}, [2]],
    {"/" => {device: "/dev/sda1"}, "with-dash" => 1, "rec" => 2},
    nix_apply(nix_ref("lib.mkForce"), {a: [1]})
  ]
  assert every?((v) -> read(render(v))[:errors] == [], shapes)
  assert read(module(%w[pkgs lib], {a: nix_ref("pkgs.git")}))[:errors] == []
end

test "a string renders to a literal whose content is the string"
  s = "a \"b\" ${c} \\ d"
  lit = first(nodes_of(read(render(s))[:root]))
  assert literal_string?(lit)
  assert string_content(lit) == "a \\\"b\\\" \\${c} \\\\ d"
end

test "render refuses a value with no one Nix reading, and a reference that is not a path"
  assert (render(:a) rescue :refused) == :refused
  assert (render({a: 1.0 / 0.0}) rescue :ok) != nil
  assert (nix_ref("a b") rescue :refused) == :refused
  assert (nix_apply("lib.mkForce", 1) rescue :refused) == :refused
  assert (nix_key(1) rescue :refused) == :refused
end
