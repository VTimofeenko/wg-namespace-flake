{
  description = "A flake that implements Wireguard adapter that gets moved into a VPN namespace";
  outputs = _: {
    nixosModules.default = import ./modules;
  };
}
