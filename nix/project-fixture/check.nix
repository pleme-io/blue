# `checks.project-fixture`: the project engine (nix/project.nix), read back
# from a built project.
#
# The fixture's own checks (its bidama test, collisions, the lock gates, its
# `check` word) are inputs, so each is built and must pass. The runner must run
# the package's tests. Then `gate.b` reads the runs' outputs and the app's.
#
# `src` is a parameter so a red run can point the SAME gate at a broken copy of
# the fixture, with a built `blue`, and no rebuild of blue itself.
#
# Red runs, 2026-09-24, each on a scratch copy of the fixture with a built
# `blue`, each red naming its fault:
#   - a run that ignores RUN_OUT     "run first: the program wrote nothing into $RUN_OUT"
#   - `second` writing first + 2     "FAIL a run reads the run it names through RUN_READS"
#   - checks/smoke.b with no tests   "…smoke.b: no `test` blocks, so nothing was tested"
#   - the package defining `unique`  bidama-collisions: (("unique" ("fixture" "shuugou")))
# and at evaluation, each a `lib.project:` error naming it: a `source(...)`
# word, `tool("no-such-tool-xyz")`, a lock key `service` no word lowers,
# `check("bidama-collisions", …)`, and `needs("no-such-pkg", …)`.
# The unbroken copy: "4 test(s): 4 passed, 0 failed".
{ pkgs, blue, engine, src }:

let
  fx = engine.projectFor { inherit pkgs blue src; };
in
pkgs.runCommand "project-fixture" { } ''
  : ${pkgs.lib.concatStringsSep " " (pkgs.lib.attrValues fx.checks)}
  GREET_OUT=$PWD/greet ${fx.apps.greet.program}
  ${fx.runner}/bin/project-fixture test ${src + "/bidamas/fixture/fixture.b"} > runner.log
  FIRST=${fx.packages.first} SECOND=${fx.packages.second} GREET=$PWD/greet \
    BLUE_PATH=${fx.bluePath} ${blue}/bin/blue test ${./gate.b} > $out
''
