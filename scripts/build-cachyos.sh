#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

WORKDIR="$ROOT_DIR/work"
OUTPUT="$ROOT_DIR/output"

mkdir -p "$WORKDIR"
mkdir -p "$OUTPUT"

echo "== Rilevamento ultima release Proton-CachyOS SLR =="

CACHYOS_TAG="$(
    curl -fsSL \
        https://api.github.com/repos/CachyOS/proton-cachyos/releases/latest |
    python3 -c 'import json, sys; print(json.load(sys.stdin)["tag_name"])'
)"

if [[ -z "$CACHYOS_TAG" ]]
then
    echo "Errore: impossibile rilevare l'ultima release Proton-CachyOS."
    exit 1
fi

echo "Ultima release rilevata: $CACHYOS_TAG"

if [[ "$CACHYOS_TAG" != cachyos-*-slr ]]
then
    echo "Errore: il tag rilevato non sembra appartenere a una release SLR."
    exit 1
fi

CACHYOS_VERSION="${CACHYOS_TAG#cachyos-}"
CACHYOS_VERSION="${CACHYOS_VERSION%-slr}"

CACHYOS_BRANCH_VERSION="${CACHYOS_VERSION//-/_}"
CACHYOS_BRANCH="cachyos_${CACHYOS_BRANCH_VERSION}/main"

BUILD_NAME="proton-cachyos-${CACHYOS_VERSION}-slr-LinUwUx"

echo "Branch sorgente: $CACHYOS_BRANCH"
echo "Nome build: $BUILD_NAME"

echo "== Verifica esistenza branch =="

if ! git ls-remote \
    --exit-code \
    --heads \
    https://github.com/CachyOS/proton-cachyos.git \
    "$CACHYOS_BRANCH" \
    >/dev/null
then
    echo "Errore: il branch sorgente non esiste:"
    echo "$CACHYOS_BRANCH"
    exit 1
fi

echo "Branch Proton-CachyOS verificato correttamente."

echo "== Clonazione Proton-CachyOS =="

cd "$WORKDIR"

rm -rf proton-cachyos

git clone \
    --branch "$CACHYOS_BRANCH" \
    --single-branch \
    --tags \
    https://github.com/CachyOS/proton-cachyos.git \
    proton-cachyos

cd proton-cachyos

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

echo "== Applicazione LinUwUx.patch =="

PATCH_FILE="$ROOT_DIR/LinUwUx.patch"

if [[ ! -f "$PATCH_FILE" ]]
then
    echo "Errore: LinUwUx.patch non trovato:"
    echo "$PATCH_FILE"
    exit 1
fi

cd "$WORKDIR/proton-cachyos"

echo "Verifica preliminare della patch..."

if ! patch --dry-run -p1 < "$PATCH_FILE"
then
    echo "Errore: LinUwUx.patch non è compatibile con questa versione di Proton-CachyOS."
    exit 1
fi

patch -p1 < "$PATCH_FILE"

echo "LinUwUx.patch applicata correttamente."

echo "== Preparazione directory di build =="

BUILD_DIR="$WORKDIR/proton-cachyos-build"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

cd "$BUILD_DIR"

echo "Directory sorgente: $WORKDIR/proton-cachyos"
echo "Directory build: $BUILD_DIR"

echo "== Configurazione Proton-CachyOS =="

"$WORKDIR/proton-cachyos/configure.sh" \
    --build-name="$BUILD_NAME" \
    --enable-cache

echo "== Compilazione Proton-CachyOS =="

make redist

echo "== Creazione archivio finale =="

REDIST_DIR="$BUILD_DIR/redist"
PACKAGE_DIR="$WORKDIR/$BUILD_NAME"
ARCHIVE="$OUTPUT/$BUILD_NAME.tar.gz"

if [[ ! -d "$REDIST_DIR" ]]
then
    echo "Errore: directory redist non trovata:"
    echo "$REDIST_DIR"
    exit 1
fi

rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR"

cp -a "$REDIST_DIR"/. "$PACKAGE_DIR"/

rm -f "$ARCHIVE"

tar -C "$WORKDIR" \
    -czf "$ARCHIVE" \
    "$BUILD_NAME"

echo "Build completata correttamente:"
echo "$ARCHIVE"
