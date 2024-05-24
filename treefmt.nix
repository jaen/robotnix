{ config, pkgs, lib, ... }:
{
  # Additional options
  options = {
    # Workaround for `config.build.programs` not evaluating properly
    # to get all formatter binaries into a devShell
    programs.mypy.package = lib.mkPackageOption pkgs [
      "python3Packages"
      "mypy"
    ] { };

    # GHA linting options
    # Needs the go implementation to work properly due to the hidden files issue
    programs.actionlint = {
      enable = lib.mkEnableOption "actionlint";
      package = lib.mkPackageOption pkgs "actionlint" { };
    };
  };

  config = {
    projectRootFile = "flake.nix";

    # The go implementation does not have problems with hidden files,
    # buth then it has this https://github.com/numtide/treefmt/issues/316,
    # so still using Rust version for now
    # package = pkgs.treefmt2;

    programs = {
      nixpkgs-fmt.enable = true;
      nixpkgs-fmt.package = pkgs.nixfmt-rfc-style;

      mypy.enable = true;
      mypy.package = pkgs.python3.withPackages(ps: with ps; [ mypy pytest ]);
      mypy.directories = {
        "." = {
          # Fot whatever reason using `settings.formatter.mypy.excludes` does not work properly
          options = lib.cli.toGNUCommandLine {} {
            exclude = [ "apks/chromium" "result" ];
          };
          # Has to be set again, because treefmt clears PYTHONPATH and running via `treefmt` fails, see:
          # https://github.com/numtide/treefmt-nix/blob/main/programs/mypy.nix#L67
          extraPythonPackages = [ pkgs.python3Packages.pytest ];
        };
      };

      # Drop–in flake8 replacement
      ruff.format = true;
      ruff.check = true;

      shfmt.enable = true;

      shellcheck.enable = true;

      actionlint.enable = true;
    };

    settings = {
      # We don't lint those files
      excludes = [
        "*.patch"
        "*.json"
        "modules/apps/updater-sepolicy/**"
        "docs/**"
        "LICENSES/**"
        # trivial and possibly replaceable with another `unshare` call nowadays
        "modules/fakeuser/fakeuser.c"
        "modules/fakeuser/meson.build"
        # mirror of nixpkgs upstream
        "pkgs/fetchgit/nix-prefetch-git"
        "flavors/lineageos/lastUpdated.epoch"
        "NEWS.md"
        "README.md"
        ".flake8"
        ".gitignore"
        "mypy.ini"
        "flake.lock"
        "treefmt.toml"
      ];

      formatter = {
        ruff-check.excludes = [ "apks/chromium/*" ];

        ruff-format.excludes = [ "apks/chromium/*" ];

        shellcheck.includes = lib.mkForce [
          "flavors/**/*.sh"
          "modules/pixel/update.sh"
          "scripts/patchelf-prefix.sh"
          "pkgs/robotnix/unpack-images.sh"
        ];

        # GHA linting implementation
        # Needs the go implementation to work properly due to the hidden files issue
        actionlint = lib.mkIf config.programs.actionlint.enable {
          command = config.programs.actionlint.package;
          includes = [
            ".github/workflows/*.yml"
            "./github/workflows/*.yml"
          ];
        };

        # This is here to shut all the "no formatter for path" for excluded files up
        # See: https://github.com/numtide/treefmt/issues/317
        # It's go-version-specific, but it doesn't hurt to leave it in
        dummy = let 
          allExcludes = config.settings.excludes
            ++ lib.concatMap (f: f.excludes) (builtins.attrValues config.settings.formatter);
        in {
          command = "true";
          includes = lib.unique allExcludes;
        };
      };
    };
  };
}
