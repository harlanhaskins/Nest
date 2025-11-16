# Nest

Nest is a small utility that manages installed Swift command-line tools.

Nest fetches and builds Swift packages from your local disk, from GitHub, or
from a remote Git repository.

## Usage

Nest installs to `~/.nest/bin` by default, but you can override this by passing
`--install-dir`.

There are three primary ways to use Nest:

### Local

If you're working on a local project, or you've already cloned something, you
can just run `nest` inside that folder to install (or update) the project to
the install dir.

```
cd MyPackage
nest # will install to ~/.nest/bin/my-package
```

You can also install by providing an explicit path with `--path`

```
nest --path MyPackage
```

### By name

If you're looking at a package on GitHub, you can install it by name by
providing the owner/repo name:

```
nest harlanhaskins/Nest
```

This will fetch and install the `nest` binary from GitHub into `~/.nest.bin`.

### By URL

If you have a full Git URL (maybe on your own host) you can install it via
`--url`

```
nest --url https://github.com/harlanhaskins/Nest.git
```

## Uninstalling

Nest supports uninstalling by either the binary name, the Swift Package name,
or the full owner/repo identifier

```
nest uninstall nest
nest uninstall Nest
nest uninstall harlanhaskins/Nest
```

# Author

Harlan Haskins ([harlan@harlanhaskins.com](mailto:harlan@harlanhaskins.com))
