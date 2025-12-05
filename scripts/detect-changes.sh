#!/bin/bash
set -e

echo "Detecting changed Crossplane files..."

# Get base and head refs from environment
# For PRs: BASE_REF will be the target branch (e.g., main)
# For pushes: BASE_REF will be empty, so we compare with previous commit
BASE_REF="${BASE_REF:-}"
HEAD_REF="${HEAD_REF:-HEAD}"
WORKING_DIR="${WORKING_DIR:-.}"

# If BASE_REF is empty (push event), use previous commit
if [ -z "$BASE_REF" ]; then
    echo "No base ref provided (push event), comparing with HEAD~1"
    BASE_REF="HEAD~1"
fi

# Change to working directory
cd "$WORKING_DIR"

# Arrays to store different types of files
declare -a XRD_FILES=()
declare -a COMPOSITION_FILES=()
declare -a PROVIDER_FILES=()
declare -a ALL_CROSSPLANE_FILES=()

# Fetch the base ref if it's a remote branch
if [[ "$BASE_REF" == origin/* ]]; then
    echo "Fetching base ref: $BASE_REF"
    git fetch origin "${BASE_REF#origin/}" --depth=1 2>/dev/null || true
fi

# Get list of changed files
echo "Comparing $BASE_REF...$HEAD_REF"

# Use git diff to find changed files
CHANGED_FILES=$(git diff --name-only "$BASE_REF" "$HEAD_REF" 2>/dev/null || echo "")

if [ -z "$CHANGED_FILES" ]; then
    echo "⚠ No changed files detected"
    echo "changed-files-count=0" >> "$GITHUB_OUTPUT"
    echo "xrd-files=[]" >> "$GITHUB_OUTPUT"
    echo "composition-files=[]" >> "$GITHUB_OUTPUT"
    echo "provider-files=[]" >> "$GITHUB_OUTPUT"
    echo "all-files=[]" >> "$GITHUB_OUTPUT"
    exit 0
fi

echo "Changed files found:"
echo "$CHANGED_FILES"
echo ""

# Function to check if a file is a YAML file
is_yaml_file() {
    local file="$1"
    [[ "$file" =~ \.(yaml|yml)$ ]]
}

# Function to extract the 'kind' from a YAML file
get_yaml_kind() {
    local file="$1"
    
    # Check if file exists (it might have been deleted)
    if [ ! -f "$file" ]; then
        echo "DELETED"
        return
    fi
    
    # Extract kind using grep and awk (avoiding yq dependency)
    # This looks for lines like "kind: Something" and extracts "Something"
    local kind=$(grep -E "^kind:\s*" "$file" | head -n 1 | awk '{print $2}' | tr -d '\r\n' || echo "")
    echo "$kind"
}

# Process each changed file
while IFS= read -r file; do
    # Skip empty lines
    [ -z "$file" ] && continue
    
    # Skip non-YAML files
    if ! is_yaml_file "$file"; then
        continue
    fi
    
    # Get the kind
    KIND=$(get_yaml_kind "$file")
    
    # Skip if we couldn't determine the kind or if it's deleted
    if [ -z "$KIND" ] || [ "$KIND" = "DELETED" ]; then
        continue
    fi
    
    # Categorize based on kind
    case "$KIND" in
        CompositeResourceDefinition)
            echo "✓ Found XRD: $file"
            XRD_FILES+=("$file")
            ALL_CROSSPLANE_FILES+=("$file")
            ;;
        Composition)
            echo "✓ Found Composition: $file"
            COMPOSITION_FILES+=("$file")
            ALL_CROSSPLANE_FILES+=("$file")
            ;;
        Provider|Configuration)
            echo "✓ Found Provider/Configuration: $file"
            PROVIDER_FILES+=("$file")
            ALL_CROSSPLANE_FILES+=("$file")
            ;;
        *)
            # Skip other kinds
            ;;
    esac
done <<< "$CHANGED_FILES"

# Count total Crossplane files
TOTAL_COUNT=${#ALL_CROSSPLANE_FILES[@]}

echo ""
echo "Summary:"
echo "- XRDs: ${#XRD_FILES[@]}"
echo "- Compositions: ${#COMPOSITION_FILES[@]}"
echo "- Providers/Configurations: ${#PROVIDER_FILES[@]}"
echo "- Total Crossplane files: $TOTAL_COUNT"

# Convert arrays to JSON for output
# Function to convert bash array to JSON array
array_to_json() {
    local arr=("$@")
    if [ ${#arr[@]} -eq 0 ]; then
        echo "[]"
        return
    fi
    
    local json="["
    for i in "${!arr[@]}"; do
        if [ $i -gt 0 ]; then
            json+=","
        fi
        # Escape quotes and backslashes in filename
        local escaped="${arr[$i]//\\/\\\\}"
        escaped="${escaped//\"/\\\"}"
        json+="\"$escaped\""
    done
    json+="]"
    echo "$json"
}

# Output results to GitHub Actions
echo "changed-files-count=$TOTAL_COUNT" >> "$GITHUB_OUTPUT"
echo "xrd-files=$(array_to_json "${XRD_FILES[@]}")" >> "$GITHUB_OUTPUT"
echo "composition-files=$(array_to_json "${COMPOSITION_FILES[@]}")" >> "$GITHUB_OUTPUT"
echo "provider-files=$(array_to_json "${PROVIDER_FILES[@]}")" >> "$GITHUB_OUTPUT"
echo "all-files=$(array_to_json "${ALL_CROSSPLANE_FILES[@]}")" >> "$GITHUB_OUTPUT"

# Also save to a temporary file for the validation step
mkdir -p /tmp/crossplane-action
echo "${ALL_CROSSPLANE_FILES[@]}" > /tmp/crossplane-action/files-to-validate.txt

if [ $TOTAL_COUNT -eq 0 ]; then
    echo ""
    echo "ℹ No Crossplane files (XRD, Composition, Provider) changed in this PR"
else
    echo ""
    echo "✅ Detected $TOTAL_COUNT Crossplane file(s) to validate"
fi
