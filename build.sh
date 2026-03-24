#!/usr/bin/env bash
# Build a .rbz extension package for SketchUp.
# Usage: ./build.sh [output_dir]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"
OUTPUT_DIR="${1:-$SCRIPT_DIR/dist}"
VERSION=$(grep -oP "PLUGIN_VERSION = '\K[^']+" "$SRC_DIR/reentrant_sketchup.rb")
OUTPUT_FILE="$OUTPUT_DIR/reentrant_sketchup-${VERSION}.rbz"

mkdir -p "$OUTPUT_DIR"

cd "$SRC_DIR"
zip -r "$OUTPUT_FILE" \
  reentrant_sketchup.rb \
  reentrant_sketchup/

echo "Built: $OUTPUT_FILE"
