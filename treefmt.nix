{ pkgs, lib, ... }:
{
  # Adding this options is a workaround for `config.build.programs` not evaluating properly
  # to get all formatter binaries into a devShell
  options.programs.mypy.package = lib.mkPackageOption pkgs [
    "python3Packages"
    "mypy"
  ] { };
  config = {
    projectRootFile = "flake.nix";

    programs = {
      nixpkgs-fmt.enable = true;
      nixpkgs-fmt.package = pkgs.nixfmt-rfc-style;

      mypy.enable = true;
      mypy.package = pkgs.python3.withPackages (
        ps: with ps; [
          mypy
          pytest
        ]
      );
      mypy.directories = {
        "." = {
          # Fot whatever reason using `settings.formatter.mypy.excludes` does not work properly
          options = [
            "--exclude"
            "apks/chromium"
            "--exclude"
            "result"
          ];
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
    };

    settings.formatter = {
      ruff-check.excludes = [ "apks/chromium/*" ];
      ruff-format.excludes = [ "apks/chromium/*" ];
      shellcheck.includes = lib.mkForce [
        "flavors/**/*.sh"
        "modules/pixel/update.sh"
        "scripts/patchelf-prefix.sh"
        "pkgs/robotnix/unpack-images.sh"
      ];
    };
  };
}
