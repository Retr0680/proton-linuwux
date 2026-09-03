#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

WORKDIR="$ROOT_DIR/work"
OUTPUT="$ROOT_DIR/output"

LINUWUX_BUILD_SUFFIX="${LINUWUX_BUILD_SUFFIX:-}"

mkdir -p "$WORKDIR"
mkdir -p "$OUTPUT"

echo "== Selecting Proton-GE release =="

GE_TAG="${1:-${GE_TAG:-}}"

if [[ -z "$GE_TAG" ]]
then
echo "Error: no Proton-GE tag specified."
echo "Usage:"
echo "$0 <GE-Proton-tag>"
exit 1
fi

if [[ "$GE_TAG" != GE-Proton* ]]
then
echo "Error: the tag does not appear to be a Proton-GE release:"
echo "$GE_TAG"
exit 1
fi

echo "Selected release: $GE_TAG"

echo "== Verifying tag exists =="

if ! git ls-remote 
--exit-code 
--tags 
https://github.com/GloriousEggroll/proton-ge-custom.git 
"refs/tags/$GE_TAG" 
>/dev/null
then
echo "Error: Proton-GE tag does not exist:"
echo "$GE_TAG"
exit 1
fi

echo "Proton-GE tag verified successfully."

echo "== Cloning Proton-GE $GE_TAG =="

cd "$WORKDIR"

rm -rf proton-ge-custom

git clone 
--branch "$GE_TAG" 
--single-branch 
https://github.com/GloriousEggroll/proton-ge-custom.git 
proton-ge-custom

cd proton-ge-custom

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

echo "== Verifying critical submodules =="

git submodule status openfst
git -C openfst rev-parse HEAD

if [[ ! -f openfst/configure.ac ]]
then
echo "Error: openfst/configure.ac is missing after submodule initialization." >&2
ls -la openfst >&2 || true
git -C openfst ls-files | head -100 >&2 || true
exit 1
fi

sha256sum openfst/configure.ac

echo "== Preparing Proton =="

./patches/protonprep-valve-staging.sh

echo "== Verifying openfst after protonprep =="

if [[ ! -f openfst/configure.ac ]]
then
echo "Error: openfst/configure.ac disappeared during protonprep." >&2
git submodule status openfst >&2 || true
git -C openfst status --short >&2 || true
ls -la openfst >&2 || true
exit 1
fi

sha256sum openfst/configure.ac

echo "== Applying LinUwUx rework =="

LINUWUX_APPLY="$ROOT_DIR/scripts/linuwux/apply.sh"

if [[ ! -f "$LINUWUX_APPLY" ]]
then
echo "Error: LinUwUx script not found:"
echo "$LINUWUX_APPLY"
exit 1
fi

bash "$LINUWUX_APPLY" "$PWD"

echo "LinUwUx rework applied successfully."

echo "== Configuring build =="

mkdir -p build

cd build

../configure.sh 
--build-name="${GE_TAG}-LinUwUx${LINUWUX_BUILD_SUFFIX}"

echo "== Pre-downloading xrandr =="

XRANDR_VERSION="1.5.4"
XRANDR_FILENAME="xrandr-${XRANDR_VERSION}.tar.xz"
XRANDR_DIR="$WORKDIR/proton-ge-custom/contrib"
XRANDR_TARBALL="$XRANDR_DIR/$XRANDR_FILENAME"
XRANDR_URL="https://xorg.freedesktop.org/archive/individual/app/$XRANDR_FILENAME"
XRANDR_SHA256="2cafccb2aaf2491a4068676117a0d4f90ab307724b96fffc54cd1da953779400"

mkdir -p "$XRANDR_DIR"
rm -f "$XRANDR_TARBALL"

wget 
--https-only 
--tries=5 
--timeout=30 
-O "$XRANDR_TARBALL" 
"$XRANDR_URL"

echo "$XRANDR_SHA256  $XRANDR_TARBALL" | sha256sum --check -

echo "== Building =="

make V=1 VERBOSE=1 redist 2>&1 | tee "$ROOT_DIR/build-ge.log"

echo "== Copying build output =="

find . -maxdepth 1 -name "*.tar.*" -exec cp {} "$OUTPUT/" ;

echo "== Proton-GE build completed =="

ls -lh "$OUTPUT"