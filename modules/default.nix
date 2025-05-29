{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib) types;
  cfg = config.services.wireguard-namespace;
in
{
  options.services.wireguard-namespace = {
    enable = lib.mkEnableOption ''
      Whether to enable the NixOS module that moves a WireGuard interface into
      a dedicated network namespace'';

    namespaceName = lib.mkOption {
      type = types.str;
      description = "The name of the VPN network namespace";
      default = "vpn";
    };

    interfaceName = lib.mkOption {
      type = types.str;
      description = "Name of the WireGuard interface name to be moved into the namespace";
    };

    extraFirewallRules = lib.mkOption {
      type = types.str;
      description = "Extra firewall rules to be set inside namespace";
      default = "";
    };

  };

  config = lib.mkIf cfg.enable {
    systemd.services."wg-netnamespace@${cfg.namespaceName}" = {
      # Implementation
      script =
        let
          firewallRules = pkgs.writeTextFile {
            name = "nft-rules";
            text = ''
              ${builtins.readFile ./namespace_default_fw.nft}

              ${cfg.extraFirewallRules}
            '';
          };
        in
        # bash
        ''
          IFACE_NAME=${cfg.interfaceName}
          NAMESPACE_NAME=${cfg.namespaceName}

          # Dump the data
          # Assume that the interface has a single address. If this assumption does not
          # hold, this will need to be marshalled through an array of some sort
          ADDR=$(ip --json addr show dev mullvad | jq --raw-output '.[].addr_info[] | select(.family=="inet") | .local')

          ip netns add "''${NAMESPACE_NAME}"
          ip link set "''${IFACE_NAME}" netns "''${NAMESPACE_NAME}"

          # Manipulate the interface in the namespace
          ip -netns "''${NAMESPACE_NAME}" addr add "$ADDR" dev "''${IFACE_NAME}"
          ip -netns "''${NAMESPACE_NAME}" link set up dev "''${IFACE_NAME}"
          # Assume all traffic should go through the interface
          ip -netns "''${NAMESPACE_NAME}" route add default dev "''${IFACE_NAME}"
          ip netns exec "''${NAMESPACE_NAME}" ${lib.getExe pkgs.nftables} --file ${firewallRules}
        '';
      path = [
        pkgs.iproute2
        pkgs.jq
        pkgs.nftables
      ];
      serviceConfig.ExecStop = lib.getExe (
        pkgs.writeShellApplication {
          name = "netns-shutdown";

          runtimeInputs = [
            pkgs.iproute2
          ];

          text = ''
            IFACE_NAME=${cfg.interfaceName}
            NAMESPACE_NAME=${cfg.namespaceName}

              # Move adapter back
              ip -netns "''${NAMESPACE_NAME}" link set "''${IFACE_NAME}" netns 1
              # Destroy the namespace
              ip netns del "''${NAMESPACE_NAME}"
          '';
        }
      );

      # Ordering
      enable = true;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = "yes";
      };
      after = [ "network-online.target" ]; # TODO: maybe order specifically after the interface is up?
      requires = [ "network-online.target" ];

      # Hardening.
      # The systemd service operates on network namespaces, so it needs some
      # broad permissions. I have tried to enable some mitigations, but there's
      # still probably room for improvement
      serviceConfig = {
        SystemCallFilter =
          lib.pipe
            [
              "swap"
              "resources"
              "obsolete"
              "reboot"
              "raw-io"
              "privileged"
              "debug"
              "clock"
            ]
            # Pipeline that constructs the calls filter sets and inverts them at the end
            [
              (map (x: "@${x}"))
              (lib.concatStringsSep " ")
              (x: "~${x}")
            ];
        RestrictAddressFamilies = "AF_INET AF_INET6 AF_NETLINK";
        NoNewPrivileges = true;
        RestrictRealtime = true;
        LockPersonality = true;
        SystemCallArchitectures = "native";
        MemoryDenyWriteExecute = true;
        ProtectClock = true;
        ProtectHostname = true;
        RestrictNamespaces = "~user ipc pid uts cgroup";
        CapabilityBoundingSet = "~CAP_SETGID CAP_SETUID CAP_BLOCK_SUSPEND CAP_SYS_BOOT CAP_SYS_CHROOT CAP_SYS_RAWIO CAP_SYS_TTY_CONFIG CAP_BPF";
        RestrictSUIDSGID = true;
        # Known to break the service
        ProtectKernelTunables = false; # Breaks start
        ProtectHome = false; # Breaks start
      };

      # Misc
      description = "WireGuard isolated network namespace (%i)";
    };
  };
}
