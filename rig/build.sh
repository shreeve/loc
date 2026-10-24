#!/bin/sh
# Builds the Rig loc as bin/loco, optimized with its safety checks kept.
set -e
cd "$(dirname "$0")/.."
mkdir -p bin
rig build --release -o bin/loco rig/main.rig
