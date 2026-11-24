#!/bin/zsh
# Builds bin/notch-yet as a universal binary (Apple Silicon + Intel), macOS 12 or later.
#   ./build.sh            build into bin/
#   ./build.sh --install  also copy it to ~/.local/bin and add the Claude Code hooks
set -e
cd "$(dirname "$0")"
mkdir -p build bin
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target $arch-apple-macos12 -o build/notch-yet-$arch Sources/main.swift
done
lipo -create -output bin/notch-yet build/notch-yet-arm64 build/notch-yet-x86_64
codesign --force --sign - bin/notch-yet
echo "Built bin/notch-yet ($(lipo -archs bin/notch-yet))"

if [[ "$1" == "--install" ]]; then
  mkdir -p ~/.local/bin
  cp bin/notch-yet ~/.local/bin/notch-yet
  ~/.local/bin/notch-yet install-hooks
fi
