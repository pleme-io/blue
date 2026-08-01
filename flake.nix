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
