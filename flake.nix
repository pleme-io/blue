{
  description = "blue — a Ruby/Elixir surface on tatara-lisp and Rust";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-25.11";
    crate2nix.url = "github:nix-community/crate2nix";
    flake-utils.url = "github:numtide/flake-utils";
    substrate = {
      url = "github:pleme-io/substrate";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    crate2nix,
    flake-utils,
    substrate,
  }:
    (import "${substrate}/lib/rust-workspace-release-flake.nix" {
      inherit nixpkgs crate2nix flake-utils;
    }) {
      toolName = "blue";
      packageName = "blue-lang-cli";
      src = self;
      repo = "pleme-io/blue";

      # `lld`, because a test needs it and the shell is where that belongs.
      #
      # `blue-lang-wasm/tests/in_engine.rs` shells out to
      # `cargo build --target wasm32-unknown-unknown` and runs the artifact in
      # a real engine with zero host imports. That build needs a wasm linker.
      #
      # It passed on every laptop and failed on the first CI run that ever
      # executed it — `error: linker 'lld' not found` — because a laptop has an
      # ambient toolchain and a nix shell has exactly what it declares. The
      # test was right; the shell was short. "Passes locally" had meant "passes
      # on machines that happen to have it", which is the property a hermetic
      # shell exists to remove.
      #
      # `devShellPackages` is dev-shell-only and distinct from
      # `nativeBuildInputs`: this is tooling the TESTS need, not the build.
      devShellPackages = [ "lld" ];

      # The module trio, deploying blue's two configurable BOUNDS as a shikumi
      # YAML at `~/.config/blue/blue.yaml` and pointing `BLUE_CONFIG` at it.
      #
      # ── WHY TWO KEYS AND NOT THE THREE THE OLD WAIVER NAMED ──────────────
      #
      # This block previously said blue had "no configuration surface to
      # deploy" and named three blocked knobs. Measured 2026-08-01, two of the
      # three were not blocked — they were settled AGAINST being configurable,
      # which is a stronger statement than "not yet decided":
      #
      #   - formatter width  — `blue-lang-fmt`'s own module docs: "There is no
      #     configuration type in this crate, and that is the feature… there is
      #     nowhere to put a knob." §0 (one way to write a thing) plus the
      #     content-addressed identity of §V.16.1 both rest on the single
      #     rendering. Typing it would be a REGRESSION.
      #   - posture ceiling  — §V.24 moved ceilings to the ROOT as a Bluefile
      #     input. `blue_lang_waku::Waku` deliberately carries none, and
      #     `blue_lang_bidama::resolve(bidama, ceiling)` takes it as an
      #     argument. A daemon knob would re-create the anti-pattern §V.24
      #     removed.
      #   - execution budget — genuinely unsettled, for a concrete reason: no
      #     default constant exists in blue to expose. `pending-shikumi: M2`.
      #
      # What is left are two BOUNDS, each with a shipped overridable default in
      # code. Raising either changes no program's meaning — only whether a
      # pathological input is refused — so exposing them cannot freeze a design
      # guess as a public interface, which was the whole objection.
      #
      # The values here are NOT restated defaults; they are the same numbers
      # `BlueConfig::prescribed_default()` returns by naming
      # `blue_lang_pkg::DEFAULT_MAX_STEPS` / `blue_lang_syntax::MAX_EXPR_DEPTH`.
      # `every_field_is_emitted_by_the_module_trio` (in `blue-lang-cli`'s
      # `config` module) reads THIS FILE and fails if a field is renamed on the
      # Rust side without being renamed here — serde ignores unknown keys, so
      # the drift would otherwise be silent and blue would run on defaults
      # while an operator read their own config and believed it.
      module = {
        description = "blue — the pleme-io language";
        withShikumiConfig = true;
        shikumiDefaults = {
          solver_max_steps = 100000;
          max_expr_depth = 256;
        };
      };
    };
}
