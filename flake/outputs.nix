{
  self,
  nixpkgs,
  nixpkgs-unstable,
  androidPkgs,
  flake-compat,
  treefmt-nix,
  nix-github-actions,
  ...
}@inputs:
let
  pkgs = import ./../pkgs/default.nix { inherit inputs; };

  treeFmt = treefmt-nix.lib.evalModule pkgs ./../treefmt.nix;

  pythonForUpdaterScripts = pkgs.python3.withPackages (
    p: with p; [
      mypy
      flake8
      pytest
    ]
  );

  # robotnixSystem evaluates a robotnix configuration
  robotnixSystem = configuration: import ./../default.nix { inherit configuration pkgs; };

  robotnixConfigurations = import ./configurations.nix { inherit robotnixSystem pkgs; };
in
{
  inherit robotnixConfigurations;

  lib = {
    inherit robotnixSystem;
  };

  defaultTemplate = {
    path = ./../template;
    description = "A basic robotnix configuration";
  };

  nixosModule = import ./../nixos; # Contains all robotnix nixos modules
  nixosModules.attestation-server = import ./../nixos/attestation-server/module.nix;

  packages.x86_64-linux = {
    manual = (import ./../docs { inherit pkgs; }).manual;
    gitRepo = pkgs.gitRepo;
  };

  devShells.x86_64-linux =
    {
      default = pkgs.mkShell {
        name = "robotnix-scripts";
        inputsFrom = [ treeFmt.config.build.devShell ];
        nativeBuildInputs = with pkgs; [
          pythonForUpdaterScripts
          gitRepo
          nix-prefetch-git
          curl
          pup
          jq
          wget

          # For chromium updater script
          cipd
          git

          cachix
        ];
        PYTHONPATH = ./../scripts;
      };
    }
    // (pkgs.lib.mapAttrs (
      _: robotnixSystem: robotnixSystem.config.build.debugShell
    ) robotnixConfigurations);

  formatter.x86_64-linux = treeFmt.config.build.wrapper;

  checks.x86_64-linux = {
    formatting = treeFmt.config.build.check self;
    pytest = pkgs.stdenvNoCC.mkDerivation {
      name = "pytest";
      src = ./..;

      dontBuild = true;
      doCheck = true;

      nativeBuildInputs = with pkgs; [
        pythonForUpdaterScripts
        git
        gitRepo
        nix-prefetch-git
      ];
      checkPhase = ''
        NIX_PREFIX="$TMPDIR/nix"

        mkdir -p "$NIX_PREFIX"

        export NIX_STATE_DIR="$NIX_PREFIX/var/nix"

        pytest "$src" \
          -p no:cacheprovider \
          --junitxml="$out/report.xml"
      '';
    };
  };

  githubActions = nix-github-actions.lib.mkGithubMatrix { inherit (self) checks; };
}
