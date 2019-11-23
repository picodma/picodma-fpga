let sources = import ./nix/sources.nix;
    pkgs = import ./nix/default.nix { inherit sources; };
    haskellPackages = pkgs.haskell.packages.ghc865;

in haskellPackages.developPackage {
  root = pkgs.nix-gitignore.gitignoreSource [] ./.;
  name = "picodma-fpga";

  overrides = (self: super:
    { ghc = super.ghc // { withPackages = super.ghc.withHoogle; };
      ghcWithPackages = self.ghc.withPackages;
    });

  modifier = drv: pkgs.haskell.lib.overrideCabal drv (attrs: {
    buildTools = (attrs.buildTools or [])
      ++ [
        pkgs.niv
        pkgs.yosys
      ]
      ++ (with haskellPackages; [
        cabal-install
        clash-ghc
        clash-lib
        clash-ghc

        shake
        interpolate
        bytestring
        regex-tdfa
        influxdb
    ]);
  });

  returnShellEnv = true;
}
