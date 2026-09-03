#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR="$ROOT_DIR/work"
OUTPUT_DIR="$ROOT_DIR/output"

LINUWUX_BUILD_SUFFIX="${LINUWUX_BUILD_SUFFIX:--Rework}"

GE_REPO="https://github.com/GloriousEggroll/proton-ge-custom.git"

mkdir -p "$WORKDIR"
mkdir -p "$OUTPUT_DIR"

echo "== Selecting Proton-GE release =="

GE_TAG="${1:-${GE_TAG:-}}"

if [[ -z "$GE_TAG" ]]; then
    echo "Error: No Proton-GE tag specified."
    echo "Usage: $0 <GE-Proton-tag>"
    exit 1
fi

if [[ "$GE_TAG" != GE-Proton* ]]; then
    echo "Error: Invalid Proton-GE tag."
    echo "Tag: $GE_TAG"
    exit 1
fi

echo "Selected release: $GE_TAG"

echo "== Verifying Proton-GE tag =="

if ! git ls-remote --exit-code --tags "$GE_REPO" "refs/tags/$GE_TAG" >/dev/null 2>&1; then
    echo "Error: Proton-GE tag does not exist."
    echo "Tag: $GE_TAG"
    exit 1
fi

echo "Proton-GE tag verified successfully."

SOURCE_DIR="$WORKDIR/proton-ge-custom"
BUILD_NAME="${GE_TAG}-LinUwUx${LINUWUX_BUILD_SUFFIX}"

echo "== Preparing workspace =="

rm -rf "$SOURCE_DIR"
rm -rf "$OUTPUT_DIR"

mkdir -p "$SOURCE_DIR"
mkdir -p "$OUTPUT_DIR"

echo "== Cloning Proton-GE =="

git clone \
    --branch "$GE_TAG" \
    --single-branch \
    --depth 1 \
    "$GE_REPO" \
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

echo "== Verifying required files =="

if [[ ! -f "$SOURCE_DIR/openfst/configure.ac" ]]; then
    echo "Error: openfst/configure.ac is missing."
    echo "Submodule initialization may have failed."
    exit 1
fi

echo "Required files verified."

echo "== Preparing Proton =="

./patches/protonprep-valve-staging.sh

echo "== Verifying Proton after preparation =="

if [[ ! -f "$SOURCE_DIR/openfst/configure.ac" ]]; then
    echo "Error: openfst/configure.ac disappeared during Proton preparation."
    exit 1
fi

echo "== Applying LinUwUx integration =="

LINUWUX_APPLY="$ROOT_DIR/scripts/linuwux/apply.sh"

if [[ ! -f "$LINUWUX_APPLY" ]]; then
    echo "Error: LinUwUx apply script not found."
    echo "Expected path: $LINUWUX_APPLY"
    exit 1
fi

bash "$LINUWUX_APPLY" "$SOURCE_DIR"

echo "LinUwUx integration applied successfully."

echo "== Configuring build =="

rm -rf "$SOURCE_DIR/build"
mkdir -p "$SOURCE_DIR/build"

cd "$SOURCE_DIR/build"

../configure.sh --build-name="$BUILD_NAME"

echo "== Pre-downloading xrandr =="

XRANDR_VERSION="1.5.4"
XRANDR_FILENAME="xrandr-${XRANDR_VERSION}.tar.xz"
XRANDR_DIR="$SOURCE_DIR/contrib"
XRANDR_TARBALL="$XRANDR_DIR/$XRANDR_FILENAME"
XRANDR_URL="https://xorg.freedesktop.org/archive/individual/app/$XRANDR_FILENAME"
XRANDR_SHA256="2cafccb2aaf2491a4068676117a0d4f90ab307724b96fffc54cd1da953779400"

mkdir -p "$XRANDR_DIR"

if [[ ! -f "$XRANDR_TARBALL" ]]; then
    wget \
        --https-only \
        --tries=5 \
        --timeout=30 \
        -O "$XRANDR_TARBALL" \
        "$XRANDR_URL"
fi

echo "$XRANDR_SHA256  $XRANDR_TARBALL" | sha256sum --check -

echo "== Building Proton-GE =="

make V=1 VERBOSE=1 redist 2>&1 | tee "$ROOT_DIR/build-ge.log"

echo "== Locating build archive =="

mapfile -t ARCHIVES < <(
    find "$SOURCE_DIR/build" \
        -maxdepth 1 \
        -type f \
        \( -name "*.tar.gz" -o -name "*.tar.xz" \) \
        -print
)

if [[ "${#ARCHIVES[@]}" -eq 0 ]]; then
    echo "Error: No Proton-GE build archive was found."

    echo "Build directory contents:"
    ls -lah "$SOURCE_DIR/build" || true

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
    TEMP_DIR="$WORKDIR/ge-package"

    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"

    tar -xf "$ARCHIVE" -C "$TEMP_DIR"

    tar -C "$TEMP_DIR" -czf "$FINAL_ARCHIVE" .
fi

echo "== Proton-GE build completed successfully =="

echo "Output archive:"
echo "$FINAL_ARCHIVE"

ls -lh "$OUTPUT_DIR"