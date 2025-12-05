#!/bin/bash
set -e

echo "Setting up Crossplane CLI..."

# Check if crossplane is already installed
if command -v crossplane &> /dev/null; then
    INSTALLED_VERSION=$(crossplane --version 2>&1 || echo "unknown")
    echo "✓ Crossplane CLI already installed: $INSTALLED_VERSION"
    echo "Using existing installation"
    exit 0
fi

# Use the official Crossplane install script
# This always installs the latest stable version from main branch
echo "Installing Crossplane CLI using official installer..."
curl -sL "https://raw.githubusercontent.com/crossplane/crossplane/main/install.sh" | sh

# The official installer places the binary in the current directory
# Move it to a proper location in PATH
if [ -f "./crossplane" ]; then
    echo "Moving crossplane binary to /usr/local/bin..."
    
    # Try to move to /usr/local/bin
    if sudo mv ./crossplane /usr/local/bin/crossplane 2>/dev/null; then
        echo "✓ Installed to /usr/local/bin/crossplane"
    else
        # If sudo fails, try user local bin
        mkdir -p "$HOME/.local/bin"
        mv ./crossplane "$HOME/.local/bin/crossplane"
        echo "✓ Installed to $HOME/.local/bin/crossplane"
        
        # Add to PATH if not already there
        if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
            echo "$HOME/.local/bin" >> "$GITHUB_PATH"
            export PATH="$HOME/.local/bin:$PATH"
        fi
    fi
fi

# Verify installation
if crossplane --version &> /dev/null; then
    INSTALLED_VERSION=$(crossplane --version 2>&1)
    echo "✅ Crossplane CLI installed successfully!"
    echo "$INSTALLED_VERSION"
else
    echo "❌ Failed to verify Crossplane CLI installation"
    exit 1
fi
