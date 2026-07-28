#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

WORKDIR="$ROOT_DIR/work"
OUTPUT="$ROOT_DIR/output"

mkdir -p "$WORKDIR"
mkdir -p "$OUTPUT"

echo "== Rilevamento ultima release Proton-GE =="

GE_TAG="$(
    curl -fsSL \
        https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest |
    python3 -c 'import json, sys; print(json.load(sys.stdin)["tag_name"])'
)"

if [[ -z "$GE_TAG" ]]
then
    echo "Errore: impossibile rilevare l'ultima release Proton-GE."
    exit 1
fi

echo "Ultima release rilevata: $GE_TAG"

echo "== Clonazione Proton-GE $GE_TAG =="

cd "$WORKDIR"

rm -rf proton-ge-custom

git clone \
    --branch "$GE_TAG" \
    --single-branch \
    https://github.com/GloriousEggroll/proton-ge-custom.git \
    proton-ge-custom

cd proton-ge-custom


echo "== Aggiornamento submodule =="

git submodule sync --recursive

for attempt in 1 2 3 4 5
do
    echo "Tentativo submodule $attempt di 5"

    if git submodule update --init --recursive --jobs 1
    then
        break
    fi

    if [ "$attempt" -eq 5 ]
    then
        echo "Errore: impossibile scaricare tutti i submodule dopo 5 tentativi."
        exit 1
    fi

    wait_seconds=$((attempt * 60))

    echo "Download fallito. Attendo $wait_seconds secondi prima di riprovare..."
    sleep "$wait_seconds"
done

echo "== Diagnostica openfst =="

echo "Tag Proton-GE: $GE_TAG"

echo "Commit Proton-GE:"
git rev-parse HEAD

echo "Commit submodule openfst:"
git submodule status openfst || true

echo "Contenuto della cartella openfst:"
ls -la openfst

echo "Ricerca configure.ac:"
find openfst -maxdepth 2 \
    \( -name "configure.ac" -o -name "CMakeLists.txt" \) \
    -print

echo "== Preparazione Proton =="

./patches/protonprep-valve-staging.sh

echo "== Applicazione LinUwUx.patch =="

patch -p1 < "$ROOT_DIR/LinUwUx.patch"

echo "== Disabilito ccache =="

export CCACHE_DISABLE=1


echo "== Configurazione build =="

mkdir -p build

cd build


../configure.sh \
    --build-name="${GE_TAG}-LinUwUx"


echo "== Download preventivo xrandr =="

XRANDR_DIR="$WORKDIR/proton-ge-custom/contrib"
XRANDR_TARBALL="$XRANDR_DIR/xrandr-1.5.4.tar.xz"

mkdir -p "$XRANDR_DIR"
rm -f "$XRANDR_TARBALL"

wget \
    --https-only \
    --no-check-certificate \
    --tries=5 \
    --timeout=30 \
    -O "$XRANDR_TARBALL" \
    "https://xorg.freedesktop.org/archive/individual/app/xrandr-1.5.4.tar.xz"

test -s "$XRANDR_TARBALL"

echo "== Compilazione =="

make redist 2>&1 | tee "$ROOT_DIR/build-ge.log"

echo "== Copia risultato =="

find . -maxdepth 1 -name "*.tar.*" -exec cp {} "$OUTPUT/" \;

echo "== Proton-GE completato =="

ls -lh "$OUTPUT"
