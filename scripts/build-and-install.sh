#!/bin/bash
set -e

# ==============================================================================
# build-and-install.sh
# Build Typeflow from source using clang (no Xcode required) and install.
#
# Usage:
#   ./scripts/build-and-install.sh          # Build and install
#   ./scripts/build-and-install.sh --build  # Build only (no install)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build_release"
APP_NAME="Typeflow"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
INSTALL_DIR="/Library/Input Methods"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
step()  { echo -e "${CYAN}[STEP]${NC} $1"; }

BUILD_ONLY=false
if [ "$1" = "--build" ]; then
    BUILD_ONLY=true
fi

echo "========================================"
echo "  Typeflow Build System"
echo "========================================"
echo ""

# Check prerequisites
step "Checking prerequisites..."
command -v clang++ >/dev/null 2>&1 || error "clang++ not found. Install Xcode Command Line Tools: xcode-select --install"
command -v ibtool >/dev/null 2>&1 || error "ibtool not found. Install Xcode Command Line Tools: xcode-select --install"
command -v actool >/dev/null 2>&1 || warn "actool not found - will skip asset catalog compilation"

# Determine architecture
ARCH=$(uname -m)
info "Building for architecture: $ARCH"

# ---------------------------------------------------------------------------
# Source files
# ---------------------------------------------------------------------------

# App source files (.mm = Objective-C++)
APP_MM_SOURCES=(
    "$PROJECT_DIR/src/main.mm"
    "$PROJECT_DIR/src/InputController.mm"
    "$PROJECT_DIR/src/ConversionEngine.mm"
    "$PROJECT_DIR/src/NextWordPredictor.mm"
    "$PROJECT_DIR/src/PreferencesWindowController.mm"
)

# App source files (.m = Objective-C)
APP_M_SOURCES=(
    "$PROJECT_DIR/src/InputApplicationDelegate.m"
    "$PROJECT_DIR/src/AnnotationWinController.m"
    "$PROJECT_DIR/src/WebServer.m"
    "$PROJECT_DIR/src/NSScreen+PointConversion.m"
)

# GCDWebServer sources
GCDWEBSERVER_SOURCES=(
    "$PROJECT_DIR/Pods/GCDWebServer/GCDWebServer/Core/GCDWebServer.m"
    "$PROJECT_DIR/Pods/GCDWebServer/GCDWebServer/Core/GCDWebServerConnection.m"
    "$PROJECT_DIR/Pods/GCDWebServer/GCDWebServer/Core/GCDWebServerFunctions.m"
    "$PROJECT_DIR/Pods/GCDWebServer/GCDWebServer/Core/GCDWebServerRequest.m"
    "$PROJECT_DIR/Pods/GCDWebServer/GCDWebServer/Core/GCDWebServerResponse.m"
    "$PROJECT_DIR/Pods/GCDWebServer/GCDWebServer/Responses/GCDWebServerDataResponse.m"
    "$PROJECT_DIR/Pods/GCDWebServer/GCDWebServer/Responses/GCDWebServerErrorResponse.m"
    "$PROJECT_DIR/Pods/GCDWebServer/GCDWebServer/Responses/GCDWebServerFileResponse.m"
    "$PROJECT_DIR/Pods/GCDWebServer/GCDWebServer/Responses/GCDWebServerStreamedResponse.m"
    "$PROJECT_DIR/Pods/GCDWebServer/GCDWebServer/Requests/GCDWebServerDataRequest.m"
    "$PROJECT_DIR/Pods/GCDWebServer/GCDWebServer/Requests/GCDWebServerFileRequest.m"
    "$PROJECT_DIR/Pods/GCDWebServer/GCDWebServer/Requests/GCDWebServerMultiPartFormRequest.m"
    "$PROJECT_DIR/Pods/GCDWebServer/GCDWebServer/Requests/GCDWebServerURLEncodedFormRequest.m"
)

# MDCDamerauLevenshtein sources
MDC_SOURCES=(
    "$PROJECT_DIR/Pods/MDCDamerauLevenshtein/MDCDamerauLevenshtein/Algorithms/MDCDamerauLevenshteinDistance.m"
    "$PROJECT_DIR/Pods/MDCDamerauLevenshtein/MDCDamerauLevenshtein/Algorithms/MDCLevenshteinDistance.m"
    "$PROJECT_DIR/Pods/MDCDamerauLevenshtein/MDCDamerauLevenshtein/Algorithms/Data Structures/MDCDistanceMatrix.m"
    "$PROJECT_DIR/Pods/MDCDamerauLevenshtein/MDCDamerauLevenshtein/Algorithms/Data Structures/NSString+MDCCompare.m"
    "$PROJECT_DIR/Pods/MDCDamerauLevenshtein/MDCDamerauLevenshtein/Categories/NSString+MDCDamerauLevenshteinDistance.m"
    "$PROJECT_DIR/Pods/MDCDamerauLevenshtein/MDCDamerauLevenshtein/Categories/NSString+MDCLevenshteinDistance.m"
)

# ---------------------------------------------------------------------------
# Include paths
# ---------------------------------------------------------------------------
INCLUDE_FLAGS=(
    -I"$PROJECT_DIR/src"
    -I"$PROJECT_DIR/include"
    -I"$PROJECT_DIR/third_party/llama.cpp/include"
    -I"$PROJECT_DIR/third_party/llama.cpp/ggml/include"
    -I"$PROJECT_DIR/Pods/GCDWebServer/GCDWebServer/Core"
    -I"$PROJECT_DIR/Pods/GCDWebServer/GCDWebServer/Requests"
    -I"$PROJECT_DIR/Pods/GCDWebServer/GCDWebServer/Responses"
    -I"$PROJECT_DIR/Pods/MDCDamerauLevenshtein"
    -I"$PROJECT_DIR/Pods/MDCDamerauLevenshtein/MDCDamerauLevenshtein"
    -I"$PROJECT_DIR/Pods/MDCDamerauLevenshtein/MDCDamerauLevenshtein/Algorithms"
    -I"$PROJECT_DIR/Pods/MDCDamerauLevenshtein/MDCDamerauLevenshtein/Algorithms/Data Structures"
    -I"$PROJECT_DIR/Pods/MDCDamerauLevenshtein/MDCDamerauLevenshtein/Categories"
)

# LLM mode: enable real llama.cpp inference if libraries exist
USE_LLAMA=0
if [ -f "$PROJECT_DIR/lib/libllama.a" ] && [ -f "$PROJECT_DIR/lib/libggml.a" ]; then
    USE_LLAMA=1
    info "llama.cpp libraries found - enabling real LLM prediction"
else
    warn "llama.cpp libraries not found - using mock prediction mode"
    warn "Run ./scripts/setup-llama.sh to enable real LLM prediction"
fi

# Common compiler flags
COMMON_FLAGS=(
    -fobjc-arc
    -fmodules
    -mmacosx-version-min=13.0
    -DHALLELUJAH_USE_LLAMA=$USE_LLAMA
    -Wno-nullability-completeness
    -Wno-objc-missing-super-calls
)

# Frameworks to link
FRAMEWORKS=(
    -framework Cocoa
    -framework InputMethodKit
    -framework Carbon
    -framework JavaScriptCore
    -framework AppKit
    -framework CoreServices
    -framework Metal
    -framework MetalKit
    -framework Accelerate
    -framework Foundation
)

# ---------------------------------------------------------------------------
# Step 1: Clean and prepare
# ---------------------------------------------------------------------------
step "Preparing build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/obj"

# ---------------------------------------------------------------------------
# Step 2: Compile all source files to .o
# ---------------------------------------------------------------------------
step "Compiling source files..."

OBJ_FILES=()

compile_m() {
    local src="$1"
    local name=$(basename "$src" | sed 's/[.+]/_/g')
    local obj="$BUILD_DIR/obj/${name}.o"
    clang -c -ObjC "${COMMON_FLAGS[@]}" "${INCLUDE_FLAGS[@]}" "$src" -o "$obj" 2>&1
    OBJ_FILES+=("$obj")
    echo "  CC  $(basename "$src")"
}

compile_mm() {
    local src="$1"
    local name=$(basename "$src" | sed 's/[.+]/_/g')
    local obj="$BUILD_DIR/obj/${name}.o"
    clang++ -c -ObjC++ -std=c++17 "${COMMON_FLAGS[@]}" "${INCLUDE_FLAGS[@]}" "$src" -o "$obj" 2>&1
    OBJ_FILES+=("$obj")
    echo "  CXX $(basename "$src")"
}

# Compile app .mm sources
for src in "${APP_MM_SOURCES[@]}"; do
    compile_mm "$src"
done

# Compile app .m sources
for src in "${APP_M_SOURCES[@]}"; do
    compile_m "$src"
done

# Compile GCDWebServer
for src in "${GCDWEBSERVER_SOURCES[@]}"; do
    compile_m "$src"
done

# Compile MDCDamerauLevenshtein
for src in "${MDC_SOURCES[@]}"; do
    compile_m "$src"
done

info "Compiled ${#OBJ_FILES[@]} object files"

# ---------------------------------------------------------------------------
# Step 3: Link
# ---------------------------------------------------------------------------
step "Linking $APP_NAME..."

LINK_LIBS=("$PROJECT_DIR/lib/libmarisa.a")

if [ "$USE_LLAMA" = "1" ]; then
    LINK_LIBS+=(
        "$PROJECT_DIR/lib/libllama.a"
        "$PROJECT_DIR/lib/libggml.a"
        "$PROJECT_DIR/lib/libggml-base.a"
        "$PROJECT_DIR/lib/libggml-metal.a"
        "$PROJECT_DIR/lib/libggml-cpu.a"
        "$PROJECT_DIR/lib/libggml-blas.a"
    )
fi

clang++ \
    "${OBJ_FILES[@]}" \
    "${LINK_LIBS[@]}" \
    "${FRAMEWORKS[@]}" \
    -mmacosx-version-min=13.0 \
    -lstdc++ \
    -o "$BUILD_DIR/$APP_NAME"

info "Linked binary: $BUILD_DIR/$APP_NAME"

# Strip local debug symbol metadata from release builds to avoid shipping
# developer machine paths in the distributed binary.
if command -v strip >/dev/null 2>&1; then
    strip -S -x "$BUILD_DIR/$APP_NAME" 2>/dev/null || warn "strip failed - continuing with unstripped binary"
fi

# ---------------------------------------------------------------------------
# Step 4: Create .app bundle
# ---------------------------------------------------------------------------
step "Creating app bundle..."

CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

mkdir -p "$MACOS"
mkdir -p "$RESOURCES"
mkdir -p "$RESOURCES/en.lproj"
mkdir -p "$RESOURCES/Base.lproj"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$MACOS/$APP_NAME"

# Create Info.plist (resolve variables)
sed 's/$(PRODUCT_BUNDLE_IDENTIFIER)/com.typeflow.inputmethod.TypeflowInputMethod/g' \
    "$PROJECT_DIR/Info.plist" > "$CONTENTS/Info.plist"

# Copy resources
cp "$PROJECT_DIR/him.icns" "$RESOURCES/"
cp "$PROJECT_DIR/him.png" "$RESOURCES/"
cp "$PROJECT_DIR/dictionary/google_227800_words.bin" "$RESOURCES/"
cp "$PROJECT_DIR/dictionary/words_with_frequency_and_translation_and_ipa.json" "$RESOURCES/"
cp "$PROJECT_DIR/dictionary/phonex_encoded_words.json" "$RESOURCES/"
cp "$PROJECT_DIR/dictionary/cedict.json" "$RESOURCES/"
cp "$PROJECT_DIR/src/phonex.js" "$RESOURCES/"

# Copy web directory
cp -R "$PROJECT_DIR/web" "$RESOURCES/web"

# Copy localized strings
cp "$PROJECT_DIR/en.lproj/InfoPlist.strings" "$RESOURCES/en.lproj/"

# Compile XIBs to NIBs
step "Compiling XIB files..."
ibtool --compile "$RESOURCES/Base.lproj/AnnotationWindow.nib" "$PROJECT_DIR/Base.lproj/AnnotationWindow.xib" 2>/dev/null
ibtool --compile "$RESOURCES/PreferencesMenu.nib" "$PROJECT_DIR/PreferencesMenu.xib" 2>/dev/null

# Create PkgInfo
echo -n "APPL????" > "$CONTENTS/PkgInfo"

info "App bundle created: $APP_BUNDLE"

# Verify
ls -la "$MACOS/$APP_NAME"
echo ""
du -sh "$APP_BUNDLE"

# ---------------------------------------------------------------------------
# Step 5: Install (requires sudo)
# ---------------------------------------------------------------------------
if [ "$BUILD_ONLY" = true ]; then
    info "Build complete (install skipped)."
    info "App bundle: $APP_BUNDLE"
    exit 0
fi

echo ""
step "Installing to $INSTALL_DIR..."
echo ""
warn "This requires sudo to install to /Library/Input Methods/"
warn "The existing Typeflow input method will be replaced."
echo ""
read -p "Continue with installation? [y/N] " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    info "Installation cancelled. Build is at: $APP_BUNDLE"
    exit 0
fi

# Kill running instance
pkill -9 Typeflow 2>/dev/null || true
sleep 1

# Remove old installation
sudo rm -rf "$INSTALL_DIR/$APP_NAME.app"

# Install new version
sudo cp -R "$APP_BUNDLE" "$INSTALL_DIR/$APP_NAME.app"

# Register and activate input source
sudo "$INSTALL_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME" --install

echo ""
info "========================================"
info "  Installation complete!"
info "========================================"
info ""
info "Typeflow has been installed to: $INSTALL_DIR/$APP_NAME.app"
info ""
info "To use it:"
info "  1. Open System Settings → Keyboard → Input Sources"
info "  2. Click '+' and find 'Typeflow' under Chinese"
info "  3. Switch to it using the input source menu bar icon"
info ""
info "Preferences: http://localhost:62720/index.html"
info ""
info "Note: Currently running in MOCK prediction mode (built-in bigrams)."
info "For real LLM prediction, rebuild with HALLELUJAH_USE_LLAMA=1 and run: ./scripts/setup-llama.sh"
