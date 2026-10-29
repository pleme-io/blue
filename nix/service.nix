{ lib, pkgs, blue, bl, common, src, m, name, bluePath, programFile, lockFile, imageGate, oci, moduleTrio, chartLibraries ? { }, component ? null }:

let
  inherit (builtins) attrNames;

  services = m.services or { };

  own = lib.filterAttrs (_: s: !(s ? host)) services;

  envPrefix = sn: "${lib.toUpper (lib.replaceStrings [ "-" ] [ "_" ] sn)}_";

  trees = lib.mapAttrs
    (sn: _: pkgs.runCommand "service-${sn}-tree" { } ''
      BLUE_PATH=${bluePath} ${blue}/bin/blue run --quiet ${./service-render.b} -- ${lockFile} ${sn} $out
    '')
    services;

  apps = lib.mapAttrs
    (sn: spec: pkgs.runCommand "service-${sn}-app" { } (''
      mkdir -p $out/app $out/share/blue $out/share/${sn}
      ln -s ${programFile spec.program} $out/app/${baseNameOf spec.program}
      ln -s ${bluePath} $out/share/blue/bidamas
      ln -s ${trees.${sn}}/config/${sn}.yaml $out/share/${sn}/defaults.yaml
    '' + lib.concatMapStrings
      (a: ''
        mkdir -p "$out/app/${dirOf a}"
        ln -s ${builtins.path { path = src + "/${a}"; name = baseNameOf a; }} "$out/app/${a}"
      '')
      (spec.assets or [ ])))
    own;

  program = sn: spec: "${apps.${sn}}/app/${baseNameOf spec.program}";

  wasmOwn = lib.filterAttrs (_: s: (s.runtime.kind or "wasm") == "wasm") own;

  components = lib.optionalAttrs (component != null) (lib.mapAttrs
    (sn: spec: pkgs.runCommand "service-${sn}-component" { } (''
      mkdir -p $out/app/share/${sn}
      ln -s ${component} $out/component.wasm
      cp -L ${programFile spec.program} $out/app/${baseNameOf spec.program}
      cp -L ${trees.${sn}}/config/${sn}.yaml $out/app/share/${sn}/defaults.yaml
    '' + lib.concatMapStrings
      (a: ''
        mkdir -p "$out/app/${dirOf a}"
        cp -rL ${builtins.path { path = src + "/${a}"; name = baseNameOf a; }} "$out/app/${a}"
      '')
      (spec.assets or [ ])))
    wasmOwn);

  componentServesCheck = sn: spec:
    let port = toString (spec.port + 1); in
    pkgs.runCommand "service-${sn}-component-serves" { nativeBuildInputs = [ pkgs.curl pkgs.wasmtime ]; __darwinAllowLocalNetworking = true; } ''
      export HOME=$TMPDIR
      wasmtime run -S inherit-network=y -S tcp=y \
        --dir ${components.${sn}}/app::/app \
        --env BLUE_SERVICE=${sn} \
        --env ${envPrefix sn}DEFAULTS=/app/share/${sn}/defaults.yaml \
        --env ${envPrefix sn}LISTEN__HOST=127.0.0.1 \
        --env ${envPrefix sn}LISTEN__PORT=${port} \
        ${components.${sn}}/component.wasm /app/${baseNameOf spec.program} > serve.log 2>&1 &
      pid=$!
      for i in $(seq 1 300); do
        if curl -sf -o health.txt http://127.0.0.1:${port}${spec.probe}; then break; fi
        if ! kill -0 $pid 2>/dev/null; then cat serve.log >&2; exit 1; fi
        sleep 0.1
      done
      code=$(curl -s -o root.txt -w '%{http_code}' http://127.0.0.1:${port}/ || true)
      kill $pid
      test -s health.txt || { echo "service-${sn}-component-serves: ${spec.probe} never answered from the component" >&2; cat serve.log >&2; exit 1; }
      test "$code" -ge 200 -a "$code" -lt 500 || { echo "service-${sn}-component-serves: / answered $code" >&2; cat root.txt serve.log >&2; exit 1; }
      cat health.txt root.txt > $out
    '';

  envOf = sn: {
    BLUE_SERVICE = sn;
    "${envPrefix sn}DEFAULTS" = "${apps.${sn}}/share/${sn}/defaults.yaml";
  };

  executables = lib.mapAttrs
    (sn: spec: bl.mkBlueApp (common // {
      name = sn;
      program = program sn spec;
      env = envOf sn;
      chdir = "${apps.${sn}}/app";
    }))
    own;

  images = import ./image.nix { inherit lib pkgs oci blue; };

  imageSets =
    if own == { } || !pkgs.stdenv.isLinux then { }
    else if oci == null || !(oci ? mkHardenedImageSet) then
      throw "lib.project: the Bluefile declares service ${lib.concatStringsSep ", " (attrNames own)}, and this engine was given no image factory (`oci.mkHardenedImageSet`, substrate.lib.<system>)"
    else lib.mapAttrs
      (sn: spec: (images.build {
        what = "service(\"${sn}\")";
        name = sn;
        inherit (spec) repository;
        version = m.version;
        program = program sn spec;
        env = envOf sn // { BLUE_PATH = "${bluePath}"; };
        ports = [ spec.port ];
        contents = [ apps.${sn} ];
        workdir = "${apps.${sn}}/app";
      }).set)
      own;

  chartCheck = sn: spec:
    let
      wasm = (spec.runtime.kind or "wasm") == "wasm";
      chart = "chart${lib.optionalString wasm " --set runtime.component.closure=/nix/store/00000000000000000000000000000000-${sn}-component"}";
      withDb = (spec.schema or { }) != { };
    in
    pkgs.runCommand "service-${sn}-chart" { nativeBuildInputs = [ pkgs.kubernetes-helm ]; } (''
      export HOME=$TMPDIR
      cp -r ${trees.${sn}}/chart chart && chmod -R u+w chart
      mkdir -p chart/charts
    '' + lib.concatStrings (lib.mapAttrsToList (l: path: ''
      cp -r ${path} chart/charts/${l}
    '') chartLibraries) + ''
      helm lint --strict ${chart}
      helm template t ${chart} > rendered.yaml
    '' + lib.optionalString wasm ''
      grep -q '^      runtimeClassName: wasm$' rendered.yaml || { echo "service-${sn}-chart: a wasm service rendered no runtimeClassName" >&2; exit 1; }
      grep -q 'image: "nix:/nix/store/00000000000000000000000000000000-${sn}-component"' rendered.yaml
      grep -q 'blue.pleme.io/access' rendered.yaml
      grep -q 'wasm.pleme.io/app: "\{0,1\}app"\{0,1\}$' rendered.yaml
      if helm template t chart > /dev/null 2> noclosure.log; then
        echo "service-${sn}-chart: a wasm service rendered with no component closure" >&2
        exit 1
      fi
      grep -q 'closure' noclosure.log
    '' + lib.optionalString (!wasm) ''
      if grep -q 'runtimeClassName' rendered.yaml; then
        echo "service-${sn}-chart: a native service rendered a runtimeClassName" >&2
        exit 1
      fi
    '' + ''
      grep -q '^kind: Deployment$' rendered.yaml
      grep -q '^kind: Service$' rendered.yaml
      grep -q '^kind: "PrometheusRule"$' rendered.yaml
      grep -q 'alert: "SloAvailabilityBurn1h"' rendered.yaml
      grep -q 'grafana_dashboard: "1"' rendered.yaml
      grep -q '"uid": "${sn}-slo"' rendered.yaml
      grep -q 'prometheus.io/path: /metrics' rendered.yaml
      helm template t ${chart} --set slo.rules=false --set slo.dashboard=false > off.yaml
      if grep -q 'PrometheusRule\|grafana_dashboard' off.yaml; then
        echo "service-${sn}-chart: the SLO rules or dashboard rendered while switched off" >&2
        exit 1
      fi
      if helm template t ${chart} --set config.not_declared=1 > /dev/null 2> unknown.log; then
        echo "service-${sn}-chart: the values schema accepted an undeclared setting" >&2
        exit 1
      fi
      grep -q "additional properties 'not_declared' not allowed" unknown.log
      if helm template t ${chart} --set-string listen.port=eighty > /dev/null 2> type.log; then
        echo "service-${sn}-chart: the values schema accepted a text port" >&2
        exit 1
      fi
      grep -q 'want integer' type.log
    '' + lib.optionalString withDb ''
      if grep -q '^kind: DatabaseMigration$' rendered.yaml; then
        echo "service-${sn}-chart: the migration rendered with the database off" >&2
        exit 1
      fi
      if helm template t ${chart} --set database.enabled=true > /dev/null 2> db.log; then
        echo "service-${sn}-chart: a database migration rendered with no host" >&2
        exit 1
      fi
      grep -q 'database.host is required' db.log
      helm template t ${chart} --set database.enabled=true --set database.host=pg --set database.credentialsSecret=pg > db.yaml
      grep -q '^kind: DatabaseMigration$' db.yaml
    '' + ''
      cp rendered.yaml $out
    '');

  servesCheck = sn: spec:
    pkgs.runCommand "service-${sn}-serves" { nativeBuildInputs = [ pkgs.curl ]; __darwinAllowLocalNetworking = true; } ''
      export HOME=$TMPDIR
      BLUE_SERVICE=${sn} ${envPrefix sn}LISTEN__HOST=127.0.0.1 ${executables.${sn}}/bin/${sn} > serve.log 2>&1 &
      pid=$!
      for i in $(seq 1 300); do
        if curl -sf -o health.txt http://127.0.0.1:${toString spec.port}${spec.probe}; then break; fi
        if ! kill -0 $pid 2>/dev/null; then cat serve.log >&2; exit 1; fi
        sleep 0.1
      done
      code=$(curl -s -o root.txt -w '%{http_code}' http://127.0.0.1:${toString spec.port}/ || true)
      curl -sf -o metrics.txt http://127.0.0.1:${toString spec.port}/metrics || true
      kill $pid
      grep -Eq '^http_requests_total\{service="${sn}",code="[2-4]xx"\} [1-9]' metrics.txt || { echo "service-${sn}-serves: /metrics did not count the request to /" >&2; cat metrics.txt serve.log >&2; exit 1; }
      grep -q '^http_request_duration_seconds_count{service="${sn}"} ' metrics.txt
      test -s health.txt || { echo "service-${sn}-serves: ${spec.probe} never answered" >&2; cat serve.log >&2; exit 1; }
      test "$code" -ge 200 -a "$code" -lt 500 || { echo "service-${sn}-serves: / answered $code" >&2; cat root.txt serve.log >&2; exit 1; }
      cat health.txt root.txt metrics.txt > $out
    '';

  migrationsCheck = sn: spec:
    let
      sql = "${trees.${sn}}/chart/files/schema.sql";
      columns = t: toString (1 + builtins.length (attrNames spec.schema.${t}));
    in
    pkgs.runCommand "service-${sn}-migrations" { nativeBuildInputs = [ pkgs.postgresql ]; } (''
      export HOME=$TMPDIR PGHOST=$TMPDIR PGDATABASE=postgres
      initdb -D $TMPDIR/pg -U "$(id -un)" > /dev/null
      pg_ctl -D $TMPDIR/pg -o "-k $TMPDIR -h 127.0.0.1 -p 54329" -w start > /dev/null
      export PGPORT=54329
      psql -v ON_ERROR_STOP=1 -q -f ${sql}
      psql -v ON_ERROR_STOP=1 -q -f ${sql}
    '' + lib.concatMapStrings
      (t: ''
        test "$(psql -tAc "select count(*) from information_schema.columns where table_name = '${t}'")" = "${columns t}"
      '')
      (attrNames spec.schema) + ''
      pg_ctl -D $TMPDIR/pg -m fast stop > /dev/null
      touch $out
    '');

  trios = lib.optionalAttrs (moduleTrio != null) (lib.mapAttrs
    (sn: _: moduleTrio.mkModuleTrio {
      kind = "service";
      name = sn;
      description = "${sn}, a blue service declared in ${name}'s Bluefile";
      packageAttr = sn;
      binaryName = sn;
      scope = "system";
    })
    own);

  anyAttrs = lib.mkOption { type = lib.types.attrsOf lib.types.anything; default = { }; };
  anyList = lib.mkOption { type = lib.types.listOf lib.types.anything; default = [ ]; };

  stubs = {
    nixos.options = {
      assertions = anyList;
      environment.etc = anyAttrs;
      environment.systemPackages = anyList;
      systemd.services = anyAttrs;
      systemd.timers = anyAttrs;
    };
    darwin.options = {
      assertions = anyList;
      environment.etc = anyAttrs;
      environment.systemPackages = anyList;
      launchd.daemons = anyAttrs;
    };
    homeManager.options = {
      assertions = anyList;
      home.homeDirectory = lib.mkOption { type = lib.types.str; default = "/home/test"; };
      home.packages = anyList;
      home.file = anyAttrs;
      home.activation = anyAttrs;
      home.sessionVariables = anyAttrs;
      launchd.agents = anyAttrs;
      systemd.user.services = anyAttrs;
      systemd.user.timers = anyAttrs;
      blackmatter.components.anvil.mcp.servers = anyAttrs;
    };
  };

  trioCheck = sn: trio:
    let
      evalArm = arm: enable: lib.evalModules {
        class = arm;
        modules = [
          trio."${arm}Module"
          stubs.${arm}
          (lib.optionalAttrs enable { pleme.${sn} = { enable = true; package = executables.${sn}; }; })
        ];
        specialArgs.pkgs = pkgs // { ${sn} = executables.${sn}; };
      };
      failed = e: map (a: a.message) (builtins.filter (a: !a.assertion) e.config.assertions);
      nixos = evalArm "nixos" true;
      darwin = evalArm "darwin" true;
      off = evalArm "nixos" false;
      plain = builtins.unsafeDiscardStringContext;
      unit = plain (builtins.toJSON (nixos.config.systemd.services.${sn} or null));
      daemon = plain (builtins.toJSON (darwin.config.launchd.daemons.${sn} or null));
      exe = plain "${executables.${sn}}/bin/${sn}";
      claims = {
        "the nixos arm renders a systemd unit" = nixos.config.systemd.services ? ${sn} && failed nixos == [ ];
        "the unit runs the service's executable" = lib.hasInfix exe unit;
        "the darwin arm renders a launchd daemon" = darwin.config.launchd.daemons ? ${sn} && failed darwin == [ ];
        "the daemon runs the service's executable" = lib.hasInfix exe daemon;
        "home-manager refuses a system service" = trio.concept.support.homeManager.verdict == "refuses" && trio.concept.support.homeManager.why == "scope";
        "an arm left off renders nothing" = !(off.config.systemd.services ? ${sn});
      };
      broken = lib.attrNames (lib.filterAttrs (_: ok: !ok) claims);
    in
    if broken != [ ] then throw "service-${sn}-trio: ${lib.concatStringsSep "; " broken}"
    else pkgs.writeText "service-${sn}-trio" (builtins.toJSON (lib.attrNames claims));

  checks = lib.concatMapAttrs
    (sn: spec: {
      "service-${sn}-fresh" = pkgs.runCommand "service-${sn}-fresh" { } ''
        if ! diff -r ${trees.${sn}} ${builtins.path { path = src + "/${spec.output}"; name = "service-${sn}-committed"; }} > drift.log; then
          echo "service-${sn}-fresh: ${spec.output} is stale. Regenerate it: nix run .#regen" >&2
          head -60 drift.log >&2
          exit 1
        fi
        touch $out
      '';
      "service-${sn}-chart" = chartCheck sn spec;
    }
    // lib.optionalAttrs (executables ? ${sn}) { "service-${sn}-serves" = servesCheck sn spec; }
    // lib.optionalAttrs (components ? ${sn}) { "service-${sn}-component-serves" = componentServesCheck sn spec; }
    // lib.optionalAttrs ((spec.schema or { }) != { }) { "service-${sn}-migrations" = migrationsCheck sn spec; }
    // lib.optionalAttrs (trios ? ${sn}) { "service-${sn}-trio" = trioCheck sn trios.${sn}; }
    // lib.optionalAttrs (imageSets ? ${sn}) {
      "image-${sn}-distroless" = imageGate {
        name = "image-${sn}-distroless";
        image = imageSets.${sn}.packages."${sn}Image";
        tier = "distroless-static";
      };
    })
    services;
in
{
  inherit services trios executables components;

  packages = executables
    // lib.mapAttrs' (sn: c: lib.nameValuePair "service-${sn}-component" c) components
    // lib.mapAttrs' (sn: t: lib.nameValuePair "service-${sn}-tree" t) trees
    // lib.concatMapAttrs (sn: set: { "image-${sn}" = set.packages."${sn}Image"; }) imageSets;

  apps = lib.concatMapAttrs
    (sn: set: {
      "grype-scan-${sn}" = set.apps."grype-scan:${sn}";
      "scan-floor-${sn}" = {
        type = "app";
        program = "${oci.mkScanFloorApp {
          imagePath = set.packages."${sn}Image";
          expectTargets = [ "rustbinary" ];
          label = sn;
          inherit (oci.hardenedImageSetArgs) tataraScript;
        }}";
      };
    })
    imageSets;

  inherit checks;
}
