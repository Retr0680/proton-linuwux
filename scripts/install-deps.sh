#!/usr/bin/env bash

set -e

echo "== Aggiornamento pacchetti =="

sudo apt update


echo "== Installazione dipendenze Proton =="

sudo apt install -y \
    build-essential \
    gcc \
    g++ \
    clang \
    llvm \
    lld \
    cmake \
    ninja-build \
    meson \
    python3 \
    python3-pip \
    python3-venv \
    git \
    wget \
    curl \
    patch \
    unzip \
    bzip2 \
    xz-utils \
    tar \
    flex \
    bison \
    gettext \
    pkg-config \
    mingw-w64 \
    nasm \
    yasm \
    fontforge \
    cabextract \
    libfreetype6-dev \
    libfontconfig1-dev \
    libx11-dev \
    libxext-dev \
    libxrender-dev \
    libxrandr-dev \
    libxinerama-dev \
    libxcursor-dev \
    libxi-dev \
    libgl1-mesa-dev \
    libvulkan-dev


echo "== Installazione Rust =="

if ! command -v cargo >/dev/null 2>&1
then
    curl https://sh.rustup.rs -sSf | sh -s -- -y
fi


source "$HOME/.cargo/env"


echo "== Installazione tool Rust =="

cargo install cbindgen || true


echo "== Pulizia spazio disco =="

sudo rm -rf /usr/local/lib/android
sudo rm -rf /usr/share/dotnet
sudo rm -rf /opt/ghc


echo "== Ambiente pronto =="
