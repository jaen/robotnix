# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

{ inputs ? (import (
    fetchTarball {
      url = "https://github.com/nix-community/flake-compat/archive/8bf105319d44f6b9f0d764efa4fdef9f1cc9ba1c.tar.gz";
      sha256 = "sha256:0b1vcbficjcrdyqzn4pbb63xwjch1056nmjyyhk4p7kdskhl3nlj"; }
  ) {
    src =  ../.;
  }).defaultNix.inputs,
  ... }@args:

let
  inherit (inputs) nixpkgs androidPkgs;
in nixpkgs.legacyPackages.x86_64-linux.appendOverlays [
  (self: super: {
    androidPkgs.packages = androidPkgs.packages.x86_64-linux;
    androidPkgs.sdk = androidPkgs.sdk.x86_64-linux;
  })
  (import ./overlay.nix { inherit inputs; })
]
