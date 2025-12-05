# Examples

This directory contains examples to help you get started with the Crossplane Validation Action.

## 📂 Folder Structure

### `manifests/`
Sample Crossplane manifest files that demonstrate the types of resources this action can validate:

- **`sample-composition.yaml`** - Example Crossplane Composition showing resource composition patterns
- **`sample-xrd.yaml`** - Example CompositeResourceDefinition (XRD) 
- **`sample-provider.yaml`** - Example Provider configuration for schema resolution
- **`sample-with-errors.yaml`** - Example file with intentional validation errors (useful for testing)

### `workflows/`
Example GitHub Actions workflow files showing different ways to use this action:

- **`basic-validation.yml`** - Minimal setup for PR validation
  - Simple configuration with default settings
  - Perfect for getting started quickly

- **`advanced-validation.yml`** - Advanced configuration with all options
  - Custom cache directory and working directory
  - Shows how to use action outputs
  - Demonstrates custom reporting in job summaries
  - Includes PR comment creation on validation failures

- **`multi-environment.yml`** - Matrix strategy for multiple directories
  - Validates multiple isolated Crossplane directories in parallel
  - Example: separate `dev/`, `staging/`, and `prod/` configurations
  - Shows environment-specific cache directories
  - Demonstrates fail-fast: false for independent validation

## 🚀 Quick Start

1. Choose the workflow that best matches your use case
2. Copy it to your repository's `.github/workflows/` directory
3. Adjust the paths and options as needed
4. Commit and push to trigger the workflow

## 💡 Tips

- Start with `basic-validation.yml` if you're new to this action
- Use `advanced-validation.yml` if you need custom reporting or error handling
- Use `multi-environment.yml` if you have multiple separate Crossplane directories in your repository
- Check the main [README.md](../README.md) for full documentation on inputs and outputs
