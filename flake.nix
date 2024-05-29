{
  description = "GitHub to Forgejo migration script";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    systems.url = "github:nix-systems/default";
  };

  outputs = { self, nixpkgs, systems }: let
    inherit (nixpkgs) lib;

    eachSystem = lib.genAttrs (import systems);
  in {
    packages = eachSystem (system: let pkgs = import nixpkgs { inherit system; }; in rec {
      inherit (self.overlays.github2forgejo pkgs pkgs) github2forgejo;

      default = github2forgejo;
    });

    overlays = rec {
      default        = github2forgejo;
      github2forgejo = (final: super: {
        github2forgejo = super.callPackage ./package.nix {};
      });
    };

    nixosModules = rec {
      default        = github2forgejo;
      github2forgejo = { config, utils, lib, pkgs, ... }: let
        cfg = config.services.github2forgejo;
      in {
        options.services.github2forgejo = {
          enable  = lib.mkEnableOption (lib.mdDoc "the github2forgejo timer");
          package = lib.mkPackageOption pkgs "github2forgejo" {};

          environmentFile = lib.mkOption {
            type    = lib.types.path;
            default = null;
            description = lib.mdDoc ''
              File containing environment variables required by GitHub2Forgejo,
              in the format of an EnvironmentFile as described by {manpage}`systemd.exec(5)`.

              You must set ALL of these environment variables:

                GITHUB_USER: The user to fetch the repositories from.
                GITHUB_TOKEN: An access token for fetching private repositories. Optional.
               
                FORGEJO_URL: The URL to the Forgejo instance. Must include the protocol (https://).
                FORGEJO_USER: The user to migrate the repositories to.
                FORGEJO_TOKEN: An access token for the specified user.
               
                STRATEGY:
                  The strategy. Valid options are "mirrored" or "cloned" (case insensitive).
                  "mirrored" will mirror the repository and tell the Forgejo instance to
                  periodically update it, "cloned" will only clone once. "cloned" is
                  useful if you are never going to use GitHub again.
               
                FORCE_SYNC:
                  Whether to delete a mirrored repo from the Forgejo instance if the
                  source on GitHub doesn't exist anymore. Must be either "true" or "false".

              You must set an environment variable to an empty string to leave it "unset".
            '';

            example = "/secrets/github2forgejo.env";
          };

          timerConfig = lib.mkOption {
            type    = with lib.types; nullOr (attrsOf utils.systemdUtils.unitOptions.unitOption);
            default = {
              OnCalendar = "daily";
              Persistent = true;
            };

            description = lib.mdDoc ''
              When to run the script. See {manpage}`systemd.timer(5)` for
              details. If null, no timer will be created and the script
              will only run when explicitly started.
            '';

            example = {
              OnCalendar         = "00:05";
              RandomizedDelaySec = "5h";
              Persistent         = true;
            };
          };
        };

        config = lib.mkIf cfg.enable {
          systemd.services.github2forgejo = {
            wants            = [ "network-online.target" ];
            after            = [ "network-online.target" ];
            restartIfChanged = false;

            serviceConfig = {
              Type      = "oneshot";
              ExecStart = toString cfg.package;

              User        = "github2forgejo";
              DynamicUser = true;

              EnvironmentFile = cfg.environmentFile;
            };
          };

          systemd.timers.github2forgejo = lib.mkIf (cfg.timerConfig != null) {
            wantedBy    = [ "timers.target" ];
            timerConfig = cfg.timerConfig;
          };
        };
      };
    };
  };
}
