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

      # No `module` yet, and that is a decision rather than an omission.
      #
      # The module trio would deploy `blue` to the fleet with a shikumi YAML
      # config surface. Blue has no configuration surface to deploy: the CLI
      # takes a file and a subcommand, and the things that WILL be configurable
      # — the posture ceiling, the default execution budget, the formatter
      # width — are each blocked on a design that is not settled
      # (`theory/BLUE.md` §V.19, §V.13).
      #
      # Emitting an options schema now would freeze guesses as a public
      # interface. `pending-shikumi:` in CLAUDE.md carries this, per the fleet
      # ★★ CONFIGURATION MANAGEMENT waiver grammar.
    };
}
