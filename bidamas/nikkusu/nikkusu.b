use("junjo", [:upper_bound])
use("retsu", [:first, :flat_map, :is_empty, :last, :rest, :running_sum, :size])

# nikkusu (ニックス) — Nix source as data: rnix's lossless tree from nix_parse, and the queries a linter asks of it (attrpath bindings, calls by head, with scopes, angle paths, option declarations).

def read(source)
  t = nix_parse(source)
  {
    source:,
    root: get(t, :root),
    errors: get(t, :errors),
    line_starts: cons(
      0,
      running_sum(map((l) -> length(l) + 1, split(source, "\n")))
    )
  }
end

def kind(n)
  if n == nil
    nil
  else
    get(n, :kind)
  end
end

def token?(n)
  get(n, :text) != nil
end

def kids(n)
  cs = get(n, :children)
  if cs == nil
    []
  else
    cs
  end
end

def nodes_of(n)
  filter((c) -> get(c, :children) != nil, kids(n))
end

def trivia?(n)
  kind(n) == "TOKEN_WHITESPACE" or kind(n) == "TOKEN_COMMENT"
end

def significant(n)
  filter((c) -> not trivia?(c), kids(n))
end

def text(n)
  if token?(n)
    get(n, :text)
  else
    join(map(text, kids(n)), "")
  end
end

def code(n)
  if token?(n)
    if trivia?(n)
      ""
    else
      get(n, :text)
    end
  else
    join(map(code, kids(n)), "")
  end
end

def line_of(doc, offset)
  upper_bound(get(doc, :line_starts), offset)
end

def line_count(n)
  size(split(text(n), "\n"))
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
    [
      "NODE_ROOT",
      "NODE_APPLY",
      "NODE_PAREN",
      "NODE_LIST",
      "NODE_IF_ELSE",
      "NODE_WITH",
      "NODE_BIN_OP",
      "NODE_LAMBDA",
      "NODE_ASSERT"
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
    start: get(n, :start)
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
    value = nth(1, parts)
    if value == nil
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
      flat_map((c) -> bindings_in(c, [], :let, nil), lets),
      bindings_in(body, prefix, scope, outer)
    )
  elsif k == "NODE_ATTR_SET"
    flat_map((c) -> bindings_in(c, prefix, :attrs, outer), nodes_of(n))
  elsif passes_path?(k)
    flat_map((c) -> bindings_in(c, prefix, scope, outer), nodes_of(n))
  else
    flat_map((c) -> bindings_in(c, [], :nested, outer), nodes_of(n))
  end
end

def under?(b, prefix)
  p = get(b, :path)
  size(p) >= size(prefix) and take(size(prefix), p) == prefix
end

def module_path(b)
  config_relative(get(b, :path))
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
    append(args_of(first(parts)), [nth(1, parts)])
  else
    []
  end
end

def call(n)
  h = head_of(n)
  {
    head: code(h),
    head_node: h,
    args: args_of(n),
    node: n,
    start: get(n, :start)
  }
end

def calls(root)
  calls_in(root, false)
end

def calls_in(n, as_head)
  if kind(n) == "NODE_APPLY"
    parts = nodes_of(n)
    inner = append(
      calls_in(first(parts), true),
      flat_map((c) -> calls_in(c, false), rest(parts))
    )
    if as_head
      inner
    else
      cons(call(n), inner)
    end
  else
    flat_map((c) -> calls_in(c, false), nodes_of(n))
  end
end

def head_name(c)
  last(split(get(c, :head), "."))
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
    fn(w)
      {namespace: code(first(nodes_of(w))), node: w, start: get(w, :start)}
    end,
    of_kind("NODE_WITH", root)
  )
end

def angle_paths(root)
  map(
    (p) -> {path: code(p), node: p, start: get(p, :start)},
    of_kind("NODE_PATH_SEARCH", root)
  )
end

def option_calls()
  ["mkOption", "mkEnableOption", "mkPackageOption", "mkSinkUndeclaredOptions"]
end

def options_roots(root)
  filter(
    fn(b)
      o = get(b, :outer)
      get(b, :scope) == :attrs and
        first(get(b, :path)) == "options" and
        (o == nil or first(o) != "options") and
        (size(get(b, :path)) > 1 or kind(get(b, :value)) == "NODE_ATTR_SET")
    end,
    bindings(root)
  )
end

def option_declarations(root)
  append(
    map(
      (b) -> {at: get(b, :dotted), node: get(b, :node), start: get(b, :start)},
      options_roots(root)
    ),
    map(
      (c) -> {at: get(c, :head), node: get(c, :node), start: get(c, :start)},
      calls_named(root, option_calls)
    )
  )
end

def attr(set, name)
  hit = filter(
    (b) -> get(b, :path) == [name],
    flat_map((c) -> bindings_in(c, [], :attrs, nil), nodes_of(set))
  )
  if is_empty(hit)
    nil
  else
    get(first(hit), :value)
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
  "{ config, lib, ... }:\nlet cfg = config.pleme.x; in {\n  options.pleme.x.enable = lib.mkEnableOption \"x\";\n  config = lib.mkIf cfg.enable {\n    systemd.services.x = { };\n    environment.etc.\"a b\".text = \"hi\";\n    inherit (cfg) port;\n  };\n}\n"
end

def dotted_of(doc)
  map((b) -> get(b, :dotted), bindings(get(doc, :root)))
end

test "read: the tree is lossless, error-free, and lines count from one"
  d = read(sample)
  assert text(get(d, :root)) == sample
  assert get(d, :errors) == []
  assert line_of(d, 0) == 1
  assert line_of(d, 22) == 2
  assert line_of(d, length(sample) - 1) == 9
end

test "read on empty source is a root with one error and no bindings"
  assert kind(nil) == nil
  d = read("")
  assert kind(get(d, :root)) == "NODE_ROOT"
  assert size(get(d, :errors)) == 1
  assert bindings(get(d, :root)) == []
  assert calls(get(d, :root)) == []
end

test "bindings: nested sets and wrappers give dotted paths, let and inherit are scoped"
  d = read(sample)
  ds = dotted_of(d)
  assert member?("options.pleme.x.enable", ds) == true
  assert member?("config.systemd.services.x", ds) == true
  assert member?("config.environment.etc.a b.text", ds) == true
  assert member?("config.port", ds) == true
  lets = filter((b) -> get(b, :scope) == :let, bindings(get(d, :root)))
  assert map((b) -> get(b, :dotted), lets) == ["cfg"]
  assert member?("cfg", filter((x) -> x != "cfg", ds)) == false
end

test "module_path drops a leading config, and under? reads a prefix"
  d = read(sample)
  b = first(
    filter(
      (b) -> get(b, :dotted) == "config.systemd.services.x",
      bindings(get(d, :root))
    )
  )
  assert module_path(b) == ["systemd", "services", "x"]
  assert under?(b, ["config", "systemd"]) == true
  assert under?(b, ["systemd"]) == false
end

test "calls: a curried call is one call with its head and every argument"
  d = read("lib.nixosSystem { system = \"x\"; } // f a (g b)")
  cs = calls(get(d, :root))
  assert map((c) -> get(c, :head), cs) == ["lib.nixosSystem", "f", "g"]
  assert size(get(nth(1, cs), :args)) == 2
  assert head_name(first(cs)) == "nixosSystem"
  assert map(
    (c) -> get(c, :head),
    calls_named(get(d, :root), ["nixosSystem", "darwinSystem"])
  ) ==
    ["lib.nixosSystem"]
  assert calls_named(get(d, :root), ["darwinSystem"]) == []
end

test "with scopes and angle paths are found, and comments never are"
  d = read("# with pkgs; <nixpkgs>\nwith pkgs; [ (import <nixpkgs> { }) ]")
  assert map((w) -> get(w, :namespace), withs(get(d, :root))) == ["pkgs"]
  assert map((p) -> get(p, :path), angle_paths(get(d, :root))) == ["<nixpkgs>"]
  assert withs(get(read("{ a = 1; }"), :root)) == []
end

test "option declarations come from options bindings and mkOption calls"
  d = read(sample)
  os = option_declarations(get(d, :root))
  assert map((o) -> get(o, :at), os) ==
    ["options.pleme.x.enable", "lib.mkEnableOption"]
  assert option_declarations(get(read("{ a.options = 1; }"), :root)) == []
  assert option_declarations(get(read("{ options = [ 1 ]; }"), :root)) == []
  assert size(option_declarations(get(read("{ options = { }; }"), :root))) == 1
end

test "attr reads one attribute of a set literal, and module_function? a module"
  d = read("{ url = \"u\"; sha256 = \"h\"; }")
  set = first(nodes_of(get(d, :root)))
  assert string_content(attr(set, "url")) == "u"
  assert attr(set, "hash") == nil
  m = first(nodes_of(get(read(sample), :root)))
  assert module_function?(m) == true
  assert module_function?(first(nodes_of(get(read("{ lib }: { }"), :root)))) ==
    false
end

test "string_content and line_count read a string's body"
  d = read("''\n  a\n  b\n''")
  s = first(nodes_of(get(d, :root)))
  assert line_count(s) == 4
  assert string_content(first(nodes_of(get(read("\"x${y}z\""), :root)))) ==
    "x${y}z"
  assert literal_string?(first(nodes_of(get(read("\"x${y}\""), :root)))) ==
    false
end
