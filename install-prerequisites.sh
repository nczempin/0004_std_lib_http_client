#!/usr/bin/env bash
# Install prerequisites for building HTTP client library on Ubuntu 24.04

set -e

echo "Installing build prerequisites for Ubuntu 24.04..."
sudo apt update && sudo apt install -y \
    cmake \
    python3.12-venv \
    cargo \
    build-essential \
    pkg-config \
    libboost-all-dev \
    libgtest-dev \
    libcurl4-openssl-dev \
    lcov

echo "Prerequisites installed successfully!"
echo "You can now run: bash setup.sh"
