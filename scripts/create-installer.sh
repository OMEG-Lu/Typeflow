#!/bin/bash
set -e

# ==============================================================================
# create-installer.sh
# Build Typeflow and create a .pkg installer for distribution.
#
# Usage:
#   ./scripts/create-installer.sh
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build_release"
PKG_DIR="$PROJECT_DIR/build_pkg"
APP_NAME="Typeflow"
VERSION="1.0.0"
IDENTIFIER="com.typeflow.inputmethod"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
step()  { echo -e "${CYAN}[STEP]${NC} $1"; }

echo "========================================"
echo "  Typeflow Installer Builder"
echo "========================================"
echo ""

# Step 1: Build the app
step "Building Typeflow..."
bash "$SCRIPT_DIR/build-and-install.sh" --build

# Step 2: Prepare pkg staging
step "Preparing installer package..."
rm -rf "$PKG_DIR"
mkdir -p "$PKG_DIR/payload/Library/Input Methods"
mkdir -p "$PKG_DIR/scripts"

# Copy app bundle to payload
cp -R "$BUILD_DIR/$APP_NAME.app" "$PKG_DIR/payload/Library/Input Methods/$APP_NAME.app"

# Step 3: Create post-install script
cat > "$PKG_DIR/scripts/postinstall" << 'POSTINSTALL'
#!/bin/bash

# Kill any running instance
pkill -9 Typeflow 2>/dev/null || true
sleep 1

# Register the input source
"/Library/Input Methods/Typeflow.app/Contents/MacOS/Typeflow" --install 2>/dev/null || true

# Create models directory
MODELS_DIR="$HOME/Library/Application Support/Typeflow/models"
mkdir -p "$MODELS_DIR"

exit 0
POSTINSTALL
chmod +x "$PKG_DIR/scripts/postinstall"

# Step 4: Build the component package
step "Building component package..."
pkgbuild \
    --root "$PKG_DIR/payload" \
    --scripts "$PKG_DIR/scripts" \
    --identifier "$IDENTIFIER" \
    --version "$VERSION" \
    --install-location "/" \
    "$PKG_DIR/$APP_NAME-component.pkg"

# Step 5: Create distribution XML for a nicer installer UI
cat > "$PKG_DIR/distribution.xml" << DISTXML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>Typeflow Input Method</title>
    <welcome file="welcome.html" mime-type="text/html"/>
    <conclusion file="conclusion.html" mime-type="text/html"/>
    <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
    <domains enable_localSystem="true"/>
    <pkg-ref id="$IDENTIFIER"/>
    <choices-outline>
        <line choice="default">
            <line choice="$IDENTIFIER"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="$IDENTIFIER" visible="false">
        <pkg-ref id="$IDENTIFIER"/>
    </choice>
    <pkg-ref id="$IDENTIFIER" version="$VERSION">#$APP_NAME-component.pkg</pkg-ref>
</installer-gui-script>
DISTXML

# Step 6: Create welcome and conclusion HTML
mkdir -p "$PKG_DIR/resources"

cat > "$PKG_DIR/resources/welcome.html" << 'WELCOME'
<!DOCTYPE html>
<html>
<head><style>
body { font-family: -apple-system, sans-serif; padding: 20px; color: #333; }
h1 { font-size: 22px; margin-bottom: 10px; }
h2 { font-size: 16px; color: #666; margin-top: 20px; }
ul { padding-left: 20px; }
li { margin: 6px 0; }
.feature { color: #007AFF; font-weight: 500; }
</style></head>
<body>
<h1>Typeflow Input Method</h1>
<p>An intelligent English input method for macOS with AI-powered next-word prediction.</p>
<h2>Features</h2>
<ul>
<li><span class="feature">Smart Predictions</span> - Context-aware next-word suggestions powered by local LLM</li>
<li><span class="feature">Spell Correction</span> - Automatic typo detection and correction</li>
<li><span class="feature">Word Completion</span> - 227,000+ word dictionary with frequency ranking</li>
<li><span class="feature">Translations</span> - Chinese translations for English words</li>
<li><span class="feature">Privacy</span> - All processing happens locally on your Mac</li>
</ul>
<h2>Requirements</h2>
<ul>
<li>macOS 13.0 (Ventura) or later</li>
<li>Apple Silicon or Intel Mac</li>
</ul>
</body>
</html>
WELCOME

cat > "$PKG_DIR/resources/conclusion.html" << 'CONCLUSION'
<!DOCTYPE html>
<html>
<head><style>
body { font-family: -apple-system, sans-serif; padding: 20px; color: #333; }
h1 { font-size: 22px; color: #28a745; }
h2 { font-size: 16px; color: #666; margin-top: 20px; }
ol { padding-left: 20px; }
li { margin: 8px 0; }
code { background: #f0f0f0; padding: 2px 6px; border-radius: 3px; font-size: 13px; }
.note { background: #fff3cd; border: 1px solid #ffc107; border-radius: 6px; padding: 12px; margin-top: 15px; }
</style></head>
<body>
<h1>Installation Complete!</h1>
<h2>How to activate Typeflow:</h2>
<ol>
<li>Open <strong>System Settings</strong> &rarr; <strong>Keyboard</strong> &rarr; <strong>Input Sources</strong></li>
<li>Click <strong>Edit</strong>, then click <strong>+</strong></li>
<li>Find <strong>Typeflow</strong> under <strong>English</strong></li>
<li>Add it and switch to it using the menu bar icon</li>
</ol>
<div class="note">
<strong>Note:</strong> For AI predictions, you need to download a model.
Open Typeflow preferences from the menu bar and select a model size.
</div>
</body>
</html>
CONCLUSION

# Step 7: Build the final product archive
step "Building final installer..."
productbuild \
    --distribution "$PKG_DIR/distribution.xml" \
    --resources "$PKG_DIR/resources" \
    --package-path "$PKG_DIR" \
    "$PROJECT_DIR/Typeflow-Installer.pkg"

info "========================================"
info "  Installer created successfully!"
info "========================================"
info ""
info "  Installer: $PROJECT_DIR/Typeflow-Installer.pkg"
info "  Size: $(du -sh "$PROJECT_DIR/Typeflow-Installer.pkg" | cut -f1)"
info ""
info "  Users can double-click to install."
info ""

# Cleanup
rm -rf "$PKG_DIR"
