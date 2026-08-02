{
  # The bidama distribution as a Nix flake — the PINNING half of blue's
  # packaging answer.
  #
  # ## Why this exists beside the git registry rather than instead of it
  #
  # `blue-lang-pkg`'s `GitRegistry` answers *"what does this package need"* by
  # reading `bidamas/<pkg>/Bluefile` out of a checkout. What it does NOT do is
  # say **which** checkout: it resolves from a working tree already on disk, so
  # it has no opinion about revisions.
  #
  # That is exactly the half a flake supplies. A consumer adds this flake as an
  # input, `flake.lock` records a revision and a NAR hash, and the distribution
  # a build sees is byte-identical to the one that was tested. Git answers the
  # dependency question; nix answers the identity question. They compose, and
  # neither is a second package manager for the other.
  #
  # This is the arrangement `docs/COMPETING-LANGUAGES.md` §1 argues for after
  # reviewing Cargo, Go modules, Hex, Unison, Deno and npm: Go proves a language
  # can resolve straight from VCS with no registry service, and Nix supplies the
  # pinning that raw VCS resolution lacks.
  #
  # ## What a consumer gets
  #
  # `packages.<system>.bidamas` — the distribution as a store path. Being in the
  # store is the point: the path is content-addressed, so two builds that
  # resolve the same revision cannot disagree about what a bidama contains.
  #
  # ## Tier — do not round this up
  #
  # This packages the distribution as DATA and checks each package's manifest
  # parses. It does not build blue, does not run the bidamas' behaviour tests
  # (those live in `blue-lang-runtime/tests/bidama_distribution.rs`, where a
  # failure is a red build), and does not make nix the *resolver*. Calling this
  # "nix is blue's package manager" would be a round-up: nix is the delivery and
  # pinning layer, and the resolver is still `blue-lang-pkg`.

  description = "bidamas — blue's standard distribution, pinned";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAll (pkgs: {
        default = self.packages.${pkgs.system}.bidamas;

        # The distribution, verbatim, as a store path.
        #
        # Copied rather than generated: a bidama is authored blue source, and a
        # build step that rewrote it would put a second author between the file
        # a human reads and the file a program loads.
        bidamas = pkgs.runCommand "bidamas" { } ''
          mkdir -p $out
          cp -r ${./.}/* $out/
          # A distribution with no packages is a packaging bug that otherwise
          # surfaces much later as "package not found", pointing the reader at
          # a missing dependency instead of an empty directory.
          count=$(find $out -mindepth 2 -name Bluefile | wc -l)
          if [ "$count" -lt 3 ]; then
            echo "bidamas: only $count Bluefile(s) found; refusing to publish" >&2
            exit 1
          fi
          echo "bidamas: packaged $count package(s)"
        '';
      });

      checks = forAll (pkgs: {
        # Every package directory must carry a Bluefile that NAMES ITSELF.
        #
        # A manifest declaring a different package resolves to the wrong thing
        # silently — the registry keys on what `package(...)` says, not on the
        # directory, precisely so the filesystem cannot lie about identity. That
        # protection is only real if something checks the two agree.
        manifests-name-themselves = pkgs.runCommand "bidama-manifests" { } ''
          fail=0
          for d in ${./.}/*/; do
            name=$(basename "$d")
            [ -f "$d/Bluefile" ] || continue
            if ! grep -q "package(\"$name\"" "$d/Bluefile"; then
              echo "$name/Bluefile does not declare package(\"$name\", …)" >&2
              fail=1
            fi
          done
          [ "$fail" -eq 0 ] || exit 1
          touch $out
        '';
      });
    };
}
