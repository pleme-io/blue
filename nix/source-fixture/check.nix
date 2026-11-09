{ pkgs, blue, engine, src, tree }:

let
  pin = (builtins.fromJSON (builtins.readFile (src + "/Bluefile.lock"))).sources.upstream;
  asked = { type = "github"; owner = "pleme-io"; repo = "blue"; inherit (pin) rev narHash; };
  fetchTree = args:
    assert pkgs.lib.assertMsg (args == asked)
      "source-fixture: fetchTree was asked ${builtins.toJSON args}, the lock pins ${builtins.toJSON asked}";
    tree;
  fx = engine.projectFor { inherit pkgs blue src fetchTree; };
in
pkgs.runCommand "source-fixture" { } ''
  : ${pkgs.lib.concatStringsSep " " (pkgs.lib.attrValues fx.checks)}
  ${fx.runner}/bin/source-fixture test ${src + "/checks/reaches.b"} > $out
''
