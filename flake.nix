{
  description = "Build Android (AOSP) using Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    androidPkgs.url = "github:tadfisher/android-nixpkgs/stable";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      androidPkgs,
      treefmt-nix,
      ...
    }@inputs:
    let
      pkgs = import ./pkgs/default.nix { inherit inputs; };
      unstablePkgs = nixpkgs-unstable.legacyPackages.x86_64-linux;

      treeFmt = treefmt-nix.lib.evalModule unstablePkgs ./treefmt.nix;
      pythonForUpdaterScripts = pkgs.python3.withPackages (
        p: with p; [
          mypy
          flake8
          pytest
        ]
      );
    in
    {
      # robotnixSystem evaluates a robotnix configuration
      lib.robotnixSystem = configuration: import ./default.nix { inherit configuration pkgs; };

      defaultTemplate = {
        path = ./template;
        description = "A basic robotnix configuration";
      };

      nixosModule = import ./nixos; # Contains all robotnix nixos modules
      nixosModules.attestation-server = import ./nixos/attestation-server/module.nix;

      packages.x86_64-linux = {
        manual = (import ./docs { inherit pkgs; }).manual;
      };

      devShell.x86_64-linux = pkgs.mkShell {
        name = "robotnix-scripts";
        nativeBuildInputs = with pkgs; [
          pythonForUpdaterScripts
          gitRepo
          nix-prefetch-git
          curl
          pup
          jq
          shellcheck
          wget

          # For chromium updater script
          # python2
          cipd
          git

          cachix

          treeFmt.config.build.wrapper
        ];
        PYTHONPATH = ./scripts;
      };

      formatter.x86_64-linux = treeFmt.config.build.wrapper;

      checks.x86_64-linux = {
        formatting = treeFmt.config.build.check self;
      };
    };
}
