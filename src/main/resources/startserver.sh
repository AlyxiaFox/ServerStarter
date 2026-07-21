#!/bin/bash

# `-d64` option was removed in Java 10, this handles these versions accordingly
JAVA_FLAGS=""
if (( $(java -version 2>&1 | head -1 | cut -d'"' -f2 | sed '/^1\./s///' | cut -d'.' -f1) < 10 )); then
    JAVA_FLAGS="-d64"
fi

# ---------------------------------------------------------------------------
# RAMDisk
#
# ServerStarter never creates a tmpfs itself. With ramDisk enabled it only rsyncs the world to and
# from ${levelName}_backup around launch and shutdown, so mounting it is this script's job. If the
# mount does not happen the server runs against a half-set-up world folder.
# ---------------------------------------------------------------------------
DO_RAMDISK=0
SAVE_DIR=""

teardown_ramdisk() {
    [ "$DO_RAMDISK" -eq 1 ] || return 0

    # Never remove the folder while the tmpfs is still mounted. rm would wipe the live world and
    # the mv below would then nest the backup inside the mountpoint.
    if ! sudo umount "$SAVE_DIR"; then
        echo "Could not unmount the RAMDisk at '${SAVE_DIR}'. Leaving it in place; the saved world is in '${SAVE_DIR}_backup'." >&2
        return 1
    fi

    DO_RAMDISK=0
    rm -rf "$SAVE_DIR"
    mv "${SAVE_DIR}_backup" "$SAVE_DIR"
}
# Runs after the server process returns, including when it is interrupted.
trap teardown_ramdisk EXIT

# Read the value without matching commented-out lines or trailing inline comments.
RAMDISK_SETTING=$(sed -n 's/^[[:space:]]*ramDisk:[[:space:]]*\([^#[:space:]]*\).*/\1/p' server-setup-config.yaml 2>/dev/null | head -1)

# YAML reads true, yes and on as boolean true, so accept every spelling the launcher would.
case "$RAMDISK_SETTING" in
    [Tt]rue|TRUE|[Yy]es|YES|[Oo]n|ON)
        SAVE_DIR=$(sed -n 's/^[[:space:]]*level-name[[:space:]]*=[[:space:]]*\(.*\)/\1/p' server.properties 2>/dev/null | head -1)
        SAVE_DIR="${SAVE_DIR%$'\r'}"

        if [ -z "$SAVE_DIR" ]; then
            echo "ramDisk is enabled but level-name could not be read from server.properties." >&2
            exit 1
        fi
        if [ ! -d "$SAVE_DIR" ]; then
            echo "ramDisk is enabled but the world folder '${SAVE_DIR}' does not exist yet." >&2
            echo "Let the server run once fully before turning ramDisk on." >&2
            exit 1
        fi
        if [ -e "${SAVE_DIR}_backup" ]; then
            echo "ramDisk is enabled but '${SAVE_DIR}_backup' already exists, so a previous run did not shut down cleanly." >&2
            echo "Restore that folder by hand before starting again, otherwise it would be overwritten." >&2
            exit 1
        fi

        mv "$SAVE_DIR" "${SAVE_DIR}_backup" || exit 1
        mkdir "$SAVE_DIR" || exit 1

        if sudo mount -t tmpfs -o size=2G tmpfs "$SAVE_DIR"; then
            DO_RAMDISK=1
        else
            # Without this the world would be left in _backup and the server would generate a new
            # one on disk, which the teardown would then delete.
            echo "Could not mount the tmpfs. Restoring the world and continuing without a RAMDisk." >&2
            rmdir "$SAVE_DIR"
            mv "${SAVE_DIR}_backup" "$SAVE_DIR"
        fi
        ;;
esac

if [ -f serverstarter-@@serverstarter-libVersion@@.jar ]; then
    echo "Skipping download. Using existing serverstarter-@@serverstarter-libVersion@@.jar"
else
    export URL="https://github.com/AlyxiaFox/ServerStarter/releases/download/v@@serverstarter-libVersion@@/serverstarter-@@serverstarter-libVersion@@.jar"
    echo $URL
    which wget >> /dev/null
    if [ $? -eq 0 ]; then
        echo "DEBUG: (wget) Downloading ${URL}"
        wget -O serverstarter-@@serverstarter-libVersion@@.jar "${URL}"
    else
        which curl >> /dev/null
        if [ $? -eq 0 ]; then
            echo "DEBUG: (curl) Downloading ${URL}"
            curl -o serverstarter-@@serverstarter-libVersion@@.jar -L "${URL}"
        else
            echo "Neither wget or curl were found on your system. Please install one and try again"
        fi
    fi
fi

# Left as the last command so the launcher's exit code becomes this script's exit code.
java $JAVA_FLAGS -jar serverstarter-@@serverstarter-libVersion@@.jar
