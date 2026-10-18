#!/usr/bin/env bash
# Work around a removed Debian source archive pinned by older Proton tags.
set -Eeuo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <proton-source-dir>" >&2
    exit 2
fi

SOURCE_DIR="$(realpath "$1")"
MAKEFILE="$SOURCE_DIR/protonfixes/Makefile"

if [[ ! -f "$MAKEFILE" ]]; then
    echo "No protonfixes Makefile at $MAKEFILE; skipping unzip URL compatibility fix."
    exit 0
fi

OLD_REVISION='UNZIP_DEBIAN_REVISION := 29'
OLD_URL='UNZIP_BASE_URL := https://deb.debian.org/debian/pool/main/u/unzip'
SNAPSHOT_URL='UNZIP_BASE_URL := https://snapshot.debian.org/archive/debian/20250311T215724Z/pool/main/u/unzip'

if grep -Fxq "$OLD_REVISION" "$MAKEFILE"; then
    if grep -Fxq "$OLD_URL" "$MAKEFILE"; then
        echo "== Fixing stale unzip 6.0-29 Debian source URL =="
        sed -i "s|^$OLD_URL$|$SNAPSHOT_URL|" "$MAKEFILE"
    fi

    if ! grep -Fxq "$SNAPSHOT_URL" "$MAKEFILE"; then
        echo "Error: protonfixes pins unzip revision 29, but its source URL changed unexpectedly." >&2
        echo "File: $MAKEFILE" >&2
        exit 1
    fi

    echo "Using immutable Debian snapshot for unzip 6.0-29."
else
    echo "protonfixes does not pin the removed unzip 6.0-29 archive; no change needed."
fi
