#!/bin/bash
set -e

# ==============================================================================
# setup-llama.sh
# Build llama.cpp static library and download GGUF models for Typeflow
# next-word prediction feature.
#
# Usage:
#   ./scripts/setup-llama.sh              # Build llama.cpp + download small model
#   ./scripts/setup-llama.sh --all        # Build + download all 4 models
#   ./scripts/setup-llama.sh --model small|medium|large|xlarge  # Download specific model
#   ./scripts/setup-llama.sh --build-only # Only build llama.cpp, skip model download
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LLAMA_DIR="$PROJECT_DIR/third_party/llama.cpp"
LLAMA_BUILD_DIR="$LLAMA_DIR/build"
LIB_OUTPUT_DIR="$PROJECT_DIR/lib"
INCLUDE_OUTPUT_DIR="$PROJECT_DIR/include/llama"

MODEL_DIR="$HOME/Library/Application Support/Typeflow/models"

# llama.cpp version tag
LLAMA_TAG="b8559"

# Model download URLs (Hugging Face)
# Small: SmolLM-135M quantized
MODEL_SMALL_URL="https://huggingface.co/QuantFactory/SmolLM-135M-GGUF/resolve/main/SmolLM-135M.Q8_0.gguf"
MODEL_SMALL_FILE="smollm-135m-q8_0.gguf"

# Medium: Qwen2-0.5B quantized
MODEL_MEDIUM_URL="https://huggingface.co/Qwen/Qwen2-0.5B-Instruct-GGUF/resolve/main/qwen2-0_5b-instruct-q8_0.gguf"
MODEL_MEDIUM_FILE="qwen2-0.5b-q8_0.gguf"

# Large: Qwen2-1.5B quantized (Q4_K_M for reasonable size)
MODEL_LARGE_URL="https://huggingface.co/Qwen/Qwen2-1.5B-Instruct-GGUF/resolve/main/qwen2-1_5b-instruct-q4_k_m.gguf"
MODEL_LARGE_FILE="qwen2-1.5b-q4_k_m.gguf"

# XLarge: Qwen2.5-3B quantized (Q4_K_M for best quality)
MODEL_XLARGE_URL="https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf"
MODEL_XLARGE_FILE="qwen2.5-3b-q4_k_m.gguf"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ==============================================================================
# Clone / update llama.cpp
# ==============================================================================
setup_llama_source() {
    info "Setting up llama.cpp source..."

    if [ ! -d "$LLAMA_DIR" ]; then
        mkdir -p "$PROJECT_DIR/third_party"
        info "Cloning llama.cpp (tag: $LLAMA_TAG)..."
        git clone --depth 1 --branch "$LLAMA_TAG" \
            https://github.com/ggerganov/llama.cpp.git "$LLAMA_DIR"
    else
        info "llama.cpp source already exists at $LLAMA_DIR"
        cd "$LLAMA_DIR"
        CURRENT_TAG=$(git describe --tags --exact-match 2>/dev/null || echo "unknown")
        if [ "$CURRENT_TAG" != "$LLAMA_TAG" ]; then
            warn "Current tag ($CURRENT_TAG) differs from target ($LLAMA_TAG)."
            warn "To update, remove $LLAMA_DIR and re-run this script."
        fi
    fi
}

# ==============================================================================
# Build llama.cpp as static library
# ==============================================================================
build_llama() {
    info "Building llama.cpp static library..."

    mkdir -p "$LLAMA_BUILD_DIR"
    cd "$LLAMA_BUILD_DIR"

    # Build with Metal (GPU) support on macOS
    local path_sanitize_flags="-fdebug-prefix-map=$PROJECT_DIR=. -fmacro-prefix-map=$PROJECT_DIR=."
    cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF \
        -DGGML_METAL=ON \
        -DGGML_ACCELERATE=ON \
        -DLLAMA_BUILD_TESTS=OFF \
        -DLLAMA_BUILD_EXAMPLES=OFF \
        -DLLAMA_BUILD_SERVER=OFF \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
        -DCMAKE_C_FLAGS_RELEASE="$path_sanitize_flags" \
        -DCMAKE_CXX_FLAGS_RELEASE="$path_sanitize_flags" \
        -DCMAKE_OSX_ARCHITECTURES="arm64"

    cmake --build . --config Release -j$(sysctl -n hw.ncpu)

    info "Copying built libraries and headers..."

    # Copy static libraries
    mkdir -p "$LIB_OUTPUT_DIR"
    find "$LLAMA_BUILD_DIR" -name "*.a" -exec cp {} "$LIB_OUTPUT_DIR/" \;
    find "$LIB_OUTPUT_DIR" -name "*.a" -exec strip -S -x {} \; 2>/dev/null || true

    # Copy headers
    mkdir -p "$INCLUDE_OUTPUT_DIR"
    cp "$LLAMA_DIR/include/llama.h" "$INCLUDE_OUTPUT_DIR/" 2>/dev/null || true
    cp "$LLAMA_DIR/include/llama-cpp.h" "$INCLUDE_OUTPUT_DIR/" 2>/dev/null || true
    cp "$LLAMA_DIR/ggml/include/ggml.h" "$INCLUDE_OUTPUT_DIR/" 2>/dev/null || true
    cp "$LLAMA_DIR/ggml/include/ggml-alloc.h" "$INCLUDE_OUTPUT_DIR/" 2>/dev/null || true
    cp "$LLAMA_DIR/ggml/include/ggml-backend.h" "$INCLUDE_OUTPUT_DIR/" 2>/dev/null || true
    cp "$LLAMA_DIR/ggml/include/ggml-metal.h" "$INCLUDE_OUTPUT_DIR/" 2>/dev/null || true
    # Also copy common headers if they exist
    cp "$LLAMA_DIR/common/common.h" "$INCLUDE_OUTPUT_DIR/" 2>/dev/null || true

    info "Libraries copied to $LIB_OUTPUT_DIR"
    info "Headers copied to $INCLUDE_OUTPUT_DIR"
    ls -la "$LIB_OUTPUT_DIR"/*.a 2>/dev/null || warn "No .a files found"
}

# ==============================================================================
# Download a model
# ==============================================================================
download_model() {
    local url="$1"
    local filename="$2"
    local label="$3"
    local filepath="$MODEL_DIR/$filename"

    if [ -f "$filepath" ]; then
        info "$label model already exists: $filepath"
        return
    fi

    mkdir -p "$MODEL_DIR"
    info "Downloading $label model..."
    info "  URL: $url"
    info "  Destination: $filepath"
    info "  This may take a while depending on your connection speed."

    if command -v curl &>/dev/null; then
        curl -L --progress-bar -o "$filepath" "$url"
    elif command -v wget &>/dev/null; then
        wget --show-progress -O "$filepath" "$url"
    else
        error "Neither curl nor wget found. Please install one and try again."
    fi

    if [ -f "$filepath" ]; then
        local size=$(du -h "$filepath" | cut -f1)
        info "$label model downloaded successfully ($size)"
    else
        error "Failed to download $label model"
    fi
}

download_small()  { download_model "$MODEL_SMALL_URL"  "$MODEL_SMALL_FILE"  "Small (SmolLM-135M)"; }
download_medium() { download_model "$MODEL_MEDIUM_URL" "$MODEL_MEDIUM_FILE" "Medium (Qwen2-0.5B)"; }
download_large()  { download_model "$MODEL_LARGE_URL"  "$MODEL_LARGE_FILE"  "Large (Qwen2-1.5B)"; }
download_xlarge() { download_model "$MODEL_XLARGE_URL" "$MODEL_XLARGE_FILE" "XLarge (Qwen2.5-3B)"; }

# ==============================================================================
# Print status
# ==============================================================================
print_status() {
    echo ""
    info "=== Setup Status ==="

    echo -n "  llama.cpp source: "
    [ -d "$LLAMA_DIR" ] && echo -e "${GREEN}OK${NC}" || echo -e "${RED}MISSING${NC}"

    echo -n "  Static libraries: "
    ls "$LIB_OUTPUT_DIR"/*.a &>/dev/null && echo -e "${GREEN}OK${NC}" || echo -e "${RED}MISSING${NC}"

    echo -n "  Small model:  "
    [ -f "$MODEL_DIR/$MODEL_SMALL_FILE" ] && echo -e "${GREEN}OK${NC} ($(du -h "$MODEL_DIR/$MODEL_SMALL_FILE" | cut -f1))" || echo -e "${YELLOW}Not downloaded${NC}"

    echo -n "  Medium model: "
    [ -f "$MODEL_DIR/$MODEL_MEDIUM_FILE" ] && echo -e "${GREEN}OK${NC} ($(du -h "$MODEL_DIR/$MODEL_MEDIUM_FILE" | cut -f1))" || echo -e "${YELLOW}Not downloaded${NC}"

    echo -n "  Large model:  "
    [ -f "$MODEL_DIR/$MODEL_LARGE_FILE" ] && echo -e "${GREEN}OK${NC} ($(du -h "$MODEL_DIR/$MODEL_LARGE_FILE" | cut -f1))" || echo -e "${YELLOW}Not downloaded${NC}"

    echo -n "  XLarge model: "
    [ -f "$MODEL_DIR/$MODEL_XLARGE_FILE" ] && echo -e "${GREEN}OK${NC} ($(du -h "$MODEL_DIR/$MODEL_XLARGE_FILE" | cut -f1))" || echo -e "${YELLOW}Not downloaded${NC}"

    echo ""
    info "Model directory: $MODEL_DIR"
    echo ""
}

# ==============================================================================
# Main
# ==============================================================================
main() {
    local build_only=false
    local download_all=false
    local specific_model=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --build-only)
                build_only=true
                shift
                ;;
            --all)
                download_all=true
                shift
                ;;
            --model)
                specific_model="$2"
                shift 2
                ;;
            --status)
                print_status
                exit 0
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --build-only        Only build llama.cpp, skip model download"
                echo "  --all               Download all 4 model tiers"
                echo "  --model TIER        Download specific model (small|medium|large|xlarge)"
                echo "  --status            Show current setup status"
                echo "  --help              Show this help"
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done

    echo "========================================"
    echo "  Typeflow LLM Setup"
    echo "========================================"
    echo ""

    # Step 1: Get llama.cpp source
    setup_llama_source

    # Step 2: Build
    build_llama

    if [ "$build_only" = true ]; then
        info "Build complete (model download skipped)."
        print_status
        exit 0
    fi

    # Step 3: Download models
    if [ -n "$specific_model" ]; then
        case "$specific_model" in
            small)  download_small ;;
            medium) download_medium ;;
            large)  download_large ;;
            xlarge) download_xlarge ;;
            *)      error "Unknown model tier: $specific_model (use small|medium|large|xlarge)" ;;
        esac
    elif [ "$download_all" = true ]; then
        download_small
        download_medium
        download_large
        download_xlarge
    else
        # Default: download small model only
        download_small
    fi

    print_status

    info "Setup complete! You can now build Typeflow with next-word prediction."
    info "Remember to add the llama.cpp libraries to your Xcode project."
}

main "$@"
