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
    version: version,
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
  assoc(
    cfg,
    :waivers,
    append(get(cfg, :waivers), [{rule: rule, glob: glob, reason: reason}])
  )
end

def disable(cfg, rule, reason)
  assoc(
    cfg,
    :disabled,
    append(get(cfg, :disabled), [{rule: rule, reason: reason}])
  )
end

def finding(rule, file, line, subject, message)
  {rule: rule, file: file, line: line, subject: subject, message: message}
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
  !is_empty(filter(fn(g) glob_match?(g, name) end, get(cfg, :top)))
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
      fn(e) !allowed_top?(get(repo, :config), e) end,
      top_entries(get(repo, :files))
    )
  )
end

def node_dirs(files)
  unique(
    map(
      fn(p) nth(1, segments(p)) end,
      filter(
        fn(p) first(segments(p)) == "nodes" && size(segments(p)) > 2 end,
        files
      )
    )
  )
end

def node_dir_of(text)
  if contains?(text, "nodes/")
    before_first("#{after_first(text, "nodes/")}/", "/")
  else
    nil
  end
end

def declared_nodes(repo)
  cfg = get(repo, :config)
  path = get(cfg, :registry)
  if member?(path, get(repo, :files))
    doc = nikkusu::read(source_of(repo, path))
    filter(
      fn(d) d != nil end,
      map(
        fn(c)
          a = first(args_of(get(c, :node)))
          if a != nil && kind(a) == "NODE_ATTR_SET"
            v = attr(a, "nodeDir")
            if v == nil
              nil
            else
              node_dir_of(code(v))
            end
          else
            nil
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
      missing_layers = if member?(n, declared) &&
        !member?("#{dir}/layers.nix", files)
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
    fn(p) before_first(last(segments(p)), ".nix") end,
    filter(
      fn(p)
        glob_match?("modules/pleme/shared/*.nix", p) &&
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
  v = if a != nil && kind(a) == "NODE_ATTR_SET"
    attr(a, "kind")
  else
    nil
  end
  if v != nil && literal_string?(v)
    string_content(v)
  elsif v == nil
    "binary"
  else
    "computed"
  end
end

def self_rendering?(repo, m)
  !is_empty(trio_calls(repo, "modules/pleme/shared/#{m}.nix"))
end

def factory_proven?(repo, m)
  cs = trio_calls(repo, "modules/pleme/shared/#{m}.nix")
  !is_empty(cs) &&
    is_empty(
      filter(
        fn(c) !member?(spec_kind(c), ["binary", "package", "service"]) end,
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
      fn(m) !member?("parts/#{m}.nix", files) && !factory_proven?(repo, m) end,
      shared_modules(files)
    )
  )
end

def route_files(repo)
  files = get(repo, :files)
  filter(
    fn(p)
      !is_empty(
        filter(
          fn(g) glob_match?(g, p) end,
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
    fn(p) code(get(nikkusu::read(source_of(repo, p)), :root)) end,
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
        !member?("modules/pleme/nixos/#{m}.nix", files) &&
          !member?("modules/pleme/darwin/#{m}.nix", files) &&
          is_empty(filter(fn(t) contains?(t, "shared/#{m}.nix") end, routes)) &&
          !self_rendering?(repo, m)
      end,
      shared_modules(files)
    )
  )
end

def binding_finding(rule, f, b, message)
  at(f, get(f, :doc), rule, get(b, :start), get(b, :dotted), message)
end

def module_bindings(f)
  filter(fn(b) get(b, :scope) == :attrs end, get(f, :bindings))
end

def starts?(path, prefix)
  size(path) >= size(prefix) && take(size(prefix), path) == prefix
end

def check_system_calls(f, repo)
  if !is_empty(
    filter(
      fn(g) glob_match?(g, get(f, :path)) end,
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
  if p == ["networking", "hostName"] || p == ["networking", "hostId"]
    true
  elsif size(p) >= 3 && first(p) == "fileSystems" && last(p) == "device"
    v != nil && contains?(code(v), "by-uuid")
  elsif starts?(p, ["sops", "secrets"]) && last(p) == "sopsFile"
    v != nil && contains?(code(v), "nodes/")
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
    filter(fn(b) identity?(b) end, module_bindings(f))
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
    nodes_where(fn(n) module_function?(n) end, get(f, :root))
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
  first(path) != "options" &&
    !is_empty(filter(fn(x) starts?(p, x) end, platform_prefixes()))
end

def emits_platform?(b)
  o = get(b, :outer)
  platform_path?(get(b, :path)) && (o == nil || !platform_path?(o))
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
    filter(fn(b) emits_platform?(b) end, module_bindings(f))
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
        kind(n) == "NODE_SELECT" &&
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
  if a == nil
    false
  elsif kind(a) == "NODE_ATTR_SET"
    is_empty(filter(fn(k) attr(a, k) != nil end, pin_attrs()))
  else
    kind(a) == "NODE_STRING" || kind(a) == "NODE_PATH_ABS"
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
    filter(fn(c) unpinned?(c) end, named(get(f, :calls), fetchers()))
  )
end

def script_body(c)
  n = head_name(c)
  args = get(c, :args)
  if n == "writeShellApplication"
    if first(args) != nil && kind(first(args)) == "NODE_ATTR_SET"
      attr(first(args), "text")
    else
      nil
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
  if body == nil || kind(body) != "NODE_STRING"
    0
  else
    size(filter(fn(l) trim(l) != "" end, lines(string_content(body))))
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
      fn(c) script_lines(script_body(c)) > 3 end,
      named(get(f, :calls), scripts())
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
  if own != nil && own != "" && starts_with?(file, "#{own}/")
    after_first(file, "#{own}/")
  else
    nil
  end
end

def check_pleme_declarations(tree, repo)
  declarers = get(get(repo, :config), :declarers)
  flat_map(
    fn(o)
      map(
        fn(d)
          rel = own_file(tree, d)
          where = if rel == nil
            "outside this repository (#{d})"
          else
            rel
          end
          finding(
            "tree/pleme-options-declared-in-shared",
            if rel == nil
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
            rel == nil ||
              is_empty(filter(fn(g) glob_match?(g, rel) end, declarers))
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
          file = if rel == nil
            "(external)"
          else
            rel
          end
          shown = if rel == nil
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
            rel == nil || !glob_match?("nodes/**", rel)
          end,
          get(o, :definitions)
        )
      )
    end,
    get(tree, :hostname)
  )
end

def unit_kinds()
  [:shared, :package, :overlay, :registry]
end

def unit(kind_of, name, file, files)
  {kind: kind_of, name: name, file: file, files: files}
end

def nix_under(files, prefix)
  filter(fn(p) starts_with?(p, prefix) && ends_with?(p, ".nix") end, files)
end

def dir_units(files, root, kind_of, skip, pool)
  depth = size(segments(root))
  under = filter(fn(p) starts_with?(p, "#{root}/") end, pool)
  singles = map(
    fn(p)
      unit(kind_of, before_first(nth(depth, segments(p)), ".nix"), p, [p])
    end,
    filter(
      fn(p)
        size(segments(p)) == depth + 1 &&
          ends_with?(p, ".nix") &&
          !member?(p, skip)
      end,
      under
    )
  )
  dirs = unique(
    map(
      fn(p) nth(depth, segments(p)) end,
      filter(fn(p) size(segments(p)) > depth + 1 end, under)
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
  if n == nil
    nil
  elsif k == "NODE_ATTR_SET"
    n
  elsif k == "NODE_ROOT" || k == "NODE_PAREN"
    returned_set(first(nodes_of(n)))
  elsif k == "NODE_LAMBDA" || k == "NODE_LET_IN"
    returned_set(last(nodes_of(n)))
  else
    nil
  end
end

def overlay_units(repo)
  flat_map(
    fn(p)
      set = returned_set(get(nikkusu::read(source_of(repo, p)), :root))
      if set == nil
        []
      else
        map(
          fn(a) unit(:overlay, a, p, [p]) end,
          unique(
            map(
              fn(b) first(get(b, :path)) end,
              filter(
                fn(b) get(b, :scope) == :attrs && get(b, :outer) == nil end,
                bindings(set)
              )
            )
          )
        )
      end
    end,
    filter(
      fn(p)
        size(segments(p)) == 2 &&
          p != "overlays/default.nix" &&
          ends_with?(p, ".nix")
      end,
      nix_under(get(repo, :files), "overlays/")
    )
  )
end

def resolve(segs, acc)
  if is_empty(segs)
    acc
  elsif first(segs) == "." || first(segs) == ""
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
    fn(c) relative_to(get(f, :path), code(first(get(c, :args)))) end,
    filter(
      fn(c)
        first(get(c, :args)) != nil &&
          kind(first(get(c, :args))) == "NODE_PATH_REL"
      end,
      named(get(f, :calls), ["import"])
    )
  )
end

def spec_names(c)
  a = last(get(c, :args))
  if a == nil || kind(a) != "NODE_ATTR_SET"
    []
  else
    filter(
      fn(x) x != nil end,
      map(
        fn(k)
          v = attr(a, k)
          if v != nil && literal_string?(v)
            string_content(v)
          else
            nil
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
      ends_with?(p, ".nix") &&
        (starts_with?(p, "modules/") ||
          starts_with?(p, "profiles/") ||
          starts_with?(p, "pkgs/") ||
          starts_with?(p, "overlays/") ||
          starts_with?(p, "lib/"))
    end,
    files
  )
  facts = map(fn(p) file_facts(p, source_of(repo, p)) end, wanted)
  trio = filter(
    fn(f) !is_empty(named(get(f, :calls), get(cfg, :trio_factory))) end,
    facts
  )
  consumers = filter(
    fn(f)
      !is_empty(
        filter(
          fn(g) glob_match?(g, get(f, :path)) end,
          get(cfg, :concept_consumers)
        )
      )
    end,
    facts
  )
  {
    trio_files: map(fn(f) get(f, :path) end, trio),
    names: unique(
      flat_map(
        fn(f)
          flat_map(
            fn(c) spec_names(c) end,
            named(get(f, :calls), get(cfg, :trio_factory))
          )
        end,
        trio
      )
    ),
    trio_imports: unique(flat_map(fn(f) imported_files(f) end, trio)),
    consumed: unique(flat_map(fn(f) imported_files(f) end, consumers))
  }
end

def registry_units(files, facts)
  map(
    fn(p)
      unit(:registry, before_first(nth(1, segments(p)), ".nix"), p, [p])
    end,
    filter(
      fn(p)
        size(segments(p)) == 2 &&
          starts_with?(p, "lib/") &&
          ends_with?(p, ".nix") &&
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
  !is_empty(
    filter(fn(p) member?(p, get(facts, :trio_files)) end, get(u, :files))
  ) ||
    member?(get(u, :name), get(facts, :names)) ||
    get(u, :kind) == :registry &&
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
    filter(fn(u) !covered?(u, facts) end, concept_units(repo, facts))
  )
end

def rule(id, plane, tier, scope, why, fix, check)
  {
    id: id,
    plane: plane,
    tier: tier,
    scope: scope,
    why: why,
    fix: fix,
    check: check
  }
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
      fn(r) check_concepts(r) end
    ),
    rule(
      "layout/top-level",
      :layout,
      :gate,
      ["*"],
      "a fleet repo is one instance of a template: every top-level entry is one the standard names or the instance declares",
      "move the entry under an allowed directory, or name it with allow_top in kijun.b",
      fn(r) check_top(r) end
    ),
    rule(
      "layout/node-shape",
      :layout,
      :gate,
      ["nodes/*/"],
      "a node is a directory selected through default.nix; a registry-declared NixOS node selects layers from layers.nix",
      "add nodes/<n>/default.nix (and layers.nix for a NixOS node), or move what is not a node out of nodes/",
      fn(r) check_nodes(r) end
    ),
    rule(
      "layout/shared-has-proof",
      :layout,
      :gate,
      ["modules/pleme/shared/*.nix"],
      "an option that exists is not a type: each shared options module is proven by a stub-universe harness, unless it is a binary, package or service trio, which substrate's module-trio-kinds matrix proves",
      "add parts/<name>.nix, or declare the concept through mkModuleTrio as a binary, package or service kind; a registry trio keeps its harness, since its projections are its own logic",
      fn(r) check_proof(r) end
    ),
    rule(
      "layout/shared-reachable",
      :layout,
      :gate,
      ["modules/pleme/shared/*.nix"],
      "a shared options module nothing renders or imports is dead weight that looks live; a file that calls mkModuleTrio renders itself, since its module arm picks the platform by class",
      "add modules/pleme/{nixos,darwin}/<name>.nix, import shared/<name>.nix from an import route, or declare the concept through mkModuleTrio",
      fn(r) check_reachable(r) end
    ),
    rule(
      "expr/parses",
      :expression,
      :gate,
      ["**/*.nix"],
      "a file the parser refuses is checked by no rule",
      "fix the syntax error",
      fn(f, r) check_parses(f, r) end
    ),
    rule(
      "expr/node-system-only-via-mkNode",
      :expression,
      :gate,
      ["**/*.nix"],
      "a machine is declared through the node engine only; a bespoke nixosSystem or darwinSystem call bypasses the registry and its gates",
      "declare the node in the registry, or name the file in the engine setting",
      fn(f, r) check_system_calls(f, r) end
    ),
    rule(
      "expr/profile-no-identity",
      :expression,
      :gate,
      ["profiles/**/*.nix"],
      "a profile is reusable across nodes, so it carries no node identity: hostname, hostId, disk UUIDs, node-scoped secrets",
      "set the value in nodes/<n>/",
      fn(f, r) check_profile_identity(f, r) end
    ),
    rule(
      "expr/lib-is-data",
      :expression,
      :gate,
      ["lib/**/*.nix"],
      "data never lives in a module, and lib/ is where data lives: no options, no module functions",
      "move the module to modules/pleme/<layer>/ and keep the data in lib/",
      fn(f, r) check_lib_data(f, r) end
    ),
    rule(
      "expr/shared-declares-only",
      :expression,
      :gate,
      ["modules/pleme/shared/**/*.nix"],
      "options never emit: a shared module is imported on both platforms, so platform config there fails the other platform",
      "move the emission to modules/pleme/{nixos,darwin}/<name>.nix",
      fn(f, r) check_shared_emission(f, r) end
    ),
    rule(
      "expr/shared-asks-no-platform",
      :expression,
      :advise,
      ["modules/pleme/shared/**/*.nix"],
      "renderers never decide: a shared module that branches on the platform has taken a renderer's decision",
      "split the branch into the platform renderers",
      fn(f, r) check_shared_platform_question(f, r) end
    ),
    rule(
      "expr/nodes-declare-no-options",
      :expression,
      :gate,
      ["nodes/**/*.nix"],
      "a node is identity and selection; an option it declares is a primitive nobody else can reach",
      "declare the option in modules/pleme/shared/ and set it from the node",
      fn(f, r) check_node_options(f, r) end
    ),
    rule(
      "expr/no-angle-paths",
      :expression,
      :gate,
      ["**/*.nix"],
      "an angle path resolves through NIX_PATH, which the flake lock does not pin",
      "take the input from the flake's inputs",
      fn(f, r) check_angle(f, r) end
    ),
    rule(
      "expr/no-unpinned-fetch",
      :expression,
      :gate,
      ["**/*.nix"],
      "a fetch with no hash is whatever the server serves today",
      "add the hash, or make it a flake input",
      fn(f, r) check_fetch(f, r) end
    ),
    rule(
      "expr/no-shell",
      :expression,
      :advise,
      ["**/*.nix"],
      "no shell beyond three lines of glue: past that it is a typed tool",
      "write it as a blue program or a typed binary",
      fn(f, r) check_shell(f, r) end
    ),
    rule(
      "tree/pleme-options-declared-in-shared",
      :tree,
      :gate,
      ["modules/pleme/**"],
      "the pleme.* surface is declared in one layer, so every node reads one vocabulary",
      "move the declaration to modules/pleme/shared/ or the platform renderer",
      fn(t, r) check_pleme_declarations(t, r) end
    ),
    rule(
      "tree/hostname-from-node",
      :tree,
      :gate,
      ["nodes/**"],
      "a hostname is a node's identity, so only the node defines it",
      "define networking.hostName in nodes/<n>/",
      fn(t, r) check_hostname(t, r) end
    )
  ]
end

def disabled_ids(cfg)
  map(fn(d) get(d, :rule) end, get(cfg, :disabled))
end

def active(cfg, plane)
  filter(
    fn(r)
      get(r, :plane) == plane && !member?(get(r, :id), disabled_ids(cfg))
    end,
    rules()
  )
end

def in_scope?(r, path)
  !is_empty(filter(fn(g) glob_match?(g, path) end, get(r, :scope)))
end

def file_facts(path, source)
  doc = nikkusu::read(source)
  {
    path: path,
    doc: doc,
    root: get(doc, :root),
    bindings: bindings(get(doc, :root)),
    calls: calls(get(doc, :root))
  }
end

def expression_findings(repo)
  rs = active(get(repo, :config), :expression)
  flat_map(
    fn(p)
      mine = filter(fn(r) in_scope?(r, p) end, rs)
      if is_empty(mine)
        []
      else
        f = file_facts(p, source_of(repo, p))
        flat_map(fn(r) get(r, :check)(f, repo) end, mine)
      end
    end,
    filter(fn(p) ends_with?(p, ".nix") end, get(repo, :files))
  )
end

def layout_findings(repo)
  flat_map(fn(r) get(r, :check)(repo) end, active(get(repo, :config), :layout))
end

def tree_findings(repo, trees)
  rs = active(get(repo, :config), :tree)
  flat_map(fn(t) flat_map(fn(r) get(r, :check)(t, repo) end, rs) end, trees)
end

def waiver_refusal(w)
  prefix = "skip-#{get(w, :rule)}: "
  reason = get(w, :reason)
  if !starts_with?(reason, prefix) || trim(after_first(reason, prefix)) == ""
    refusal(
      :waiver,
      "the waiver of #{get(w, :rule)} for #{get(w, :glob)} must read \"#{prefix}<typed reason>\""
    )
  elsif is_empty(filter(fn(r) get(r, :id) == get(w, :rule) end, rules()))
    refusal(:waiver, "#{get(w, :rule)} is not a rule of the standard")
  else
    nil
  end
end

def valid_waivers(cfg)
  filter(fn(w) waiver_refusal(w) == nil end, get(cfg, :waivers))
end

def config_refusals(cfg)
  append(
    filter(
      fn(x) x != nil end,
      map(fn(w) waiver_refusal(w) end, get(cfg, :waivers))
    ),
    map(
      fn(d)
        refusal(:disable, "#{get(d, :rule)} is not a rule of the standard")
      end,
      filter(
        fn(d)
          is_empty(filter(fn(r) get(r, :id) == get(d, :rule) end, rules()))
        end,
        get(cfg, :disabled)
      )
    )
  )
end

def waived?(ws, x)
  !is_empty(
    filter(
      fn(w)
        get(w, :rule) == get(x, :rule) &&
          glob_match?(get(w, :glob), get(x, :file))
      end,
      ws
    )
  )
end

def tier_of(id)
  get(first(filter(fn(r) get(r, :id) == id end, rules())), :tier)
end

def key_of(x)
  "#{get(x, :file)}::#{get(x, :subject)}"
end

def measurements(xs)
  map(
    fn(p) hadome::measurement(first(p), nth(1, p)) end,
    frequencies(map(fn(x) key_of(x) end, xs))
  )
end

def rule_ids(xs)
  unique(map(fn(x) get(x, :rule) end, xs))
end

def baseline_text(gates)
  baseline_with(gates, [])
end

def baseline_with(gates, kept)
  own = map(
    fn(id) [id, measurements(filter(fn(x) get(x, :rule) == id end, gates))] end,
    rule_ids(gates)
  )
  held = map(
    fn(id)
      [
        id,
        map(
          fn(r) hadome::measurement(get(r, :key), get(r, :size)) end,
          filter(fn(r) get(r, :kind) == id end, kept)
        )
      ]
    end,
    unique(map(fn(r) get(r, :kind) end, kept))
  )
  join(
    map(
      fn(p) hadome::render(first(p), nth(1, p)) end,
      sort_keyed(fn(p) first(p) end, append(own, held))
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
  map(fn(r) get(r, :id) end, flat_map(fn(p) active(cfg, p) end, planes))
end

def split_rows(rows, ids)
  [
    filter(fn(r) member?(get(r, :kind), ids) end, rows),
    filter(fn(r) !member?(get(r, :kind), ids) end, rows)
  ]
end

def judge(gates, rows)
  ids = unique(append(rule_ids(gates), map(fn(r) get(r, :kind) end, rows)))
  per = map(
    fn(id)
      mine = filter(fn(x) get(x, :rule) == id end, gates)
      ms = measurements(mine)
      fresh = hadome::failures(rows, id, ms)
      bad_keys = map(
        fn(m) get(m, :key) end,
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
        new: filter(fn(x) member?(key_of(x), bad_keys) end, mine),
        orphans: hadome::orphans(rows, id, map(fn(m) get(m, :key) end, ms)),
        shrunk: hadome::shrunk(rows, id, ms)
      }
    end,
    ids
  )
  {
    new: flat_map(fn(p) get(p, :new) end, per),
    failures: flat_map(fn(p) get(p, :failures) end, per),
    orphans: flat_map(
      fn(p) map(fn(k) "#{get(p, :rule)}: #{k}" end, get(p, :orphans)) end,
      per
    ),
    shrunk: flat_map(
      fn(p)
        map(
          fn(m) "#{get(p, :rule)}: #{get(m, :key)} #{to_s(get(m, :size))}" end,
          get(p, :shrunk)
        )
      end,
      per
    )
  }
end

def tree_expr()
  "c: let lib = c.pkgs.lib; walk = defs: path: v: if lib.isOption v then [({ path = lib.concatStringsSep \".\" path; declarations = v.declarations or []; } // lib.optionalAttrs defs { definitions = map (d: d.file) (v.definitionsWithLocations or []); })] else if builtins.isAttrs v && !(lib.isDerivation v) then lib.concatLists (lib.mapAttrsToList (n: x: walk defs (path ++ [n]) x) v) else []; in { pleme = walk false [\"pleme\"] (c.options.pleme or {}); hostname = walk true [\"networking\" \"hostName\"] (c.options.networking.hostName or {}); }"
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
  if xs == nil
    []
  else
    map(
      fn(o)
        {
          path: get_str(o, "path", ""),
          declarations: or_list(as_json(o, "declarations")),
          definitions: or_list(as_json(o, "definitions"))
        }
      end,
      xs
    )
  end
end

def or_list(xs)
  if xs == nil || !list?(xs)
    []
  else
    xs
  end
end

def tree_of(root, own, configuration)
  cap = exec_capture(
    "nix",
    "eval",
    "--json",
    "#{root}##{configuration}",
    "--apply",
    tree_expr()
  )
  if status_of(cap) != 0
    {
      configuration: configuration,
      own: own,
      pleme: [],
      hostname: [],
      error: trim(stderr_of(cap))
    }
  else
    doc = json_parse(stdout_of(cap))
    {
      configuration: configuration,
      own: own,
      pleme: entries(as_json(doc, "pleme")),
      hostname: entries(as_json(doc, "hostname")),
      error: nil
    }
  end
end

def tracked(root)
  cap = exec_capture("git", "-C", root, "ls-files")
  if status_of(cap) != 0
    nil
  else
    filter(fn(l) l != "" end, split(stdout_of(cap), "\n"))
  end
end

def source_of(repo, path)
  get(repo, :read)(path)
end

def on_disk(root, files)
  {root: root, files: files, read: fn(p) read_or(path_join(root, p), "") end}
end

def in_memory(sources)
  {
    root: ".",
    files: map(fn(s) first(s) end, sources),
    read: fn(p)
      hit = filter(fn(s) first(s) == p end, sources)
      if is_empty(hit)
        ""
      else
        nth(1, first(hit))
      end
    end
  }
end

def evaluate(cfg, source, trees)
  repo = assoc(source, :config, cfg)
  all = append(
    append(layout_findings(repo), expression_findings(repo)),
    unique(tree_findings(repo, trees))
  )
  ws = valid_waivers(cfg)
  live = filter(fn(x) !waived?(ws, x) end, all)
  {
    findings: live,
    gates: filter(fn(x) tier_of(get(x, :rule)) == :gate end, live),
    advice: filter(fn(x) tier_of(get(x, :rule)) == :advise end, live),
    waived: filter(fn(x) waived?(ws, x) end, all),
    refusals: config_refusals(cfg),
    tree_errors: filter(
      fn(e) e != nil end,
      map(
        fn(t)
          if get(t, :error) == nil
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
  elsif !member?(first(args), ["check", "baseline", "rules"])
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
  if is_empty(args) || get(acc, :error) != nil
    acc
  else
    a = first(args)
    if a == "--json"
      flags(rest(args), assoc(acc, :json, true))
    elsif a == "--tree"
      flags(rest(args), assoc(acc, :tree, true))
    elsif a == "--root" || a == "--baseline"
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
  "#{get(cfg, :standard)} v#{to_s(get(cfg, :version))}: #{to_s(size(rules()))} rules\n\n#{join(map(fn(r) rule_line(r) end, rules()), "\n")}"
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
    fn(id) [id, size(filter(fn(x) get(x, :rule) == id end, xs))] end,
    sort_keyed(fn(id) id end, rule_ids(xs))
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

def report_json(cfg, result, verdict)
  json_stringify(
    {
      standard: get(cfg, :standard),
      version: get(cfg, :version),
      ok: is_empty(get(verdict, :new)),
      new: map(fn(x) plain(x) end, get(verdict, :new)),
      findings: map(fn(x) plain(x) end, get(result, :findings)),
      counts: map(
        fn(c) {rule: first(c), count: nth(1, c)} end,
        counts(get(result, :findings))
      ),
      waived: size(get(result, :waived)),
      orphans: get(verdict, :orphans),
      shrunk: get(verdict, :shrunk),
      refusals: map(fn(r) kyohi::why(r) end, get(result, :refusals)),
      disabled: get(cfg, :disabled),
      tree_errors: get(result, :tree_errors)
    }
  )
end

def report_text(cfg, result, verdict)
  head = "kijun #{get(cfg, :standard)} v#{to_s(get(cfg, :version))}: #{to_s(size(get(result, :gates)))} gate findings, #{to_s(size(get(result, :advice)))} advice, #{to_s(size(get(result, :waived)))} waived\n"
  per = join(
    map(
      fn(c) "  #{first(c)} #{to_s(tier_of(first(c)))} #{to_s(nth(1, c))}\n" end,
      counts(get(result, :findings))
    ),
    ""
  )
  fresh = if is_empty(get(verdict, :new))
    "no gate finding outside the baseline\n"
  else
    "#{to_s(size(get(verdict, :new)))} gate findings outside the baseline:\n#{join(map(fn(x) finding_line(x) end, get(verdict, :new)), "")}"
  end
  shrink = if is_empty(get(verdict, :orphans)) &&
    is_empty(get(verdict, :shrunk))
    ""
  else
    "the baseline can shrink (run kijun baseline): #{to_s(size(get(verdict, :orphans)))} gone, #{to_s(size(get(verdict, :shrunk)))} smaller\n"
  end
  refused = join(
    map(fn(r) "refused: #{kyohi::why(r)}\n" end, get(result, :refusals)),
    ""
  )
  off = join(
    map(
      fn(d) "disabled: #{get(d, :rule)}: #{get(d, :reason)}\n" end,
      get(cfg, :disabled)
    ),
    ""
  )
  blind = join(
    map(fn(e) "tree blind: #{e}\n" end, get(result, :tree_errors)),
    ""
  )
  "#{head}#{per}#{refused}#{off}#{blind}#{shrink}#{fresh}"
end

def run(cfg, args)
  a = parse_args(args)
  if get(a, :error) != nil
    write_stderr("kijun: #{get(a, :error)}\n")
    throw(error(:kijun_usage, get(a, :error)))
  elsif get(a, :command) == "rules"
    write_stdout(rules_text(cfg))
    nil
  else
    root = get(a, :root)
    files = tracked(root)
    if files == nil
      write_stderr("kijun: #{root} is not a git work tree\n")
      throw(error(:kijun_usage, "not a git work tree"))
    end
    trees = if get(a, :tree)
      own = own_source(root)
      map(fn(c) tree_of(root, own, c) end, get(cfg, :configurations))
    else
      []
    end
    result = evaluate(cfg, on_disk(root, files), trees)
    base = if get(a, :baseline) == nil
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
      if get(a, :json)
        write_stdout("#{report_json(cfg, result, verdict)}\n")
      else
        write_stdout(report_text(cfg, result, verdict))
      end
      if !is_empty(get(verdict, :new))
        throw(error(:kijun_failed, "gate findings outside the baseline"))
      end
      nil
    end
  end
end

def main()
  args = argv()
  root = get(flags(drop(1, args), {root: ".", error: nil}), :root)
  local = path_join(root, "kijun.b")
  if read_or(local, "") != ""
    status = apply(
      exec_check,
      append(["blue", "run", "--quiet", local, "--"], args)
    )
    if status != 0
      throw(error(:kijun_failed, "kijun.b exited #{to_s(status)}"))
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
    error: nil
  }
  if kind_of == :declaration
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
  {sources: sources, trees: trees}
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
  k = if kind_of == nil
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
            module_with(
              "  networking.hostName = \"plo\";\n  networking.hostId = \"8425e349\";\n  fileSystems.\"/\".device = \"/dev/disk/by-uuid/abc\";\n  sops.secrets.k.sopsFile = ../../nodes/plo/secrets.yaml;\n  sops.secrets.f.sopsFile = ../../secrets.yaml;"
            )
          ]
        ],
        []
      ),
      good: example(
        [
          [
            "profiles/p/default.nix",
            module_with(
              "  networking.firewall.enable = true;\n  fileSystems.\"/\".fsType = \"ext4\";"
            )
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
            module_with(
              "  options.pleme.x.enable = lib.mkEnableOption \"x\";\n  config = lib.mkIf config.pleme.x.enable { systemd.services.x = { }; };"
            )
          ]
        ],
        []
      ),
      good: example(
        [
          [
            "modules/pleme/shared/x.nix",
            module_with(
              "  options.pleme.x.enable = lib.mkEnableOption \"x\";\n  config = lib.mkIf config.pleme.x.enable { pleme.y = 1; };"
            )
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
      rule: "tree/hostname-from-node",
      fires: 1,
      bad: example([], [tree_case("profiles/p/default.nix", :definition)]),
      good: example([], [tree_case("nodes/a/default.nix", :definition)])
    }
  ]
end

def fired(cfg, c, id)
  filter(
    fn(x) get(x, :rule) == id end,
    get(evaluate(cfg, in_memory(get(c, :sources)), get(c, :trees)), :findings)
  )
end

test "every rule has a violating and a clean fixture, so a rule cannot land without both"
  ids = map(fn(r) get(r, :id) end, rules())
  covered = filter(
    fn(f) get(f, :bad) != nil && get(f, :good) != nil end,
    fixtures()
  )
  assert filter(
    fn(id) is_empty(filter(fn(f) get(f, :rule) == id end, covered)) end,
    ids
  ) ==
    []
  assert filter(fn(f) !member?(get(f, :rule), ids) end, fixtures()) == []
  assert size(ids) == size(unique(ids))
end

test "each rule fires exactly as often as its violating fixture says, and never on its clean one"
  cfg = fleet_repo(1)
  quiet = filter(
    fn(f) size(fired(cfg, get(f, :bad), get(f, :rule))) != get(f, :fires) end,
    fixtures()
  )
  noisy = filter(
    fn(f) !is_empty(fired(cfg, get(f, :good), get(f, :rule))) end,
    fixtures()
  )
  assert map(fn(f) get(f, :rule) end, quiet) == []
  assert map(fn(f) get(f, :rule) end, noisy) == []
end

test "trio/every-concept names every unit kind once and is silent when each is a trio"
  cfg = fleet_repo(1)
  subjects = fn(declared)
    map(
      fn(x) get(x, :subject) end,
      fired(cfg, example(concept_sources(declared), []), "trio/every-concept")
    )
  end
  assert sort_keyed(fn(t) t end, subjects(false)) ==
    ["overlay o", "package p", "registry r", "shared x"]
  assert subjects(true) == []
  kinds = map(
    fn(t) before_first(t, " ") end,
    sort_keyed(fn(t) t end, subjects(false))
  )
  assert sort_keyed(fn(t) t end, kinds) ==
    sort_keyed(fn(t) t end, map(fn(k) to_s(k) end, unit_kinds()))
end

test "a registry is a concept only when a configuration layer imports it"
  xs = fired(
    fleet_repo(1),
    example(concept_sources(false), []),
    "trio/every-concept"
  )
  assert filter(fn(x) get(x, :file) == "lib/unread.nix" end, xs) == []
  assert relative_to("modules/pleme/nixos/a.nix", "../../../lib/r.nix") ==
    "lib/r.nix"
  assert relative_to("nodes/plo/default.nix", "./hw.nix") == "nodes/plo/hw.nix"
end

test "a package directory with no nix of its own is still a concept, covered by a spec naming it"
  rust = [["pkgs/q/Cargo.toml", ""], ["pkgs/q/src/main.rs", "fn main() {}"]]
  assert map(
    fn(x) get(x, :subject) end,
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
      fn(t) t end,
      map(fn(x) get(x, :subject) end, fired(fleet_repo(1), c, id))
    )
  end
  assert subjects("layout/shared-reachable") == ["x"]
  assert subjects("layout/shared-has-proof") == ["r", "x"]
  assert spec_kind(
    first(calls(get(nikkusu::read("f { kind = k; }"), :root)))
  ) ==
    "computed"
end

test "trio/every-concept is the first rule the standard lists"
  assert get(first(rules()), :id) == "trio/every-concept"
end

test "the same declaration seen from two configurations is one finding"
  t = tree_case("lib/x.nix", :declaration)
  two = [t, assoc(t, :configuration, "nixosConfigurations.b")]
  xs = filter(
    fn(x) get(x, :rule) == "tree/pleme-options-declared-in-shared" end,
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
  f = first(filter(fn(f) get(f, :rule) == "layout/node-shape" end, fixtures()))
  xs = fired(fleet_repo(1), get(f, :bad), "layout/node-shape")
  assert sort_keyed(fn(t) t end, map(fn(x) get(x, :subject) end, xs)) ==
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
    fn(x) get(x, :rule) == "expr/no-angle-paths" end,
    get(r, :findings)
  )
  assert map(fn(x) get(x, :file) end, angle) == ["lib/b.nix"]
  assert size(get(r, :waived)) == 1
  assert get(r, :refusals) == []
end

test "a waiver without its typed skip reason is refused and covers nothing"
  c = example([["lib/a.nix", "import <nixpkgs> { }"]], [])
  cfg = waive(fleet_repo(1), "expr/no-angle-paths", "lib/**", "because")
  r = evaluate(cfg, in_memory(get(c, :sources)), [])
  assert size(get(r, :refusals)) == 1
  assert size(
    filter(fn(x) get(x, :rule) == "expr/no-angle-paths" end, get(r, :findings))
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
  assert map(fn(x) get(x, :file) end, get(judge([a, b], rows), :new)) ==
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
  assert map(fn(r) get(r, :kind) end, first(parts)) == ["expr/no-angle-paths"]
  assert get(judge([e], first(parts)), :orphans) == []
  assert baseline_with([e], nth(1, parts)) == baseline_text([t, e])
  assert size(first(split_rows(rows, ran_ids(fleet_repo(1), true)))) == 2
end

test "the rules listing is the standard: every rule, with why and fix"
  t = rules_text(fleet_repo(1))
  assert size(filter(fn(r) contains?(t, get(r, :id)) end, rules())) ==
    size(rules())
  assert contains?(t, "fleet-repo v1") == true
end

test "arguments: a command is required and flags are read"
  assert get(parse_args([]), :error) != nil
  assert get(parse_args(["lint"]), :error) != nil
  a = parse_args(["check", "--json", "--root", "/r", "--tree"])
  assert [get(a, :json), get(a, :root), get(a, :tree)] == [true, "/r", true]
  assert get(parse_args(["check", "--root"]), :error) != nil
end
