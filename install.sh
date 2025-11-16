#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}==> Nest Bootstrap Installer${NC}"
echo ""

# Check if swift is available
if ! command -v swift &> /dev/null; then
    echo -e "${RED}Error: Swift is not installed or not in PATH${NC}"
    echo "Please install Swift from https://swift.org/download/"
    exit 1
fi

# Create temporary directory
TEMP_DIR=$(mktemp -d)
echo -e "${BLUE}==> Creating temporary directory: $TEMP_DIR${NC}"

# Cleanup function
cleanup() {
    echo -e "${BLUE}==> Cleaning up temporary directory${NC}"
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Clone Nest repository
echo -e "${BLUE}==> Cloning Nest repository${NC}"
git clone https://github.com/harlanhaskins/Nest.git "$TEMP_DIR/Nest"
cd "$TEMP_DIR/Nest"

# Build Nest in release mode
echo -e "${BLUE}==> Building Nest in release mode${NC}"
swift build -c release

# Get the path to the built binary
NEST_BINARY="$TEMP_DIR/Nest/.build/release/nest"

if [ ! -f "$NEST_BINARY" ]; then
    echo -e "${RED}Error: Failed to build Nest${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Nest built successfully${NC}"
echo ""

# Use Nest to install itself
echo -e "${BLUE}==> Installing Nest using itself${NC}"
"$NEST_BINARY" install --path "$TEMP_DIR/Nest"

echo ""
echo -e "${GREEN}==> Installation complete!${NC}"
echo ""
echo "Nest has been installed to ~/.nest/bin/nest"
echo ""

# Detect user's shell and provide appropriate instructions
DETECTED_SHELL=$(basename "$SHELL")
echo "To use Nest, add ~/.nest/bin to your PATH:"
echo ""

case "$DETECTED_SHELL" in
    fish)
        echo -e "${BLUE}For Fish shell:${NC}"
        echo "  fish_add_path \$HOME/.nest/bin"
        echo ""
        echo "Add this line to ~/.config/fish/config.fish"
        ;;
    zsh)
        echo -e "${BLUE}For Zsh:${NC}"
        echo "  export PATH=\"\$HOME/.nest/bin:\$PATH\""
        echo ""
        echo "Add this line to ~/.zshrc"
        ;;
    bash)
        echo -e "${BLUE}For Bash:${NC}"
        echo "  export PATH=\"\$HOME/.nest/bin:\$PATH\""
        echo ""
        echo "Add this line to ~/.bashrc or ~/.bash_profile"
        ;;
    *)
        echo -e "${BLUE}For your shell ($DETECTED_SHELL):${NC}"
        echo "  export PATH=\"\$HOME/.nest/bin:\$PATH\""
        echo ""
        echo "Add this line to your shell's configuration file"
        ;;
esac
