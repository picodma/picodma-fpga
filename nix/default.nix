{ sources ? import ./sources.nix }:

let
  overlay = super: pkgs: {
    # Nix tooling
    niv = (import sources.niv {}).niv;
    gitignore = import sources.gitignore {};

    # haskellPackages = pkgs.haskellPackages.override {
      # overrides = self: super: {
    # Haskell overrides
    haskell = pkgs.haskell // {
      packageOverrides = self: super: {

        clash-prelude =
          pkgs.haskell.lib.dontCheck
          # (pkgs.haskell.lib.dontHaddock
          (self.callCabal2nix "clash-prelude" (sources.clash-compiler + "/clash-prelude") {});
        clash-lib =
          pkgs.haskell.lib.dontCheck
          (pkgs.haskell.lib.dontHaddock
          (self.callCabal2nix "clash-lib" (sources.clash-compiler + "/clash-lib") {}));
        clash-ghc =
          pkgs.haskell.lib.dontCheck
          (pkgs.haskell.lib.dontHaddock
          (self.callCabal2nix "clash-ghc" (sources.clash-compiler + "/clash-ghc") {}));
        # External overrides
        ghc-typelits-extra =
          self.callCabal2nix "ghc-typelits-extra" sources.ghc-typelits-extra {};
        ghc-typelits-knownnat =
          self.callCabal2nix "ghc-typelits-knownnat" sources.ghc-typelits-knownnat {};

        higgledy =
          self.callCabal2nix "higgledy" sources.higgledy {};

        type-errors =
          self.callCabal2nix "type-errors" sources.type-errors {};

        first-class-families =
          self.callCabal2nix "first-class-families" sources.first-class-families {};
      # });
    };
    };
  } // import sources.clash-compiler {};

in import sources.nixpkgs { overlays = [ overlay ]; }
