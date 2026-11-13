@moduledoc """
kijun (基準) — the standard a private nix fleet repo is held to, as data: layout, expression and evaluated-tree rules, per-entry waivers, and a baseline ratchet.

    nix_string("a\"b${c}\\") #=> "\"a\\\"b\\${c}\\\\\""
"""

use("deeta", %i[as_json get_str])
use("hadome")

use("jisho", %i[append_at from_entries])

use(
  "kakehashi/nikkusu",
  %i[
    angle_paths
    args_of
    attr
    bindings
    calls
    calls_named
    code
    config_relative
    head_name
    kind
    line_of
    literal_string?
    module_function?
    module_path
    named
    nodes_of
    nodes_where
    option_declarations
    string_content
  ]
)

use("kyohi", [:refusal])

use("moji", %i[after_first before_first glob_match? lines trim])

use("retsu", %i[first flat_map is_empty last rest size take_n])

use("settei")

use("shisutemu", %i[blue_exe read_or status_of stderr_of stdout_of])
use("shuugou", %i[frequencies unique])

@doc """
fleet_repo: the fleet-repo standard at `version`, as the config an instance's kijun.b starts from: the top-level allowlist, the node registry, import routes, declarers and the trio factory, with no waivers.

    fleet_repo(1)[:registry] #=> "lib/nodes.nix"
"""
def fleet_repo(version)
  {
    standard: "fleet-repo",
    version:,
    top: %w[
      flake.nix
      flake.lock
      fleet.nix
      lib
      modules
      profiles
      nodes
      users
      parts
      overlays
      pkgs
      docs
      secrets*.yaml
      .sops.yaml
      .github
      .gitignore
      .envrc
      CLAUDE.md
      AGENTS.md
      README.md
      LICENSE*
      nixosConfigurations
      darwinConfigurations
      homeConfigurations
      kijun.b
      kijun.baseline
    ],
    registry: "lib/nodes.nix",
    node_constructor: "mkNode",
    engine: ["parts/fleet.nix"],
    import_routes: %w[
      modules/pleme/nixos/default.nix
      modules/pleme/darwin/default.nix
      lib/fleet-universal-modules.nix
      parts/fleet.nix
      lib/nodes.nix
      nodes/*/default.nix
      profiles/*/default.nix
    ],
    declarers: %w[
      modules/pleme/shared/**
      modules/pleme/nixos/**
      modules/pleme/darwin/**
      modules/pleme/home-manager/**
    ],
    trio_factory: ["mkModuleTrio"],
    concept_consumers: %w[modules/** profiles/**],
    configurations: [],
    waivers: [],
    disabled: [],
    baseline: "kijun.baseline"
  }
end

@doc """
allow_top: an instance names extra top-level entries the standard does not.

    allow_top({top: ["lib"]}, ["bin"]) #=> {top: ["lib", "bin"]}
"""
def allow_top(cfg, entries)
  append_field(cfg, :top, entries)
end

@doc """
configurations: an instance names the configurations the tree plane evaluates.

    configurations({configurations: []}, ["nixosConfigurations.plo"]) #=> {configurations: ["nixosConfigurations.plo"]}
"""
def configurations(cfg, names)
  append_field(cfg, :configurations, names)
end

@doc """
append_field: `cfg` with `xs` appended to the list at `key`.

    append_field({top: ["a"]}, :top, ["b"]) #=> {top: ["a", "b"]}
"""
def append_field(cfg, key, xs)
  append_at(cfg, key, xs)
end

@doc """
waive: exempt one path from one rule with a reason.

    waive({waivers: []}, "expr/no-shell", "pkgs/a.nix", "skip-expr/no-shell: vendored")[:waivers] #=> [{rule: "expr/no-shell", glob: "pkgs/a.nix", reason: "skip-expr/no-shell: vendored"}]
"""
def waive(cfg, rule, glob, reason)
  assoc(cfg, :waivers, append(cfg[:waivers], [{rule:, glob:, reason:}]))
end

@doc """
disable: switch one rule off for an instance, with the reason it is off; the rule then runs nowhere.

    disable({disabled: []}, "expr/no-shell", "bootstrap repo") #=> {disabled: [{rule: "expr/no-shell", reason: "bootstrap repo"}]}
"""
def disable(cfg, rule, reason)
  assoc(cfg, :disabled, append(cfg[:disabled], [{rule:, reason:}]))
end

@doc """
finding: one violation of a rule: where it is, what it is about, and why it fails.

    finding("expr/no-angle-paths", "lib/a.nix", 1, "<nixpkgs>", "m")[:subject] #=> "<nixpkgs>"
"""
def finding(rule, file, line, subject, message)
  {rule:, file:, line:, subject:, message:}
end

@doc """
at: a finding inside a parsed file, located at the line that holds the offset `start`.

    f = file_facts("lib/a.nix", "{\n  x = 1;\n}")
    at(f, f[:doc], "expr/parses", 4, "x", "m")[:line] #=> 2
"""
def at(f, doc, rule, start, subject, message)
  finding(rule, f[:path], line_of(doc, start), subject, message)
end

@doc """
segments: the parts of a repository path, the unit every layout rule reads.

    segments("nodes/plo/default.nix") #=> ["nodes", "plo", "default.nix"]
"""
def segments(path)
  split(path, "/")
end

@doc """
top_entries: the repository's top-level entries, a directory marked with a trailing slash.

    top_entries(["flake.nix", "lib/a.nix", "lib/b.nix"]) #=> ["flake.nix", "lib/"]
"""
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

@doc """
allowed_top?: a top-level entry is one the standard's allowlist, or the instance's, matches.

    allowed_top?(fleet_repo(1), "bin/") #=> false
"""
def allowed_top?(cfg, entry)
  name = if ends_with?(entry, "/")
    before_first(entry, "/")
  else
    entry
  end
  not is_empty(filter((g) -> glob_match?(g, name), cfg[:top]))
end

@doc """
check_top: the layout/top-level rule: one finding per top-level entry the standard does not allow.

    map((x) -> x[:subject], check_top({config: fleet_repo(1), files: ["flake.nix", "stray.txt"]})) #=> ["stray.txt"]
"""
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
    filter((e) -> not allowed_top?(repo[:config], e), top_entries(repo[:files]))
  )
end

@doc """
node_dirs: the directory names under nodes/ that hold at least one file.

    node_dirs(["nodes/plo/default.nix", "nodes/README.md", "lib/a.nix"]) #=> ["plo"]
"""
def node_dirs(files)
  unique(
    map(
      (p) -> segments(p)[1],
      filter(
        (p) -> first(segments(p)) == "nodes" and size(segments(p)) > 2,
        files
      )
    )
  )
end

@doc """
node_dir_of: the node directory a registry's nodeDir path names, or nil when it names none.

    node_dir_of("../nodes/plo") #=> "plo"
"""
def node_dir_of(text)
  if contains?(text, "nodes/")
    before_first("#{after_first(text, "nodes/")}/", "/")
  end
end

@doc """
declared_nodes: the node directories the registry declares through the node constructor; none when there is no registry.

    repo = assoc(in_memory([["lib/nodes.nix", "{ plo = mkNode { name = \"plo\"; nodeDir = ../nodes/plo; }; }"]]), :config, fleet_repo(1))
    declared_nodes(repo) #=> ["plo"]
"""
def declared_nodes(repo)
  cfg = repo[:config]
  path = cfg[:registry]
  if member?(path, repo[:files])
    doc = kakehashi::nikkusu::read(source_of(repo, path))
    filter(
      (d) -> d != nil,
      map(
        fn(c)
          a = first(args_of(c[:node]))
          if a != nil and kind(a) == "NODE_ATTR_SET"
            v = attr(a, "nodeDir")
            if v.nil?
              nil
            else
              node_dir_of(code(v))
            end
          end
        end,
        calls_named(doc[:root], [cfg[:node_constructor]])
      )
    )
  else
    []
  end
end

@doc """
check_nodes: the layout/node-shape rule: a node directory with no default.nix, and a registry-declared node with no layers.nix.

    repo = assoc(in_memory([["nodes/zed/hw.nix", "{ }"]]), :config, fleet_repo(1))
    map((x) -> x[:subject], check_nodes(repo)) #=> ["default.nix"]
"""
def check_nodes(repo)
  files = repo[:files]
  declared = declared_nodes(repo)
  flat_map(
    node_dirs(files),
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
    end
  )
end

@doc """
shared_modules: the names of the shared options modules, one file each under modules/pleme/shared, its default.nix aside.

    shared_modules(["modules/pleme/shared/x.nix", "modules/pleme/shared/default.nix"]) #=> ["x"]
"""
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

@doc """
trio_calls: the calls of the trio factory in one file of the repository.

    repo = assoc(in_memory([trio_source("p", "package")]), :config, fleet_repo(1))
    size(trio_calls(repo, "modules/pleme/shared/p.nix")) #=> 1
"""
def trio_calls(repo, path)
  named(
    calls(kakehashi::nikkusu::read(source_of(repo, path))[:root]),
    repo[:config][:trio_factory]
  )
end

@doc """
spec_kind: the kind a trio call declares: its literal kind, "binary" when none is set, "computed" when it is not a literal.

    spec_kind(first(calls(kakehashi::nikkusu::read("f { kind = k; }")[:root]))) #=> "computed"
"""
def spec_kind(c)
  a = last(c[:args])
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

@doc """
self_rendering?: a shared module that calls the trio factory renders itself, since its module arm picks the platform.

    repo = assoc(in_memory([trio_source("b", nil)]), :config, fleet_repo(1))
    self_rendering?(repo, "b") #=> true
"""
def self_rendering?(repo, m)
  not is_empty(trio_calls(repo, "modules/pleme/shared/#{m}.nix"))
end

@doc """
factory_proven?: a shared module whose every trio call is a binary, package or service kind is proven by substrate's matrix, so it needs no harness of its own.

    repo = assoc(in_memory([trio_source("r", "registry")]), :config, fleet_repo(1))
    factory_proven?(repo, "r") #=> false
"""
def factory_proven?(repo, m)
  cs = trio_calls(repo, "modules/pleme/shared/#{m}.nix")
  not is_empty(cs) and
    is_empty(
      filter((c) -> not member?(spec_kind(c), %w[binary package service]), cs)
    )
end

@doc """
check_proof: the layout/shared-has-proof rule: a shared module with no parts/ harness that the factory does not prove.

    repo = assoc(in_memory([["modules/pleme/shared/x.nix", "{ }"]]), :config, fleet_repo(1))
    map((x) -> x[:subject], check_proof(repo)) #=> ["x"]
"""
def check_proof(repo)
  files = repo[:files]
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

@doc """
route_files: the repository's files that the config names as import routes.

    route_files({config: fleet_repo(1), files: ["profiles/p/default.nix", "lib/a.nix"]}) #=> ["profiles/p/default.nix"]
"""
def route_files(repo)
  files = repo[:files]
  filter(
    fn(p)
      not is_empty(
        filter((g) -> glob_match?(g, p), repo[:config][:import_routes])
      )
    end,
    files
  )
end

@doc """
check_reachable: the layout/shared-reachable rule: a shared module no renderer, import route or trio call reaches.

    repo = assoc(in_memory([["modules/pleme/shared/x.nix", "{ }"]]), :config, fleet_repo(1))
    map((x) -> x[:subject], check_reachable(repo)) #=> ["x"]
"""
def check_reachable(repo)
  files = repo[:files]
  routes = map(
    (p) -> code(kakehashi::nikkusu::read(source_of(repo, p))[:root]),
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

@doc """
binding_finding: a finding about one attribute binding, located at the binding and named by its dotted path.

    f = file_facts("profiles/p/default.nix", "{ networking.hostName = \"plo\"; }")
    binding_finding("expr/profile-no-identity", f, first(module_bindings(f)), "m")[:subject] #=> "networking.hostName"
"""
def binding_finding(rule, f, b, message)
  at(f, f[:doc], rule, b[:start], b[:dotted], message)
end

@doc """
module_bindings: the attribute-set bindings of a parsed file, the ones a module sets.

    size(module_bindings(file_facts("lib/a.nix", "{ a = 1; b = 2; }"))) #=> 2
"""
def module_bindings(f)
  filter((b) -> b[:scope] == :attrs, f[:bindings])
end

@doc """
starts?: an option path begins with the given prefix of segments.

    starts?(["sops", "secrets", "k"], ["sops", "secrets"]) #=> true
"""
def starts?(path, prefix)
  size(path) >= size(prefix) and take(size(prefix), path) == prefix
end

@doc """
check_system_calls: the expr/node-system-only-via-mkNode rule: a nixosSystem or darwinSystem call outside the node engine.

    f = file_facts("parts/nixos.nix", "{ a = inputs.nixpkgs.lib.nixosSystem { modules = [ ]; }; }")
    size(check_system_calls(f, {config: fleet_repo(1)})) #=> 1
"""
def check_system_calls(f, repo)
  if not is_empty(
    filter((g) -> glob_match?(g, f[:path]), repo[:config][:engine])
  )
    []
  else
    map(
      fn(c)
        at(
          f,
          f[:doc],
          "expr/node-system-only-via-mkNode",
          c[:start],
          c[:head],
          "#{c[:head]} builds a system outside the node engine; declare the node through the registry"
        )
      end,
      named(f[:calls], %w[nixosSystem darwinSystem])
    )
  end
end

@doc """
identity?: a binding sets a node's identity: its hostname or hostId, a disk by UUID, or a secret from a node's directory.

    identity?(first(module_bindings(file_facts("profiles/p/default.nix", "{ networking.hostName = \"plo\"; }")))) #=> true
"""
def identity?(b)
  p = module_path(b)
  v = b[:value]
  if p == %w[networking hostName] or p == %w[networking hostId]
    true
  elsif size(p) >= 3 and first(p) == "fileSystems" and last(p) == "device"
    v != nil and contains?(code(v), "by-uuid")
  elsif starts?(p, %w[sops secrets]) and last(p) == "sopsFile"
    v != nil and contains?(code(v), "nodes/")
  else
    false
  end
end

@doc """
check_profile_identity: the expr/profile-no-identity rule: a profile that sets a node's identity.

    f = file_facts("profiles/p/default.nix", "{ networking.hostName = \"plo\"; networking.firewall.enable = true; }")
    size(check_profile_identity(f, nil)) #=> 1
"""
def check_profile_identity(f, _repo)
  map(
    fn(b)
      binding_finding(
        "expr/profile-no-identity",
        f,
        b,
        "a profile sets #{b[:dotted]}, which is a node's identity; set it in the node"
      )
    end,
    filter(identity?, module_bindings(f))
  )
end

@doc """
declaration_findings: one finding of `rule` per option a file declares, saying where the declaration sits.

    f = file_facts("lib/a.nix", "{ lib, ... }: { options.x = lib.mkOption { }; }")
    size(declaration_findings("expr/lib-is-data", f, "lib/")) > 0 #=> true
"""
def declaration_findings(rule, f, where)
  map(
    fn(d)
      at(
        f,
        f[:doc],
        rule,
        d[:start],
        d[:at],
        "#{where} declares an option (#{d[:at]})"
      )
    end,
    option_declarations(f[:root])
  )
end

@doc """
check_lib_data: the expr/lib-is-data rule: an option declaration or a module function in lib/.

    check_lib_data(file_facts("lib/a.nix", "{ lib }: { x = 1; options = [ \"a\" ]; }"), nil) #=> []
"""
def check_lib_data(f, _repo)
  modules = map(
    fn(l)
      at(
        f,
        f[:doc],
        "expr/lib-is-data",
        l[:start],
        "module function",
        "a module function (a lambda taking config) lives in lib/, which holds data"
      )
    end,
    nodes_where((n) -> module_function?(n), f[:root])
  )
  append(declaration_findings("expr/lib-is-data", f, "lib/"), modules)
end

@doc """
platform_prefixes: the config paths only a platform renderer may emit, since each exists on one platform only.

    member?(["launchd"], platform_prefixes) #=> true
"""
def platform_prefixes()
  [
    ["systemd"],
    ["launchd"],
    %w[environment etc],
    %w[environment systemPackages],
    %w[networking firewall],
    %w[networking hosts],
    %w[security sudo],
    %w[users users],
    ["boot"],
    ["homebrew"]
  ]
end

@doc """
platform_path?: a binding path lands under a platform prefix; an option declaration never does.

    platform_path?(["systemd", "services", "x"]) #=> true
"""
def platform_path?(path)
  p = config_relative(path)
  first(path) != "options" and
    not is_empty(filter((x) -> starts?(p, x), platform_prefixes))
end

@doc """
emits_platform?: a binding is the outermost one that emits platform config, so a nested emission is named once.

    emits_platform?({path: ["systemd", "services", "x"], outer: nil}) #=> true
"""
def emits_platform?(b)
  o = b[:outer]
  platform_path?(b[:path]) and (o.nil? or not platform_path?(o))
end

@doc """
check_shared_emission: the expr/shared-declares-only rule: a shared module that emits platform config.

    f = file_facts("modules/pleme/shared/x.nix", module_with("  config = lib.mkIf config.pleme.x.enable { pleme.y = 1; };"))
    check_shared_emission(f, nil) #=> []
"""
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

@doc """
check_shared_platform_question: the expr/shared-asks-no-platform rule: a shared module that asks isDarwin or isLinux.

    f = file_facts("modules/pleme/shared/x.nix", module_with("  pleme.x = pkgs.stdenv.hostPlatform.isDarwin;"))
    map((x) -> x[:subject], check_shared_platform_question(f, nil)) #=> ["pkgs.stdenv.hostPlatform.isDarwin"]
"""
def check_shared_platform_question(f, _repo)
  map(
    fn(n)
      at(
        f,
        f[:doc],
        "expr/shared-asks-no-platform",
        n[:start],
        code(n),
        "a shared module asks #{code(n)}, a rendering decision"
      )
    end,
    nodes_where(
      fn(n)
        kind(n) == "NODE_SELECT" and
          member?(last(split(code(n), ".")), %w[isDarwin isLinux])
      end,
      f[:root]
    )
  )
end

@doc """
check_node_options: the expr/nodes-declare-no-options rule: an option declared in a node file.

    check_node_options(file_facts("nodes/plo/default.nix", module_with("  pleme.x = true;")), nil) #=> []
"""
def check_node_options(f, _repo)
  declaration_findings("expr/nodes-declare-no-options", f, "a node file")
end

@doc """
check_angle: the expr/no-angle-paths rule: an angle path, which NIX_PATH resolves and the flake lock does not pin.

    map((x) -> x[:subject], check_angle(file_facts("lib/a.nix", "import <nixpkgs> { }"), nil)) #=> ["<nixpkgs>"]
"""
def check_angle(f, _repo)
  map(
    fn(p)
      at(
        f,
        f[:doc],
        "expr/no-angle-paths",
        p[:start],
        p[:path],
        "#{p[:path]} resolves through NIX_PATH, which a flake does not pin"
      )
    end,
    angle_paths(f[:root])
  )
end

@doc """
fetchers: the fetch functions the unpinned-fetch rule reads.

    member?("fetchFromGitHub", fetchers) #=> true
"""
def fetchers()
  %w[
    fetchTarball
    fetchurl
    fetchzip
    fetchGit
    fetchgit
    fetchTree
    fetchFromGitHub
    fetchFromGitLab
  ]
end

@doc """
pin_attrs: the attributes any one of which pins a fetch to its content.

    member?("narHash", pin_attrs) #=> true
"""
def pin_attrs()
  %w[hash sha256 narHash outputHash rev]
end

@doc """
unpinned?: a fetch call carries no pin: a bare URL, or an attribute set with no hash or rev.

    unpinned?(first(calls(kakehashi::nikkusu::read("fetchurl { url = \"https://example.invalid/b\"; }")[:root]))) #=> true
"""
def unpinned?(c)
  a = first(c[:args])
  if a.nil?
    false
  elsif kind(a) == "NODE_ATTR_SET"
    is_empty(filter((k) -> attr(a, k) != nil, pin_attrs))
  else
    kind(a) == "NODE_STRING" or kind(a) == "NODE_PATH_ABS"
  end
end

@doc """
check_fetch: the expr/no-unpinned-fetch rule: a fetch that takes whatever the server serves today.

    f = file_facts("lib/a.nix", "builtins.fetchTarball { url = \"https://example.invalid/a.tar.gz\"; sha256 = \"0abc\"; }")
    check_fetch(f, nil) #=> []
"""
def check_fetch(f, _repo)
  map(
    fn(c)
      at(
        f,
        f[:doc],
        "expr/no-unpinned-fetch",
        c[:start],
        c[:head],
        "#{c[:head]} with no hash fetches whatever the server serves today"
      )
    end,
    filter(unpinned?, named(f[:calls], fetchers))
  )
end

@doc """
script_body: the argument of a script-writing call that holds its shell text, which sits at a different place for each writer.

    c = first(named(calls(kakehashi::nikkusu::read("writeShellScript \"a\" \"echo hi\"")[:root]), scripts))
    string_content(script_body(c)) #=> "echo hi"
"""
def script_body(c)
  n = head_name(c)
  args = c[:args]
  if n == "writeShellApplication"
    if first(args) != nil and kind(first(args)) == "NODE_ATTR_SET"
      attr(first(args), "text")
    end
  elsif member?(n, %w[runCommand runCommandLocal runCommandNoCC runCommandCC])
    args[2]
  else
    args[1]
  end
end

@doc """
script_lines: the non-blank lines of a literal script body; 0 when the body is not a literal string.

    script_lines(nil) #=> 0
"""
def script_lines(body)
  if body.nil? or kind(body) != "NODE_STRING"
    0
  else
    size(filter((l) -> trim(l) != "", lines(string_content(body))))
  end
end

@doc """
scripts: the nixpkgs writers that carry shell text, the calls the no-shell rule reads.

    member?("writeShellApplication", scripts) #=> true
"""
def scripts()
  %w[
    writeShellScript
    writeShellScriptBin
    writeShellApplication
    writeScript
    writeScriptBin
    runCommand
    runCommandLocal
    runCommandNoCC
    runCommandCC
  ]
end

@doc """
check_shell: the expr/no-shell rule: a script writer carrying more than three lines of shell.

    f = file_facts("pkgs/a.nix", join_lines(["pkgs.writeShellScript \"a\" ''", "  one", "  two", "  three", "  four", "''"]))
    size(check_shell(f, nil)) #=> 1
"""
def check_shell(f, _repo)
  map(
    fn(c)
      at(
        f,
        f[:doc],
        "expr/no-shell",
        c[:start],
        c[:head],
        "#{c[:head]} carries #{to_s(script_lines(script_body(c)))} lines of shell; past 3 lines it is a typed tool"
      )
    end,
    filter((c) -> script_lines(script_body(c)) > 3, named(f[:calls], scripts))
  )
end

@doc """
check_parses: the expr/parses rule: the first parse error of a file, since a file the parser refuses is checked by no rule.

    map((x) -> x[:subject], check_parses(file_facts("lib/a.nix", "{ a = ; }"), nil)) #=> ["parse"]
"""
def check_parses(f, _repo)
  map(
    fn(e)
      at(
        f,
        f[:doc],
        "expr/parses",
        e[:start],
        "parse",
        "does not parse: #{e[:message]}"
      )
    end,
    take_n(f[:doc][:errors], 1)
  )
end

@doc """
own_file: a store path from an evaluated tree, as a path in this repository; nil when it lies outside the repository's own source.

    own_file({own: "/nix/store/h-source"}, "/nix/store/h-source/lib/x.nix") #=> "lib/x.nix"
"""
def own_file(tree, file)
  own = tree[:own]
  if own != nil and own != "" and starts_with?(file, "#{own}/")
    after_first(file, "#{own}/")
  end
end

@doc """
check_pleme_declarations: the tree/pleme-options-declared-in-shared rule: a pleme.* option declared outside the declarer globs.

    map((x) -> x[:file], check_pleme_declarations(tree_case("lib/x.nix", :declaration), {config: fleet_repo(1)})) #=> ["lib/x.nix"]
"""
def check_pleme_declarations(tree, repo)
  declarers = repo[:config][:declarers]
  flat_map(
    tree[:pleme],
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
            o[:path],
            "#{o[:path]} is declared in #{where}, not under modules/pleme/{shared,<platform>}"
          )
        end,
        filter(
          fn(d)
            rel = own_file(tree, d)
            rel.nil? or is_empty(filter((g) -> glob_match?(g, rel), declarers))
          end,
          o[:declarations]
        )
      )
    end
  )
end

@doc """
check_hostname: the tree/hostname-from-node rule: networking.hostName defined anywhere but under nodes/.

    check_hostname(tree_case("nodes/a/default.nix", :definition), nil) #=> []
"""
def check_hostname(tree, _repo)
  flat_map(
    tree[:hostname],
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
            "#{tree[:configuration]} networking.hostName",
            "networking.hostName of #{tree[:configuration]} is defined in #{shown}, not under nodes/"
          )
        end,
        filter(
          fn(d)
            rel = own_file(tree, d)
            rel.nil? or not glob_match?("nodes/**", rel)
          end,
          o[:definitions]
        )
      )
    end
  )
end

@doc """
declared_at: the repository file that declares an option in an evaluated tree, or "(external)" when no own file does.

    declared_at(tree_case("lib/x.nix", :declaration), "pleme.x") #=> "lib/x.nix"
"""
def declared_at(tree, option)
  hit = filter((o) -> o[:path] == option, append(tree[:pleme], tree[:hostname]))
  rels = filter(
    (r) -> r != nil,
    map((d) -> own_file(tree, d), flat_map(hit, (o) -> o[:declarations]))
  )
  if is_empty(rels)
    "(external)"
  else
    first(rels)
  end
end

@doc """
check_option_evaluates: the tree/option-evaluates rule: one finding per option the tree probe could not evaluate, at its declaration.

    map((x) -> x[:file], check_option_evaluates(tree_case("modules/pleme/shared/x.nix", :blind), nil)) #=> ["modules/pleme/shared/x.nix"]
"""
def check_option_evaluates(tree, _repo)
  map(
    fn(b)
      finding(
        "tree/option-evaluates",
        declared_at(tree, b[:option]),
        0,
        "#{tree[:configuration]} #{b[:option]}",
        "#{b[:option]} does not evaluate on #{tree[:configuration]} (#{b[:error]}), so no tree rule sees its definitions there"
      )
    end,
    or_list(tree[:blind])
  )
end

@doc """
unit_kinds: the kinds of concept the trio rule counts.

    unit_kinds #=> [:shared, :package, :overlay, :registry]
"""
def unit_kinds()
  %i[shared package overlay registry]
end

@doc """
unit: one concept the fleet manages: its kind, its name, the file or directory that holds it, and its nix files.

    unit(:package, "p", "pkgs/p/", ["pkgs/p/default.nix"])[:name] #=> "p"
"""
def unit(kind_of, name, file, files)
  {kind: kind_of, name:, file:, files:}
end

@doc """
nix_under: the nix files under a path prefix.

    nix_under(["pkgs/p/default.nix", "pkgs/p/src/main.rs"], "pkgs/") #=> ["pkgs/p/default.nix"]
"""
def nix_under(files, prefix)
  filter((p) -> starts_with?(p, prefix) and ends_with?(p, ".nix"), files)
end

@doc """
dir_units: the concepts directly under `root`: each nix file one unit, each subdirectory one unit, minus the files in `skip`.

    fs = ["pkgs/default.nix", "pkgs/a.nix", "pkgs/p/default.nix"]
    map((u) -> u[:name], dir_units(fs, "pkgs", :package, ["pkgs/default.nix"], fs)) #=> ["a", "p"]
"""
def dir_units(files, root, kind_of, skip, pool)
  depth = size(segments(root))
  under = filter((p) -> starts_with?(p, "#{root}/"), pool)
  singles = map(
    (p) -> unit(kind_of, before_first(segments(p)[depth], ".nix"), p, [p]),
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
      (p) -> segments(p)[depth],
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

@doc """
returned_set: the attribute set an expression evaluates to, looking through lambdas, let and parentheses; nil when it is not one.

    kind(returned_set(kakehashi::nikkusu::read("final: prev: { o = 1; }")[:root])) #=> "NODE_ATTR_SET"
"""
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

@doc """
overlay_units: one concept per package an overlay file adds, named by its top-level attribute.

    repo = assoc(in_memory([["overlays/o.nix", "final: prev: { o = prev.hello; }"]]), :config, fleet_repo(1))
    map((u) -> u[:name], overlay_units(repo)) #=> ["o"]
"""
def overlay_units(repo)
  flat_map(
    filter(
      fn(p)
        size(segments(p)) == 2 and
          p != "overlays/default.nix" and
          ends_with?(p, ".nix")
      end,
      nix_under(repo[:files], "overlays/")
    ),
    fn(p)
      set = returned_set(kakehashi::nikkusu::read(source_of(repo, p))[:root])
      if set.nil?
        []
      else
        map(
          (a) -> unit(:overlay, a, p, [p]),
          unique(
            map(
              (b) -> first(b[:path]),
              filter(
                (b) -> b[:scope] == :attrs and b[:outer].nil?,
                bindings(set)
              )
            )
          )
        )
      end
    end
  )
end

@doc """
resolve: path segments applied to a directory, "." and ".." resolved.

    resolve(["..", "lib", "r.nix"], ["modules", "pleme"]) #=> ["modules", "lib", "r.nix"]
"""
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

@doc """
relative_to: the repository path a relative import in `file` names.

    relative_to("modules/pleme/nixos/a.nix", "../../../lib/r.nix") #=> "lib/r.nix"
"""
def relative_to(file, rel)
  dir = take(size(segments(file)) - 1, segments(file))
  join(resolve(segments(rel), dir), "/")
end

@doc """
imported_files: the repository files a parsed file imports by relative path.

    imported_files(file_facts("modules/pleme/nixos/use.nix", "let r = import ../../../lib/r.nix; in { }")) #=> ["lib/r.nix"]
"""
def imported_files(f)
  map(
    (c) -> relative_to(f[:path], code(first(c[:args]))),
    filter(
      fn(c)
        first(c[:args]) != nil and kind(first(c[:args])) == "NODE_PATH_REL"
      end,
      named(f[:calls], ["import"])
    )
  )
end

@doc """
spec_names: the concept names a trio call covers: its literal name and packageAttr.

    spec_names(first(calls(kakehashi::nikkusu::read("mkModuleTrio { name = \"tools\"; packageAttr = \"p\"; }")[:root]))) #=> ["tools", "p"]
"""
def spec_names(c)
  a = last(c[:args])
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
        %w[name packageAttr]
      )
    )
  end
end

@doc """
concept_facts: what the trio rule reads of the repository: the files that call the factory, the names their specs cover, what they import, and what the configuration layers import.

    repo = assoc(in_memory(concept_sources(false)), :config, fleet_repo(1))
    concept_facts(repo)[:consumed] #=> ["lib/r.nix"]
"""
def concept_facts(repo)
  cfg = repo[:config]
  files = repo[:files]
  wanted = filter(
    fn(p)
      ends_with?(p, ".nix") and
        (
          starts_with?(p, "modules/") or
          starts_with?(p, "profiles/") or
          starts_with?(p, "pkgs/") or
          starts_with?(p, "overlays/") or
          starts_with?(p, "lib/")
        )
    end,
    files
  )
  facts = map((p) -> file_facts(p, source_of(repo, p)), wanted)
  trio = filter(
    (f) -> not is_empty(named(f[:calls], cfg[:trio_factory])),
    facts
  )
  consumers = filter(
    fn(f)
      not is_empty(
        filter((g) -> glob_match?(g, f[:path]), cfg[:concept_consumers])
      )
    end,
    facts
  )
  {
    trio_files: map((f) -> f[:path], trio),
    names: unique(
      flat_map(
        trio,
        (f) -> flat_map(named(f[:calls], cfg[:trio_factory]), spec_names)
      )
    ),
    trio_imports: unique(flat_map(trio, imported_files)),
    consumed: unique(flat_map(consumers, imported_files))
  }
end

@doc """
registry_units: one concept per lib/ file a configuration layer imports; a registry nobody reads as configuration is not one.

    map((u) -> u[:name], registry_units(["lib/r.nix", "lib/unread.nix"], {consumed: ["lib/r.nix"]})) #=> ["r"]
"""
def registry_units(files, facts)
  map(
    (p) -> unit(:registry, before_first(segments(p)[1], ".nix"), p, [p]),
    filter(
      fn(p)
        size(segments(p)) == 2 and
          starts_with?(p, "lib/") and
          ends_with?(p, ".nix") and
          member?(p, facts[:consumed])
      end,
      files
    )
  )
end

@doc """
concept_units: every concept the fleet manages: shared modules, packages, overlay-added packages and consumed registries.

    repo = assoc(in_memory(concept_sources(false)), :config, fleet_repo(1))
    map((u) -> to_s(u[:kind]), concept_units(repo, concept_facts(repo))) #=> ["shared", "package", "overlay", "registry"]
"""
def concept_units(repo, facts)
  files = repo[:files]
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

@doc """
covered?: a concept is declared through the trio factory: one of its files calls it, a spec names it, or a trio file imports the registry.

    covered?({kind: :package, name: "p", file: "pkgs/p/", files: []}, {trio_files: [], names: ["p"], trio_imports: []}) #=> true
"""
def covered?(u, facts)
  not is_empty(filter((p) -> member?(p, facts[:trio_files]), u[:files])) or
    member?(u[:name], facts[:names]) or
    u[:kind] == :registry and member?(u[:file], facts[:trio_imports])
end

@doc """
check_concepts: the trio/every-concept rule: a concept not declared through the module-trio factory.

    check_concepts(assoc(in_memory(concept_sources(true)), :config, fleet_repo(1))) #=> []
"""
def check_concepts(repo)
  facts = concept_facts(repo)
  map(
    fn(u)
      finding(
        "trio/every-concept",
        u[:file],
        0,
        "#{to_s(u[:kind])} #{u[:name]}",
        "the #{to_s(u[:kind])} concept #{u[:name]} is not declared through the module-trio factory; declare it with mkModuleTrio { kind = ...; } so it has one type-known interface on every arm"
      )
    end,
    filter((u) -> not covered?(u, facts), concept_units(repo, facts))
  )
end

@doc """
rule: one rule of the standard: its id, the plane it reads, whether it gates or advises, the paths it covers, why it holds, how to fix a finding, and the check that finds them.

    rule("x/y", :layout, :gate, ["*"], "why", "fix", check_top)[:tier] #=> :gate
"""
def rule(id, plane, tier, scope, why, fix, check)
  {id:, plane:, tier:, scope:, why:, fix:, check:}
end

@doc """
rules: the standard itself: every rule, in the order `kijun rules` lists them.

    first(rules)[:id] #=> "trio/every-concept"
"""
def rules()
  [
    rule(
      "trio/every-concept",
      :layout,
      :gate,
      %w[modules/pleme/shared/** pkgs/** overlays/*.nix lib/*.nix],
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

@doc """
disabled_ids: the ids of the rules an instance switched off.

    disabled_ids({disabled: [{rule: "expr/no-shell", reason: "r"}]}) #=> ["expr/no-shell"]
"""
def disabled_ids(cfg)
  map((d) -> d[:rule], cfg[:disabled])
end

@doc """
active: the rules of one plane that run for an instance, its disabled ones left out.

    map((r) -> r[:id], active(disable(fleet_repo(1), "tree/option-evaluates", "r"), :tree)) #=> ["tree/pleme-options-declared-in-shared", "tree/hostname-from-node"]
"""
def active(cfg, plane)
  filter(
    (r) -> r[:plane] == plane and not member?(r[:id], disabled_ids(cfg)),
    rules
  )
end

@doc """
in_scope?: a rule reads a path when one of its scope globs matches it.

    in_scope?({scope: ["nodes/**"]}, "nodes/plo/default.nix") #=> true
"""
def in_scope?(r, path)
  not is_empty(filter((g) -> glob_match?(g, path), r[:scope]))
end

@doc """
file_facts: one nix file parsed once for every expression rule: its path, syntax tree, bindings and calls.

    size(file_facts("lib/a.nix", "{ a = 1; }")[:bindings]) #=> 1
"""
def file_facts(path, source)
  doc = kakehashi::nikkusu::read(source)
  {
    path:,
    doc:,
    root: doc[:root],
    bindings: bindings(doc[:root]),
    calls: calls(doc[:root])
  }
end

@doc """
expression_findings: every active expression rule run over each nix file in its scope; a file no rule covers is not parsed.

    repo = assoc(in_memory([["lib/a.nix", "import <nixpkgs> { }"]]), :config, fleet_repo(1))
    map((x) -> x[:rule], expression_findings(repo)) #=> ["expr/no-angle-paths"]
"""
def expression_findings(repo)
  rs = active(repo[:config], :expression)
  flat_map(
    filter((p) -> ends_with?(p, ".nix"), repo[:files]),
    fn(p)
      mine = filter((r) -> in_scope?(r, p), rs)
      if is_empty(mine)
        []
      else
        f = file_facts(p, source_of(repo, p))
        flat_map(mine, (r) -> r[:check](f, repo))
      end
    end
  )
end

@doc """
layout_findings: every active layout rule run over the repository's file list.

    repo = assoc(in_memory([["flake.nix", "{ }"], ["stray.txt", ""]]), :config, fleet_repo(1))
    map((x) -> x[:rule], layout_findings(repo)) #=> ["layout/top-level"]
"""
def layout_findings(repo)
  flat_map(active(repo[:config], :layout), (r) -> r[:check](repo))
end

@doc """
tree_findings: every active tree rule run over each evaluated configuration tree.

    map((x) -> x[:rule], tree_findings({config: fleet_repo(1)}, [tree_case("lib/x.nix", :declaration)])) #=> ["tree/pleme-options-declared-in-shared"]
"""
def tree_findings(repo, trees)
  rs = active(repo[:config], :tree)
  flat_map(trees, (t) -> flat_map(rs, (r) -> r[:check](t, repo)))
end

@doc """
waiver_refusal: why a waiver is refused: its reason is not a typed `skip-<rule>:` line, or it names no rule of the standard; nil when it is sound.

    kyohi::why(waiver_refusal({rule: "expr/nope", glob: "**", reason: "skip-expr/nope: x"})) #=> "expr/nope is not a rule of the standard"
"""
def waiver_refusal(w)
  prefix = "skip-#{w[:rule]}: "
  reason = w[:reason]
  if not starts_with?(reason, prefix) or trim(after_first(reason, prefix)) == ""
    refusal(
      :waiver,
      "the waiver of #{w[:rule]} for #{w[:glob]} must read \"#{prefix}<typed reason>\""
    )
  elsif is_empty(filter((r) -> r[:id] == w[:rule], rules))
    refusal(:waiver, "#{w[:rule]} is not a rule of the standard")
  end
end

@doc """
valid_waivers: the waivers that hold; a refused one covers nothing.

    valid_waivers({waivers: [{rule: "expr/no-shell", glob: "**", reason: "because"}]}) #=> []
"""
def valid_waivers(cfg)
  filter((w) -> waiver_refusal(w).nil?, cfg[:waivers])
end

@doc """
config_refusals: every refused waiver and every disable naming no rule, each refused alone.

    size(config_refusals({waivers: [], disabled: [{rule: "x/y", reason: "r"}]})) #=> 1
"""
def config_refusals(cfg)
  append(
    filter((x) -> x != nil, map(waiver_refusal, cfg[:waivers])),
    map(
      (d) -> refusal(:disable, "#{d[:rule]} is not a rule of the standard"),
      filter(
        (d) -> is_empty(filter((r) -> r[:id] == d[:rule], rules)),
        cfg[:disabled]
      )
    )
  )
end

@doc """
waived?: a finding is covered by a waiver of its rule whose glob matches its file.

    waived?([{rule: "expr/no-angle-paths", glob: "lib/*"}], {rule: "expr/no-angle-paths", file: "lib/a.nix"}) #=> true
"""
def waived?(ws, x)
  not is_empty(
    filter((w) -> w[:rule] == x[:rule] and glob_match?(w[:glob], x[:file]), ws)
  )
end

@doc """
tier_of: whether a rule gates or only advises.

    tier_of("expr/no-shell") #=> :advise
"""
def tier_of(id)
  rule_field(id, :tier)
end

@doc """
rule_field: the value at `key` of the rule whose id is `id`; an unknown id raises.

    rule_field("trio/every-concept", :tier) #=> :gate
"""
def rule_field(id, key)
  get(first(filter((r) -> r[:id] == id, rules)), key)
end

@doc """
key_of: the baseline key of a finding, its file and subject, so a moved line keeps its row.

    key_of({file: "lib/a.nix", subject: "<nixpkgs>"}) #=> "lib/a.nix::<nixpkgs>"
"""
def key_of(x)
  "#{x[:file]}::#{x[:subject]}"
end

@doc """
measurements: findings counted per key, as the ratchet's measurements.

    size(measurements([{file: "a", subject: "s"}, {file: "a", subject: "s"}])) #=> 1
"""
def measurements(xs)
  map((p) -> hadome::measurement(first(p), p[1]), frequencies(map(key_of, xs)))
end

@doc """
rule_ids: the rules that have findings, each once, in first-seen order.

    rule_ids([{rule: "a"}, {rule: "b"}, {rule: "a"}]) #=> ["a", "b"]
"""
def rule_ids(xs)
  unique(map((x) -> x[:rule], xs))
end

@doc """
baseline_text: the kijun.baseline a set of gate findings records.

    baseline_text([finding("expr/no-angle-paths", "lib/a.nix", 1, "<nixpkgs>", "m")]) #=> "expr/no-angle-paths: lib/a.nix::<nixpkgs> 1\n"
"""
def baseline_text(gates)
  baseline_with(gates, [])
end

@doc """
baseline_with: the baseline for this run's gate findings, keeping the rows of planes that did not run.

    t = finding("tree/hostname-from-node", "(external)", 0, "a networking.hostName", "m")
    baseline_with([], hadome::parse(baseline_text([t]))) #=> baseline_text([t])
"""
def baseline_with(gates, kept)
  own = map(
    (id) -> [id, measurements(filter((x) -> x[:rule] == id, gates))],
    rule_ids(gates)
  )
  held = map(
    fn(id)
      [
        id,
        map(
          (r) -> hadome::measurement(r[:key], r[:size]),
          filter((r) -> r[:kind] == id, kept)
        )
      ]
    end,
    unique(map((r) -> r[:kind], kept))
  )
  join(
    map(
      (p) -> hadome::render(first(p), p[1]),
      sort_keyed((p) -> first(p), append(own, held))
    ),
    ""
  )
end

@doc """
ran_ids: the ids of the rules this run executes; the tree plane runs only with --tree.

    member?("tree/hostname-from-node", ran_ids(fleet_repo(1), false)) #=> false
"""
def ran_ids(cfg, tree)
  planes = if tree
    %i[layout expression tree]
  else
    %i[layout expression]
  end
  map((r) -> r[:id], flat_map(planes, (p) -> active(cfg, p)))
end

@doc """
split_rows: baseline rows split into those of rules that ran, which are judged, and the rest, which are kept as they are.

    split_rows([{kind: "a"}, {kind: "b"}], ["a"]) #=> [[{kind: "a"}], [{kind: "b"}]]
"""
def split_rows(rows, ids)
  [
    filter((r) -> member?(r[:kind], ids), rows),
    filter((r) -> not member?(r[:kind], ids), rows)
  ]
end

@doc """
judge: the ratchet's verdict: gate findings outside the baseline are new, baseline rows no finding holds are orphans, and rows whose count fell can shrink.

    a = finding("expr/no-angle-paths", "lib/a.nix", 1, "<nixpkgs>", "m")
    b = finding("expr/no-angle-paths", "lib/b.nix", 1, "<nixpkgs>", "m")
    map((x) -> x[:file], judge([a, b], hadome::parse(baseline_text([a])))[:new]) #=> ["lib/b.nix"]
"""
def judge(gates, rows)
  ids = unique(append(rule_ids(gates), map((r) -> r[:kind], rows)))
  per = map(
    fn(id)
      mine = filter((x) -> x[:rule] == id, gates)
      ms = measurements(mine)
      fresh = hadome::failures(rows, id, ms)
      bad_keys = map(
        (m) -> m[:key],
        filter(
          (m) -> hadome::judge(rows, id, m[:key], m[:size]) != {verdict: :held},
          ms
        )
      )
      {
        rule: id,
        failures: fresh,
        new: filter((x) -> member?(key_of(x), bad_keys), mine),
        orphans: hadome::orphans(rows, id, map((m) -> m[:key], ms)),
        shrunk: hadome::shrunk(rows, id, ms)
      }
    end,
    ids
  )
  {
    new: flat_map(per, (p) -> p[:new]),
    failures: flat_map(per, (p) -> p[:failures]),
    orphans: flat_map(per, (p) -> map((k) -> "#{p[:rule]}: #{k}", p[:orphans])),
    shrunk: flat_map(
      per,
      (p) -> map((m) -> "#{p[:rule]}: #{m[:key]} #{to_s(m[:size])}", p[:shrunk])
    )
  }
end

@doc """
nix_string: a text as a nix string literal, quotes, backslashes and interpolation escaped.

    nix_string("pleme.a") #=> "\"pleme.a\""
"""
def nix_string(s)
  "\"#{replace(replace(replace(s, "\\", "\\\\"), "\"", "\\\""), "$", "\\$")}\""
end

@doc """
tree_expr: the nix function the tree probe applies to a configuration: the declarations and definitions of every pleme.* option and of networking.hostName, skipping the options already known not to evaluate.

    contains?(tree_expr(["pleme.a"]), "excluded = [ \"pleme.a\" ]") #=> true
"""
def tree_expr(excluded)
  skip = join(map(nix_string, excluded), " ")
  "c: let lib = c.pkgs.lib; excluded = [ #{skip} ]; defsOf = d: v: if builtins.elem d excluded then { definitions = [ ]; threw = false; } else let fs = builtins.addErrorContext (\"kijun\" + \"-option \" + d) (map (x: x.file) (v.definitionsWithLocations or [ ])); r = builtins.tryEval (builtins.deepSeq fs fs); in if r.success then { definitions = r.value; threw = false; } else { definitions = [ ]; threw = true; }; walk = path: v: if lib.isOption v then [ ({ path = lib.concatStringsSep \".\" path; declarations = v.declarations or [ ]; } // defsOf (lib.concatStringsSep \".\" path) v) ] else if builtins.isAttrs v && !(lib.isDerivation v) then lib.concatLists (lib.mapAttrsToList (n: x: walk (path ++ [ n ]) x) v) else [ ]; in { pleme = walk [ \"pleme\" ] (c.options.pleme or { }); hostname = walk [ \"networking\" \"hostName\" ] (c.options.networking.hostName or { }); }"
end

@doc """
failing_option: the option whose evaluation failed, read from the last kijun-option tag in nix's trace; nil when no tag is there.

    failing_option(unlines(["error:", "       … kijun-option pleme.fleet.nixRepo", "       error: attribute 'darwinUser' missing"])) #=> "pleme.fleet.nixRepo"
"""
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

@doc """
last_error: the innermost error message in nix's stderr, the one that names the cause.

    last_error(unlines(["error:", "       error: attribute 'darwinUser' missing"])) #=> "attribute 'darwinUser' missing"
"""
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

# waive B0083: integration debt recorded 2026-11-13: no test of this file declared kind: :integration reaches it yet
@doc """
own_source: the store path of the flake's own source, which tells this repository's files apart from its inputs' in an evaluated tree; "" when nix cannot say.

    procedure?(own_source) #=> true
"""
def own_source(root)
  cap = exec_capture("nix", "flake", "metadata", "--json", root)
  if status_of(cap) == 0
    get_str(json_parse(stdout_of(cap)), "path", "")
  else
    ""
  end
end

@doc """
entries: the option entries of the tree probe's JSON, each with its path, declarations, definitions and whether it threw.

    entries(nil) #=> []
"""
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

@doc """
or_list: a value read from JSON as a list, or [] when it is absent or not a list.

    or_list("x") #=> []
"""
def or_list(xs)
  if xs.nil? or not list?(xs)
    []
  else
    xs
  end
end

@doc """
tree_of: the evaluated option tree of one configuration, from a probe that starts with no option known to fail.

    procedure?(tree_of) #=> true
"""
def tree_of(root, own, configuration)
  probe(root, own, configuration, [])
end

# waive B0083: integration debt recorded 2026-11-13: no test of this file declared kind: :integration reaches it yet
@doc """
probe: evaluate one configuration's option tree with nix; an option whose evaluation fails is set aside as blind and the probe runs again, so one bad option never hides the rest.

    procedure?(probe) #=> true
"""
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
    tree_expr(map((b) -> b[:option], blind))
  )
  if status_of(cap) != 0
    err = stderr_of(cap)
    o = failing_option(err)
    if o != nil and is_empty(filter((b) -> b[:option] == o, blind))
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
        {option: x[:path], error: "threw while its definitions were evaluated"}
      end,
      filter((x) -> x[:threw], append(pleme, hostname))
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

# waive B0083: integration debt recorded 2026-11-13: no test of this file declared kind: :integration reaches it yet
@doc """
tracked: the files git tracks under root, the set a flake sees; nil when root is not a work tree.

    procedure?(tracked) #=> true
"""
def tracked(root)
  cap = exec_capture("git", "-C", root, "ls-files")
  if status_of(cap) != 0
    nil
  else
    filter((l) -> l != "", split(stdout_of(cap), line_break))
  end
end

@doc """
source_of: the text of one repository file, through the repository's own reader.

    source_of(in_memory([["lib/a.nix", "{ }"]]), "lib/a.nix") #=> "{ }"
"""
def source_of(repo, path)
  repo[:read](path)
end

@doc """
on_disk: a repository read from a checkout: its tracked files, each read from disk when a rule asks.

    on_disk("/r", ["flake.nix"])[:files] #=> ["flake.nix"]
"""
def on_disk(root, files)
  {root:, files:, read: (p) -> read_or(path_join(root, p), "")}
end

@doc """
in_memory: a repository held as [path, text] pairs, so every rule runs without a checkout.

    in_memory([["lib/a.nix", "{ }"]])[:files] #=> ["lib/a.nix"]
"""
def in_memory(sources)
  {
    root: ".",
    files: map((s) -> first(s), sources),
    read: fn(p)
      hit = filter((s) -> first(s) == p, sources)
      if is_empty(hit)
        ""
      else
        first(hit)[1]
      end
    end
  }
end

@doc """
evaluate: the standard applied to a repository and its evaluated trees: findings split into gates, advice and waived, with the config's refusals.

    map((x) -> x[:rule], evaluate(fleet_repo(1), in_memory([["lib/a.nix", "import <nixpkgs> { }"]]), [])[:gates]) #=> ["expr/no-angle-paths"]
"""
def evaluate(cfg, source, trees)
  evaluate_timed(cfg, source, trees, () -> 0)
end

@doc """
evaluate_timed: evaluate, with each plane's time read from `clock`.

    evaluate_timed(fleet_repo(1), in_memory([]), [], () -> 5)[:ms] #=> {layout: 0, expression: 0, tree: 0}
"""
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
    gates: filter((x) -> tier_of(x[:rule]) == :gate, live),
    advice: filter((x) -> tier_of(x[:rule]) == :advise, live),
    waived: filter((x) -> waived?(ws, x), all),
    refusals: config_refusals(cfg),
    ms: {layout: t1 - t0, expression: t2 - t1, tree: t3 - t2},
    tree_errors: filter(
      (e) -> e != nil,
      map(
        fn(t)
          if t[:error].nil?
            nil
          else
            "#{t[:configuration]}: #{t[:error]}"
          end
        end,
        trees
      )
    )
  }
end

@doc """
settings: kijun's core model: the checkout to judge, the baseline file, and how to report.

    settei::defaults_of(settings)[:root] #=> "."
"""
def settings()
  k = settei::knob
  {
    root: k(
      ".",
      {set_by: [:flag], value_name: "PATH", doc: "the checkout to judge"}
    ),
    baseline: k(
      "",
      {
        set_by: [:flag],
        value_name: "PATH",
        doc: "the baseline file; the standard's own when empty"
      }
    ),
    json: k(false, {set_by: [:flag], doc: "report as one JSON record"}),
    tree: k(
      false,
      {
        set_by: [:flag],
        doc: "also judge the merged module tree of each configuration"
      }
    )
  }
end

@doc """
frame: kijun's commands, from which its help and completion are rendered.

    size(frame[:commands]) #=> 3
"""
def frame()
  {
    name: "kijun",
    about: "a fleet repository judged against its standard",
    commands: [
      {
        name: :check,
        about: "judge the checkout; a finding outside the baseline fails"
      },
      {name: :baseline, about: "write the checkout's findings to the baseline"},
      {name: :rules, about: "list the standard's rules, each with why and fix"}
    ]
  }
end

@doc """
parse_args: kijun's command line, read through its settings and frame: the command and flags, or help, completion or explain text, or a usage error field, never a raise.

    parse_args(["check", "--json", "--root", "/r"])[:root] #=> "/r"
"""
def parse_args(args)
  o = settei::line("kijun", settings, frame, args, nil, settei::no_env)
  if o[:kind] == :run
    line_opts = o[:opts]
    if line_opts[:command].nil?
      {error: "a command: check, baseline or rules"}
    else
      {
        command: to_s(line_opts[:command]),
        root: line_opts[:root],
        json: line_opts[:json],
        tree: line_opts[:tree],
        baseline: if line_opts[:baseline] == ""
          nil
        else
          line_opts[:baseline]
        end,
        error: nil
      }
    end
  elsif o[:kind] == :usage
    {error: first(split(o[:text], line_break)), text: o[:text]}
  else
    {error: nil, text: o[:text]}
  end
end

@doc """
flags: the flags after kijun's command, read through its rendered line into the keys `acc` holds; a bad flag sets `error`.

    flags(["--tree"], {tree: false, error: nil}) #=> {tree: true, error: nil}
    flags(["--bogus"], {tree: false, error: nil})[:error] #=> "kijun: unknown flag --bogus"
"""
def flags(args, acc)
  parsed = parse_args(append(["check"], args))
  if parsed[:error] != nil
    assoc(acc, :error, parsed[:error])
  else
    from_entries(
      map(
        fn(e)
          if first(e) == :error
            e
          else
            [first(e), get(parsed, first(e))]
          end
        end,
        map_entries(acc)
      )
    )
  end
end

@doc """
rule_line: one rule as `kijun rules` lists it: id, plane, tier and scope, then why and fix.

    starts_with?(rule_line(first(rules)), "trio/every-concept\tlayout\tgate") #=> true
"""
def rule_line(r)
  unlines(
    [
      "#{r[:id]}\t#{to_s(r[:plane])}\t#{to_s(r[:tier])}\t#{join(r[:scope], " ")}",
      "  why: #{r[:why]}",
      "  fix: #{r[:fix]}"
    ]
  )
end

@doc """
rules_text: the whole standard as `kijun rules` prints it, headed by its name, version and rule count.

    first(lines(rules_text(fleet_repo(1)))) #=> "fleet-repo v1: 18 rules"
"""
def rules_text(cfg)
  join_lines(
    [
      "#{cfg[:standard]} v#{to_s(cfg[:version])}: #{to_s(size(rules))} rules",
      "",
      join(map(rule_line, rules), line_break)
    ]
  )
end

@doc """
finding_line: one finding as a report line, file:line first so an editor can jump to it.

    finding_line(finding("expr/no-angle-paths", "lib/a.nix", 2, "<nixpkgs>", "m")) #=> "lib/a.nix:2: expr/no-angle-paths: m\n"
"""
def finding_line(x)
  where = if x[:line] > 0
    "#{x[:file]}:#{to_s(x[:line])}"
  else
    x[:file]
  end
  unlines(["#{where}: #{x[:rule]}: #{x[:message]}"])
end

@doc """
counts: the number of findings per rule, ordered by rule id.

    counts([{rule: "b"}, {rule: "a"}, {rule: "b"}]) #=> [["a", 1], ["b", 2]]
"""
def counts(xs)
  map(
    (id) -> [id, size(filter((x) -> x[:rule] == id, xs))],
    sort_keyed((id) -> id, rule_ids(xs))
  )
end

@doc """
plain: a finding as the JSON report carries it: only its rule, file, line, subject and message.

    plain({rule: "r", file: "f", line: 1, subject: "s", message: "m", extra: 1}) #=> {rule: "r", file: "f", line: 1, subject: "s", message: "m"}
"""
def plain(x)
  {
    rule: x[:rule],
    file: x[:file],
    line: x[:line],
    subject: x[:subject],
    message: x[:message]
  }
end

@doc """
plane_of: which plane a rule reads: layout, expression or tree.

    plane_of("expr/no-shell") #=> :expression
"""
def plane_of(id)
  rule_field(id, :plane)
end

@doc """
plane_counts: per plane, how many findings, gates, advice and waivers it produced and how long it took.

    r = evaluate(fleet_repo(1), in_memory([["lib/a.nix", "import <nixpkgs> { }"]]), [])
    map((p) -> p[:findings], plane_counts(r, {wall: 7, planes: {layout: 1, expression: 2, tree: 3}})) #=> [0, 1, 0]
"""
def plane_counts(result, timing)
  map(
    fn(p)
      mine = (k) -> size(filter((x) -> plane_of(x[:rule]) == p, get(result, k)))
      {
        plane: p,
        findings: mine(:findings),
        gates: mine(:gates),
        advice: mine(:advice),
        waived: mine(:waived),
        ms: get(timing[:planes], p)
      }
    end,
    %i[layout expression tree]
  )
end

@doc """
report_json: the `kijun check --json` report: the verdict, every finding, the counts and the timing.

    r = evaluate(fleet_repo(1), in_memory([["lib/a.nix", "import <nixpkgs> { }"]]), [])
    json_get(json_parse(report_json(fleet_repo(1), r, judge(r[:gates], []), {wall: 7, planes: {layout: 1, expression: 2, tree: 3}})), :wall_ms) #=> 7
"""
def report_json(cfg, result, verdict, timing)
  json_stringify(
    {
      wall_ms: timing[:wall],
      planes: plane_counts(result, timing),
      standard: cfg[:standard],
      version: cfg[:version],
      ok: is_empty(verdict[:new]),
      new: map(plain, verdict[:new]),
      findings: map(plain, result[:findings]),
      counts: map(
        (c) -> {rule: first(c), count: c[1]},
        counts(result[:findings])
      ),
      waived: size(result[:waived]),
      orphans: verdict[:orphans],
      shrunk: verdict[:shrunk],
      refusals: map((r) -> kyohi::why(r), result[:refusals]),
      disabled: cfg[:disabled],
      tree_errors: result[:tree_errors]
    }
  )
end

@doc """
timing_line: the report's last line: wall time, then each plane's findings and time.

    r = evaluate(fleet_repo(1), in_memory([["lib/a.nix", "import <nixpkgs> { }"]]), [])
    timing_line(r, {wall: 7, planes: {layout: 1, expression: 2, tree: 3}}) #=> "wall 7 ms: layout 0 findings 1 ms, expression 1 findings 2 ms, tree 0 findings 3 ms\n"
"""
def timing_line(result, timing)
  ps = join(
    map(
      fn(p)
        "#{to_s(p[:plane])} #{to_s(p[:findings])} findings #{to_s(p[:ms])} ms"
      end,
      plane_counts(result, timing)
    ),
    ", "
  )
  unlines(["wall #{to_s(timing[:wall])} ms: #{ps}"])
end

@doc """
report_text: the `kijun check` report for people: totals, counts per rule, refusals, disabled rules, blind trees, what the baseline can shed, and the gate findings outside it.

    r = evaluate(fleet_repo(1), in_memory([["lib/a.nix", "import <nixpkgs> { }"]]), [])
    first(lines(report_text(fleet_repo(1), r, judge(r[:gates], []), {wall: 7, planes: {layout: 1, expression: 2, tree: 3}}))) #=> "kijun fleet-repo v1: 1 gate findings, 0 advice, 0 waived"
"""
def report_text(cfg, result, verdict, timing)
  head = unlines(
    [
      "kijun #{cfg[:standard]} v#{to_s(cfg[:version])}: #{to_s(size(result[:gates]))} gate findings, #{to_s(size(result[:advice]))} advice, #{to_s(size(result[:waived]))} waived"
    ]
  )
  per = join(
    map(
      fn(c)
        unlines(["  #{first(c)} #{to_s(tier_of(first(c)))} #{to_s(c[1])}"])
      end,
      counts(result[:findings])
    ),
    ""
  )
  fresh = if is_empty(verdict[:new])
    unlines(["no gate finding outside the baseline"])
  else
    join_lines(
      [
        "#{to_s(size(verdict[:new]))} gate findings outside the baseline:",
        join(map(finding_line, verdict[:new]), "")
      ]
    )
  end
  shrink = if is_empty(verdict[:orphans]) and is_empty(verdict[:shrunk])
    ""
  else
    unlines(
      [
        "the baseline can shrink (run kijun baseline): #{to_s(size(verdict[:orphans]))} gone, #{to_s(size(verdict[:shrunk]))} smaller"
      ]
    )
  end
  refused = join(
    map((r) -> unlines(["refused: #{kyohi::why(r)}"]), result[:refusals]),
    ""
  )
  off = join(
    map(
      (d) -> unlines(["disabled: #{d[:rule]}: #{d[:reason]}"]),
      cfg[:disabled]
    ),
    ""
  )
  blind = join(
    map((e) -> unlines(["tree blind: #{e}"]), result[:tree_errors]),
    ""
  )
  "#{head}#{per}#{refused}#{off}#{blind}#{shrink}#{fresh}#{timing_line(result, timing)}"
end

@doc """
run: one kijun command against a checkout with a given standard: list the rules, check against the baseline, or rewrite the baseline. A bad line or a gate finding outside the baseline raises.

    procedure?(run) #=> true
"""
def run(cfg, args)
  a = parse_args(args)
  if a[:error] != nil
    write_stderr(
      if a[:text].nil?
        unlines(["kijun: #{a[:error]}"])
      else
        a[:text]
      end
    )
    raise(:kijun_usage, a[:error])
  elsif a[:command].nil?
    write_stdout(a[:text])
    nil
  elsif a[:command] == "rules"
    write_stdout(rules_text(cfg))
    nil
  else
    started = now_ms
    root = a[:root]
    files = tracked(root)
    if files.nil?
      write_stderr(unlines(["kijun: #{root} is not a git work tree"]))
      raise(:kijun_usage, "not a git work tree")
    end
    before_tree = now_ms
    trees = if a[:tree]
      own = own_source(root)
      map((c) -> tree_of(root, own, c), cfg[:configurations])
    else
      []
    end
    tree_ms = now_ms - before_tree
    result = evaluate_timed(cfg, on_disk(root, files), trees, () -> now_ms)
    base = if a[:baseline].nil?
      path_join(root, cfg[:baseline])
    else
      a[:baseline]
    end
    rows = split_rows(hadome::parse(read_or(base, "")), ran_ids(cfg, a[:tree]))
    if a[:command] == "baseline"
      write_file(base, baseline_with(result[:gates], rows[1]))
      write_stdout(
        unlines(
          [
            "kijun: wrote #{to_s(size(result[:gates]))} gate findings to #{base}"
          ]
        )
      )
      nil
    else
      verdict = judge(result[:gates], first(rows))
      ms = result[:ms]
      timing = {
        wall: now_ms - started,
        planes: assoc(ms, :tree, ms[:tree] + tree_ms)
      }
      if a[:json]
        write_stdout(unlines([report_json(cfg, result, verdict, timing)]))
      else
        write_stdout(report_text(cfg, result, verdict, timing))
      end
      if not is_empty(verdict[:new])
        raise(:kijun_failed, "gate findings outside the baseline")
      end
      nil
    end
  end
end

# waive B0083: integration debt recorded 2026-11-13: no test of this file declared kind: :integration reaches it yet
@doc """
main: the kijun command's entry point: a repository's own kijun.b runs in its place when there is one, else the fleet-repo standard v1.

    procedure?(() -> main) #=> true
"""
def main()
  args = argv
  root = parse_args(args)[:root] or "."
  local = path_join(root, "kijun.b")
  if read_or(local, "") != ""
    status = exec_check(
      *append([blue_exe, "run", "--quiet", local, "--"], args)
    )
    if status != 0
      raise(:kijun_failed, "kijun.b exited #{to_s(status)}")
    end
    nil
  else
    run(fleet_repo(1), args)
  end
end

@doc """
tree_case: an evaluated tree the tree-rule tests read, with one option at `file`: a pleme.x declaration, a blind pleme.x, or a hostname definition.

    first(tree_case("lib/x.nix", :declaration)[:pleme])[:declarations] #=> ["/nix/store/h-source/lib/x.nix"]
"""
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

@doc """
example: one fixture case: the repository's sources and its evaluated trees.

    example([], []) #=> {sources: [], trees: []}
"""
def example(sources, trees)
  {sources:, trees:}
end

@doc """
module_with: a NixOS module source around the given body, for fixtures.

    module_with("  pleme.x = true;") #=> "{ config, lib, pkgs, ... }:\n{\n  pleme.x = true;\n}\n"
"""
def module_with(body)
  unlines(["{ config, lib, pkgs, ... }:", "{", body, "}"])
end

@doc """
concept_sources: a repository with one concept of each kind, every one declared through the trio factory when `declared`, none otherwise.

    map((s) -> first(s), concept_sources(false))[6] #=> "lib/r.nix"
"""
def concept_sources(declared)
  shared = if declared
    unlines(
      [
        "{ inputs, ... }:",
        "let",
        "  t = inputs.substrate.moduleTrio;",
        "  r = import ../../../lib/r.nix;",
        "in",
        "{",
        "  imports = [",
        "    (t.mkModuleTrio { kind = \"registry\"; name = \"x\"; entries.default = r; }).module",
        "    (t.mkModuleTrio { kind = \"package\"; name = \"tools\"; packageAttr = \"p\"; }).module",
        "    (t.mkModuleTrio { kind = \"service\"; name = \"o\"; }).module",
        "  ];",
        "}"
      ]
    )
  else
    unlines(
      [
        "{ lib, ... }:",
        "{",
        "  options.pleme.x.enable = lib.mkEnableOption \"x\";",
        "}"
      ]
    )
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
      unlines(
        ["{ ... }:", "let", "  r = import ../../../lib/r.nix;", "in", "{ }"]
      )
    ]
  ]
end

@doc """
trio_source: a shared module file that declares its concept through mkModuleTrio, of the given kind or none.

    first(trio_source("p", "package")) #=> "modules/pleme/shared/p.nix"
"""
def trio_source(name, kind_of)
  k = if kind_of.nil?
    ""
  else
    "kind = \"#{kind_of}\"; "
  end
  [
    "modules/pleme/shared/#{name}.nix",
    unlines(
      [
        "{ inputs, ... }:",
        "{",
        "  imports = [ (inputs.substrate.moduleTrio.mkModuleTrio { #{k}name = \"#{name}\"; }).module ];",
        "}"
      ]
    )
  ]
end

@doc """
fixtures: one violating and one clean case per rule, with how often the violating one fires; a rule cannot land without both.

    size(fixtures) #=> size(rules)
"""
def fixtures()
  registry = [
    "lib/nodes.nix",
    unlines(["{ plo = mkNode { name = \"plo\"; nodeDir = ../nodes/plo; }; }"])
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
          ["profiles/p/default.nix", join_lines(["{ # shared/x.nix", "}"])]
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
              join_lines(
                [
                  "  networking.hostName = \"plo\";",
                  "  networking.hostId = \"8425e349\";",
                  "  fileSystems.\"/\".device = \"/dev/disk/by-uuid/abc\";",
                  "  sops.secrets.k.sopsFile = ../../nodes/plo/secrets.yaml;",
                  "  sops.secrets.f.sopsFile = ../../secrets.yaml;"
                ]
              )
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
              join_lines(
                [
                  "  networking.firewall.enable = true;",
                  "  fileSystems.\"/\".fsType = \"ext4\";"
                ]
              )
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
              join_lines(
                [
                  "  options.pleme.x.enable = lib.mkEnableOption \"x\";",
                  "  config = lib.mkIf config.pleme.x.enable { systemd.services.x = { }; };"
                ]
              )
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
              join_lines(
                [
                  "  options.pleme.x.enable = lib.mkEnableOption \"x\";",
                  "  config = lib.mkIf config.pleme.x.enable { pleme.y = 1; };"
                ]
              )
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
        [
          [
            "lib/a.nix",
            join_lines(["# <nixpkgs>", "import ./x.nix { s = \"<nixpkgs>\"; }"])
          ]
        ],
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
            join_lines(
              [
                "pkgs.writeShellScript \"a\" ''",
                "  one",
                "  two",
                "  three",
                "  four",
                "''"
              ]
            )
          ]
        ],
        []
      ),
      good: example(
        [
          [
            "pkgs/a.nix",
            join_lines(
              [
                "pkgs.writeShellScript \"a\" ''",
                "  one",
                "  two",
                "  three",
                "''"
              ]
            )
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

@doc """
fired: the findings of one rule on one fixture case.

    size(fired(fleet_repo(1), example([["lib/a.nix", "import <nixpkgs> { }"]], []), "expr/no-angle-paths")) #=> 1
"""
def fired(cfg, c, id)
  filter(
    (x) -> x[:rule] == id,
    evaluate(cfg, in_memory(c[:sources]), c[:trees])[:findings]
  )
end

test "every rule has a violating and a clean fixture, so a rule cannot land without both"
  ids = map((r) -> r[:id], rules)
  covered = filter((f) -> f[:bad] != nil and f[:good] != nil, fixtures)
  assert filter(
    (id) -> is_empty(filter((f) -> f[:rule] == id, covered)),
    ids
  ) == []
  assert filter((f) -> not member?(f[:rule], ids), fixtures) == []
  assert size(ids) == size(unique(ids))
end

test "each rule fires exactly as often as its violating fixture says, and never on its clean one"
  cfg = fleet_repo(1)
  quiet = filter(
    (f) -> size(fired(cfg, f[:bad], f[:rule])) != f[:fires],
    fixtures
  )
  noisy = filter((f) -> not is_empty(fired(cfg, f[:good], f[:rule])), fixtures)
  assert map((f) -> f[:rule], quiet) == []
  assert map((f) -> f[:rule], noisy) == []
end

test "trio/every-concept names every unit kind once and is silent when each is a trio"
  cfg = fleet_repo(1)
  subjects = fn(declared)
    map(
      (x) -> x[:subject],
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
  assert filter((x) -> x[:file] == "lib/unread.nix", xs) == []
  assert relative_to("modules/pleme/nixos/a.nix", "../../../lib/r.nix") ==
    "lib/r.nix"
  assert relative_to("nodes/plo/default.nix", "./hw.nix") == "nodes/plo/hw.nix"
end

test "a package directory with no nix of its own is still a concept, covered by a spec naming it"
  rust = [["pkgs/q/Cargo.toml", ""], ["pkgs/q/src/main.rs", "fn main() {}"]]
  assert map(
    (x) -> x[:subject],
    fired(fleet_repo(1), example(rust, []), "trio/every-concept")
  ) == ["package q"]
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
    sort_keyed((t) -> t, map((x) -> x[:subject], fired(fleet_repo(1), c, id)))
  end
  assert subjects("layout/shared-reachable") == ["x"]
  assert subjects("layout/shared-has-proof") == %w[r x]
  assert spec_kind(
    first(calls(kakehashi::nikkusu::read("f { kind = k; }")[:root]))
  ) == "computed"
end

test "an uncatchable failure is located at its option's tag, and the error is its last line"
  err = unlines(
    [
      "error:",
      "       … while evaluating the attribute 'definitions'",
      "       … kijun-option pleme.fleet.nixRepo",
      "       … while evaluating the attribute 'default'",
      "       error: attribute 'darwinUser' missing"
    ]
  )
  assert failing_option(err) == "pleme.fleet.nixRepo"
  assert last_error(err) == "attribute 'darwinUser' missing"
  assert failing_option(unlines(["error: flake has no attribute"])).nil?
  assert last_error(unlines(["error: flake has no attribute"])) ==
    "flake has no attribute"
  assert nix_string("a\"b${c}\\") == "\"a\\\"b\\${c}\\\\\""
  assert contains?(
    tree_expr(%w[pleme.a pleme.b]),
    "excluded = [ \"pleme.a\" \"pleme.b\" ]"
  ) == true
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
  assert map((x) -> [x[:rule], x[:file]], r[:findings]) ==
    [
      %w[tree/hostname-from-node profiles/p/default.nix],
      %w[tree/option-evaluates modules/pleme/shared/x.nix]
    ]
  assert map((x) -> x[:rule], r[:advice]) == ["tree/option-evaluates"]
end

test "check --json carries the wall time and one count per plane"
  c = example([["lib/a.nix", "import <nixpkgs> { }"]], [])
  r = evaluate(fleet_repo(1), in_memory(c[:sources]), [])
  timing = {wall: 7, planes: {layout: 1, expression: 2, tree: 3}}
  doc = json_parse(report_json(fleet_repo(1), r, judge(r[:gates], []), timing))
  assert json_get(doc, :wall_ms) == 7
  assert map(
    (p) -> [json_get(p, :plane), json_get(p, :findings), json_get(p, :ms)],
    json_get(doc, :planes)
  ) == [["layout", 0, 1], ["expression", 1, 2], ["tree", 0, 3]]
  assert contains?(
    report_text(fleet_repo(1), r, judge(r[:gates], []), timing),
    "wall 7 ms"
  ) == true
end

test "trio/every-concept is the first rule the standard lists"
  assert first(rules)[:id] == "trio/every-concept"
end

test "the same declaration seen from two configurations is one finding"
  t = tree_case("lib/x.nix", :declaration)
  two = [t, assoc(t, :configuration, "nixosConfigurations.b")]
  xs = filter(
    (x) -> x[:rule] == "tree/pleme-options-declared-in-shared",
    evaluate(fleet_repo(1), in_memory([]), two)[:findings]
  )
  assert size(xs) == 1
end

test "a finding names its file and line"
  c = example(
    [["lib/a.nix", unlines(["{", "  x = import <nixpkgs> { };", "}"])]],
    []
  )
  x = first(fired(fleet_repo(1), c, "expr/no-angle-paths"))
  assert x[:file] == "lib/a.nix"
  assert x[:line] == 2
  assert x[:subject] == "<nixpkgs>"
end

test "node-shape names both a missing default.nix and a NixOS node's missing layers.nix"
  f = first(filter((f) -> f[:rule] == "layout/node-shape", fixtures))
  xs = fired(fleet_repo(1), f[:bad], "layout/node-shape")
  assert sort_keyed((t) -> t, map((x) -> x[:subject], xs)) ==
    %w[default.nix layers.nix]
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
  r = evaluate(cfg, in_memory(c[:sources]), [])
  angle = filter((x) -> x[:rule] == "expr/no-angle-paths", r[:findings])
  assert map((x) -> x[:file], angle) == ["lib/b.nix"]
  assert size(r[:waived]) == 1
  assert r[:refusals] == []
end

test "a waiver without its typed skip reason is refused and covers nothing"
  c = example([["lib/a.nix", "import <nixpkgs> { }"]], [])
  cfg = waive(fleet_repo(1), "expr/no-angle-paths", "lib/**", "because")
  r = evaluate(cfg, in_memory(c[:sources]), [])
  assert size(r[:refusals]) == 1
  assert size(filter((x) -> x[:rule] == "expr/no-angle-paths", r[:findings])) ==
    1
  bogus = waive(fleet_repo(1), "expr/nope", "**", "skip-expr/nope: x")
  assert size(evaluate(bogus, in_memory([]), [])[:refusals]) == 1
end

test "a disabled rule runs nowhere, and an unknown one is refused"
  c = example([["lib/a.nix", "import <nixpkgs> { }"]], [])
  cfg = disable(fleet_repo(1), "expr/no-angle-paths", "bootstrap repo")
  assert fired(cfg, c, "expr/no-angle-paths") == []
  assert size(fired(fleet_repo(1), c, "expr/no-angle-paths")) == 1
  assert size(
    evaluate(disable(fleet_repo(1), "x/y", "r"), in_memory([]), [])[:refusals]
  ) == 1
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
  assert baseline_text([a]) ==
    unlines(["expr/no-angle-paths: lib/a.nix::<nixpkgs> 1"])
  assert judge([a], rows)[:new] == []
  assert map((x) -> x[:file], judge([a, b], rows)[:new]) == ["lib/b.nix"]
  gone = judge([], rows)
  assert gone[:new] == []
  assert gone[:orphans] == ["expr/no-angle-paths: lib/a.nix::<nixpkgs>"]
  assert size(judge([a, a], rows)[:new]) == 2
  assert judge([], [])[:new] == []
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
  assert map((r) -> r[:kind], first(parts)) == ["expr/no-angle-paths"]
  assert judge([e], first(parts))[:orphans] == []
  assert baseline_with([e], parts[1]) == baseline_text([t, e])
  assert size(first(split_rows(rows, ran_ids(fleet_repo(1), true)))) == 2
end

test "the rules listing is the standard: every rule, with why and fix"
  t = rules_text(fleet_repo(1))
  assert size(filter((r) -> contains?(t, r[:id]), rules)) == size(rules)
  assert contains?(t, "fleet-repo v1") == true
end

test "arguments: a command is required and flags are read"
  assert parse_args([])[:error] != nil
  assert parse_args(["lint"])[:error] != nil
  a = parse_args(%w[check --json --root /r --tree])
  assert [a[:json], a[:root], a[:tree]] == [true, "/r", true]
  assert parse_args(%w[check --root])[:error] != nil
end

test "append_field grows one list and leaves the rest of the config"
  assert append_field({top: []}, :top, []) == {top: []}
  cfg = {top: ["a"], configurations: []}
  assert append_field(cfg, :top, []) == cfg
  assert append_field(cfg, :top, %w[b c]) ==
    {top: %w[a b c], configurations: []}
  assert allow_top(cfg, ["b"]) == append_field(cfg, :top, ["b"])
  assert configurations(cfg, ["plo"])[:configurations] == ["plo"]
end

test "rule_field reads one field of a rule by id"
  assert (rule_field("no-such-rule", :tier) rescue :unknown) == :unknown
  assert rule_field("trio/every-concept", :id) == "trio/every-concept"
  assert rule_field("trio/every-concept", :plane) == :layout
  assert tier_of("trio/every-concept") == :gate
  assert plane_of("trio/every-concept") == :layout
end

test "kijun's command line is rendered from its settings: help names every flag, a bad flag or command is a usage error, and the record keeps its shape"
  h = parse_args(["--help"])
  assert h[:error].nil?
  missing = filter(
    (f) -> not contains?(h[:text], f),
    %w[--root --baseline --json --tree check baseline rules]
  )
  assert missing == []

  assert parse_args(%w[check --bogus])[:error] != nil
  assert parse_args(["lint"])[:error] != nil
  assert parse_args(%w[baseline --baseline /b]) ==
    {
      command: "baseline",
      root: ".",
      json: false,
      tree: false,
      baseline: "/b",
      error: nil
    }
  assert parse_args(["check"])[:baseline].nil?
  assert contains?(parse_args(%w[--explain tree])[:text], "tree")
end
