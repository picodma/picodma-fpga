let sources = import ./nix/sources.nix;
    pkgs = import ./nix { inherit sources; };
    haskellPackages = pkgs.haskell.packages.ghc865;

in haskellPackages.callCabal2nix "picodma-fpga" ./. { }
    # picodma-fpga = haskellPackages.developPackage {
    #   root = (pkgs.gitignore.gitignoreSource ./.);
    #   name = "picodma-fpga";

    #   overrides = (self: super:
    #     { ghc = super.ghc // { withPackages = super.ghc.withHoogle; };
    #       ghcWithPackages = self.ghc.withPackages;
    #     });

    #   modifier = drv: pkgs.haskell.lib.overrideCabal drv (attrs: {
    #     buildTools = (attrs.buildTools or [])
    #       ++ [
    #         pkgs.niv
    #         pkgs.yosys
    #       ]
    #       ++ (with haskellPackages; [
    #         cabal-install
    #         clash-ghc
    #         clash-lib
    #         clash-ghc

    #         shake
    #         interpolate
    #         bytestring
    #         regex-tdfa
    #         influxdb
    #     ]);

    #     buildDepends = (attrs.buildDepends or []) ++ [ haskellPackages.shake ];
    #   });
    #   returnShellEnv = true;
    # };
# in { inherit pkgs picodma-fpga; }
