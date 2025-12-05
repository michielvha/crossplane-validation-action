#!/bin/bash
set -e

VERSION="${1:-latest}"

echo "Setting up Crossplane CLI..."

# Check if crossplane is already installed
if command -v crossplane &> /dev/null; then
    INSTALLED_VERSION=$(crossplane --version 2>&1 | grep -oP 'v\d+\.\d+\.\d+' || echo "unknown")
    echo "✓ Crossplane CLI already installed: $INSTALLED_VERSION"
    
    # If a specific version is requested and it doesn't match, reinstall
    if [ "$VERSION" != "latest" ] && [ "$INSTALLED_VERSION" != "$VERSION" ]; then
        echo "⚠ Requested version ($VERSION) differs from installed version ($INSTALLED_VERSION)"
        echo "Reinstalling Crossplane CLI..."
    else
        echo "Using existing installation"
        exit 0
    fi
fi

# Determine the latest version if requested
if [ "$VERSION" = "latest" ]; then
    echo "Fetching latest Crossplane CLI version..."
    VERSION=$(curl -sL https://api.github.com/repos/crossplane/crossplane/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
    echo "Latest version: $VERSION"
fi

# Detect OS and architecture
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

# Map architecture names
case "$ARCH" in
    x86_64)
        ARCH="amd64"
        ;;
    aarch64|arm64)
        ARCH="arm64"
        ;;
    *)
        echo "❌ Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# Map OS names
case "$OS" in
    linux)
        OS="linux"
        ;;
    darwin)
        OS="darwin"
        ;;
    mingw*|msys*|cygwin*)
        OS="windows"
        ;;
    *)
        echo "❌ Unsupported OS: $OS"
        exit 1
        ;;
esac

# Construct download URL
DOWNLOAD_URL="https://releases.crossplane.io/stable/${VERSION}/bin/${OS}_${ARCH}/crank"
echo "Downloading Crossplane CLI from: $DOWNLOAD_URL"

# Create temporary directory
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

# Download the CLI
if ! curl -sL -o "$TMP_DIR/crossplane" "$DOWNLOAD_URL"; then
    echo "❌ Failed to download Crossplane CLI"
    exit 1
fi

# Make it executable
chmod +x "$TMP_DIR/crossplane"

# Move to a directory in PATH
INSTALL_DIR="/usr/local/bin"
if [ ! -w "$INSTALL_DIR" ]; then
    # Try user local bin if system bin is not writable
    INSTALL_DIR="$HOME/.local/bin"
    mkdir -p "$INSTALL_DIR"
fi

mv "$TMP_DIR/crossplane" "$INSTALL_DIR/crossplane"

# Add to PATH if not already there
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> "$GITHUB_PATH"
    export PATH="$INSTALL_DIR:$PATH"
fi

# Verify installation
if crossplane --version &> /dev/null; then
    INSTALLED_VERSION=$(crossplane --version 2>&1 | grep -oP 'v\d+\.\d+\.\d+' || echo "unknown")
    echo "✅ Crossplane CLI installed successfully: $INSTALLED_VERSION"
else
    echo "❌ Failed to verify Crossplane CLI installation"
    exit 1
fi
