#!/bin/bash
# ServerStarter egg installer.
#
# Runs once, in the installer container, with the server volume mounted at /mnt/server.
# It only stages files: it downloads the pinned ServerStarter jar, writes
# server-setup-config.yaml from the egg variables, and seeds eula.txt and
# server.properties. The modpack and mod loader are installed lazily on first boot,
# because ServerStarter's checkFolder/lockfile logic is idempotent and the installer
# image has no JRE to run it with.

set -euo pipefail

SERVERSTARTER_URL="https://github.com/AlyxiaFox/ServerStarter/releases/download/v2.4.1/serverstarter.jar"
SERVERSTARTER_SHA256="1c518e108875787a06844ee37e17f908d469cda58864490eaaf9c42a3ca19753"

# Version-agnostic: it takes the loader version to install as a CLI argument.
FABRIC_INSTALLER_VERSION="1.0.3"

MC_VERSION="${MC_VERSION:-}"
LOADER_TYPE="${LOADER_TYPE:-forge}"
LOADER_VERSION="${LOADER_VERSION:-}"
MODPACK_URL="${MODPACK_URL:-}"
MAX_RAM="${MAX_RAM:-4G}"
MIN_RAM="${MIN_RAM:-1G}"
AUTO_RESTART="${AUTO_RESTART:-false}"
JAVA_ARGS="${JAVA_ARGS:-}"
EULA="${EULA:-false}"

# Wings always mounts the server volume here; the override exists so the script can be
# exercised outside a Pterodactyl installer container.
SERVER_DIR="${SERVER_DIR:-/mnt/server}"

fail() { echo "ERROR: $*" >&2; exit 1; }

echo "=============================================="
echo " ServerStarter egg installer"
echo "=============================================="

[ -n "$MC_VERSION" ]     || fail "MC_VERSION is empty."
[ -n "$LOADER_VERSION" ] || fail "LOADER_VERSION is empty."
[ -n "$MODPACK_URL" ]    || fail "MODPACK_URL is empty. This egg only supports 'zip' modpacks; the CurseForge API path in ServerStarter is unmaintained and broken."

command -v curl >/dev/null 2>&1 || fail "curl is not available in the installer image."

# YAML booleans must be bare, so anything that is not exactly true becomes false.
case "${AUTO_RESTART,,}" in
    true|1|yes) AUTO_RESTART="true" ;;
    *)          AUTO_RESTART="false" ;;
esac
case "${EULA,,}" in
    true|1|yes) EULA="true" ;;
    *)          EULA="false" ;;
esac

mkdir -p "$SERVER_DIR"
cd "$SERVER_DIR"

echo "--> Downloading ServerStarter from ${SERVERSTARTER_URL}"
curl -fsSL --retry 3 -o serverstarter.jar "$SERVERSTARTER_URL"
echo "${SERVERSTARTER_SHA256}  serverstarter.jar" | sha256sum -c - \
    || fail "Checksum mismatch on serverstarter.jar. Refusing to continue."

# ---------------------------------------------------------------------------
# Per-loader launch wiring.
#
# startCommand is an argv array. Every token, including an option's value, has to
# be its own entry, otherwise the loader passes "--fml.x value" through as a single
# unrecognised argument (upstream issue #65 -- not a bug, just an easy mistake).
# ---------------------------------------------------------------------------
case "${LOADER_TYPE,,}" in
    forge)
        # Forge 1.17+ launches through the generated args file rather than a jar.
        INSTALLER_URL="https://maven.minecraftforge.net/net/minecraftforge/forge/{{@mcversion@}}-{{@loaderversion@}}/forge-{{@mcversion@}}-{{@loaderversion@}}-installer.jar"
        INSTALLER_ARGS='    - "--installServer"'
        START_FILE='forge-{{@mcversion@}}-{{@loaderversion@}}.jar'
        START_COMMAND='    - "@libraries/net/minecraftforge/forge/{{@mcversion@}}-{{@loaderversion@}}/{{@os@}}_args.txt"
    - "nogui"'
        ;;
    forge-legacy)
        # Forge 1.16 and older: launch the universal jar directly.
        INSTALLER_URL="https://maven.minecraftforge.net/net/minecraftforge/forge/{{@mcversion@}}-{{@loaderversion@}}/forge-{{@mcversion@}}-{{@loaderversion@}}-installer.jar"
        INSTALLER_ARGS='    - "--installServer"'
        START_FILE='forge-{{@mcversion@}}-{{@loaderversion@}}.jar'
        START_COMMAND='    - "-jar"
    - "{{@startFile@}}"
    - "nogui"'
        ;;
    fabric)
        # ServerStarter passes installerArguments through verbatim with no placeholder
        # substitution, so the versions have to be baked in literally here.
        INSTALLER_URL="https://maven.fabricmc.net/net/fabricmc/fabric-installer/${FABRIC_INSTALLER_VERSION}/fabric-installer-${FABRIC_INSTALLER_VERSION}.jar"
        INSTALLER_ARGS="    - \"server\"
    - \"-mcversion\"
    - \"${MC_VERSION}\"
    - \"-loader\"
    - \"${LOADER_VERSION}\"
    - \"-downloadMinecraft\""
        START_FILE='fabric-server-launch.jar'
        START_COMMAND='    - "-jar"
    - "{{@startFile@}}"
    - "nogui"'
        ;;
    *)
        fail "Unknown LOADER_TYPE '${LOADER_TYPE}'. Use forge, forge-legacy or fabric."
        ;;
esac

# Aikar's flags, plus whatever the operator added in JAVA_ARGS.
JAVA_ARGS_YAML=""
append_java_arg() { JAVA_ARGS_YAML="${JAVA_ARGS_YAML}    - \"$1\""$'\n'; }
for arg in \
    -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 \
    -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch \
    -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M \
    -XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 \
    -XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 \
    -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 \
    -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1 \
    -Dfml.readTimeout=90 -Dfml.queryResult=confirm ; do
    append_java_arg "$arg"
done
# Unquoted on purpose: JAVA_ARGS is a freeform, space-separated string.
for arg in ${JAVA_ARGS}; do
    append_java_arg "$arg"
done

echo "--> Writing server-setup-config.yaml"
if [ -f server-setup-config.yaml ]; then
    cp server-setup-config.yaml server-setup-config.yaml.bak
    echo "    (existing config backed up to server-setup-config.yaml.bak)"
fi

cat > server-setup-config.yaml <<YAML
# Generated by the ServerStarter Pterodactyl/Calagopus egg. Reinstalling overwrites this file.
_specver: 2

modpack:
  name: "ServerStarter modpack"
  description: "Installed by the ServerStarter egg"

install:
  curseForgeApiKey: ""
  mcVersion: "${MC_VERSION}"
  loaderVersion: "${LOADER_VERSION}"
  installerUrl: "${INSTALLER_URL}"
  installerArguments:
${INSTALLER_ARGS}
  modpackUrl: "${MODPACK_URL}"
  # Only 'zip' is supported. ServerStarter's CurseForge API path is unmaintained.
  modpackFormat: zip
  formatSpecific: {}
  # Empty means /home/container, so the world and configs land where the panel,
  # the SFTP browser and the port rewriter expect them.
  baseInstallPath: ""
  # Keep the pack archive from clobbering panel-owned files. server.properties is
  # excluded so the port Wings writes survives the first install.
  ignoreFiles:
    - server.properties
    - eula.txt
    - serverstarter.jar
    - server-setup-config.yaml
  additionalFiles: []
  localFiles: []
  checkFolder: true
  installLoader: true
  spongeBootstrapper: ""
  connectTimeout: 60
  readTimeout: 60

launch:
  spongefix: false
  # rsyncs the world to and from \${levelName}_backup. It does NOT create a tmpfs;
  # one has to already be mounted at that path by the node admin.
  ramDisk: false
  checkOffline: false
  checkUrls: []
  maxRam: "${MAX_RAM}"
  minRam: "${MIN_RAM}"
  # false hands crash supervision to Wings, so the panel sees the real exit code.
  autoRestart: ${AUTO_RESTART}
  crashLimit: 5
  crashTimer: 60min
  preJavaArgs: ""
  startFile: "${START_FILE}"
  startCommand:
${START_COMMAND}
  # Left empty so the JRE baked into the selected Docker image is used.
  forcedJavaPath: ""
  supportedJavaVersions: []
  javaArgs:
${JAVA_ARGS_YAML}
YAML

echo "--> Seeding eula.txt (EULA=${EULA})"
{
    echo "#By changing the setting below to TRUE you are indicating your agreement to our EULA (https://aka.ms/MinecraftEULA)."
    echo "#$(date -u)"
    echo "eula=${EULA}"
} > eula.txt

if [ ! -f server.properties ]; then
    echo "--> Seeding server.properties"
    {
        echo "server-ip=0.0.0.0"
        echo "server-port=25565"
        echo "query.port=25565"
        echo "enable-query=true"
    } > server.properties
fi

echo
echo "=============================================="
echo " Install complete."
echo "   loader     : ${LOADER_TYPE} ${LOADER_VERSION} (MC ${MC_VERSION})"
echo "   modpack    : ${MODPACK_URL}"
echo "   memory     : ${MIN_RAM} - ${MAX_RAM}"
echo "   autoRestart: ${AUTO_RESTART}"
if [ "$EULA" != "true" ]; then
    echo
    echo " EULA is not accepted, so Minecraft will refuse to start."
    echo " Set the EULA variable to true and restart."
fi
echo
echo " The modpack and mod loader download on first boot, so the first"
echo " start takes several minutes and the console will look busy."
echo "=============================================="
