{ pkgs, lib, ... }:
{
  projectRootFile = "flake.nix";

  programs = {
    nixpkgs-fmt.enable = true;
    nixpkgs-fmt.package = pkgs.nixfmt-rfc-style;

    mypy.enable = true;
    mypy.directories = {
      "." = {
        # Fot whatever reason `excludes` doesn't work
        options = [
          "--exclude"
          "apks/chromium"
        ];
        extraPythonPackages = [ pkgs.python3.pkgs.pytest ];
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
}
