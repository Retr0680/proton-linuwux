#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

WORKDIR="$ROOT_DIR/work"
OUTPUT="$ROOT_DIR/output"

mkdir -p "$WORKDIR"
mkdir -p "$OUTPUT"

echo "== Clonazione Proton-GE =="

cd "$WORKDIR"

rm -rf proton-ge-custom


git clone \
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
    --build-name="GE-LinUwUx"


echo "== Download preventivo xrandr =="

XRANDR_TARBALL="$WORKDIR/proton-ge-custom/contrib/xrandr-1.5.4.tar.xz"

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
