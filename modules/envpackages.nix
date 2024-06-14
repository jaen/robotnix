# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{
  config,
  pkgs,
  lib,
  ...
}:

let
  inherit (lib) mkIf mkMerge;
in
{
  # It's convenient to have this all in one file, instead of separately in 9/default.nix, 10/default.nix, etc
  # Check build/soong/ui/build/paths/config.go for a list of things that are needed
  envPackages =
    with pkgs;
    mkMerge ([
      [
        bc
        git
        gnumake
        jre8_headless
        lsof
        m4
        ncurses5
        libxcrypt-legacy
        openssl # Used in avbtool
        psmisc # for "fuser", "pstree"
        rsync
        unzip
        zip

        # Things not in build/soong/ui/build/paths/config.go
        nettools # Needed for "hostname" in build/soong/ui/build/sandbox_linux.go
        procps # Needed for "ps" in build/envsetup.sh
      ]
      (mkIf (config.androidVersion >= 12) [
        freetype # Needed by jdk9 prebuilt
        fontconfig

        # Goldfish doesn't need py2 anymore in Android 12+!
        # c.f. https://android.googlesource.com/device/generic/goldfish/+/605e6a14e44c99e87d48bf52507f8aa01633fb04
        python3
      ])
    ]);
}
