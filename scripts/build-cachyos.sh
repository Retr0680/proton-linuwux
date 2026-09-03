#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR="$ROOT_DIR/work"
OUTPUT_DIR="$ROOT_DIR/output"

LINUWUX_BUILD_SUFFIX="${LINUWUX_BUILD_SUFFIX:--Rework}"

CACHYOS_REPO="https://github.com/CachyOS/proton-cachyos.git"

mkdir -p "$WORKDIR"
mkdir -p "$OUTPUT_DIR"

echo "== Selecting Proton-CachyOS release =="

CACHYOS_TAG="${1:-${CACHYOS_TAG:-}}"

if [[ -z "$CACHYOS_TAG" ]]; then
    echo "Error: No Proton-CachyOS tag specified."
    echo "Usage: $0 <cachyos-tag>"
    exit 1
fi

if [[ "$CACHYOS_TAG" != cachyos-*-slr ]]; then
    echo "Error: Invalid Proton-CachyOS SLR tag."
    echo "Tag: $CACHYOS_TAG"
    exit 1
fi

echo "Selected release: $CACHYOS_TAG"

echo "== Verifying Proton-CachyOS tag =="

if ! git ls-remote --exit-code --tags "$CACHYOS_REPO" "refs/tags/$CACHYOS_TAG" >/dev/null 2>&1; then
    echo "Error: Proton-CachyOS tag does not exist."
    echo "Tag: $CACHYOS_TAG"
    exit 1
fi

echo "Proton-CachyOS tag verified successfully."

SOURCE_DIR="$WORKDIR/proton-cachyos"
BUILD_DIR="$WORKDIR/proton-cachyos-build"

BUILD_NAME="${CACHYOS_TAG}-LinUwUx${LINUWUX_BUILD_SUFFIX}"

echo "Source tag: $CACHYOS_TAG"
echo "Build name: $BUILD_NAME"

echo "== Preparing workspace =="

rm -rf "$SOURCE_DIR"
rm -rf "$BUILD_DIR"
rm -rf "$OUTPUT_DIR"

mkdir -p "$BUILD_DIR"
mkdir -p "$OUTPUT_DIR"

echo "== Cloning Proton-CachyOS =="

git clone \
    --branch "$CACHYOS_TAG" \
    --single-branch \
    --depth 1 \
    "$CACHYOS_REPO" \
    "$SOURCE_DIR"

cd "$SOURCE_DIR"

echo "== Updating submodules =="

git submodule sync --recursive

for attempt in 1 2 3 4 5; do
    echo "Submodule initialization attempt $attempt of 5"

    if git submodule update --init --recursive --checkout --force --jobs 1; then
        echo "Submodules initialized successfully."
        break
    fi

    if [[ "$attempt" -eq 5 ]]; then
        echo "Error: Failed to initialize submodules after 5 attempts."
        exit 1
    fi

    wait_seconds=$((attempt * 30))

    echo "Submodule initialization failed."
    echo "Retrying in $wait_seconds seconds..."

    sleep "$wait_seconds"
done

echo "== Applying LinUwUx integration =="

LINUWUX_APPLY="$ROOT_DIR/scripts/linuwux/apply.sh"

if [[ ! -f "$LINUWUX_APPLY" ]]; then
    echo "Error: LinUwUx apply script not found."
    echo "Expected path: $LINUWUX_APPLY"
    exit 1
fi

bash "$LINUWUX_APPLY" "$SOURCE_DIR"

echo "LinUwUx integration applied successfully."

echo "== Configuring Proton-CachyOS =="

cd "$BUILD_DIR"

"$SOURCE_DIR/configure.sh" \
    --build-name="$BUILD_NAME" \
    --enable-ccache

echo "== Building Proton-CachyOS =="

make V=1 VERBOSE=1 redist 2>&1 | tee "$ROOT_DIR/build-cachyos.log"

echo "== Locating build archive =="

mapfile -t ARCHIVES < <(
    find "$BUILD_DIR" \
        -maxdepth 1 \
        -type f \
        \( -name "*.tar.gz" -o -name "*.tar.xz" \) \
        -print
)

if [[ "${#ARCHIVES[@]}" -eq 0 ]]; then
    echo "Error: No Proton-CachyOS build archive was found."

    echo "Build directory contents:"
    ls -lah "$BUILD_DIR" || true

    exit 1
fi

echo "Found build archives:"

printf '%s\n' "${ARCHIVES[@]}"

ARCHIVE="${ARCHIVES[0]}"

FINAL_ARCHIVE="$OUTPUT_DIR/${BUILD_NAME}.tar.gz"

echo "== Preparing final archive =="

if [[ "$ARCHIVE" == *.tar.gz ]]; then
    cp "$ARCHIVE" "$FINAL_ARCHIVE"
else
    TEMP_DIR="$WORKDIR/cachy-package"

    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"

    tar -xf "$ARCHIVE" -C "$TEMP_DIR"

    tar -C "$TEMP_DIR" -czf "$FINAL_ARCHIVE" .
fi

echo "== Proton-CachyOS build completed successfully =="

echo "Output archive:"
echo "$FINAL_ARCHIVE"

ls -lh "$OUTPUT_DIR"