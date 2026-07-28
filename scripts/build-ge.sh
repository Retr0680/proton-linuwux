#!/usr/bin/env bash

set -e

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

git submodule update --init --recursive


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


echo "== Compilazione =="

export WGETRC="$ROOT_DIR/wgetrc"

make redist


echo "== Copia risultato =="

find . -maxdepth 1 -name "*.tar.*" -exec cp {} "$OUTPUT/" \;


echo "== Proton-GE completato =="

ls -lh "$OUTPUT"
