> **This is a fork of [BloodyMods/ServerStarter](https://github.com/BloodyMods/ServerStarter)**, which has been
> unmaintained since July 2022. It is patched to run as a supervised container process so it can back a
> Pterodactyl/Calagopus egg. See [`pterodactyl/`](pterodactyl/) for the egg, and the
> [v2.4.2 release notes](https://github.com/AlyxiaFox/ServerStarter/releases/tag/v2.4.2) for what changed.
>
> The CurseForge (`curse` / `curseid`) modpack formats are broken upstream and are not fixed here. Use
> `modpackFormat: zip`.

# Minecraft Server File Specification

## What is this?
This is the specification for a file that is supposed to be distributed together with or separately from the modpack.
It is supposed to be used by server launchers (_like this one_) to know what it is supposed to do.

The launcher in this repository reads that file, downloads and unpacks the modpack, installs the mod loader,
and then starts the Minecraft server as a subprocess and keeps an eye on it.

## Why?
You might ask, why not just throw the client files next to a forge installer and then call it a day?
You are correct, you can do this if you set it up on your local server, but that is a lot of manual labor.

But it allows for more:
* Reduced size of the server files when downloading and uploading to a server.
* As it is not launching the server directly but a subprocess it allows for specifying java args easily,
    which might not always be possible on some hosting providers.
* This file format is not bound to any program, modpack, or even programming language!
    A parser could be written for any other utility program to take care of the special problems specified in the file.
* With the use of wildcard options and regex selectors it could be made to even work across modpack versions.

## Running a server

### On your own machine
Grab `serverstarter-<version>.zip` from the [latest release](https://github.com/AlyxiaFox/ServerStarter/releases/latest).
It contains the launcher jar, an example `server-setup-config.yaml`, and a start script for either platform.

1. Unpack it into an empty folder, which becomes the server directory.
2. Edit `server-setup-config.yaml`. At minimum set `modpackUrl`, `mcVersion` and `loaderVersion`.
3. Run `startserver.sh` on Linux or macOS, or `startserver.bat` on Windows.

The first start downloads the modpack and the mod loader, so it takes a while. Every start after that goes
straight to launching the server.

You can also skip the start script and run the jar yourself, as long as `server-setup-config.yaml` sits next to it:

```
java -jar serverstarter-<version>.jar
```

Pass `install` as an argument to set everything up and exit without starting the server, which is handy when you
are preparing an image or a container:

```
java -jar serverstarter-<version>.jar install
```

The server will not start until the Minecraft EULA is accepted. Either answer the prompt on first run, or set
`SERVERSTARTER_ACCEPT_EULA=true` in the environment, which is what you want on an unattended machine where nothing
can answer a prompt.

### With Pterodactyl or Calagopus
[`pterodactyl/`](pterodactyl/) holds a ready-made egg. Import `egg-serverstarter.json` through
**Admin → Nests → Import Egg** and fill in the modpack URL, Minecraft version and loader version. The egg pins a
specific release of the launcher jar and verifies its checksum, so installs are reproducible.
See [`pterodactyl/README.md`](pterodactyl/README.md) for the variables and the design decisions behind them.

## Format
See [`server-setup-config.yaml`](server-setup-config.yaml) for an example file showing how this file should be laid out.
Every option is documented in place.

A few things are worth knowing before you write your own:

* `startCommand` is an argument array, not a command line. Every token has to be its own entry, including the value
    of an option, otherwise the loader receives `--option value` as a single unrecognised argument and refuses to start.
* `installerArguments` is passed to the mod loader installer verbatim. The `{{@mcversion@}}` style placeholders are
    **not** substituted there, so versions have to be written out in full.
* `baseInstallPath` is where the server ends up. Leave it empty to install into the current directory.
* `ramDisk` does not create a RAMDisk. It only rsyncs the world to and from `<levelName>_backup` around launch and
    shutdown, so something else has to mount a tmpfs at the world path. `startserver.sh` does this for you;
    if you launch the jar directly, you are on your own.

The launcher records what it installed in `serverstarter.lock`. It reinstalls when the modpack URL or the loader
version in the config no longer matches that file, so changing either is enough to pull a new pack. Delete the
lockfile to force a reinstall. Runtime output is mirrored to `serverstarter.log`.

## What this fork changes
* The Minecraft process's exit code is passed through, so a crash is distinguishable from a clean shutdown and a
    supervisor such as Wings, systemd or Docker can act on it. Upstream always exited `0`.
* The EULA can be accepted through the environment instead of the interactive prompt, which would otherwise block
    forever in a container where stdin never delivers a line and never reaches EOF.
* An unset `${ENV_VAR}` in the config resolves to an empty string with a warning rather than aborting the whole
    config load.
* A malformed config reports the actual parse error instead of an unrelated `NoClassDefFoundError`.
* `serverstarter.log` is actually written. It used to be truncated after its sink had already opened it, which on
    Linux left no log on disk at all.
* The RAMDisk branch in `startserver.sh` works, and refuses to run rather than shuffling directories around when the
    world folder or a leftover backup would be at risk.
* Releases ship a fat jar and a standalone archive, both with checksums.

## Requirements
Java has to match the Minecraft version, not the launcher. The launcher itself is built for Java 8 and runs on
anything newer.

| Minecraft | Java |
| --- | --- |
| 1.12 – 1.16 | 8 to 11 |
| 1.17 – 1.20.4 | 17 |
| 1.20.5 – 1.21.x | 21 |
| 26.1 and newer | 25 |

If several JVMs are on the `PATH`, `supportedJavaVersions` lets the launcher pick a matching one, and
`forcedJavaPath` pins an exact binary. Leave both empty when the machine or container already has the right JVM.

## Building
Build with JDK 17. The Gradle version in the wrapper does not run on JDK 20 or newer.

```
./gradlew shadowJar          # the runnable fat jar, in build/libs
./gradlew zipDist            # the distributable archive, in build/release
```

Both accept `-Pversion=<version>` to stamp a version onto the output. Tagging a commit as `v<version>` and pushing
it builds and publishes a release through GitHub Actions.

## Credits
Originally created by [BloodWorkXGaming](https://github.com/BloodWorkXGaming), Yoosk and contributors. This fork keeps
the original MIT license, see [LICENSE.md](LICENSE.md).
