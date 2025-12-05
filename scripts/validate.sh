#!/bin/bash
set -e

echo "Validating Crossplane files..."

# Get configuration from environment
CACHE_DIR="${CACHE_DIR:-.crossplane/cache}"
CLEAN_CACHE="${CLEAN_CACHE:-false}"
FAIL_ON_ERROR="${FAIL_ON_ERROR:-true}"
WORKING_DIR="${WORKING_DIR:-.}"

# Change to working directory
cd "$WORKING_DIR"

# Read the list of files to validate
FILES_TO_VALIDATE_FILE="/tmp/crossplane-action/files-to-validate.txt"

if [ ! -f "$FILES_TO_VALIDATE_FILE" ]; then
    echo "⚠ No files to validate (detection step may have found no changes)"
    echo "validated-files=[]" >> "$GITHUB_OUTPUT"
    echo "validation-result=No Crossplane files to validate" >> "$GITHUB_OUTPUT"
    echo "success-count=0" >> "$GITHUB_OUTPUT"
    echo "failure-count=0" >> "$GITHUB_OUTPUT"
    exit 0
fi

# Read files into array
mapfile -t FILES_TO_VALIDATE < "$FILES_TO_VALIDATE_FILE"

if [ ${#FILES_TO_VALIDATE[@]} -eq 0 ]; then
    echo "⚠ No files to validate"
    echo "validated-files=[]" >> "$GITHUB_OUTPUT"
    echo "validation-result=No Crossplane files to validate" >> "$GITHUB_OUTPUT"
    echo "success-count=0" >> "$GITHUB_OUTPUT"
    echo "failure-count=0" >> "$GITHUB_OUTPUT"
    exit 0
fi

echo "Files to validate: ${FILES_TO_VALIDATE[*]}"
echo ""

# Clean cache if requested
if [ "$CLEAN_CACHE" = "true" ]; then
    echo "Cleaning cache directory: $CACHE_DIR"
    rm -rf "$CACHE_DIR"
fi

# Ensure cache directory exists
mkdir -p "$CACHE_DIR"

# Counters
SUCCESS_COUNT=0
FAILURE_COUNT=0
MISSING_SCHEMA_COUNT=0

# Arrays to track results
declare -a VALIDATED_FILES=()
declare -a FAILED_FILES=()
declare -a ERROR_MESSAGES=()

# Temporary file to store validation output
VALIDATION_OUTPUT=$(mktemp)
trap "rm -f $VALIDATION_OUTPUT" EXIT

# Separate files into extensions (schemas) and resources
# Extensions: XRDs, Providers, Configurations
# Resources: Compositions, Claims, and other resources
declare -a EXTENSION_FILES=()
declare -a RESOURCE_FILES=()

echo "Categorizing files..."
for file in "${FILES_TO_VALIDATE[@]}"; do
    if [ ! -f "$file" ]; then
        echo "⚠ File not found: $file"
        continue
    fi
    
    # Determine file type by examining the kind field
    KIND=$(grep -E "^kind:\s*" "$file" | head -n 1 | awk '{print $2}' | tr -d '\r\n' || echo "")
    
    case "$KIND" in
        CompositeResourceDefinition|Provider|Configuration|Function)
            echo "  Extension: $file (kind: $KIND)"
            EXTENSION_FILES+=("$file")
            ;;
        Composition|CompositeResource|Claim|*)
            echo "  Resource: $file (kind: $KIND)"
            RESOURCE_FILES+=("$file")
            ;;
    esac
done

echo ""
echo "Extensions: ${#EXTENSION_FILES[@]} file(s)"
echo "Resources: ${#RESOURCE_FILES[@]} file(s)"
echo ""

# If we have no resources to validate, we're done
if [ ${#RESOURCE_FILES[@]} -eq 0 ] && [ ${#EXTENSION_FILES[@]} -eq 0 ]; then
    echo "⚠ No files to validate"
elif [ ${#RESOURCE_FILES[@]} -eq 0 ]; then
    echo "⚠ Only extensions found, nothing to validate against them"
    SUCCESS_COUNT=${#EXTENSION_FILES[@]}
    VALIDATED_FILES=("${EXTENSION_FILES[@]}")
else
    # Run validation
    echo "==========================================="
    echo "Starting validation..."
    echo "==========================================="
    echo ""
    
    # Build the command
    # If we have extensions, use them; otherwise try to validate resources standalone
    if [ ${#EXTENSION_FILES[@]} -gt 0 ]; then
        # Join extension files with commas
        EXTENSIONS=$(IFS=,; echo "${EXTENSION_FILES[*]}")
        RESOURCES=$(IFS=,; echo "${RESOURCE_FILES[*]}")
        
        echo "Running: crossplane beta validate $EXTENSIONS $RESOURCES"
        
        if crossplane beta validate --cache-dir="$CACHE_DIR" "$EXTENSIONS" "$RESOURCES" > "$VALIDATION_OUTPUT" 2>&1; then
            VALIDATION_SUCCEEDED=true
        else
            VALIDATION_SUCCEEDED=false
        fi
    else
        # No extensions, try to validate resources alone (may need to download schemas)
        RESOURCES=$(IFS=,; echo "${RESOURCE_FILES[*]}")
        
        echo "Running: crossplane beta validate $RESOURCES (standalone)"
        echo "Note: This may fail if schemas are not available"
        
        if crossplane beta validate --cache-dir="$CACHE_DIR" "$RESOURCES" > "$VALIDATION_OUTPUT" 2>&1; then
            VALIDATION_SUCCEEDED=true
        else
            VALIDATION_SUCCEEDED=false
        fi
    fi
    
    # Show output
    cat "$VALIDATION_OUTPUT"
    echo ""
fi

# Parse the validation output
# The output format is typically:
# [✓] or [x] followed by resource info
# Example: [✓] apiextensions.crossplane.io/v1, Kind=CompositeResourceDefinition, my-xrd validated successfully
# Example: [x] schema validation error ...

if [ -n "$VALIDATION_OUTPUT" ] && [ -f "$VALIDATION_OUTPUT" ]; then
    while IFS= read -r line; do
        if [[ "$line" =~ ^\[✓\] ]]; then
            # Success line
            ((SUCCESS_COUNT++))
            # Extract filename or resource name
            if [[ "$line" =~ Kind=([^,]+),\ ([^\ ]+) ]]; then
                resource_name="${BASH_REMATCH[2]}"
                VALIDATED_FILES+=("$resource_name")
            fi
        elif [[ "$line" =~ ^\[x\] ]]; then
            # Failure line
            ((FAILURE_COUNT++))
            # Extract error message
            error_msg=$(echo "$line" | sed 's/^\[x\] //')
            ERROR_MESSAGES+=("$error_msg")
            
            # Try to extract filename
            if [[ "$line" =~ Kind=([^,]+),\ ([^\ ]+) ]]; then
                resource_name="${BASH_REMATCH[2]}"
                FAILED_FILES+=("$resource_name")
            fi
        elif [[ "$line" =~ "missing schemas" ]]; then
            # Extract missing schema count
            if [[ "$line" =~ ([0-9]+)\ missing\ schemas ]]; then
                MISSING_SCHEMA_COUNT="${BASH_REMATCH[1]}"
            fi
        fi
    done < "$VALIDATION_OUTPUT"
fi

# If we have files but no success/failure counts, fall back to simple counting
if [ $SUCCESS_COUNT -eq 0 ] && [ $FAILURE_COUNT -eq 0 ]; then
    if [ "$VALIDATION_SUCCEEDED" = true ]; then
        SUCCESS_COUNT=${#FILES_TO_VALIDATE[@]}
        VALIDATED_FILES=("${FILES_TO_VALIDATE[@]}")
    else
        FAILURE_COUNT=${#FILES_TO_VALIDATE[@]}
        FAILED_FILES=("${FILES_TO_VALIDATE[@]}")
    fi
fi

echo ""
echo "==========================================="
echo "Validation Summary"
echo "==========================================="
echo "Total files: ${#FILES_TO_VALIDATE[@]}"
echo "✅ Successful: $SUCCESS_COUNT"
echo "❌ Failed: $FAILURE_COUNT"
echo "⚠ Missing schemas: $MISSING_SCHEMA_COUNT"
echo ""

# Output detailed errors if any
if [ $FAILURE_COUNT -gt 0 ]; then
    echo "Validation Errors:"
    for error in "${ERROR_MESSAGES[@]}"; do
        echo "  ❌ $error"
    done
    echo ""
fi

# Create JSON output for validated files
validated_files_json="["
for i in "${!VALIDATED_FILES[@]}"; do
    if [ $i -gt 0 ]; then
        validated_files_json+=","
    fi
    escaped="${VALIDATED_FILES[$i]//\"/\\\"}"
    validated_files_json+="\"$escaped\""
done
validated_files_json+="]"

# Create validation result summary
if [ $FAILURE_COUNT -eq 0 ]; then
    VALIDATION_RESULT="✅ All $SUCCESS_COUNT file(s) validated successfully"
else
    VALIDATION_RESULT="❌ $FAILURE_COUNT file(s) failed validation, $SUCCESS_COUNT passed"
fi

# Output to GitHub Actions
echo "validated-files=$validated_files_json" >> "$GITHUB_OUTPUT"
echo "validation-result=$VALIDATION_RESULT" >> "$GITHUB_OUTPUT"
echo "success-count=$SUCCESS_COUNT" >> "$GITHUB_OUTPUT"
echo "failure-count=$FAILURE_COUNT" >> "$GITHUB_OUTPUT"

# Create GitHub Actions summary
{
    echo "## Crossplane Validation Results"
    echo ""
    echo "| Metric | Count |"
    echo "|--------|-------|"
    echo "| Total Files | ${#FILES_TO_VALIDATE[@]} |"
    echo "| ✅ Passed | $SUCCESS_COUNT |"
    echo "| ❌ Failed | $FAILURE_COUNT |"
    echo "| ⚠ Missing Schemas | $MISSING_SCHEMA_COUNT |"
    echo ""
    
    if [ $FAILURE_COUNT -gt 0 ]; then
        echo "### ❌ Validation Errors"
        echo ""
        for error in "${ERROR_MESSAGES[@]}"; do
            echo "- $error"
        done
        echo ""
    fi
    
    if [ $SUCCESS_COUNT -gt 0 ]; then
        echo "### ✅ Successfully Validated Files"
        echo ""
        for file in "${VALIDATED_FILES[@]}"; do
            echo "- $file"
        done
        echo ""
    fi
} >> "$GITHUB_STEP_SUMMARY"

# Exit with error if validation failed and fail-on-error is true
if [ $FAILURE_COUNT -gt 0 ] && [ "$FAIL_ON_ERROR" = "true" ]; then
    echo ""
    echo "❌ Validation failed with $FAILURE_COUNT error(s)"
    exit 1
fi

if [ $FAILURE_COUNT -gt 0 ]; then
    echo ""
    echo "⚠ Validation failed but continuing (fail-on-error=false)"
fi

echo ""
echo "✅ Validation complete!"
