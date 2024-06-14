# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{
  config,
  pkgs,
  lib,
  robotnixlib,
  ...
}:

let
  inherit (lib)
    mkIf
    mkMerge
    mkOption
    mkOptionDefault
    mkEnableOption
    mkDefault
    types
    ;

  inherit (robotnixlib) formatSecondsSinceEpoch;

  fakeuser = pkgs.callPackage ./fakeuser { };
in
{
  options = import ./options.nix { inherit lib; };

  config = mkMerge [
    (mkIf
      (lib.elem config.device [
        "arm64"
        "arm"
        "x86"
        "x86_64"
      ])
      {
        # If this is a generic build for an arch, just set the arch as well
        arch = mkDefault config.device;
        deviceFamily = mkDefault "generic";
      }
    )
    {
      apiLevel =
        {
          "12" = 32;
          "13" = 33;
        }
        .${builtins.toString config.androidVersion} or 32;

      buildNumber = mkOptionDefault (formatSecondsSinceEpoch config.buildDateTime);

      productName = mkIf (config.device != null) (
        mkOptionDefault "${config.productNamePrefix}${config.device}"
      );

      system.extraConfig = lib.concatMapStringsSep "\n" (
        name: "PRODUCT_PACKAGES += ${name}"
      ) config.system.additionalProductPackages;

      product.extraConfig = lib.concatMapStringsSep "\n" (
        name: "PRODUCT_PACKAGES += ${name}"
      ) config.product.additionalProductPackages;

      vendor.extraConfig = lib.concatMapStringsSep "\n" (
        name: "PRODUCT_PACKAGES += ${name}"
      ) config.vendor.additionalProductPackages;

      # TODO: The " \\" in the below sed is a bit flaky, and would require the line to end in " \\"
      # come up with something more robust.
      source.dirs."build/make".postPatch =
        ''
          ${lib.concatMapStringsSep "\n" (
            name: "sed -i '/${name} \\\\/d' target/product/*.mk"
          ) config.removedProductPackages}
        ''
        + (
          if (config.androidVersion >= 10) then
            ''
              echo "\$(call inherit-product-if-exists, robotnix/config/system.mk)" >> target/product/handheld_system.mk
              echo "\$(call inherit-product-if-exists, robotnix/config/product.mk)" >> target/product/handheld_product.mk
              echo "\$(call inherit-product-if-exists, robotnix/config/vendor.mk)" >> target/product/handheld_vendor.mk
            ''
          else if
            (config.androidVersion >= 8) # FIXME Unclear if android 8 has these...
          then
            ''
              echo "\$(call inherit-product-if-exists, robotnix/config/system.mk)" >> target/product/core.mk
              echo "\$(call inherit-product-if-exists, robotnix/config/product.mk)" >> target/product/core.mk
              echo "\$(call inherit-product-if-exists, robotnix/config/vendor.mk)" >> target/product/core.mk
            ''
          else
            ''
              # no-op as it's not present in android 7 and under?
            ''
        );

      source.dirs."robotnix/config".src =
        let
          systemMk = pkgs.writeTextFile {
            name = "system.mk";
            text = config.system.extraConfig;
          };
          productMk = pkgs.writeTextFile {
            name = "product.mk";
            text = config.product.extraConfig;
          };
          vendorMk = pkgs.writeTextFile {
            name = "vendor.mk";
            text = config.vendor.extraConfig;
          };
        in
        pkgs.runCommand "robotnix-config" { } ''
          mkdir -p $out
          cp ${systemMk} $out/system.mk
          cp ${productMk} $out/product.mk
          cp ${vendorMk} $out/vendor.mk
        '';

      # A hack to make sure the out directory remains writeable after copying files/directories from /nix/store mounted sources
      source.dirs."prebuilts/build-tools".postPatch = mkIf (config.androidVersion >= 10) (
        let
          patchedCp = pkgs.substituteAll {
            src = ./fix-permissions.sh;
            inherit (pkgs) bash;
          };
        in
        ''
          pushd path/linux-x86
          mv cp .cp-wrapped
          cp ${patchedCp} cp
          chmod +x cp
          popd
        ''
      );

      envVars = mkMerge [
        {
          BUILD_NUMBER = config.buildNumber;
          BUILD_DATETIME = builtins.toString config.buildDateTime;
          DISPLAY_BUILD_NUMBER = "true"; # Enabling this shows the BUILD_ID concatenated with the BUILD_NUMBER in the settings menu
        }
        (mkIf config.ccache.enable {
          CCACHE_EXEC = pkgs.ccache + /bin/ccache;
          USE_CCACHE = "true";
          CCACHE_DIR = "/var/cache/ccache"; # Make configurable?
          CCACHE_UMASK = "007"; # CCACHE_DIR should be user root, group nixbld
          CCACHE_COMPILERCHECK = "content"; # Default is a mtime+size check. We can't fully rely on that.
        })
        (mkIf (config.androidVersion >= 11) {
          # Android 11 ninja filters env vars for more correct incrementalism.
          # However, env vars like LD_LIBRARY_PATH must be set for nixpkgs build-userenv-fhs to work
          ALLOW_NINJA_ENV = "true";
        })
      ];

      build = rec {
        postRaviole = lib.elem config.deviceFamily [ "raviole" "bluejay" "pantah" ];
        postPantah = lib.elem config.deviceFamily [ "pantah" ];
        androidBuilderToolkit =
          let
            requiredNativeBuildInputs = [ config.build.env fakeuser pkgs.util-linux ];
            builder = pkgs.writeShellScript "builder.sh" ''
              export SAVED_UID=$(${pkgs.coreutils}/bin/id -u)
              export SAVED_GID=$(${pkgs.coreutils}/bin/id -g)
              # Become a fake "root" in a new namespace so we can bind mount sources
              ${pkgs.toybox}/bin/cat << 'EOF' | ${pkgs.util-linux}/bin/unshare -m -r ${pkgs.runtimeShell}
              source $stdenv/setup
              genericBuild
              EOF
            '';
          in
          {
            inherit requiredNativeBuildInputs builder;
            # pass this to stdenv.mkDerivation to get the unpacked source for builds.
            flags = {
              inherit builder;
              srcs = [ ];

              nativeBuildInputs = requiredNativeBuildInputs;

              unpackPhase = pkgs.writeShellScript "android-source-unpack.sh" ''
                export rootDir=$PWD
                source ${config.build.unpackScript}
              '';
            };

            enterUserEnv = name: buildPhase: pkgs.writeShellScript "enter-user-env-for-${name}.sh" ''
              # Become the original user--not fake root.
              set -e -o pipefail
              ${pkgs.toybox}/bin/cat << 'EOF2' | fakeuser $SAVED_UID $SAVED_GID robotnix-build
              ${buildPhase}
              EOF2
              exit ''${PIPESTATUS[1]}
            '';

            buildPhase = { ninjaArgs ? "", makeTargets }: ''
              source build/envsetup.sh
              choosecombo ${config.buildType} ${config.productName} ${config.variant}

              # Fail early if the product was not selected properly
              test -n "$TARGET_PRODUCT" || exit 1
              CORES=''${NIX_BUILD_CORES:-$(${pkgs.coreutils}/bin/nproc)}
              export NINJA_ARGS="-j$CORES ${toString ninjaArgs} -v -d explain"
              ${lib.optionalString (config.androidVersion >= 13)''
              # needed for fontconfig
              export XDG_CACHE_HOME=$(pwd)
              export FONTCONFIG_PATH=$(get_build_var PRODUCT_OUT)/obj/ETC/fonts.xml_intermediates/
              export FONTCONFIG_FILE=fonts.xml
              ''}
              m ${toString makeTargets} | cat
              exit_code=''${PIPESTATUS[0]}
              # the android 13 build doesn't seem to set this var
              if [[ -z "$ANDROID_PRODUCT_OUT" ]]; then
                ANDROID_PRODUCT_OUT="$(get_build_var PRODUCT_OUT)"
              fi
              echo $ANDROID_PRODUCT_OUT > ANDROID_PRODUCT_OUT
              exit $exit_code
            '';
          };

        mkAndroid =
          { name
          , makeTargets ? [ ]
          , installPhase
          , buildPhase ? androidBuilderToolkit.buildPhase { inherit makeTargets ninjaArgs; }
          , nativeBuildInputs ? [ ]
          , outputs ? [ "out" ]
          , ninjaArgs ? ""
          , ...
          }@inputs:
          # Use NoCC here so we don't get extra environment variables that might conflict with AOSP build stuff. Like CC, NM, etc.
          pkgs.stdenvNoCC.mkDerivation (androidBuilderToolkit.flags // (inputs // {
            # TODO: update in the future, might not be required.
            # gets permissed denied if not set, in some of our deps
            dontUpdateAutotoolsGnuConfigScripts = true;

            nativeBuildInputs = androidBuilderToolkit.requiredNativeBuildInputs ++ nativeBuildInputs;
            # TODO: Clean this stuff up. unshare / robotnix-build could probably be combined into a single utility.
            requiredSystemFeatures = [ "big-parallel" ];

            dontConfigure = true;
            # This was originally in the buildPhase, but building the sdk / atree would complain for unknown reasons when it was set
            # export OUT_DIR=$rootDir/out
            buildPhase = androidBuilderToolkit.enterUserEnv "mkAndroid-${name}" ''
              ${buildPhase}
            '';

            preInstall = ''
              if [ -f ANDROID_PRODUCT_OUT ]; then
                export ANDROID_PRODUCT_OUT=$(cat ANDROID_PRODUCT_OUT)
              fi
            '' + (inputs.preInstall or "");

            installPhase = ''
              set -e -o pipefail
              runHook preInstall
              ${installPhase}
              runHook postInstall
            '';

            dontFixup = true;
            dontMoveLib64 = true;
          }) // config.envVars);

        android = mkAndroid {
          name = "robotnix-${config.productName}-${config.buildNumber}";
          makeTargets = [
            "target-files-package"
            "otatools-package"
          ];
          # Note that $ANDROID_PRODUCT_OUT is set by choosecombo above
          installPhase = ''
            mkdir -p $out
            cp --reflink=auto $ANDROID_PRODUCT_OUT/otatools.zip $out/
            cp --reflink=auto $ANDROID_PRODUCT_OUT/obj/PACKAGING/target_files_intermediates/${config.productName}-target_files-${config.buildNumber}.zip $out/
          '';
        };

        checkAndroid = mkAndroid {
          name = "robotnix-check-${config.device}-${config.buildNumber}";
          makeTargets = [
            "target-files-package"
            "otatools-package"
          ];
          ninjaArgs = "-n"; # Pretend to run the actual build steps
          # Just copy some things that are useful for debugging
          installPhase = ''
            mkdir -p $out
            cp -r out/*.{log,gz} $out/
            cp -r out/.module_paths $out/
          '';
        };

        moduleInfo = mkAndroid {
          name = "robotnix-module-info-${config.device}-${config.buildNumber}.json";
          # Can't use absolute path from $ANDROID_PRODUCT_OUT here since make needs a relative path
          makeTargets = [ "$(get_build_var PRODUCT_OUT)/module-info.json" ];
          installPhase = ''
            cp $ANDROID_PRODUCT_OUT/module-info.json $out
          '';
        };

        # Save significant build time by building components simultaneously.
        mkAndroidComponents =
          targets:
          mkAndroid {
            name = "robotnix-android-components";
            makeTargets = targets ++ [ "$(get_build_var PRODUCT_OUT)/module-info.json" ];
            installPhase = ''
              ${pkgs.python3.interpreter} - "$out" "$ANDROID_PRODUCT_OUT/module-info.json" ${lib.escapeShellArgs targets} << EOF
              import json
              import os
              import shutil
              import sys
              outdir = sys.argv[1]
              module_info = json.load(open(sys.argv[2]))
              targets = sys.argv[3:]
              for target in targets:
                  if target in module_info:
                      for item in module_info[target]['installed']:
                          if item.startswith('out/'):
                              output = outdir + item[3:]
                          else:
                              output = outdir + '/' + item
                          os.makedirs(os.path.dirname(output), exist_ok=True)
                          shutil.copyfile(item, output)
              EOF
            '';
          };

        mkAndroidComponent =
          target:
          (mkAndroidComponents [ target ]).overrideAttrs (_: {
            name = target;
          });

        otaTools = fixOtaTools "${config.build.android}/otatools.zip";

        # Also make a version without building all of target-files-package.  This
        # is just for debugging. We save significant time for a full build by
        # normally building target-files-package and otatools-package
        # simultaneously
        otaToolsQuick = fixOtaTools (mkAndroid {
          name = "otatools.zip";
          makeTargets = [ "otatools-package" ];
          installPhase = ''
            cp --reflink=auto $ANDROID_PRODUCT_OUT/otatools.zip $out
          '';
        });

        fixOtaTools =
          src:
          pkgs.stdenv.mkDerivation {
            name = "ota-tools";
            inherit src;
            sourceRoot = ".";
            nativeBuildInputs = with pkgs; [
              unzip
              python3Packages.pytest
            ];
            buildInputs = [ (pkgs.python3.withPackages (p: [ p.protobuf ])) ];
            postPatch =
              lib.optionalString (config.androidVersion == 11) ''
                cp bin/debugfs_static bin/debugfs
              ''
              + lib.optionalString (config.androidVersion <= 10) ''
                substituteInPlace releasetools/common.py \
                  --replace 'self.search_path = platform_search_path.get(sys.platform)' "self.search_path = \"$out\"" \
              '';

            dontBuild = true;

            installPhase =
              ''
                for file in bin/*; do
                  isELF "$file" || continue
                  bash ${../../scripts/patchelf-prefix.sh} "$file" "${pkgs.stdenv.cc.bintools.dynamicLinker}" || continue
                done
              ''
              + ''
                mkdir -p $out
                cp --reflink=auto -r * $out/
              ''
              + lib.optionalString (config.androidVersion <= 10) ''
                ln -s $out/releasetools/sign_target_files_apks.py $out/bin/sign_target_files_apks
                ln -s $out/releasetools/img_from_target_files.py $out/bin/img_from_target_files
                ln -s $out/releasetools/ota_from_target_files.py $out/bin/ota_from_target_files
              '';

            # Since we copy everything from build dir into $out, we don't want
            # env-vars file which contains a bunch of references we don't need
            noDumpEnvVars = true;

            # This breaks the executables with embedded python interpreters
            dontStrip = true;
          };

        # Just included for convenience when building outside of nix.
        # TODO: Better way than creating all these scripts and feeding with init-file?
        #        debugUnpackScript = config.build.debugUnpackScript;
        #        debugPatchScript = config.build.debugPatchScript;
        debugBuildScript = pkgs.writeShellScript "debug-build.sh" ''
          ${lib.replaceStrings [ " | cat" ] [ "" ] (
            config.build.androidBuilderToolkit.buildPhase { makeTargets = config.build.android.makeTargets; }
          )}
        '';

        unsharedDebugEnterEnv = pkgs.writeShellScript "debug-enter-env2.sh" ''
          export rootDir=$PWD
          export PATH=${config.build.env}/bin/:$PATH
          source ${config.build.unpackScript}
          # ''${config.build.adevtool.patchPhase}
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (name: value: "export ${name}=${value}") config.envVars
          )}
          # Become the original user--not fake root. Enter an FHS user namespace
          ${fakeuser}/bin/fakeuser $SAVED_UID $SAVED_GID ${config.build.env}/bin/robotnix-build
        '';

        debugEnterEnv = pkgs.writeShellScript "debug-enter-env.sh" ''
          export SAVED_UID=$(${pkgs.coreutils}/bin/id -u) SAVED_GID=$(${pkgs.coreutils}/bin/id -g)
          ${pkgs.util-linux}/bin/unshare -m -r ${unsharedDebugEnterEnv}
        '';

        debugShell = config.build.mkAndroid {
          name = "${config.device}-debug-shell";
          outputs = [ "out" ];
          unpackPhase = "true";
          buildPhase = "true";
          installPhase = ''
            mkdir -p $out/bin
            ln -s ${debugEnterEnv} $out/bin/debug-enter-env.sh
            ln -s ${unsharedDebugEnterEnv} $out/bin/unshared-debug-enter-env.sh
            ln -s ${debugBuildScript} $out/bin/debug-build.sh
          '';
        };

        # debugEnterEnv = pkgs.writeShellScript "debug-enter-env.sh" ''
        #   export SAVED_UID=$(${pkgs.coreutils}/bin/id -u)
        #   export SAVED_GID=$(${pkgs.coreutils}/bin/id -g)
        #   ${pkgs.util-linux}/bin/unshare -m -r ${pkgs.writeShellScript "debug-enter-env2.sh" ''
        #     export rootDir=$PWD
        #     source ${config.build.unpackScript}
        #     ${lib.concatStringsSep "\n" (
        #       lib.mapAttrsToList (name: value: "export ${name}=${value}") config.envVars
        #     )}
        #
        #     # Become the original user--not fake root. Enter an FHS user namespace
        #     ${fakeuser}/bin/fakeuser $SAVED_UID $SAVED_GID ${config.build.env}/bin/robotnix-build
        #   ''}
        # '';

        env =
          let
            # Ugly workaround needed in Android >= 12
            patchedPkgs = pkgs.extend (
              self: super: {
                bashInteractive = super.bashInteractive.overrideAttrs (attrs: {
                  # Removed:
                  # -DDEFAULT_PATH_VALUE="/no-such-path"
                  # -DSTANDARD_UTILS_PATH="/no-such-path"
                  # This creates a bash closer to a normal FHS distro bash.
                  # Somewhere in the android build system >= android 12, bash starts
                  # inside an environment with PATH unset, and it gets "/no-such-path"
                  # Command: env -i bash -c 'echo $PATH'
                  # On NixOS/nixpkgs it outputs:  /no-such-path
                  # On normal distros it outputs: /usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin:.
                  NIX_CFLAGS_COMPILE = ''
                    -DSYS_BASHRC="/etc/bashrc"
                    -DSYS_BASH_LOGOUT="/etc/bash_logout"
                    -DNON_INTERACTIVE_LOGIN_SHELLS
                    -DSSH_SOURCE_BASHRC
                  '';
                });
              }
            );
            buildFHSUserEnv =
              if (config.androidVersion >= 12) then patchedPkgs.buildFHSUserEnv else pkgs.buildFHSUserEnv;
          in
          buildFHSUserEnv {
            name = "robotnix-build";
            targetPkgs = pkgs: config.envPackages;
            multiPkgs = pkgs: with pkgs; [ zlib ];

            # TODO might not be needed in the future, required now because
            # Android works in mysterious ways. Wasn't needed in the past
            # because these paths were already a part of LD_LIBRARY_PATH
            # when using FHS.
            #
            # See here for issue when it was introduced https://github.com/NixOS/nixpkgs/issues/262775
            # Inspiration taken from here https://github.com/NixOS/nixpkgs/pull/278361
            # More information here as well https://github.com/NixOS/nixpkgs/issues/103648
            profile = ''
              export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/lib:/usr/lib32
            '';
          };
      };
    }
  ];
}
