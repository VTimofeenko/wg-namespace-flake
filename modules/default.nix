{ pkgs, lib, config, ... }:
let
  cfg = config.services.wireguard-namespace;
in
{
  options.services.wireguard-namespace = with lib; {
    namespace_name = mkOption {
      type = types.str;
      description = "The name of the VPN network namespace";
      default = "vpn";
    };
    dns_server = mkOption {
      type = types.str;
      description = "IP address of the DNS server to be used in the network namespace";
    };
    extraFirewallRules = mkOption {
      type = types.str;
      default = "";
    };
    # Default options follow
    ips = mkOption {
      example = [ "192.168.2.1/24" ];
      default = [ ];
      type = with types; listOf str;
      description = "The IP addresses of the interface.";
    };
    privateKeyFile = mkOption {
      example = "/private/wireguard_key";
      type = with types; nullOr str;
      description = ''
        Private key file as generated by <command>wg genkey</command>.
      '';
    };
    peers =
      let
        peerOpts = {

          options = {

            publicKey = mkOption {
              example = "xTIBA5rboUvnH4htodjb6e697QjLERt1NAB4mZqp8Dg=";
              type = types.str;
              description = "The base64 public key of the peer.";
            };

            presharedKey = mkOption {
              default = null;
              example = "rVXs/Ni9tu3oDBLS4hOyAUAa1qTWVA3loR8eL20os3I=";
              type = with types; nullOr str;
              description = ''
                Base64 preshared key generated by <command>wg genpsk</command>.
                Optional, and may be omitted. This option adds an additional layer of
                symmetric-key cryptography to be mixed into the already existing
                public-key cryptography, for post-quantum resistance.
                Warning: Consider using presharedKeyFile instead if you do not
                want to store the key in the world-readable Nix store.
              '';
            };

            presharedKeyFile = mkOption {
              default = null;
              example = "/private/wireguard_psk";
              type = with types; nullOr str;
              description = ''
                File pointing to preshared key as generated by <command>wg genpsk</command>.
                Optional, and may be omitted. This option adds an additional layer of
                symmetric-key cryptography to be mixed into the already existing
                public-key cryptography, for post-quantum resistance.
              '';
            };

            allowedIPs = mkOption {
              example = [ "10.192.122.3/32" "10.192.124.1/24" ];
              type = with types; listOf str;
              description = ''List of IP (v4 or v6) addresses with CIDR masks from
        which this peer is allowed to send incoming traffic and to which
        outgoing traffic for this peer is directed. The catch-all 0.0.0.0/0 may
        be specified for matching all IPv4 addresses, and ::/0 may be specified
        for matching all IPv6 addresses.'';
            };

            endpoint = mkOption {
              default = null;
              example = "demo.wireguard.io:12913";
              type = with types; nullOr str;
              description = ''Endpoint IP or hostname of the peer, followed by a colon,
        and then a port number of the peer.
        Warning for endpoints with changing IPs:
        The WireGuard kernel side cannot perform DNS resolution.
        Thus DNS resolution is done once by the <literal>wg</literal> userspace
        utility, when setting up WireGuard. Consequently, if the IP address
        behind the name changes, WireGuard will not notice.
        This is especially common for dynamic-DNS setups, but also applies to
        any other DNS-based setup.
        If you do not use IP endpoints, you likely want to set
        <option>networking.wireguard.dynamicEndpointRefreshSeconds</option>
        to refresh the IPs periodically.
        '';
            };

            dynamicEndpointRefreshSeconds = mkOption {
              default = 0;
              example = 5;
              type = with types; int;
              description = ''
                Periodically re-execute the <literal>wg</literal> utility every
                this many seconds in order to let WireGuard notice DNS / hostname
                changes.
                Setting this to <literal>0</literal> disables periodic reexecution.
              '';
            };

            persistentKeepalive = mkOption {
              default = null;
              type = with types; nullOr int;
              example = 25;
              description = ''This is optional and is by default off, because most
        users will not need it. It represents, in seconds, between 1 and 65535
        inclusive, how often to send an authenticated empty packet to the peer,
        for the purpose of keeping a stateful firewall or NAT mapping valid
        persistently. For example, if the interface very rarely sends traffic,
        but it might at anytime receive traffic from a peer, and it is behind
        NAT, the interface might benefit from having a persistent keepalive
        interval of 25 seconds; however, most users will not need this.'';
            };

          };

        };
      in
      mkOption {
        default = [ ];
        description = "Peers linked to the interface.";
        type = with types; listOf (submodule peerOpts);
      };
  };
  config = {
    environment.etc = {
      "netns/${cfg.namespace_name}/resolv.conf".text = ''nameserver ${cfg.dns_server}'';
      # This setting forces the use of resolv.conf instead of dbus interface provided by systemd-resolved
      "netns/${cfg.namespace_name}/nsswitch.conf".text = ''
        passwd:    files systemd
        group:     files systemd
        shadow:    files

        hosts:     dns
        networks:  files

        ethers:    files
        services:  files
        protocols: files
        rpc:       files
      '';
    };
    environment.etc."nftables.d/${cfg.namespace_name}-namespace/${cfg.namespace_name}.nft".text = ''
      ${builtins.readFile ./namespace_default_fw.nft}

      ${cfg.extraFirewallRules}

    '';
    networking.wireguard.interfaces."${cfg.namespace_name}" = {
      ips = cfg.ips;
      privateKeyFile = cfg.privateKeyFile;
      interfaceNamespace = cfg.namespace_name;
      peers = cfg.peers;
      preSetup = [
        ''${pkgs.iproute2}/bin/ip netns add ${cfg.namespace_name}''
        ''${pkgs.iproute2}/bin/ip netns exec ${cfg.namespace_name} ${pkgs.nftables}/bin/nft --file /etc/nftables.d/${cfg.namespace_name}-namespace/${cfg.namespace_name}.nft''

      ];
      postShutdown = [ ''${pkgs.iproute2}/bin/ip netns del ${cfg.namespace_name}'' ];
    };
  };
}
