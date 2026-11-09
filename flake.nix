{
  description = "NVIDIA OpenShell — up-to-date packaging, kept ahead of nixpkgs";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      overlays.default = final: prev: {
        openshell = final.callPackage ./pkgs/openshell/package.nix { };
      };

      packages = forAllSystems (
        pkgs: rec {
          openshell = pkgs.callPackage ./pkgs/openshell/package.nix { };
          default = openshell;
        }
      );

      apps = forAllSystems (
        pkgs: {
          default = {
            type = "app";
            program = "${self.packages.${pkgs.system}.openshell}/bin/openshell";
          };
        }
      );
    };
}
