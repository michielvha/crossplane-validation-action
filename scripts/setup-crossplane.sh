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
    # Make sure it's executable
    chmod +x ./crossplane
    
    echo "Installing crossplane binary to /usr/local/bin..."
    
    # Try to install to /usr/local/bin (preserves permissions)
    if sudo install -m 755 ./crossplane /usr/local/bin/crossplane 2>/dev/null; then
        echo "✓ Installed to /usr/local/bin/crossplane"
        rm -f ./crossplane
        
        # Ensure /usr/local/bin is in PATH
        export PATH="/usr/local/bin:$PATH"
    else
        # If sudo fails, try user local bin
        echo "Sudo not available, installing to $HOME/.local/bin..."
        mkdir -p "$HOME/.local/bin"
        install -m 755 ./crossplane "$HOME/.local/bin/crossplane"
        rm -f ./crossplane
        echo "✓ Installed to $HOME/.local/bin/crossplane"
        
        # Add to PATH for current shell
        export PATH="$HOME/.local/bin:$PATH"
        
        # Add to GITHUB_PATH for future steps
        if [ -n "$GITHUB_PATH" ]; then
            echo "$HOME/.local/bin" >> "$GITHUB_PATH"
        fi
    fi
fi

# Verify installation
echo "Verifying installation..."
if command -v crossplane &> /dev/null; then
    INSTALLED_VERSION=$(crossplane --version 2>&1)
    echo "✅ Crossplane CLI installed successfully!"
    echo "$INSTALLED_VERSION"
else
    echo "❌ Failed to find crossplane in PATH"
    echo "PATH is: $PATH"
    echo "Checking common locations..."
    ls -la /usr/local/bin/crossplane 2>/dev/null || echo "Not in /usr/local/bin"
    ls -la "$HOME/.local/bin/crossplane" 2>/dev/null || echo "Not in ~/.local/bin"
    exit 1
fi
