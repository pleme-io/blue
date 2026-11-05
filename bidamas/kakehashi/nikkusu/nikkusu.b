@moduledoc """
nikkusu (ニックス) — Nix source as data: rnix's lossless tree from nix_parse, and the queries a linter asks of it (attrpath bindings, calls by head, with scopes, angle paths, option declarations).

    withs(get(read("{ a = 1; }"), :root)) #=> []
"""

use("junjo", [:upper_bound])
use("retsu", %i[first flat_map is_empty last rest running_sum size])

@doc """
read: The whole content of a source, by the source's space: in_space("gitto", repo) reads a file at a ref. Raises :usage when no space owns the subject or the space has no handler.
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

def kind(n)
  if n.nil?
    nil
  else
    n[:kind]
  end
end

def token?(n)
  n[:text] != nil
end

def kids(n)
  cs = n[:children]
  if cs.nil?
    []
  else
    cs
  end
end

def nodes_of(n)
  filter((c) -> c[:children] != nil, kids(n))
end

def trivia?(n)
  kind(n) == "TOKEN_WHITESPACE" or kind(n) == "TOKEN_COMMENT"
end

def significant(n)
  filter((c) -> not trivia?(c), kids(n))
end

def text(n)
  if token?(n)
    n[:text]
  else
    join(map(text, kids(n)), "")
  end
end

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

def line_of(doc, offset)
  upper_bound(doc[:line_starts], offset)
end

def line_count(n)
  size(split(text(n), line_break))
end

def nodes_where(f, n)
  below = append(*map((c) -> nodes_where(f, c), nodes_of(n)))
  if f(n)
    cons(n, below)
  else
    below
  end
end

def of_kind(k, n)
  nodes_where((x) -> kind(x) == k, n)
end

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

def literal_string?(n)
  kind(n) == "NODE_STRING" and
    is_empty(filter((c) -> kind(c) == "NODE_INTERPOL", kids(n)))
end

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

def attrpath(n)
  map(segment, nodes_of(n))
end

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

def bindings(root)
  bindings_in(root, [], :attrs, nil)
end

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

def under?(b, prefix)
  p = b[:path]
  size(p) >= size(prefix) and take(size(prefix), p) == prefix
end

def module_path(b)
  config_relative(b[:path])
end

def config_relative(p)
  if first(p) == "config"
    rest(p)
  else
    p
  end
end

def head_of(n)
  if kind(n) == "NODE_APPLY"
    head_of(first(nodes_of(n)))
  else
    n
  end
end

def args_of(n)
  if kind(n) == "NODE_APPLY"
    parts = nodes_of(n)
    append(args_of(first(parts)), [parts[1]])
  else
    []
  end
end

def call(n)
  h = head_of(n)
  {head: code(h), head_node: h, args: args_of(n), node: n, start: n[:start]}
end

def calls(root)
  calls_in(root, false)
end

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

def head_name(c)
  last(split(c[:head], "."))
end

def called?(c, names)
  member?(head_name(c), names)
end

def named(cs, names)
  filter((c) -> called?(c, names), cs)
end

def calls_named(root, names)
  named(calls(root), names)
end

def withs(root)
  map(
    (w) -> {namespace: code(first(nodes_of(w))), node: w, start: w[:start]},
    of_kind("NODE_WITH", root)
  )
end

def angle_paths(root)
  map(
    (p) -> {path: code(p), node: p, start: p[:start]},
    of_kind("NODE_PATH_SEARCH", root)
  )
end

def option_calls()
  %w[mkOption mkEnableOption mkPackageOption mkSinkUndeclaredOptions]
end

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

def dotted_of(doc)
  map((b) -> b[:dotted], bindings(doc[:root]))
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
