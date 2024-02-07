# GitHub to Gitea/Forgejo Migration Script

Plain simple, just install [Nushell](https://nushell.sh) and run the script:

```nu
./migrate.nu --help
```

You can either specify all the CLI flags for a uninteractive run,
or run the script like so:

```nu
./migrate.nu
```

And get a nice interactive experience.

This works on any Gitea or Forgejo instance.

## FAQ

### What is the difference between mirroring and cloning?

- **Mirroring:** Will get updated every now and then,
  keeping the repository in sync with the remote.

- **Cloning:** Will only clone the remote, and will
  not update or link to it anywhere in the repository.
  This is good for when you are migrating off GitHub permanently
  and will never come back.

### Can I migrate specific repositories?

Sure, just pass the URLs to them as arguments:

```nu
./migrate.nu https://github.com/RGBCube/Foo https://github.com/RGBCube/Bar
```

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
