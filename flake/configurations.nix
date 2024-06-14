{ robotnixSystem, pkgs }:
{
  lineageos = (
    pkgs.lib.listToAttrs (
      map (device: {
        name = device;
        value = robotnixSystem {
          inherit device;

          flavor = "lineageos";
          androidVersion = 13;

          ccache.enable = true;

          # apv.enable = false;
          # adevtool.hash = "sha256-FZ5MAr9xlhwwT6OIZKAgC82sLn/Mcn/RHwZmiU37jxc="; 
        };
      }) [ "lemonade" ]
    )
  );

  grapheneos = (
    pkgs.lib.listToAttrs (
      map
        (device: {
          name = device;
          value = robotnixSystem {
            inherit device;

            flavor = "grapheneos";

            androidVersion = 13;

            ccache.enable = true;

            # apv.enable = false;
            # adevtool.hash = "sha256-NwUeDYmo3Kh8LKt9pZylzpI2yb5YDKWLo+ZiavrmDmw=";
          };
        })
        [
          "oriole"
          "panther"
        ]
    )
  );
}
