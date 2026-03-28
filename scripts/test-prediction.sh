#!/bin/bash
set -e

# ==============================================================================
# test-prediction.sh
# Interactive CLI tool to test next-word prediction
#
# This script compiles and runs a minimal test program that exercises
# the NextWordPredictor in mock mode (no llama.cpp needed).
#
# Usage:
#   ./scripts/test-prediction.sh
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build_test"
TEST_BINARY="$BUILD_DIR/test_prediction"

echo "========================================"
echo "  Typeflow Next-Word Prediction Test Tool"
echo "========================================"
echo ""

# Create build directory
mkdir -p "$BUILD_DIR"

echo "[1/2] Compiling test program..."

# Compile the standalone test program
# Uses mock mode only (no llama.cpp dependency)
clang++ -std=c++17 -ObjC++ \
    -framework Cocoa \
    -framework JavaScriptCore \
    -I"$PROJECT_DIR/src" \
    -DHALLELUJAH_USE_LLAMA=0 \
    "$PROJECT_DIR/scripts/test_prediction_main.mm" \
    "$PROJECT_DIR/src/NextWordPredictor.mm" \
    -o "$TEST_BINARY"

echo "[2/2] Running tests..."
echo ""

"$TEST_BINARY"

echo ""
echo "Test complete."

# Clean up
# rm -rf "$BUILD_DIR"
