Flake that provides a NixOS module which creates a network namespace and moves a
WireGuard adapter to that namespace. Whatever process is launched in that
namespace should egress only through the adapter.

To illustrate:

```
(user) $ curl ifconfig.co
X.X.X.X
(user) $ firejail --noprofile --netns=vpn sh
sh-5.1$ curl ifconfig.co
Y.Y.Y.Y
```

# Usage

1. Configure a WireGuard adapter, e.g. using [`systemd-networkd`][wiki].
2. Add this flake to your `inputs`;

    ```nix
    inputs = {.
      wg-namespace-flake = {
        url = "github:VTimofeenko/wg-namespace-flake";
      };
    }
    ```

3. Import the default module from this flake and configure it:

    ```nix
      # Namespace config
      services.wireguard-namespace = {
        enable = true;
        namespaceName = "vpn";
        interfaceName = "nameOfTheVPNAdapter";
      };
    ```

4. Make sure the `wg-netnamespace@vpn.service` is started

[wiki]: https://wiki.nixos.org/wiki/WireGuard#Setting_up_WireGuard_with_systemd-networkd
