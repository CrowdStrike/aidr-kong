{
  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.1";
    flake-utils.url = "github:numtide/flake-utils";
    kong-pongo = {
      url = "github:Kong/kong-pongo/2.26.0";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    kong-pongo,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {inherit system;};

      pongo = pkgs.writeShellApplication {
        name = "pongo";
        runtimeInputs = with pkgs; [bash curl coreutils];
        text = ''
          exec ${kong-pongo}/pongo.sh "$@"
        '';
      };
    in {
      devShells.default = pkgs.mkShellNoCC {
        packages = with pkgs; [
          luarocks
          pongo
        ];
      };
    });
}
