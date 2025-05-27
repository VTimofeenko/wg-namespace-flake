> [!IMPORTANT]
> This repo relies on non-`networkd` managed WireGuard. `Networkd` does not
> support namespaces: [pull request in systemd
> repo](https://github.com/systemd/systemd/pull/14915)

This is a Nix flake that configures a Linux namespace and a WireGuard adapter in it.

# Usage

For example usage, see [project notes](./project.org#usage-example)
