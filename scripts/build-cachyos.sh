#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

WORKDIR="$ROOT_DIR/work"
OUTPUT="$ROOT_DIR/output"

LINUWUX_BUILD_SUFFIX="${LINUWUX_BUILD_SUFFIX:-}"

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

BUILD_NAME="proton-cachyos-${CACHYOS_VERSION}-slr-LinUwUx${LINUWUX_BUILD_SUFFIX}"

echo "Tag sorgente: $CACHYOS_TAG"
echo "Nome build: $BUILD_NAME"

echo "== Verifica esistenza tag =="

if ! git ls-remote \
    --exit-code \
    --tags \
    https://github.com/CachyOS/proton-cachyos.git \
    "refs/tags/$CACHYOS_TAG" \
    >/dev/null
then
    echo "Errore: il tag sorgente non esiste:"
    echo "$CACHYOS_TAG"
    exit 1
fi

echo "Tag Proton-CachyOS verificato correttamente."

echo "== Clonazione Proton-CachyOS =="

cd "$WORKDIR"

rm -rf proton-cachyos

git clone \
    --branch "$CACHYOS_TAG" \
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
        echo "Errore: impossibile scaricare tutti i submodule dopo 5 tentativi."
        exit 1
    fi

    wait_seconds=$((attempt * 60))

    echo "Download fallito. Attendo $wait_seconds secondi prima di riprovare..."
    sleep "$wait_seconds"
done

echo "== Applicazione LinUwUx rework =="

LINUWUX_APPLY="$ROOT_DIR/scripts/linuwux/apply.sh"

if [[ ! -f "$LINUWUX_APPLY" ]]
then
    echo "Errore: script LinUwUx non trovato:"
    echo "$LINUWUX_APPLY"
    exit 1
fi

cd "$WORKDIR/proton-cachyos"

bash "$LINUWUX_APPLY" "$PWD"

echo "LinUwUx rework applicato correttamente."

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
    --enable-ccache

echo "== Compilazione Proton-CachyOS =="

make redist

echo "== Creazione archivio finale =="

UPSTREAM_ARCHIVE="$BUILD_DIR/$BUILD_NAME.tar.xz"
PACKAGE_DIR="$WORKDIR/$BUILD_NAME"
ARCHIVE="$OUTPUT/$BUILD_NAME.tar.gz"

if [[ ! -f "$UPSTREAM_ARCHIVE" ]]
then
    echo "Errore: archivio prodotto da Proton-CachyOS non trovato:"
    echo "$UPSTREAM_ARCHIVE"
    exit 1
fi

rm -rf "$PACKAGE_DIR"
rm -f "$ARCHIVE"

echo "Estrazione archivio Proton-CachyOS..."

tar -C "$WORKDIR" \
    -xJf "$UPSTREAM_ARCHIVE"

if [[ ! -d "$PACKAGE_DIR" ]]
then
    echo "Errore: directory della build estratta non trovata:"
    echo "$PACKAGE_DIR"
    exit 1
fi

echo "Conversione in archivio tar.gz..."

tar -C "$WORKDIR" \
    -czf "$ARCHIVE" \
    "$BUILD_NAME"

echo "Build completata correttamente:"
echo "$ARCHIVE"
