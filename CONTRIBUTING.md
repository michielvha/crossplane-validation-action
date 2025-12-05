# Contributing to Crossplane Build Check Action

Thank you for your interest in contributing! 🎉

## Development Setup

1. **Fork and clone the repository**
   ```bash
   git clone https://github.com/yourusername/crossplane-build-check-action.git
   cd crossplane-build-check-action
   ```

2. **Understand the structure**
   - `action.yml` - Main action definition
   - `scripts/` - Shell scripts for the action logic
   - `examples/` - Sample Crossplane files for testing
   - `.github/workflows/` - Test workflows
   - `docs/` - Project documentation

## Making Changes

### Shell Scripts

All scripts are in the `scripts/` directory:

- `setup-crossplane.sh` - Installs Crossplane CLI
- `detect-changes.sh` - Detects changed Crossplane files
- `validate.sh` - Runs validation

**Guidelines**:
- Use `set -e` at the top of scripts (fail fast)
- Add comments for complex logic
- Use meaningful variable names in UPPER_CASE
- Test on both Linux and macOS if possible

### Testing Your Changes

1. **Local testing** (requires Docker):
   ```bash
   # Make scripts executable
   chmod +x scripts/*.sh
   
   # Test change detection
   export GITHUB_OUTPUT=$(mktemp)
   export BASE_REF=main
   export HEAD_REF=HEAD
   bash scripts/detect-changes.sh
   cat $GITHUB_OUTPUT
   
   # Test Crossplane setup
   bash scripts/setup-crossplane.sh latest
   crossplane --version
   ```

2. **Test in a real repository**:
   - Create a test repository with Crossplane files
   - Reference your fork in the workflow:
     ```yaml
     uses: yourusername/crossplane-build-check-action@your-branch
     ```
   - Open a PR and verify the action runs correctly

3. **Use act** (GitHub Actions locally):
   ```bash
   # Install act: https://github.com/nektos/act
   act pull_request
   ```

### Commit Messages

Use conventional commits:

```
feat: add support for custom file patterns
fix: handle deleted files in change detection
docs: update README with troubleshooting section
test: add test for error scenarios
```

## Pull Request Process

1. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes**
   - Write clear, commented code
   - Update documentation if needed
   - Add tests if applicable

3. **Test thoroughly**
   - Run the test workflow
   - Test in a real repository
   - Verify all scripts work

4. **Update PROJECT_TRACKER.md**
   - Document your changes in `/docs/PROJECT_TRACKER.md`
   - Add to the "Notes & Learnings" section if relevant

5. **Submit PR**
   - Describe what changed and why
   - Reference any related issues
   - Include test results or screenshots

## Code Review

- PRs require at least one approval
- CI tests must pass
- Scripts must be shellcheck compliant (if applicable)

## Release Process

(For maintainers)

1. Update version references in README
2. Create a new tag: `git tag -a v1.x.x -m "Release v1.x.x"`
3. Push tag: `git push origin v1.x.x`
4. Create GitHub release with changelog
5. Update marketplace listing

## Questions?

- Open an issue for bugs or feature requests
- Start a discussion for questions or ideas

Thank you for contributing! 🚀
