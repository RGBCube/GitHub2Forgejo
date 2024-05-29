# GitHub to Forgejo Migration Script

Plain simple, just install [Nushell](https://nushell.sh) and run the script:

```nu
./github2forgejo --help
```

<details>
<summary>Help Output</summary>

```
Migrates a GitHub users repositories to a Forgejo instance.

Accepted environment variables:

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

To leave an environment variable unspecified, set it to an empty string.

Usage:
  > github2forgejo

Flags:
  -h, --help - Display the help message for this command
```
</details>

You can either specify all the environment variables
for a uninteractive run, or run the script like so:

```nu
./github2forgejo
```

And get a nice interactive experience.

This works on any Forgejo instance.

You can also set up a systemd service and timer to run every once in a while.

Use the flake, like so:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    github2forgejo = {
      url = "github:RGBCube/GitHub2Forgejo";

      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, github2forgejo, ... }: let inherit (nixpkgs) lib; in {
    nixosConfigurations.myserver = lib.nixosSystem {
      modules = [
        github2forgejo.nixosModules.default

        {
          nixpkgs.overlays = [ github2forgejo.overlays.default ];

          services.github2forgejo = {
            enable = true;

            # Something along the lines of:
            #
            # GITHUB_USER="RGBCube"
            # GITHUB_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
            # FORGEJO_URL="https://git.rgbcu.be/"
            # FORGEJO_USER="RGBCube"
            # FORGEJO_TOKEN="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
            # STRATEGY="mirrored"
            # FORCE_SYNC="true"
            #
            # Do `GITHUB_TOKEN=""` if you want to only mirror public repositories of a person.
            # You HAVE TO set each one of these. Leaving one unset will make the systemd unit fail!
            environmentFile = "/secrets/github2forgejo.env";

            # The default runs every day at midnight. But you can override it like so:
            #
            # timerConfig = {
            #   OnCalendar         = "00:05";
            #   RandomizedDelaySec = "5h";
            #   Persistent         = true;
            # };
            #
            # Or you can disable the timer by setting `timerConfig` to null:
            #
            # timerConfig = null;
          }
        }
      ];
    }
  };
}
```

The script is also available as a package, you just need to use the
`packages.<system>.default` or `packages.<system>.github2forgejo` outputs.

## FAQ

### What is the difference between mirroring and cloning?

- **Mirroring:** Will get updated every now and then,
  keeping the repository in sync with the remote.

- **Cloning:** Will only clone the remote, and will
  not update or link to it anywhere in the repository.
  This is good for when you are migrating off GitHub permanently
  and will never come back.

### Can I migrate specific repositories?

Nope. Just use the Forgejo web UI for that.

## License

```
Copyright (C) 2024-present  RGBCube

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
```
