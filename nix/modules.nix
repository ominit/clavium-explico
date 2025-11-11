{
  inputs,
  lib,
  ...
}: let
  evdevLoggerModule = {
    config,
    system,
    ...
  }: let
    cfg = config.services.ce-evdev-logger;
    analysisGroupName = "ce-evdev-logger-analysts";
  in {
    options.services.ce-evdev-logger = {
      enable = lib.mkEnableOption "Enable the ce-evdev-logger service";

      dbPath = lib.mkOption {
        type = lib.types.str;
        description = "Path to the SQLite database used by ce-evdev-logger.";
        example = "/var/lib/ce-evdev-logger/db.sqlite";
      };

      kbLayout = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Keyboard layout";
        example = "us";
      };

      kbModel = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Keyboard model";
        example = "pc104";
      };

      kbOptions = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Keyboard options";
        example = "caps:backspace";
      };

      kbRules = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Keyboard rules";
        example = "evdev";
      };

      kbVariant = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Keyboard variant";
        example = "colemak";
      };

      extraAnalysisUsers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = ''
          List of usernames (e.g., "alice", "bob") who should be granted read access
          to the database file for analysis. These users will be added to the
          system group "${analysisGroupName}".
        '';
      };
    };

    config = lib.mkIf cfg.enable {
      users.users.ce-evdev-logger = {
        isSystemUser = true;
        group = "ce-evdev-logger";
        extraGroups = [analysisGroupName "input"];
        description = "System user for ce-evdev-logger";
      };

      users.groups.ce-evdev-logger = {};
      users.groups.${analysisGroupName}.members = cfg.extraAnalysisUsers;

      systemd.tmpfiles.rules = [
        "d ${lib.strings.escapeNixString (builtins.dirOf cfg.dbPath)} 2770 ce-evdev-logger ${analysisGroupName} -"
      ];

      systemd.services.ce-evdev-logger = {
        description = "ce-evdev-logger service";

        wantedBy = ["multi-user.target"];
        after = ["local-fs.target" "systemd-udev-settle.service" "nss-lookup.target"];

        serviceConfig = {
          ExecStart = ''
            ${inputs.self.packages.${system}.ce-evdev-logger}/bin/ce-evdev-logger \
              --db-path "${cfg.dbPath}" \
              ${lib.optionalString (cfg.kbLayout != "") "--kb-layout \"${cfg.kbLayout}\""} \
              ${lib.optionalString (cfg.kbModel != "") "--kb-model \"${cfg.kbModel}\""} \
              ${lib.optionalString (cfg.kbVariant != "") "--kb-variant \"${cfg.kbVariant}\""} \
              ${lib.optionalString (cfg.kbOptions != "") "--kb-options \"${cfg.kbOptions}\""} \
              ${lib.optionalString (cfg.kbRules != "") "--kb-rules \"${cfg.kbRules}\""} \
          '';

          Restart = "always";
          RestartSec = "30";

          User = "ce-evdev-logger";
          Group = "ce-evdev-logger";

          # Security Hardening
          # Umask = "0007";
          PrivateTmp = true;
          # ProtectSystem = "strict";
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
          # SystemCallArchitecture = "native";
          RestrictNamespaces = true;
          RemoveIPC = true;
          PrivateUsers = true;
          # IPAddressDeny = true;
          ProtectProc = "noaccess";
          # BindReadOnlyPaths = ["/dev/input" "/nix/store"];
          SupplementaryGroups = "${builtins.toString config.users.groups.input.gid}";
          # RestrictAccessFamilies = "AF_UNIX";
          ProtectHome = true;
          ProtectHostname = true;
          RestrictRealtime = true;
          PrivateNetwork = true;
          CapabilityBoundingSet = "";
          NoNewPrivileges = true;
          RestrictSUIDSGID = true;
          # SystemCallFilter = "@system-service";
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          ProtectClock = true;
          # DeviceAllow = "/dev/input/event* r";
          # ReadOnlyPaths = "/dev/input";
          # ReadWritePaths = "${builtins.dirOf cfg.dbPath}";
          # DevicePolicy = "closed";
          # PrivateDevices = false;
        };
      };
    };
  };
in {
  flake.nixosModules = {
    inherit evdevLoggerModule;
  };
}
