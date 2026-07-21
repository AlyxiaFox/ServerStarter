# ServerStarter egg for Pterodactyl / Calagopus

Runs a zip-distributed Forge or Fabric modpack. `serverstarter.jar` is the container's main
process: it installs the modpack and the mod loader on first boot, then launches and supervises
the Minecraft server. Because ServerStarter uses `inheritIO()`, the panel console, the `stop`
command and the startup detection all talk to the real Minecraft process with nothing in between.

Import `egg-serverstarter.json` through **Admin → Nests → Import Egg**.

## What the install does

The installer container only stages files, which keeps installs fast and reproducible:

1. Downloads `serverstarter.jar` pinned to release
   [v2.4.2](https://github.com/AlyxiaFox/ServerStarter/releases/tag/v2.4.2) and verifies its SHA-256.
2. Writes `server-setup-config.yaml` from the egg variables.
3. Seeds `eula.txt` and a minimal `server.properties`.

The modpack and mod loader are **not** downloaded here. The installer image has no JRE, and
ServerStarter's lockfile logic is idempotent, so the pack installs lazily on first boot instead.
Expect the first start to take several minutes with a busy-looking console.

## Variables

| Variable | Default | Notes |
| --- | --- | --- |
| `MODPACK_URL` | — | Direct link to the server pack `.zip`. Changing it reinstalls the pack. |
| `MC_VERSION` | `1.20.1` | Exact Minecraft version. |
| `LOADER_TYPE` | `forge` | `forge` (MC 1.17+), `forge-legacy` (MC 1.16 and older), or `fabric`. |
| `LOADER_VERSION` | `47.4.1` | Forge build, or Fabric loader version. |
| `MAX_RAM` | `4G` | Heap for the Minecraft process. |
| `MIN_RAM` | `1G` | Initial heap. |
| `AUTO_RESTART` | `false` | See below. |
| `EULA` | `false` | Must be `true` before the server will start. |
| `JAVA_ARGS` | — | Extra JVM flags, on top of Aikar's. |

`LOADER_TYPE` exists because the launch command differs fundamentally between loader generations:
Forge 1.17+ boots through a generated `unix_args.txt`, while older Forge and Fabric launch a jar
directly. Picking the wrong one stops the server from starting.

## Design decisions

**`AUTO_RESTART` defaults to `false`** so Wings owns restart-on-crash and the panel records crashes
normally. This only works because the fork propagates the Minecraft exit code; upstream always
exited `0`, so every crash looked like a clean shutdown. Setting it to `true` makes ServerStarter
restart the server in-process, which keeps uptime looking continuous but hides crashes from the panel.

**Memory.** The launcher JVM is capped at 512M by the startup command and the Minecraft process gets
`MAX_RAM` on top of that. Leave roughly 1G of the server's memory limit free, or the container gets
OOM killed. The launcher needs that headroom because it reads each modpack zip entry into memory
while extracting.

**`server.properties` is protected.** It is in `ignoreFiles`, so the pack's copy will not overwrite
the port Wings writes. The trade-off is that any other settings the pack ships in that file are
ignored; set them in the panel instead.

**EULA.** The installer seeds `eula.txt`, and the `EULA` variable is also read at runtime as a
fallback. Upstream would block forever on a stdin prompt here, because in a container stdin never
delivers a line and never reaches EOF.

## Caveats

- **Only `modpackFormat: zip` works.** ServerStarter's CurseForge API paths (`curse`, `curseid`)
  broke when the CurseMeta API changed and are unfixed upstream. Passing a CurseForge project ID
  will not work.
- **Changing variables needs a reinstall.** `server-setup-config.yaml` is generated at install time.
  Reinstalling backs the old file up to `server-setup-config.yaml.bak` and does not touch the world.
- **`ramDisk` is left off and should stay off** unless a tmpfs is already mounted at the world path
  by the node admin. ServerStarter does not create one; it only rsyncs the world to and from
  `<levelName>_backup`, so enabling it without the mount just adds a pointless copy.
- Choose the Docker image to match the loader: Java 17 for Minecraft 1.17–1.20.4, Java 21 for 1.20.5+,
  Java 8 for 1.12 era packs.

## Editing the egg

`egg-serverstarter.json` embeds `install.sh` as a JSON string. Edit `install.sh` and regenerate
rather than hand-editing the JSON.
