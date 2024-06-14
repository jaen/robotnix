{ lib }:
let
  inherit (lib)
    mkIf
    mkMerge
    mkOption
    mkOptionDefault
    mkEnableOption
    mkDefault
    types
    formatSecondsSinceEpoch
    ;
in
{
  flavor = mkOption {
    default = null;
    type = types.nullOr types.str;
    description = ''
      Set to one of robotnix's supported flavors.
      Current options are `vanilla`, `grapheneos`, and `lineageos`.
    '';
    example = "vanilla";
  };

  device = mkOption {
    default = null;
    type = types.nullOr types.str;
    description = "Code name of device build target";
    example = "marlin";
  };

  deviceDisplayName = mkOption {
    default = null;
    type = types.nullOr types.str;
    description = "Display name of device build target";
    example = "Pixel XL";
  };

  deviceFamily = mkOption {
    default = null;
    type = types.nullOr types.str;
    internal = true;
  };

  arch = mkOption {
    default = "arm64";
    type = types.enum [
      "arm64"
      "arm"
      "x86_64"
      "x86"
    ];
    description = "Architecture of phone, usually set automatically by device";
  };

  variant = mkOption {
    default = "user";
    type = types.enum [
      "user"
      "userdebug"
      "eng"
    ];
    description = ''
      `user` has limited access and is suited for production.
      `userdebug` is like user but with root access and debug capability.
      `eng` is the development configuration with additional debugging tools.
    '';
  };

  productName = mkOption {
    type = types.str;
    description = "Product name for choosecombo/lunch";
    defaultText = "\${productNamePrefix}\${device}";
    example = "aosp_crosshatch";
  };

  productNamePrefix = mkOption {
    default = "aosp_";
    type = types.str;
    description = "Prefix for product name used with choosecombo/lunch";
  };

  buildType = mkOption {
    default = "release";
    type = types.enum [
      "release"
      "debug"
    ];
    description = "one of \"release\", \"debug\"";
  };

  buildNumber = mkOption {
    type = types.str;
    description = ''
      Set this to something meaningful to identify the build.
      Defaults to `YYYYMMDDHH` based on `buildDateTime`.
      Should be unique for each build for disambiguation.
    '';
    example = "201908121";
  };

  buildDateTime = mkOption {
    type = types.int;
    description = ''
      Unix time (seconds since the epoch) that this build is taking place.
      Needs to be monotonically increasing for each build if you use the over-the-air (OTA) update mechanism.
      e.g. output of `date +%s`
    '';
    example = 1565645583;
    default =
      with lib;
      foldl' max 1 (mapAttrsToList (n: v: if v.enable then v.dateTime else 1) config.source.dirs);
    defaultText = "*maximum of source.dirs.<name>.dateTime*";
  };

  androidVersion = mkOption {
    default = 12;
    type = types.int;
    description = "Used to select which Android version to use";
  };

  flavorVersion = mkOption {
    type = types.str;
    internal = true;
    description = "Version used by this flavor of Android";
  };

  apiLevel = mkOption {
    type = types.int;
    internal = true;
    readOnly = true;
  };

  # TODO: extract system/product/vendor options into a submodule
  system.additionalProductPackages = mkOption {
    default = [ ];
    type = types.listOf types.str;
    description = "`PRODUCT_PACKAGES` to add under `system` partition.";
  };

  product.additionalProductPackages = mkOption {
    default = [ ];
    type = types.listOf types.str;
    description = "`PRODUCT_PACKAGES` to add under `product` partition.";
  };

  vendor.additionalProductPackages = mkOption {
    default = [ ];
    type = types.listOf types.str;
    description = "`PRODUCT_PACKAGES` to add under `vendor` partition.";
  };

  system.additionalProductSoongNamespaces = mkOption {
    default = [ ];
    type = types.listOf types.str;
    description = "`PRODUCT_SOONG_NAMESPACES` to add under `system` partition.";
  };

  product.additionalProductSoongNamespaces = mkOption {
    default = [ ];
    type = types.listOf types.str;
    description = "`PRODUCT_SOONG_NAMESPACES` to add under `product` partition.";
  };

  vendor.additionalProductSoongNamespaces = mkOption {
    default = [ ];
    type = types.listOf types.str;
    description = "`PRODUCT_SOONG_NAMESPACES` to add under `vendor` partition.";
  };  

  removedProductPackages = mkOption {
    default = [ ];
    type = types.listOf types.str;
    description = "`PRODUCT_PACKAGES` to remove from build";
  };

  system.extraConfig = mkOption {
    default = "";
    type = types.lines;
    description = "Additional configuration to be included in system .mk file";
    internal = true;
  };

  product.extraConfig = mkOption {
    default = "";
    type = types.lines;
    description = "Additional configuration to be included in product .mk file";
    internal = true;
  };

  vendor.extraConfig = mkOption {
    default = "";
    type = types.lines;
    description = "Additional configuration to be included in vendor .mk file";
    internal = true;
  };

  ccache.enable = mkEnableOption "ccache";

  envPackages = mkOption {
    type = types.listOf types.package;
    internal = true;
    default = [ ];
  };

  envVars = mkOption {
    type = types.attrsOf types.str;
    internal = true;
    default = { };
  };

  useReproducibilityFixes = mkOption {
    type = types.bool;
    default = true;
    description = "Apply additional fixes for reproducibility";
  };

  # Random attrset to throw build products into
  build = mkOption {
    internal = true;
    default = { };
    type = types.attrs;
  };
}
