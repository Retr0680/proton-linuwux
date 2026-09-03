#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

WORKDIR="$ROOT_DIR/work"
OUTPUT="$ROOT_DIR/output"

LINUWUX_BUILD_SUFFIX="${LINUWUX_BUILD_SUFFIX:-}"

mkdir -p "$WORKDIR"
mkdir -p "$OUTPUT"

echo "== Selecting Proton-CachyOS release =="

CACHYOS_TAG="${1:-${CACHYOS_TAG:-}}"

if [[ -z "$CACHYOS_TAG" ]]
then
echo "Error: no Proton-CachyOS tag specified."
echo "Usage:"
echo "$0 <cachyos-tag>"
exit 1
fi

if [[ "$CACHYOS_TAG" != cachyos-*-slr ]]
then
echo "Error: the tag does not appear to be a Proton-CachyOS SLR release:"
echo "$CACHYOS_TAG"
exit 1
fi

echo "Selected release: $CACHYOS_TAG"

CACHYOS_VERSION="${CACHYOS_TAG#cachyos-}"
CACHYOS_VERSION="${CACHYOS_VERSION%-slr}"

BUILD_NAME="proton-cachyos-${CACHYOS_VERSION}-slr-LinUwUx${LINUWUX_BUILD_SUFFIX}"

echo "Source tag: $CACHYOS_TAG"
echo "Build name: $BUILD_NAME"

echo "== Verifying tag exists =="

if ! git ls-remote 
--exit-code 
--tags 
https://github.com/CachyOS/proton-cachyos.git 
"refs/tags/$CACHYOS_TAG" 
>/dev/null
then
echo "Error: source tag does not exist:"
echo "$CACHYOS_TAG"
exit 1
fi

echo "Proton-CachyOS tag verified successfully."

echo "== Cloning Proton-CachyOS =="

cd "$WORKDIR"

rm -rf proton-cachyos

git clone 
--branch "$CACHYOS_TAG" 
--single-branch 
--tags 
https://github.com/CachyOS/proton-cachyos.git 
proton-cachyos

cd proton-cachyos

echo "== Updating submodules =="

git submodule sync --recursive

for attempt in 1 2 3 4 5
do
echo "Submodule attempt $attempt of 5"

```
if git submodule update \
    --init \
    --recursive \
    --checkout \
    --force \
    --jobs 1
then
    break
fi

if [ "$attempt" -eq 5 ]
then
    echo "Error: unable to download all submodules after 5 attempts."
    exit 1
fi

wait_seconds=$((attempt * 60))

echo "Download failed. Waiting $wait_seconds seconds before retrying..."
sleep "$wait_seconds"
```

done

echo "== Applying LinUwUx rework =="

LINUWUX_APPLY="$ROOT_DIR/scripts/linuwux/apply.sh"

if [[ ! -f "$LINUWUX_APPLY" ]]
then
echo "Error: LinUwUx script not found:"
echo "$LINUWUX_APPLY"
exit 1
fi

cd "$WORKDIR/proton-cachyos"

bash "$LINUWUX_APPLY" "$PWD"

echo "LinUwUx rework applied successfully."

echo "== Preparing build directory =="

BUILD_DIR="$WORKDIR/proton-cachyos-build"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

cd "$BUILD_DIR"

echo "Source directory: $WORKDIR/proton-cachyos"
echo "Build directory: $BUILD_DIR"

echo "== Configuring Proton-CachyOS =="

"$WORKDIR/proton-cachyos/configure.sh" 
--build-name="$BUILD_NAME" 
--enable-ccache

echo "== Building Proton-CachyOS =="

make V=1 VERBOSE=1 redist 2>&1 | tee "$ROOT_DIR/build-cachyos.log"

echo "== Creating final archive =="

UPSTREAM_ARCHIVE="$BUILD_DIR/$BUILD_NAME.tar.xz"
PACKAGE_DIR="$WORKDIR/$BUILD_NAME"
ARCHIVE="$OUTPUT/$BUILD_NAME.tar.gz"

if [[ ! -f "$UPSTREAM_ARCHIVE" ]]
then
echo "Error: Proton-CachyOS build archive not found:"
echo "$UPSTREAM_ARCHIVE"
exit 1
fi

rm -rf "$PACKAGE_DIR"
rm -f "$ARCHIVE"

echo "Extracting Proton-CachyOS archive..."

tar -C "$WORKDIR" 
-xJf "$UPSTREAM_ARCHIVE"

if [[ ! -d "$PACKAGE_DIR" ]]
then
echo "Error: extracted build directory not found:"
echo "$PACKAGE_DIR"
exit 1
fi

echo "Converting to tar.gz archive..."

tar -C "$WORKDIR" 
-czf "$ARCHIVE" 
"$BUILD_NAME"

echo "Build completed successfully:"
echo "$ARCHIVE"