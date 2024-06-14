# SPDX-FileCopyrightText: 2020 Daniel Fullmer and robotnix contributors
# SPDX-License-Identifier: MIT

lib:

rec {
  # Guess resource type. Should normally work fine, but can't detect color/dimension types
  resourceTypeName =
    r:
    if lib.isBool r then
      "bool"
    else if lib.isInt r then
      "integer"
    else if lib.isString r then
      "string"
    else if lib.isList r then
      (
        assert (lib.length r != 0); # Cannot autodetect type of empty list
        if lib.isInt (lib.head r) then
          "integer-array"
        else if lib.isString (lib.head r) then
          "string-array"
        else
          assert false;
          "Unknown type"
      )
    else
      assert false;
      "Unknown type";
  resourceValueXML =
    value: type:
    {
      bool = lib.boolToString value;
      color = value; # define our own specialized type for these?
      dimen = value;
      integer = toString value;
      string = value;
      integer-array = lib.concatMapStringsSep "" (i: "<item>${toString i}</item>") value;
      string-array = lib.concatMapStringsSep "" (i: "<item>${i}</item>") value;
      # Ignoring other typed arrays for now
    }
    .${type};

  resourceXML =
    name: value:
    let
      resourceXMLEntity =
        name: value: type:
        ''<${type} name="${name}">${resourceValueXML value type}</${type}>'';
    in
    if lib.isAttrs value then
      # Submodule with manually specified resource type
      resourceXMLEntity name value.value value.type
    else
      # Bare value, so use Autodetected resource type
      resourceXMLEntity name value (resourceTypeName value);

  configXML = resources: ''
    <?xml version="1.0" encoding="utf-8"?>
    <resources>
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList resourceXML resources)}
    </resources>
  '';

  # Taken from https://github.com/edolstra/flake-compat/
  # Format number of seconds in the Unix epoch as %Y%m%d%H
  formatSecondsSinceEpoch =
    t:
    let
      rem = x: y: x - x / y * y;
      days = t / 86400;
      secondsInDay = rem t 86400;
      hours = secondsInDay / 3600;
      minutes = (rem secondsInDay 3600) / 60;
      seconds = rem t 60;

      # Courtesy of https://stackoverflow.com/a/32158604.
      z = days + 719468;
      era = (if z >= 0 then z else z - 146096) / 146097;
      doe = z - era * 146097;
      yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
      y = yoe + era * 400;
      doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
      mp = (5 * doy + 2) / 153;
      d = doy - (153 * mp + 2) / 5 + 1;
      m = mp + (if mp < 10 then 3 else -9);
      y' = y + (if m <= 2 then 1 else 0);

      pad = s: if builtins.stringLength s < 2 then "0" + s else s;
    in
    "${toString y'}${pad (toString m)}${pad (toString d)}${pad (toString hours)}";
}
