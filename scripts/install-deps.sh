#!/usr/bin/env bash

set -Eeuo pipefail

echo "== Updating package lists =="

APT_OPTIONS=(
    "-o"
    "Acquire::Retries=5"
    "-o"
    "Acquire::http::Timeout=30"
    "-o"
    "Acquire::https::Timeout=30"
)

sudo apt-get "${APT_OPTIONS[@]}" update

echo "== Installing build dependencies =="

PACKAGES=(
    build-essential
    gcc
    g++
    clang
    llvm
    lld
    cmake
    ninja-build
    meson

    python3
    python3-pip
    python3-venv

    git
    wget
    curl
    patch

    unzip
    bzip2
    xz-utils
    tar

    flex
    bison
    gettext
    pkg-config

    mingw-w64

    nasm
    yasm

    fontforge
    cabextract

    libfreetype6-dev
    libfontconfig1-dev

    libx11-dev
    libxext-dev
    libxrender-dev
    libxrandr-dev
    libxinerama-dev
    libxcursor-dev
    libxi-dev

    libgl1-mesa-dev
    libvulkan-dev
)

sudo env DEBIAN_FRONTEND=noninteractive \
    apt-get "${APT_OPTIONS[@]}" install -y "${PACKAGES[@]}"

echo "== Installing Rust =="

if ! command -v cargo >/dev/null 2>&1; then
    curl \
        --proto '=https' \
        --tlsv1.2 \
        -sSf \
        https://sh.rustup.rs |
        sh -s -- -y
fi

if [[ -f "$HOME/.cargo/env" ]]; then
    source "$HOME/.cargo/env"
fi

echo "== Verifying Rust installation =="

cargo --version
rustc --version

echo "== Installing Rust build tools =="

if ! command -v cbindgen >/dev/null 2>&1; then
    cargo install cbindgen
fi

echo "== Verifying installed tools =="

echo "Git:"
git --version

echo "Python:"
python3 --version

echo "GCC:"
gcc --version | head -n 1

echo "Clang:"
clang --version | head -n 1

echo "CMake:"
cmake --version | head -n 1

echo "Ninja:"
ninja --version

echo "Cargo:"
cargo --version

echo "Cbindgen:"
cbindgen --version

echo "== Cleaning unnecessary files =="

sudo apt-get clean

echo "== Dependencies installed successfully =="