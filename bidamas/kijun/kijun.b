use("deeta", [:as_json, :get_str])
use("hadome")
use("kyohi", [:refusal])
use("moji", [:after_first, :before_first, :glob_match?, :lines])

use(
  "nikkusu",
  [
    :angle_paths,
    :args_of,
    :attr,
    :bindings,
    :calls,
    :calls_named,
    :code,
    :config_relative,
    :head_name,
    :kind,
    :line_of,
    :literal_string?,
    :module_function?,
    :module_path,
    :named,
    :nodes_of,
    :nodes_where,
    :option_declarations,
    :string_content
  ]
)

use("retsu", [:first, :flat_map, :is_empty, :last, :rest, :size, :take_n])

use("shisutemu", [:read_or, :status_of, :stderr_of, :stdout_of])
use("shuugou", [:frequencies, :unique])

# kijun (基準) — the standard a private nix fleet repo is held to, as data: layout, expression and evaluated-tree rules, per-entry waivers, and a baseline ratchet.

def fleet_repo(version)
  {
    standard: "fleet-repo",
    version:,
    top: [
      "flake.nix",
      "flake.lock",
      "fleet.nix",
      "lib",
      "modules",
      "profiles",
      "nodes",
      "users",
      "parts",
      "overlays",
      "pkgs",
      "docs",
      "secrets*.yaml",
      ".sops.yaml",
      ".github",
      ".gitignore",
      ".envrc",
      "CLAUDE.md",
      "AGENTS.md",
      "README.md",
      "LICENSE*",
      "nixosConfigurations",
      "darwinConfigurations",
      "homeConfigurations",
      "kijun.b",
      "kijun.baseline"
    ],
    registry: "lib/nodes.nix",
    node_constructor: "mkNode",
    engine: ["parts/fleet.nix"],
    import_routes: [
      "modules/pleme/nixos/default.nix",
      "modules/pleme/darwin/default.nix",
      "lib/fleet-universal-modules.nix",
      "parts/fleet.nix",
      "lib/nodes.nix",
      "nodes/*/default.nix",
      "profiles/*/default.nix"
    ],
    declarers: [
      "modules/pleme/shared/**",
      "modules/pleme/nixos/**",
      "modules/pleme/darwin/**",
      "modules/pleme/home-manager/**"
    ],
    trio_factory: ["mkModuleTrio"],
    concept_consumers: ["modules/**", "profiles/**"],
    configurations: [],
    waivers: [],
    disabled: [],
    baseline: "kijun.baseline"
  }
end

def allow_top(cfg, entries)
  assoc(cfg, :top, append(get(cfg, :top), entries))
end

def configurations(cfg, names)
  assoc(cfg, :configurations, append(get(cfg, :configurations), names))
end

def waive(cfg, rule, glob, reason)
  assoc(cfg, :waivers, append(get(cfg, :waivers), [{rule:, glob:, reason:}]))
end

def disable(cfg, rule, reason)
  assoc(cfg, :disabled, append(get(cfg, :disabled), [{rule:, reason:}]))
end

def finding(rule, file, line, subject, message)
  {rule:, file:, line:, subject:, message:}
end

def at(f, doc, rule, start, subject, message)
  finding(rule, get(f, :path), line_of(doc, start), subject, message)
end

def segments(path)
  split(path, "/")
end

def top_entries(files)
  unique(
    map(
      fn(p)
        s = segments(p)
        if size(s) > 1
          "#{first(s)}/"
        else
          first(s)
        end
      end,
      files
    )
  )
end

def allowed_top?(cfg, entry)
  name = if ends_with?(entry, "/")
    before_first(entry, "/")
  else
    entry
  end
  not is_empty(filter((g) -> glob_match?(g, name), get(cfg, :top)))
end

def check_top(repo)
  map(
    fn(e)
      finding(
        "layout/top-level",
        e,
        0,
        e,
        "#{e} is not an entry the standard allows at the top level"
      )
    end,
    filter(
      (e) -> not allowed_top?(get(repo, :config), e),
      top_entries(get(repo, :files))
    )
  )
end

def node_dirs(files)
  unique(
    map(
      (p) -> nth(1, segments(p)),
      filter(
        (p) -> first(segments(p)) == "nodes" and size(segments(p)) > 2,
        files
      )
    )
  )
end

def node_dir_of(text)
  if contains?(text, "nodes/")
    before_first("#{after_first(text, "nodes/")}/", "/")
  end
end

def declared_nodes(repo)
  cfg = get(repo, :config)
  path = get(cfg, :registry)
  if member?(path, get(repo, :files))
    doc = nikkusu::read(source_of(repo, path))
    filter(
      (d) -> d != nil,
      map(
        fn(c)
          a = first(args_of(get(c, :node)))
          if a != nil and kind(a) == "NODE_ATTR_SET"
            v = attr(a, "nodeDir")
            if v.nil?
              nil
            else
              node_dir_of(code(v))
            end
          end
        end,
        calls_named(get(doc, :root), [get(cfg, :node_constructor)])
      )
    )
  else
    []
  end
end

def check_nodes(repo)
  files = get(repo, :files)
  declared = declared_nodes(repo)
  flat_map(
    fn(n)
      dir = "nodes/#{n}"
      missing_default = if member?("#{dir}/default.nix", files)
        []
      else
        [
          finding(
            "layout/node-shape",
            "#{dir}/",
            0,
            "default.nix",
            "#{dir} has no default.nix: a node directory is selected through its default.nix"
          )
        ]
      end
      missing_layers = if member?(n, declared) and
        not member?("#{dir}/layers.nix", files)
        [
          finding(
            "layout/node-shape",
            "#{dir}/",
            0,
            "layers.nix",
            "#{dir} is a NixOS node (its registry entry names it) with no layers.nix"
          )
        ]
      else
        []
      end
      append(missing_default, missing_layers)
    end,
    node_dirs(files)
  )
end

def shared_modules(files)
  map(
    (p) -> before_first(last(segments(p)), ".nix"),
    filter(
      fn(p)
        glob_match?("modules/pleme/shared/*.nix", p) and
          p != "modules/pleme/shared/default.nix"
      end,
      files
    )
  )
end

def trio_calls(repo, path)
  named(
    calls(get(nikkusu::read(source_of(repo, path)), :root)),
    get(get(repo, :config), :trio_factory)
  )
end

def spec_kind(c)
  a = last(get(c, :args))
  v = if a != nil and kind(a) == "NODE_ATTR_SET"
    attr(a, "kind")
  end
  if v != nil and literal_string?(v)
    string_content(v)
  elsif v.nil?
    "binary"
  else
    "computed"
  end
end

def self_rendering?(repo, m)
  not is_empty(trio_calls(repo, "modules/pleme/shared/#{m}.nix"))
end

def factory_proven?(repo, m)
  cs = trio_calls(repo, "modules/pleme/shared/#{m}.nix")
  not is_empty(cs) and
    is_empty(
      filter(
        (c) -> not member?(spec_kind(c), ["binary", "package", "service"]),
        cs
      )
    )
end

def check_proof(repo)
  files = get(repo, :files)
  map(
    fn(m)
      finding(
        "layout/shared-has-proof",
        "modules/pleme/shared/#{m}.nix",
        0,
        m,
        "the shared module #{m} has no proof harness at parts/#{m}.nix"
      )
    end,
    filter(
      fn(m)
        not member?("parts/#{m}.nix", files) and not factory_proven?(repo, m)
      end,
      shared_modules(files)
    )
  )
end

def route_files(repo)
  files = get(repo, :files)
  filter(
    fn(p)
      not is_empty(
        filter(
          (g) -> glob_match?(g, p),
          get(get(repo, :config), :import_routes)
        )
      )
    end,
    files
  )
end

def check_reachable(repo)
  files = get(repo, :files)
  routes = map(
    (p) -> code(get(nikkusu::read(source_of(repo, p)), :root)),
    route_files(repo)
  )
  map(
    fn(m)
      finding(
        "layout/shared-reachable",
        "modules/pleme/shared/#{m}.nix",
        0,
        m,
        "the shared module #{m} has no renderer of its name and no import route names shared/#{m}.nix"
      )
    end,
    filter(
      fn(m)
        not member?("modules/pleme/nixos/#{m}.nix", files) and
          not member?("modules/pleme/darwin/#{m}.nix", files) and
          is_empty(filter((t) -> contains?(t, "shared/#{m}.nix"), routes)) and
          not self_rendering?(repo, m)
      end,
      shared_modules(files)
    )
  )
end

def binding_finding(rule, f, b, message)
  at(f, get(f, :doc), rule, get(b, :start), get(b, :dotted), message)
end

def module_bindings(f)
  filter((b) -> get(b, :scope) == :attrs, get(f, :bindings))
end

def starts?(path, prefix)
  size(path) >= size(prefix) and take(size(prefix), path) == prefix
end

def check_system_calls(f, repo)
  if not is_empty(
    filter(
      (g) -> glob_match?(g, get(f, :path)),
      get(get(repo, :config), :engine)
    )
  )
    []
  else
    map(
      fn(c)
        at(
          f,
          get(f, :doc),
          "expr/node-system-only-via-mkNode",
          get(c, :start),
          get(c, :head),
          "#{get(c, :head)} builds a system outside the node engine; declare the node through the registry"
        )
      end,
      named(get(f, :calls), ["nixosSystem", "darwinSystem"])
    )
  end
end

def identity?(b)
  p = module_path(b)
  v = get(b, :value)
  if p == ["networking", "hostName"] or p == ["networking", "hostId"]
    true
  elsif size(p) >= 3 and first(p) == "fileSystems" and last(p) == "device"
    v != nil and contains?(code(v), "by-uuid")
  elsif starts?(p, ["sops", "secrets"]) and last(p) == "sopsFile"
    v != nil and contains?(code(v), "nodes/")
  else
    false
  end
end

def check_profile_identity(f, _repo)
  map(
    fn(b)
      binding_finding(
        "expr/profile-no-identity",
        f,
        b,
        "a profile sets #{get(b, :dotted)}, which is a node's identity; set it in the node"
      )
    end,
    filter(identity?, module_bindings(f))
  )
end

def declaration_findings(rule, f, where)
  map(
    fn(d)
      at(
        f,
        get(f, :doc),
        rule,
        get(d, :start),
        get(d, :at),
        "#{where} declares an option (#{get(d, :at)})"
      )
    end,
    option_declarations(get(f, :root))
  )
end

def check_lib_data(f, _repo)
  modules = map(
    fn(l)
      at(
        f,
        get(f, :doc),
        "expr/lib-is-data",
        get(l, :start),
        "module function",
        "a module function (a lambda taking config) lives in lib/, which holds data"
      )
    end,
    nodes_where((n) -> module_function?(n), get(f, :root))
  )
  append(declaration_findings("expr/lib-is-data", f, "lib/"), modules)
end

def platform_prefixes()
  [
    ["systemd"],
    ["launchd"],
    ["environment", "etc"],
    ["environment", "systemPackages"],
    ["networking", "firewall"],
    ["networking", "hosts"],
    ["security", "sudo"],
    ["users", "users"],
    ["boot"],
    ["homebrew"]
  ]
end

def platform_path?(path)
  p = config_relative(path)
  first(path) != "options" and
    not is_empty(filter((x) -> starts?(p, x), platform_prefixes))
end

def emits_platform?(b)
  o = get(b, :outer)
  platform_path?(get(b, :path)) and (o.nil? or not platform_path?(o))
end

def check_shared_emission(f, _repo)
  map(
    fn(b)
      binding_finding(
        "expr/shared-declares-only",
        f,
        b,
        "a shared module emits #{join(module_path(b), ".")}, which only a platform renderer may"
      )
    end,
    filter(emits_platform?, module_bindings(f))
  )
end

def check_shared_platform_question(f, _repo)
  map(
    fn(n)
      at(
        f,
        get(f, :doc),
        "expr/shared-asks-no-platform",
        get(n, :start),
        code(n),
        "a shared module asks #{code(n)}, a rendering decision"
      )
    end,
    nodes_where(
      fn(n)
        kind(n) == "NODE_SELECT" and
          member?(last(split(code(n), ".")), ["isDarwin", "isLinux"])
      end,
      get(f, :root)
    )
  )
end

def check_node_options(f, _repo)
  declaration_findings("expr/nodes-declare-no-options", f, "a node file")
end

def check_angle(f, _repo)
  map(
    fn(p)
      at(
        f,
        get(f, :doc),
        "expr/no-angle-paths",
        get(p, :start),
        get(p, :path),
        "#{get(p, :path)} resolves through NIX_PATH, which a flake does not pin"
      )
    end,
    angle_paths(get(f, :root))
  )
end

def fetchers()
  [
    "fetchTarball",
    "fetchurl",
    "fetchzip",
    "fetchGit",
    "fetchgit",
    "fetchTree",
    "fetchFromGitHub",
    "fetchFromGitLab"
  ]
end

def pin_attrs()
  ["hash", "sha256", "narHash", "outputHash", "rev"]
end

def unpinned?(c)
  a = first(get(c, :args))
  if a.nil?
    false
  elsif kind(a) == "NODE_ATTR_SET"
    is_empty(filter((k) -> attr(a, k) != nil, pin_attrs))
  else
    kind(a) == "NODE_STRING" or kind(a) == "NODE_PATH_ABS"
  end
end

def check_fetch(f, _repo)
  map(
    fn(c)
      at(
        f,
        get(f, :doc),
        "expr/no-unpinned-fetch",
        get(c, :start),
        get(c, :head),
        "#{get(c, :head)} with no hash fetches whatever the server serves today"
      )
    end,
    filter(unpinned?, named(get(f, :calls), fetchers))
  )
end

def script_body(c)
  n = head_name(c)
  args = get(c, :args)
  if n == "writeShellApplication"
    if first(args) != nil and kind(first(args)) == "NODE_ATTR_SET"
      attr(first(args), "text")
    end
  elsif member?(
    n,
    ["runCommand", "runCommandLocal", "runCommandNoCC", "runCommandCC"]
  )
    nth(2, args)
  else
    nth(1, args)
  end
end

def script_lines(body)
  if body.nil? or kind(body) != "NODE_STRING"
    0
  else
    size(filter((l) -> trim(l) != "", lines(string_content(body))))
  end
end

def scripts()
  [
    "writeShellScript",
    "writeShellScriptBin",
    "writeShellApplication",
    "writeScript",
    "writeScriptBin",
    "runCommand",
    "runCommandLocal",
    "runCommandNoCC",
    "runCommandCC"
  ]
end

def check_shell(f, _repo)
  map(
    fn(c)
      at(
        f,
        get(f, :doc),
        "expr/no-shell",
        get(c, :start),
        get(c, :head),
        "#{get(c, :head)} carries #{to_s(script_lines(script_body(c)))} lines of shell; past 3 lines it is a typed tool"
      )
    end,
    filter(
      (c) -> script_lines(script_body(c)) > 3,
      named(get(f, :calls), scripts)
    )
  )
end

def check_parses(f, _repo)
  map(
    fn(e)
      at(
        f,
        get(f, :doc),
        "expr/parses",
        get(e, :start),
        "parse",
        "does not parse: #{get(e, :message)}"
      )
    end,
    take_n(get(get(f, :doc), :errors), 1)
  )
end

def own_file(tree, file)
  own = get(tree, :own)
  if own != nil and own != "" and starts_with?(file, "#{own}/")
    after_first(file, "#{own}/")
  end
end

def check_pleme_declarations(tree, repo)
  declarers = get(get(repo, :config), :declarers)
  flat_map(
    fn(o)
      map(
        fn(d)
          rel = own_file(tree, d)
          where = if rel.nil?
            "outside this repository (#{d})"
          else
            rel
          end
          finding(
            "tree/pleme-options-declared-in-shared",
            if rel.nil?
              "(external)"
            else
              rel
            end,
            0,
            get(o, :path),
            "#{get(o, :path)} is declared in #{where}, not under modules/pleme/{shared,<platform>}"
          )
        end,
        filter(
          fn(d)
            rel = own_file(tree, d)
            rel.nil? or is_empty(filter((g) -> glob_match?(g, rel), declarers))
          end,
          get(o, :declarations)
        )
      )
    end,
    get(tree, :pleme)
  )
end

def check_hostname(tree, _repo)
  flat_map(
    fn(o)
      map(
        fn(d)
          rel = own_file(tree, d)
          file = if rel.nil?
            "(external)"
          else
            rel
          end
          shown = if rel.nil?
            d
          else
            rel
          end
          finding(
            "tree/hostname-from-node",
            file,
            0,
            "#{get(tree, :configuration)} networking.hostName",
            "networking.hostName of #{get(tree, :configuration)} is defined in #{shown}, not under nodes/"
          )
        end,
        filter(
          fn(d)
            rel = own_file(tree, d)
            rel.nil? or not glob_match?("nodes/**", rel)
          end,
          get(o, :definitions)
        )
      )
    end,
    get(tree, :hostname)
  )
end

def declared_at(tree, option)
  hit = filter(
    (o) -> get(o, :path) == option,
    append(get(tree, :pleme), get(tree, :hostname))
  )
  rels = filter(
    (r) -> r != nil,
    map((d) -> own_file(tree, d), flat_map((o) -> get(o, :declarations), hit))
  )
  if is_empty(rels)
    "(external)"
  else
    first(rels)
  end
end

def check_option_evaluates(tree, _repo)
  map(
    fn(b)
      finding(
        "tree/option-evaluates",
        declared_at(tree, get(b, :option)),
        0,
        "#{get(tree, :configuration)} #{get(b, :option)}",
        "#{get(b, :option)} does not evaluate on #{get(tree, :configuration)} (#{get(b, :error)}), so no tree rule sees its definitions there"
      )
    end,
    or_list(get(tree, :blind))
  )
end

def unit_kinds()
  [:shared, :package, :overlay, :registry]
end

def unit(kind_of, name, file, files)
  {kind: kind_of, name:, file:, files:}
end

def nix_under(files, prefix)
  filter((p) -> starts_with?(p, prefix) and ends_with?(p, ".nix"), files)
end

def dir_units(files, root, kind_of, skip, pool)
  depth = size(segments(root))
  under = filter((p) -> starts_with?(p, "#{root}/"), pool)
  singles = map(
    (p) -> unit(kind_of, before_first(nth(depth, segments(p)), ".nix"), p, [p]),
    filter(
      fn(p)
        size(segments(p)) == depth + 1 and
          ends_with?(p, ".nix") and
          not member?(p, skip)
      end,
      under
    )
  )
  dirs = unique(
    map(
      (p) -> nth(depth, segments(p)),
      filter((p) -> size(segments(p)) > depth + 1, under)
    )
  )
  append(
    singles,
    map(
      fn(d)
        unit(kind_of, d, "#{root}/#{d}/", nix_under(files, "#{root}/#{d}/"))
      end,
      dirs
    )
  )
end

def returned_set(n)
  k = kind(n)
  if n.nil?
    nil
  elsif k == "NODE_ATTR_SET"
    n
  elsif k == "NODE_ROOT" or k == "NODE_PAREN"
    returned_set(first(nodes_of(n)))
  elsif k == "NODE_LAMBDA" or k == "NODE_LET_IN"
    returned_set(last(nodes_of(n)))
  end
end

def overlay_units(repo)
  flat_map(
    fn(p)
      set = returned_set(get(nikkusu::read(source_of(repo, p)), :root))
      if set.nil?
        []
      else
        map(
          (a) -> unit(:overlay, a, p, [p]),
          unique(
            map(
              (b) -> first(get(b, :path)),
              filter(
                (b) -> get(b, :scope) == :attrs and get(b, :outer).nil?,
                bindings(set)
              )
            )
          )
        )
      end
    end,
    filter(
      fn(p)
        size(segments(p)) == 2 and
          p != "overlays/default.nix" and
          ends_with?(p, ".nix")
      end,
      nix_under(get(repo, :files), "overlays/")
    )
  )
end

def resolve(segs, acc)
  if is_empty(segs)
    acc
  elsif first(segs) == "." or first(segs) == ""
    resolve(rest(segs), acc)
  elsif first(segs) == ".."
    resolve(
      rest(segs),
      take(
        if is_empty(acc)
          0
        else
          size(acc) - 1
        end,
        acc
      )
    )
  else
    resolve(rest(segs), append(acc, [first(segs)]))
  end
end

def relative_to(file, rel)
  dir = take(size(segments(file)) - 1, segments(file))
  join(resolve(segments(rel), dir), "/")
end

def imported_files(f)
  map(
    (c) -> relative_to(get(f, :path), code(first(get(c, :args)))),
    filter(
      fn(c)
        first(get(c, :args)) != nil and
          kind(first(get(c, :args))) == "NODE_PATH_REL"
      end,
      named(get(f, :calls), ["import"])
    )
  )
end

def spec_names(c)
  a = last(get(c, :args))
  if a.nil? or kind(a) != "NODE_ATTR_SET"
    []
  else
    filter(
      (x) -> x != nil,
      map(
        fn(k)
          v = attr(a, k)
          if v != nil and literal_string?(v)
            string_content(v)
          end
        end,
        ["name", "packageAttr"]
      )
    )
  end
end

def concept_facts(repo)
  cfg = get(repo, :config)
  files = get(repo, :files)
  wanted = filter(
    fn(p)
      ends_with?(p, ".nix") and
        (starts_with?(p, "modules/") or
          starts_with?(p, "profiles/") or
          starts_with?(p, "pkgs/") or
          starts_with?(p, "overlays/") or
          starts_with?(p, "lib/"))
    end,
    files
  )
  facts = map((p) -> file_facts(p, source_of(repo, p)), wanted)
  trio = filter(
    (f) -> not is_empty(named(get(f, :calls), get(cfg, :trio_factory))),
    facts
  )
  consumers = filter(
    fn(f)
      not is_empty(
        filter(
          (g) -> glob_match?(g, get(f, :path)),
          get(cfg, :concept_consumers)
        )
      )
    end,
    facts
  )
  {
    trio_files: map((f) -> get(f, :path), trio),
    names: unique(
      flat_map(
        fn(f)
          flat_map(spec_names, named(get(f, :calls), get(cfg, :trio_factory)))
        end,
        trio
      )
    ),
    trio_imports: unique(flat_map(imported_files, trio)),
    consumed: unique(flat_map(imported_files, consumers))
  }
end

def registry_units(files, facts)
  map(
    (p) -> unit(:registry, before_first(nth(1, segments(p)), ".nix"), p, [p]),
    filter(
      fn(p)
        size(segments(p)) == 2 and
          starts_with?(p, "lib/") and
          ends_with?(p, ".nix") and
          member?(p, get(facts, :consumed))
      end,
      files
    )
  )
end

def concept_units(repo, facts)
  files = get(repo, :files)
  append(
    append(
      dir_units(
        files,
        "modules/pleme/shared",
        :shared,
        ["modules/pleme/shared/default.nix"],
        nix_under(files, "modules/pleme/shared/")
      ),
      dir_units(files, "pkgs", :package, ["pkgs/default.nix"], files)
    ),
    append(overlay_units(repo), registry_units(files, facts))
  )
end

def covered?(u, facts)
  not is_empty(
    filter((p) -> member?(p, get(facts, :trio_files)), get(u, :files))
  ) or
    member?(get(u, :name), get(facts, :names)) or
    get(u, :kind) == :registry and
      member?(get(u, :file), get(facts, :trio_imports))
end

def check_concepts(repo)
  facts = concept_facts(repo)
  map(
    fn(u)
      finding(
        "trio/every-concept",
        get(u, :file),
        0,
        "#{to_s(get(u, :kind))} #{get(u, :name)}",
        "the #{to_s(get(u, :kind))} concept #{get(u, :name)} is not declared through the module-trio factory; declare it with mkModuleTrio { kind = ...; } so it has one type-known interface on every arm"
      )
    end,
    filter((u) -> not covered?(u, facts), concept_units(repo, facts))
  )
end

def rule(id, plane, tier, scope, why, fix, check)
  {id:, plane:, tier:, scope:, why:, fix:, check:}
end

def rules()
  [
    rule(
      "trio/every-concept",
      :layout,
      :gate,
      ["modules/pleme/shared/**", "pkgs/**", "overlays/*.nix", "lib/*.nix"],
      "every concept the fleet manages, a shared module, a package, an overlay-added package or a registry consumed as configuration, has one type-known interface on the nixos, darwin and home-manager arms, so it is declared through the module-trio factory",
      "declare it with mkModuleTrio { kind = \"binary\" | \"package\" | \"registry\" | \"service\"; ... } in its own file, or name it (name or packageAttr) in a trio spec",
      check_concepts
    ),
    rule(
      "layout/top-level",
      :layout,
      :gate,
      ["*"],
      "a fleet repo is one instance of a template: every top-level entry is one the standard names or the instance declares",
      "move the entry under an allowed directory, or name it with allow_top in kijun.b",
      check_top
    ),
    rule(
      "layout/node-shape",
      :layout,
      :gate,
      ["nodes/*/"],
      "a node is a directory selected through default.nix; a registry-declared NixOS node selects layers from layers.nix",
      "add nodes/<n>/default.nix (and layers.nix for a NixOS node), or move what is not a node out of nodes/",
      check_nodes
    ),
    rule(
      "layout/shared-has-proof",
      :layout,
      :gate,
      ["modules/pleme/shared/*.nix"],
      "an option that exists is not a type: each shared options module is proven by a stub-universe harness, unless it is a binary, package or service trio, which substrate's module-trio-kinds matrix proves",
      "add parts/<name>.nix, or declare the concept through mkModuleTrio as a binary, package or service kind; a registry trio keeps its harness, since its projections are its own logic",
      check_proof
    ),
    rule(
      "layout/shared-reachable",
      :layout,
      :gate,
      ["modules/pleme/shared/*.nix"],
      "a shared options module nothing renders or imports is dead weight that looks live; a file that calls mkModuleTrio renders itself, since its module arm picks the platform by class",
      "add modules/pleme/{nixos,darwin}/<name>.nix, import shared/<name>.nix from an import route, or declare the concept through mkModuleTrio",
      check_reachable
    ),
    rule(
      "expr/parses",
      :expression,
      :gate,
      ["**/*.nix"],
      "a file the parser refuses is checked by no rule",
      "fix the syntax error",
      check_parses
    ),
    rule(
      "expr/node-system-only-via-mkNode",
      :expression,
      :gate,
      ["**/*.nix"],
      "a machine is declared through the node engine only; a bespoke nixosSystem or darwinSystem call bypasses the registry and its gates",
      "declare the node in the registry, or name the file in the engine setting",
      check_system_calls
    ),
    rule(
      "expr/profile-no-identity",
      :expression,
      :gate,
      ["profiles/**/*.nix"],
      "a profile is reusable across nodes, so it carries no node identity: hostname, hostId, disk UUIDs, node-scoped secrets",
      "set the value in nodes/<n>/",
      check_profile_identity
    ),
    rule(
      "expr/lib-is-data",
      :expression,
      :gate,
      ["lib/**/*.nix"],
      "data never lives in a module, and lib/ is where data lives: no options, no module functions",
      "move the module to modules/pleme/<layer>/ and keep the data in lib/",
      check_lib_data
    ),
    rule(
      "expr/shared-declares-only",
      :expression,
      :gate,
      ["modules/pleme/shared/**/*.nix"],
      "options never emit: a shared module is imported on both platforms, so platform config there fails the other platform",
      "move the emission to modules/pleme/{nixos,darwin}/<name>.nix",
      check_shared_emission
    ),
    rule(
      "expr/shared-asks-no-platform",
      :expression,
      :advise,
      ["modules/pleme/shared/**/*.nix"],
      "renderers never decide: a shared module that branches on the platform has taken a renderer's decision",
      "split the branch into the platform renderers",
      check_shared_platform_question
    ),
    rule(
      "expr/nodes-declare-no-options",
      :expression,
      :gate,
      ["nodes/**/*.nix"],
      "a node is identity and selection; an option it declares is a primitive nobody else can reach",
      "declare the option in modules/pleme/shared/ and set it from the node",
      check_node_options
    ),
    rule(
      "expr/no-angle-paths",
      :expression,
      :gate,
      ["**/*.nix"],
      "an angle path resolves through NIX_PATH, which the flake lock does not pin",
      "take the input from the flake's inputs",
      check_angle
    ),
    rule(
      "expr/no-unpinned-fetch",
      :expression,
      :gate,
      ["**/*.nix"],
      "a fetch with no hash is whatever the server serves today",
      "add the hash, or make it a flake input",
      check_fetch
    ),
    rule(
      "expr/no-shell",
      :expression,
      :advise,
      ["**/*.nix"],
      "no shell beyond three lines of glue: past that it is a typed tool",
      "write it as a blue program or a typed binary",
      check_shell
    ),
    rule(
      "tree/pleme-options-declared-in-shared",
      :tree,
      :gate,
      ["modules/pleme/**"],
      "the pleme.* surface is declared in one layer, so every node reads one vocabulary",
      "move the declaration to modules/pleme/shared/ or the platform renderer",
      check_pleme_declarations
    ),
    rule(
      "tree/hostname-from-node",
      :tree,
      :gate,
      ["nodes/**"],
      "a hostname is a node's identity, so only the node defines it",
      "define networking.hostName in nodes/<n>/",
      check_hostname
    ),
    rule(
      "tree/option-evaluates",
      :tree,
      :advise,
      ["**"],
      "an option whose definitions cannot be evaluated on a configuration is one no tree rule can see there; it is named alone, and every other option is still read",
      "make the option's default and definitions evaluate on that configuration's class, or declare it only on the class that can",
      check_option_evaluates
    )
  ]
end

def disabled_ids(cfg)
  map((d) -> get(d, :rule), get(cfg, :disabled))
end

def active(cfg, plane)
  filter(
    fn(r)
      get(r, :plane) == plane and not member?(get(r, :id), disabled_ids(cfg))
    end,
    rules
  )
end

def in_scope?(r, path)
  not is_empty(filter((g) -> glob_match?(g, path), get(r, :scope)))
end

def file_facts(path, source)
  doc = nikkusu::read(source)
  {
    path:,
    doc:,
    root: get(doc, :root),
    bindings: bindings(get(doc, :root)),
    calls: calls(get(doc, :root))
  }
end

def expression_findings(repo)
  rs = active(get(repo, :config), :expression)
  flat_map(
    fn(p)
      mine = filter((r) -> in_scope?(r, p), rs)
      if is_empty(mine)
        []
      else
        f = file_facts(p, source_of(repo, p))
        flat_map((r) -> get(r, :check)(f, repo), mine)
      end
    end,
    filter((p) -> ends_with?(p, ".nix"), get(repo, :files))
  )
end

def layout_findings(repo)
  flat_map((r) -> get(r, :check)(repo), active(get(repo, :config), :layout))
end

def tree_findings(repo, trees)
  rs = active(get(repo, :config), :tree)
  flat_map((t) -> flat_map((r) -> get(r, :check)(t, repo), rs), trees)
end

def waiver_refusal(w)
  prefix = "skip-#{get(w, :rule)}: "
  reason = get(w, :reason)
  if not starts_with?(reason, prefix) or trim(after_first(reason, prefix)) == ""
    refusal(
      :waiver,
      "the waiver of #{get(w, :rule)} for #{get(w, :glob)} must read \"#{prefix}<typed reason>\""
    )
  elsif is_empty(filter((r) -> get(r, :id) == get(w, :rule), rules))
    refusal(:waiver, "#{get(w, :rule)} is not a rule of the standard")
  end
end

def valid_waivers(cfg)
  filter((w) -> waiver_refusal(w).nil?, get(cfg, :waivers))
end

def config_refusals(cfg)
  append(
    filter((x) -> x != nil, map(waiver_refusal, get(cfg, :waivers))),
    map(
      fn(d)
        refusal(:disable, "#{get(d, :rule)} is not a rule of the standard")
      end,
      filter(
        (d) -> is_empty(filter((r) -> get(r, :id) == get(d, :rule), rules)),
        get(cfg, :disabled)
      )
    )
  )
end

def waived?(ws, x)
  not is_empty(
    filter(
      fn(w)
        get(w, :rule) == get(x, :rule) and
          glob_match?(get(w, :glob), get(x, :file))
      end,
      ws
    )
  )
end

def tier_of(id)
  get(first(filter((r) -> get(r, :id) == id, rules)), :tier)
end

def key_of(x)
  "#{get(x, :file)}::#{get(x, :subject)}"
end

def measurements(xs)
  map(
    (p) -> hadome::measurement(first(p), nth(1, p)),
    frequencies(map(key_of, xs))
  )
end

def rule_ids(xs)
  unique(map((x) -> get(x, :rule), xs))
end

def baseline_text(gates)
  baseline_with(gates, [])
end

def baseline_with(gates, kept)
  own = map(
    (id) -> [id, measurements(filter((x) -> get(x, :rule) == id, gates))],
    rule_ids(gates)
  )
  held = map(
    fn(id)
      [
        id,
        map(
          (r) -> hadome::measurement(get(r, :key), get(r, :size)),
          filter((r) -> get(r, :kind) == id, kept)
        )
      ]
    end,
    unique(map((r) -> get(r, :kind), kept))
  )
  join(
    map(
      (p) -> hadome::render(first(p), nth(1, p)),
      sort_keyed((p) -> first(p), append(own, held))
    ),
    ""
  )
end

def ran_ids(cfg, tree)
  planes = if tree
    [:layout, :expression, :tree]
  else
    [:layout, :expression]
  end
  map((r) -> get(r, :id), flat_map((p) -> active(cfg, p), planes))
end

def split_rows(rows, ids)
  [
    filter((r) -> member?(get(r, :kind), ids), rows),
    filter((r) -> not member?(get(r, :kind), ids), rows)
  ]
end

def judge(gates, rows)
  ids = unique(append(rule_ids(gates), map((r) -> get(r, :kind), rows)))
  per = map(
    fn(id)
      mine = filter((x) -> get(x, :rule) == id, gates)
      ms = measurements(mine)
      fresh = hadome::failures(rows, id, ms)
      bad_keys = map(
        (m) -> get(m, :key),
        filter(
          fn(m)
            hadome::judge(rows, id, get(m, :key), get(m, :size)) !=
              {verdict: :held}
          end,
          ms
        )
      )
      {
        rule: id,
        failures: fresh,
        new: filter((x) -> member?(key_of(x), bad_keys), mine),
        orphans: hadome::orphans(rows, id, map((m) -> get(m, :key), ms)),
        shrunk: hadome::shrunk(rows, id, ms)
      }
    end,
    ids
  )
  {
    new: flat_map((p) -> get(p, :new), per),
    failures: flat_map((p) -> get(p, :failures), per),
    orphans: flat_map(
      (p) -> map((k) -> "#{get(p, :rule)}: #{k}", get(p, :orphans)),
      per
    ),
    shrunk: flat_map(
      fn(p)
        map(
          (m) -> "#{get(p, :rule)}: #{get(m, :key)} #{to_s(get(m, :size))}",
          get(p, :shrunk)
        )
      end,
      per
    )
  }
end

def nix_string(s)
  "\"#{replace(replace(replace(s, "\\", "\\\\"), "\"", "\\\""), "$", "\\$")}\""
end

def tree_expr(excluded)
  skip = join(map(nix_string, excluded), " ")
  "c: let lib = c.pkgs.lib; excluded = [ #{skip} ]; defsOf = d: v: if builtins.elem d excluded then { definitions = [ ]; threw = false; } else let fs = builtins.addErrorContext (\"kijun\" + \"-option \" + d) (map (x: x.file) (v.definitionsWithLocations or [ ])); r = builtins.tryEval (builtins.deepSeq fs fs); in if r.success then { definitions = r.value; threw = false; } else { definitions = [ ]; threw = true; }; walk = path: v: if lib.isOption v then [ ({ path = lib.concatStringsSep \".\" path; declarations = v.declarations or [ ]; } // defsOf (lib.concatStringsSep \".\" path) v) ] else if builtins.isAttrs v && !(lib.isDerivation v) then lib.concatLists (lib.mapAttrsToList (n: x: walk (path ++ [ n ]) x) v) else [ ]; in { pleme = walk [ \"pleme\" ] (c.options.pleme or { }); hostname = walk [ \"networking\" \"hostName\" ] (c.options.networking.hostName or { }); }"
end

def failing_option(stderr)
  tagged = filter(
    (l) -> starts_with?(trim(l), "… kijun-option "),
    lines(stderr)
  )
  if is_empty(tagged)
    nil
  else
    trim(before_first(after_first(last(tagged), "kijun-option "), "'"))
  end
end

def last_error(stderr)
  errs = filter(
    (l) -> starts_with?(trim(l), "error:") and trim(l) != "error:",
    lines(stderr)
  )
  if is_empty(errs)
    trim(stderr)
  else
    trim(after_first(trim(last(errs)), "error:"))
  end
end

def own_source(root)
  cap = exec_capture("nix", "flake", "metadata", "--json", root)
  if status_of(cap) == 0
    get_str(json_parse(stdout_of(cap)), "path", "")
  else
    ""
  end
end

def entries(xs)
  if xs.nil?
    []
  else
    map(
      fn(o)
        {
          path: get_str(o, "path", ""),
          declarations: or_list(as_json(o, "declarations")),
          definitions: or_list(as_json(o, "definitions")),
          threw: as_json(o, "threw") == true
        }
      end,
      xs
    )
  end
end

def or_list(xs)
  if xs.nil? or not list?(xs)
    []
  else
    xs
  end
end

def tree_of(root, own, configuration)
  probe(root, own, configuration, [])
end

def probe(root, own, configuration, blind)
  cap = exec_capture(
    "nix",
    "eval",
    "--json",
    "--show-trace",
    "--option",
    "allow-import-from-derivation",
    "false",
    "#{root}##{configuration}",
    "--apply",
    tree_expr(map((b) -> get(b, :option), blind))
  )
  if status_of(cap) != 0
    err = stderr_of(cap)
    o = failing_option(err)
    if o != nil and is_empty(filter((b) -> get(b, :option) == o, blind))
      probe(
        root,
        own,
        configuration,
        append(blind, [{option: o, error: last_error(err)}])
      )
    else
      {
        configuration:,
        own:,
        pleme: [],
        hostname: [],
        blind:,
        error: last_error(err)
      }
    end
  else
    doc = json_parse(stdout_of(cap))
    pleme = entries(as_json(doc, "pleme"))
    hostname = entries(as_json(doc, "hostname"))
    threw = map(
      fn(x)
        {
          option: get(x, :path),
          error: "threw while its definitions were evaluated"
        }
      end,
      filter((x) -> get(x, :threw), append(pleme, hostname))
    )
    {
      configuration:,
      own:,
      pleme:,
      hostname:,
      blind: append(blind, threw),
      error: nil
    }
  end
end

def tracked(root)
  cap = exec_capture("git", "-C", root, "ls-files")
  if status_of(cap) != 0
    nil
  else
    filter((l) -> l != "", split(stdout_of(cap), "\n"))
  end
end

def source_of(repo, path)
  get(repo, :read)(path)
end

def on_disk(root, files)
  {root:, files:, read: (p) -> read_or(path_join(root, p), "")}
end

def in_memory(sources)
  {
    root: ".",
    files: map((s) -> first(s), sources),
    read: fn(p)
      hit = filter((s) -> first(s) == p, sources)
      if is_empty(hit)
        ""
      else
        nth(1, first(hit))
      end
    end
  }
end

def evaluate(cfg, source, trees)
  evaluate_timed(cfg, source, trees, () -> 0)
end

def evaluate_timed(cfg, source, trees, clock)
  repo = assoc(source, :config, cfg)
  t0 = clock()
  lay = layout_findings(repo)
  t1 = clock()
  expr = expression_findings(repo)
  t2 = clock()
  tr = unique(tree_findings(repo, trees))
  t3 = clock()
  all = append(append(lay, expr), tr)
  ws = valid_waivers(cfg)
  live = filter((x) -> not waived?(ws, x), all)
  {
    findings: live,
    gates: filter((x) -> tier_of(get(x, :rule)) == :gate, live),
    advice: filter((x) -> tier_of(get(x, :rule)) == :advise, live),
    waived: filter((x) -> waived?(ws, x), all),
    refusals: config_refusals(cfg),
    ms: {layout: t1 - t0, expression: t2 - t1, tree: t3 - t2},
    tree_errors: filter(
      (e) -> e != nil,
      map(
        fn(t)
          if get(t, :error).nil?
            nil
          else
            "#{get(t, :configuration)}: #{get(t, :error)}"
          end
        end,
        trees
      )
    )
  }
end

def parse_args(args)
  if is_empty(args)
    {error: "a command: check, baseline or rules"}
  elsif not member?(first(args), ["check", "baseline", "rules"])
    {error: "unknown command #{first(args)}: check, baseline or rules"}
  else
    flags(
      rest(args),
      {
        command: first(args),
        root: ".",
        json: false,
        tree: false,
        baseline: nil,
        error: nil
      }
    )
  end
end

def flags(args, acc)
  if is_empty(args) or get(acc, :error) != nil
    acc
  else
    a = first(args)
    if a == "--json"
      flags(rest(args), assoc(acc, :json, true))
    elsif a == "--tree"
      flags(rest(args), assoc(acc, :tree, true))
    elsif a == "--root" or a == "--baseline"
      if size(args) < 2
        assoc(acc, :error, "#{a} needs a path")
      else
        key = if a == "--root"
          :root
        else
          :baseline
        end
        flags(drop(2, args), assoc(acc, key, nth(1, args)))
      end
    else
      assoc(acc, :error, "unknown flag #{a}")
    end
  end
end

def rule_line(r)
  "#{get(r, :id)}\t#{to_s(get(r, :plane))}\t#{to_s(get(r, :tier))}\t#{join(get(r, :scope), " ")}\n  why: #{get(r, :why)}\n  fix: #{get(r, :fix)}\n"
end

def rules_text(cfg)
  "#{get(cfg, :standard)} v#{to_s(get(cfg, :version))}: #{to_s(size(rules))} rules\n\n#{join(map(rule_line, rules), "\n")}"
end

def finding_line(x)
  where = if get(x, :line) > 0
    "#{get(x, :file)}:#{to_s(get(x, :line))}"
  else
    get(x, :file)
  end
  "#{where}: #{get(x, :rule)}: #{get(x, :message)}\n"
end

def counts(xs)
  map(
    (id) -> [id, size(filter((x) -> get(x, :rule) == id, xs))],
    sort_keyed((id) -> id, rule_ids(xs))
  )
end

def plain(x)
  {
    rule: get(x, :rule),
    file: get(x, :file),
    line: get(x, :line),
    subject: get(x, :subject),
    message: get(x, :message)
  }
end

def plane_of(id)
  get(first(filter((r) -> get(r, :id) == id, rules)), :plane)
end

def plane_counts(result, timing)
  map(
    fn(p)
      mine = fn(k)
        size(filter((x) -> plane_of(get(x, :rule)) == p, get(result, k)))
      end
      {
        plane: p,
        findings: mine(:findings),
        gates: mine(:gates),
        advice: mine(:advice),
        waived: mine(:waived),
        ms: get(get(timing, :planes), p)
      }
    end,
    [:layout, :expression, :tree]
  )
end

def report_json(cfg, result, verdict, timing)
  json_stringify(
    {
      wall_ms: get(timing, :wall),
      planes: plane_counts(result, timing),
      standard: get(cfg, :standard),
      version: get(cfg, :version),
      ok: is_empty(get(verdict, :new)),
      new: map(plain, get(verdict, :new)),
      findings: map(plain, get(result, :findings)),
      counts: map(
        (c) -> {rule: first(c), count: nth(1, c)},
        counts(get(result, :findings))
      ),
      waived: size(get(result, :waived)),
      orphans: get(verdict, :orphans),
      shrunk: get(verdict, :shrunk),
      refusals: map((r) -> kyohi::why(r), get(result, :refusals)),
      disabled: get(cfg, :disabled),
      tree_errors: get(result, :tree_errors)
    }
  )
end

def timing_line(result, timing)
  ps = join(
    map(
      fn(p)
        "#{to_s(get(p, :plane))} #{to_s(get(p, :findings))} findings #{to_s(get(p, :ms))} ms"
      end,
      plane_counts(result, timing)
    ),
    ", "
  )
  "wall #{to_s(get(timing, :wall))} ms: #{ps}\n"
end

def report_text(cfg, result, verdict, timing)
  head = "kijun #{get(cfg, :standard)} v#{to_s(get(cfg, :version))}: #{to_s(size(get(result, :gates)))} gate findings, #{to_s(size(get(result, :advice)))} advice, #{to_s(size(get(result, :waived)))} waived\n"
  per = join(
    map(
      (c) -> "  #{first(c)} #{to_s(tier_of(first(c)))} #{to_s(nth(1, c))}\n",
      counts(get(result, :findings))
    ),
    ""
  )
  fresh = if is_empty(get(verdict, :new))
    "no gate finding outside the baseline\n"
  else
    "#{to_s(size(get(verdict, :new)))} gate findings outside the baseline:\n#{join(map(finding_line, get(verdict, :new)), "")}"
  end
  shrink = if is_empty(get(verdict, :orphans)) and
    is_empty(get(verdict, :shrunk))
    ""
  else
    "the baseline can shrink (run kijun baseline): #{to_s(size(get(verdict, :orphans)))} gone, #{to_s(size(get(verdict, :shrunk)))} smaller\n"
  end
  refused = join(
    map((r) -> "refused: #{kyohi::why(r)}\n", get(result, :refusals)),
    ""
  )
  off = join(
    map(
      (d) -> "disabled: #{get(d, :rule)}: #{get(d, :reason)}\n",
      get(cfg, :disabled)
    ),
    ""
  )
  blind = join(map((e) -> "tree blind: #{e}\n", get(result, :tree_errors)), "")
  "#{head}#{per}#{refused}#{off}#{blind}#{shrink}#{fresh}#{timing_line(result, timing)}"
end

def run(cfg, args)
  a = parse_args(args)
  if get(a, :error) != nil
    write_stderr("kijun: #{get(a, :error)}\n")
    raise(:kijun_usage, get(a, :error))
  elsif get(a, :command) == "rules"
    write_stdout(rules_text(cfg))
    nil
  else
    started = now_ms
    root = get(a, :root)
    files = tracked(root)
    if files.nil?
      write_stderr("kijun: #{root} is not a git work tree\n")
      raise(:kijun_usage, "not a git work tree")
    end
    before_tree = now_ms
    trees = if get(a, :tree)
      own = own_source(root)
      map((c) -> tree_of(root, own, c), get(cfg, :configurations))
    else
      []
    end
    tree_ms = now_ms - before_tree
    result = evaluate_timed(cfg, on_disk(root, files), trees, () -> now_ms)
    base = if get(a, :baseline).nil?
      path_join(root, get(cfg, :baseline))
    else
      get(a, :baseline)
    end
    rows = split_rows(
      hadome::parse(read_or(base, "")),
      ran_ids(cfg, get(a, :tree))
    )
    if get(a, :command) == "baseline"
      write_file(base, baseline_with(get(result, :gates), nth(1, rows)))
      write_stdout(
        "kijun: wrote #{to_s(size(get(result, :gates)))} gate findings to #{base}\n"
      )
      nil
    else
      verdict = judge(get(result, :gates), first(rows))
      ms = get(result, :ms)
      timing = {
        wall: now_ms - started,
        planes: assoc(ms, :tree, get(ms, :tree) + tree_ms)
      }
      if get(a, :json)
        write_stdout("#{report_json(cfg, result, verdict, timing)}\n")
      else
        write_stdout(report_text(cfg, result, verdict, timing))
      end
      if not is_empty(get(verdict, :new))
        raise(:kijun_failed, "gate findings outside the baseline")
      end
      nil
    end
  end
end

def main()
  args = argv
  root = get(flags(drop(1, args), {root: ".", error: nil}), :root)
  local = path_join(root, "kijun.b")
  if read_or(local, "") != ""
    status = exec_check(*append(["blue", "run", "--quiet", local, "--"], args))
    if status != 0
      raise(:kijun_failed, "kijun.b exited #{to_s(status)}")
    end
    nil
  else
    run(fleet_repo(1), args)
  end
end

def tree_case(file, kind_of)
  t = {
    configuration: "nixosConfigurations.a",
    own: "/nix/store/h-source",
    pleme: [],
    hostname: [],
    blind: [],
    error: nil
  }
  if kind_of == :blind
    assoc(
      assoc(
        t,
        :pleme,
        [
          {
            path: "pleme.x",
            declarations: ["/nix/store/h-source/#{file}"],
            definitions: []
          }
        ]
      ),
      :blind,
      [{option: "pleme.x", error: "attribute 'u' missing"}]
    )
  elsif kind_of == :declaration
    assoc(
      t,
      :pleme,
      [
        {
          path: "pleme.x",
          declarations: ["/nix/store/h-source/#{file}"],
          definitions: []
        }
      ]
    )
  else
    assoc(
      t,
      :hostname,
      [
        {
          path: "networking.hostName",
          declarations: [],
          definitions: ["/nix/store/h-source/#{file}"]
        }
      ]
    )
  end
end

def example(sources, trees)
  {sources:, trees:}
end

def module_with(body)
  "{ config, lib, pkgs, ... }:\n{\n#{body}\n}\n"
end

def concept_sources(declared)
  shared = if declared
    "{ inputs, ... }:\nlet\n  t = inputs.substrate.moduleTrio;\n  r = import ../../../lib/r.nix;\nin\n{\n  imports = [\n    (t.mkModuleTrio { kind = \"registry\"; name = \"x\"; entries.default = r; }).module\n    (t.mkModuleTrio { kind = \"package\"; name = \"tools\"; packageAttr = \"p\"; }).module\n    (t.mkModuleTrio { kind = \"service\"; name = \"o\"; }).module\n  ];\n}\n"
  else
    "{ lib, ... }:\n{\n  options.pleme.x.enable = lib.mkEnableOption \"x\";\n}\n"
  end
  [
    ["modules/pleme/shared/x.nix", shared],
    ["modules/pleme/shared/default.nix", "{ imports = [ ./x.nix ]; }"],
    ["pkgs/p/default.nix", "{ stdenv }: stdenv.mkDerivation { name = \"p\"; }"],
    ["pkgs/p/src/main.rs", "fn main() {}"],
    ["overlays/o.nix", "final: prev: let v = 1; in { o = prev.hello; }"],
    ["overlays/default.nix", "{ }"],
    ["lib/r.nix", "{ a = \"1\"; }"],
    ["lib/unread.nix", "{ b = 2; }"],
    [
      "modules/pleme/nixos/use.nix",
      "{ ... }:\nlet\n  r = import ../../../lib/r.nix;\nin\n{ }\n"
    ]
  ]
end

def trio_source(name, kind_of)
  k = if kind_of.nil?
    ""
  else
    "kind = \"#{kind_of}\"; "
  end
  [
    "modules/pleme/shared/#{name}.nix",
    "{ inputs, ... }:\n{\n  imports = [ (inputs.substrate.moduleTrio.mkModuleTrio { #{k}name = \"#{name}\"; }).module ];\n}\n"
  ]
end

def fixtures()
  registry = [
    "lib/nodes.nix",
    "{ plo = mkNode { name = \"plo\"; nodeDir = ../nodes/plo; }; }\n"
  ]
  [
    {
      rule: "trio/every-concept",
      fires: 4,
      bad: example(concept_sources(false), []),
      good: example(concept_sources(true), [])
    },
    {
      rule: "layout/top-level",
      fires: 1,
      bad: example([["flake.nix", "{ }"], ["stray.txt", ""]], []),
      good: example([["flake.nix", "{ }"], ["lib/a.nix", "{ }"]], [])
    },
    {
      rule: "layout/node-shape",
      fires: 2,
      bad: example(
        [
          registry,
          ["nodes/plo/default.nix", "{ }"],
          ["nodes/zed/hw.nix", "{ }"]
        ],
        []
      ),
      good: example(
        [
          registry,
          ["nodes/plo/default.nix", "{ }"],
          ["nodes/plo/layers.nix", "{ }"]
        ],
        []
      )
    },
    {
      rule: "layout/shared-has-proof",
      fires: 2,
      bad: example(
        [["modules/pleme/shared/x.nix", "{ }"], trio_source("r", "registry")],
        []
      ),
      good: example(
        [
          ["modules/pleme/shared/x.nix", "{ }"],
          ["parts/x.nix", "{ }"],
          trio_source("p", "package"),
          trio_source("s", "service"),
          trio_source("b", nil),
          trio_source("r", "registry"),
          ["parts/r.nix", "{ }"]
        ],
        []
      )
    },
    {
      rule: "layout/shared-reachable",
      fires: 1,
      bad: example(
        [
          ["modules/pleme/shared/x.nix", "{ }"],
          ["profiles/p/default.nix", "{ # shared/x.nix\n}"]
        ],
        []
      ),
      good: example(
        [
          ["modules/pleme/shared/x.nix", "{ }"],
          [
            "profiles/p/default.nix",
            "{ imports = [ ../../modules/pleme/shared/x.nix ]; }"
          ],
          trio_source("p", "package"),
          trio_source("r", "registry")
        ],
        []
      )
    },
    {
      rule: "expr/parses",
      fires: 1,
      bad: example([["lib/a.nix", "{ a = ; }"]], []),
      good: example([["lib/a.nix", "{ a = 1; }"]], [])
    },
    {
      rule: "expr/node-system-only-via-mkNode",
      fires: 1,
      bad: example(
        [
          [
            "parts/nixos.nix",
            "{ a = inputs.nixpkgs.lib.nixosSystem { modules = [ ]; }; }"
          ]
        ],
        []
      ),
      good: example(
        [
          [
            "parts/fleet.nix",
            "{ a = inputs.nixpkgs.lib.nixosSystem { modules = [ ]; }; }"
          ]
        ],
        []
      )
    },
    {
      rule: "expr/profile-no-identity",
      fires: 4,
      bad: example(
        [
          [
            "profiles/p/default.nix",
            module_with("  networking.hostName = \"plo\";\n  networking.hostId = \"8425e349\";\n  fileSystems.\"/\".device = \"/dev/disk/by-uuid/abc\";\n  sops.secrets.k.sopsFile = ../../nodes/plo/secrets.yaml;\n  sops.secrets.f.sopsFile = ../../secrets.yaml;")
          ]
        ],
        []
      ),
      good: example(
        [
          [
            "profiles/p/default.nix",
            module_with("  networking.firewall.enable = true;\n  fileSystems.\"/\".fsType = \"ext4\";")
          ]
        ],
        []
      )
    },
    {
      rule: "expr/lib-is-data",
      fires: 3,
      bad: example(
        [["lib/a.nix", module_with("  options.x = lib.mkOption { };")]],
        []
      ),
      good: example(
        [["lib/a.nix", "{ lib }: { x = 1; options = [ \"a\" ]; }"]],
        []
      )
    },
    {
      rule: "expr/shared-declares-only",
      fires: 1,
      bad: example(
        [
          [
            "modules/pleme/shared/x.nix",
            module_with("  options.pleme.x.enable = lib.mkEnableOption \"x\";\n  config = lib.mkIf config.pleme.x.enable { systemd.services.x = { }; };")
          ]
        ],
        []
      ),
      good: example(
        [
          [
            "modules/pleme/shared/x.nix",
            module_with("  options.pleme.x.enable = lib.mkEnableOption \"x\";\n  config = lib.mkIf config.pleme.x.enable { pleme.y = 1; };")
          ]
        ],
        []
      )
    },
    {
      rule: "expr/shared-asks-no-platform",
      fires: 1,
      bad: example(
        [
          [
            "modules/pleme/shared/x.nix",
            module_with("  pleme.x = pkgs.stdenv.hostPlatform.isDarwin;")
          ]
        ],
        []
      ),
      good: example(
        [
          [
            "modules/pleme/shared/x.nix",
            module_with("  pleme.x = pkgs.stdenv.hostPlatform.system;")
          ]
        ],
        []
      )
    },
    {
      rule: "expr/nodes-declare-no-options",
      fires: 2,
      bad: example(
        [
          [
            "nodes/plo/default.nix",
            module_with("  options.x = lib.mkOption { };")
          ]
        ],
        []
      ),
      good: example(
        [["nodes/plo/default.nix", module_with("  pleme.x = true;")]],
        []
      )
    },
    {
      rule: "expr/no-angle-paths",
      fires: 1,
      bad: example([["lib/a.nix", "import <nixpkgs> { }"]], []),
      good: example(
        [["lib/a.nix", "# <nixpkgs>\nimport ./x.nix { s = \"<nixpkgs>\"; }"]],
        []
      )
    },
    {
      rule: "expr/no-unpinned-fetch",
      fires: 2,
      bad: example(
        [
          [
            "lib/a.nix",
            "builtins.fetchTarball \"https://example.invalid/a.tar.gz\""
          ],
          [
            "lib/b.nix",
            "pkgs.fetchurl { url = \"https://example.invalid/b\"; }"
          ]
        ],
        []
      ),
      good: example(
        [
          [
            "lib/a.nix",
            "builtins.fetchTarball { url = \"https://example.invalid/a.tar.gz\"; sha256 = \"0abc\"; }"
          ]
        ],
        []
      )
    },
    {
      rule: "expr/no-shell",
      fires: 1,
      bad: example(
        [
          [
            "pkgs/a.nix",
            "pkgs.writeShellScript \"a\" ''\n  one\n  two\n  three\n  four\n''"
          ]
        ],
        []
      ),
      good: example(
        [
          [
            "pkgs/a.nix",
            "pkgs.writeShellScript \"a\" ''\n  one\n  two\n  three\n''"
          ]
        ],
        []
      )
    },
    {
      rule: "tree/pleme-options-declared-in-shared",
      fires: 1,
      bad: example([], [tree_case("lib/x.nix", :declaration)]),
      good: example([], [tree_case("modules/pleme/shared/x.nix", :declaration)])
    },
    {
      rule: "tree/option-evaluates",
      fires: 1,
      bad: example([], [tree_case("modules/pleme/shared/x.nix", :blind)]),
      good: example([], [tree_case("modules/pleme/shared/x.nix", :declaration)])
    },
    {
      rule: "tree/hostname-from-node",
      fires: 1,
      bad: example([], [tree_case("profiles/p/default.nix", :definition)]),
      good: example([], [tree_case("nodes/a/default.nix", :definition)])
    }
  ]
end

def fired(cfg, c, id)
  filter(
    (x) -> get(x, :rule) == id,
    get(evaluate(cfg, in_memory(get(c, :sources)), get(c, :trees)), :findings)
  )
end

test "every rule has a violating and a clean fixture, so a rule cannot land without both"
  ids = map((r) -> get(r, :id), rules)
  covered = filter(
    (f) -> get(f, :bad) != nil and get(f, :good) != nil,
    fixtures
  )
  assert filter(
    (id) -> is_empty(filter((f) -> get(f, :rule) == id, covered)),
    ids
  ) ==
    []
  assert filter((f) -> not member?(get(f, :rule), ids), fixtures) == []
  assert size(ids) == size(unique(ids))
end

test "each rule fires exactly as often as its violating fixture says, and never on its clean one"
  cfg = fleet_repo(1)
  quiet = filter(
    (f) -> size(fired(cfg, get(f, :bad), get(f, :rule))) != get(f, :fires),
    fixtures
  )
  noisy = filter(
    (f) -> not is_empty(fired(cfg, get(f, :good), get(f, :rule))),
    fixtures
  )
  assert map((f) -> get(f, :rule), quiet) == []
  assert map((f) -> get(f, :rule), noisy) == []
end

test "trio/every-concept names every unit kind once and is silent when each is a trio"
  cfg = fleet_repo(1)
  subjects = fn(declared)
    map(
      (x) -> get(x, :subject),
      fired(cfg, example(concept_sources(declared), []), "trio/every-concept")
    )
  end
  assert sort_keyed((t) -> t, subjects(false)) ==
    ["overlay o", "package p", "registry r", "shared x"]
  assert subjects(true) == []
  kinds = map(
    (t) -> before_first(t, " "),
    sort_keyed((t) -> t, subjects(false))
  )
  assert sort_keyed((t) -> t, kinds) ==
    sort_keyed((t) -> t, map((k) -> to_s(k), unit_kinds))
end

test "a registry is a concept only when a configuration layer imports it"
  xs = fired(
    fleet_repo(1),
    example(concept_sources(false), []),
    "trio/every-concept"
  )
  assert filter((x) -> get(x, :file) == "lib/unread.nix", xs) == []
  assert relative_to("modules/pleme/nixos/a.nix", "../../../lib/r.nix") ==
    "lib/r.nix"
  assert relative_to("nodes/plo/default.nix", "./hw.nix") == "nodes/plo/hw.nix"
end

test "a package directory with no nix of its own is still a concept, covered by a spec naming it"
  rust = [["pkgs/q/Cargo.toml", ""], ["pkgs/q/src/main.rs", "fn main() {}"]]
  assert map(
    (x) -> get(x, :subject),
    fired(fleet_repo(1), example(rust, []), "trio/every-concept")
  ) ==
    ["package q"]
  named_q = append(
    rust,
    [
      [
        "modules/pleme/shared/q.nix",
        "{ inputs, ... }: { imports = [ (inputs.substrate.moduleTrio.mkModuleTrio { kind = \"package\"; name = \"q\"; }).module ]; }"
      ]
    ]
  )
  assert fired(fleet_repo(1), example(named_q, []), "trio/every-concept") == []
end

test "a trio file renders itself, and the factory proves every kind but a registry"
  c = example(
    [
      trio_source("p", "package"),
      trio_source("b", nil),
      trio_source("r", "registry"),
      ["modules/pleme/shared/x.nix", "{ }"]
    ],
    []
  )
  subjects = fn(id)
    sort_keyed(
      (t) -> t,
      map((x) -> get(x, :subject), fired(fleet_repo(1), c, id))
    )
  end
  assert subjects("layout/shared-reachable") == ["x"]
  assert subjects("layout/shared-has-proof") == ["r", "x"]
  assert spec_kind(
    first(calls(get(nikkusu::read("f { kind = k; }"), :root)))
  ) ==
    "computed"
end

test "an uncatchable failure is located at its option's tag, and the error is its last line"
  err = "error:\n       … while evaluating the attribute 'definitions'\n       … kijun-option pleme.fleet.nixRepo\n       … while evaluating the attribute 'default'\n       error: attribute 'darwinUser' missing\n"
  assert failing_option(err) == "pleme.fleet.nixRepo"
  assert last_error(err) == "attribute 'darwinUser' missing"
  assert failing_option("error: flake has no attribute\n").nil?
  assert last_error("error: flake has no attribute\n") ==
    "flake has no attribute"
  assert nix_string("a\"b${c}\\") == "\"a\\\"b\\${c}\\\\\""
  assert contains?(
    tree_expr(["pleme.a", "pleme.b"]),
    "excluded = [ \"pleme.a\" \"pleme.b\" ]"
  ) ==
    true
end

test "a blind option is one advice finding at its declaration, and the plane keeps every other option"
  t = tree_case("modules/pleme/shared/x.nix", :blind)
  both = assoc(
    t,
    :hostname,
    [
      {
        path: "networking.hostName",
        declarations: [],
        definitions: ["/nix/store/h-source/profiles/p/default.nix"]
      }
    ]
  )
  r = evaluate(fleet_repo(1), in_memory([]), [both])
  assert map((x) -> [get(x, :rule), get(x, :file)], get(r, :findings)) ==
    [
      ["tree/hostname-from-node", "profiles/p/default.nix"],
      ["tree/option-evaluates", "modules/pleme/shared/x.nix"]
    ]
  assert map((x) -> get(x, :rule), get(r, :advice)) == ["tree/option-evaluates"]
end

test "check --json carries the wall time and one count per plane"
  c = example([["lib/a.nix", "import <nixpkgs> { }"]], [])
  r = evaluate(fleet_repo(1), in_memory(get(c, :sources)), [])
  timing = {wall: 7, planes: {layout: 1, expression: 2, tree: 3}}
  doc = json_parse(
    report_json(fleet_repo(1), r, judge(get(r, :gates), []), timing)
  )
  assert json_get(doc, "wall_ms") == 7
  assert map(
    (p) -> [json_get(p, "plane"), json_get(p, "findings"), json_get(p, "ms")],
    json_get(doc, "planes")
  ) ==
    [["layout", 0, 1], ["expression", 1, 2], ["tree", 0, 3]]
  assert contains?(
    report_text(fleet_repo(1), r, judge(get(r, :gates), []), timing),
    "wall 7 ms"
  ) ==
    true
end

test "trio/every-concept is the first rule the standard lists"
  assert get(first(rules), :id) == "trio/every-concept"
end

test "the same declaration seen from two configurations is one finding"
  t = tree_case("lib/x.nix", :declaration)
  two = [t, assoc(t, :configuration, "nixosConfigurations.b")]
  xs = filter(
    (x) -> get(x, :rule) == "tree/pleme-options-declared-in-shared",
    get(evaluate(fleet_repo(1), in_memory([]), two), :findings)
  )
  assert size(xs) == 1
end

test "a finding names its file and line"
  c = example([["lib/a.nix", "{\n  x = import <nixpkgs> { };\n}\n"]], [])
  x = first(fired(fleet_repo(1), c, "expr/no-angle-paths"))
  assert get(x, :file) == "lib/a.nix"
  assert get(x, :line) == 2
  assert get(x, :subject) == "<nixpkgs>"
end

test "node-shape names both a missing default.nix and a NixOS node's missing layers.nix"
  f = first(filter((f) -> get(f, :rule) == "layout/node-shape", fixtures))
  xs = fired(fleet_repo(1), get(f, :bad), "layout/node-shape")
  assert sort_keyed((t) -> t, map((x) -> get(x, :subject), xs)) ==
    ["default.nix", "layers.nix"]
end

test "a waiver is scoped to its rule and glob, and its siblings keep going"
  c = example(
    [
      ["lib/a.nix", "import <nixpkgs> { }"],
      ["lib/b.nix", "import <nixpkgs> { }"]
    ],
    []
  )
  cfg = waive(
    fleet_repo(1),
    "expr/no-angle-paths",
    "lib/a.nix",
    "skip-expr/no-angle-paths: bootstrap before inputs exist"
  )
  r = evaluate(cfg, in_memory(get(c, :sources)), [])
  angle = filter(
    (x) -> get(x, :rule) == "expr/no-angle-paths",
    get(r, :findings)
  )
  assert map((x) -> get(x, :file), angle) == ["lib/b.nix"]
  assert size(get(r, :waived)) == 1
  assert get(r, :refusals) == []
end

test "a waiver without its typed skip reason is refused and covers nothing"
  c = example([["lib/a.nix", "import <nixpkgs> { }"]], [])
  cfg = waive(fleet_repo(1), "expr/no-angle-paths", "lib/**", "because")
  r = evaluate(cfg, in_memory(get(c, :sources)), [])
  assert size(get(r, :refusals)) == 1
  assert size(
    filter((x) -> get(x, :rule) == "expr/no-angle-paths", get(r, :findings))
  ) ==
    1
  bogus = waive(fleet_repo(1), "expr/nope", "**", "skip-expr/nope: x")
  assert size(get(evaluate(bogus, in_memory([]), []), :refusals)) == 1
end

test "a disabled rule runs nowhere, and an unknown one is refused"
  c = example([["lib/a.nix", "import <nixpkgs> { }"]], [])
  cfg = disable(fleet_repo(1), "expr/no-angle-paths", "bootstrap repo")
  assert fired(cfg, c, "expr/no-angle-paths") == []
  assert size(fired(fleet_repo(1), c, "expr/no-angle-paths")) == 1
  assert size(
    get(
      evaluate(disable(fleet_repo(1), "x/y", "r"), in_memory([]), []),
      :refusals
    )
  ) ==
    1
end

test "allow_top extends the top-level allowlist for an instance"
  c = example([["bin/x", ""], ["flake.nix", "{ }"]], [])
  assert size(fired(fleet_repo(1), c, "layout/top-level")) == 1
  assert fired(allow_top(fleet_repo(1), ["bin"]), c, "layout/top-level") == []
end

test "the ratchet: a recorded finding holds, a new one fails, a fixed one shrinks the baseline"
  a = finding("expr/no-angle-paths", "lib/a.nix", 1, "<nixpkgs>", "m")
  b = finding("expr/no-angle-paths", "lib/b.nix", 1, "<nixpkgs>", "m")
  rows = hadome::parse(baseline_text([a]))
  assert baseline_text([a]) == "expr/no-angle-paths: lib/a.nix::<nixpkgs> 1\n"
  assert get(judge([a], rows), :new) == []
  assert map((x) -> get(x, :file), get(judge([a, b], rows), :new)) ==
    ["lib/b.nix"]
  gone = judge([], rows)
  assert get(gone, :new) == []
  assert get(gone, :orphans) == ["expr/no-angle-paths: lib/a.nix::<nixpkgs>"]
  assert size(get(judge([a, a], rows), :new)) == 2
  assert get(judge([], []), :new) == []
end

test "a plane that did not run neither judges nor drops its baseline rows"
  t = finding(
    "tree/hostname-from-node",
    "(external)",
    0,
    "a networking.hostName",
    "m"
  )
  e = finding("expr/no-angle-paths", "lib/a.nix", 1, "<nixpkgs>", "m")
  rows = hadome::parse(baseline_text([t, e]))
  parts = split_rows(rows, ran_ids(fleet_repo(1), false))
  assert map((r) -> get(r, :kind), first(parts)) == ["expr/no-angle-paths"]
  assert get(judge([e], first(parts)), :orphans) == []
  assert baseline_with([e], nth(1, parts)) == baseline_text([t, e])
  assert size(first(split_rows(rows, ran_ids(fleet_repo(1), true)))) == 2
end

test "the rules listing is the standard: every rule, with why and fix"
  t = rules_text(fleet_repo(1))
  assert size(filter((r) -> contains?(t, get(r, :id)), rules)) == size(rules)
  assert contains?(t, "fleet-repo v1") == true
end

test "arguments: a command is required and flags are read"
  assert get(parse_args([]), :error) != nil
  assert get(parse_args(["lint"]), :error) != nil
  a = parse_args(["check", "--json", "--root", "/r", "--tree"])
  assert [get(a, :json), get(a, :root), get(a, :tree)] == [true, "/r", true]
  assert get(parse_args(["check", "--root"]), :error) != nil
end
