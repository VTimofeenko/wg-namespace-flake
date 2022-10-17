{
  description = "A flake that implements Wireguard adapter that gets moved into a VPN namespace";
  outputs = { self, nixpkgs }:
    {
      nixosModules.default = import ./modules;
    };
}
