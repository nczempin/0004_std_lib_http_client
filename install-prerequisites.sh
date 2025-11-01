#!/usr/bin/env bash
# Install prerequisites for building HTTP client library on Ubuntu 24.04

set -e

echo "Installing build prerequisites for Ubuntu 24.04..."
sudo apt update && sudo apt install -y \
    cmake \
    python3.12-venv \
    build-essential \
    pkg-config \
    libboost-all-dev \
    libgtest-dev \
    libcurl4-openssl-dev \
    lcov \
    curl

echo ""
echo "Installing/updating Rust toolchain via rustup..."
if ! command -v rustup &> /dev/null; then
    echo "Installing rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source "$HOME/.cargo/env"
else
    echo "Updating existing Rust installation..."
    rustup update stable
fi

rustc --version
cargo --version

echo ""
echo "Prerequisites installed successfully!"
echo "You can now run: bash setup.sh"
