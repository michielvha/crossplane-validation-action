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

# Filter out empty strings from the array
FILES_TO_VALIDATE=("${FILES_TO_VALIDATE[@]//^$/}")

if [ ${#FILES_TO_VALIDATE[@]} -eq 0 ] || [ -z "${FILES_TO_VALIDATE[0]}" ]; then
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

# If we have resources but no extensions, intelligently find dependencies
if [ ${#RESOURCE_FILES[@]} -gt 0 ] && [ ${#EXTENSION_FILES[@]} -eq 0 ]; then
    echo "Building dependency graph for changed resources..."
    echo ""
    
    # Analyze each Composition to find what it needs
    for resource_file in "${RESOURCE_FILES[@]}"; do
        KIND=$(grep -E "^kind:\s*" "$resource_file" | head -n 1 | awk '{print $2}' | tr -d '\r\n' || echo "")
        
        if [ "$KIND" = "Composition" ]; then
            echo "📋 Analyzing Composition: $resource_file"
            
            # 1. Find the XRD this Composition references (compositeTypeRef)
            XRD_KIND=$(grep -A 3 "compositeTypeRef:" "$resource_file" | grep "kind:" | awk '{print $2}' | tr -d '\r\n' || echo "")
            
            if [ -n "$XRD_KIND" ]; then
                echo "  → Needs XRD that defines: $XRD_KIND"
                
                # Search for matching XRD
                while IFS= read -r -d '' xrd_file; do
                    FILE_KIND=$(grep -E "^kind:\s*" "$xrd_file" | awk '{print $2}' | tr -d '\r\n')
                    if [ "$FILE_KIND" = "CompositeResourceDefinition" ]; then
                        # Check if this XRD defines our needed kind
                        XRD_DEFINES=$(grep -A 10 "names:" "$xrd_file" | grep "kind:" | head -n 1 | awk '{print $2}' | tr -d '\r\n')
                        if [ "$XRD_DEFINES" = "$XRD_KIND" ]; then
                            echo "  ✓ Found XRD: $xrd_file"
                            EXTENSION_FILES+=("$xrd_file")
                            break
                        fi
                    fi
                done < <(find . -type f \( -name "*.yaml" -o -name "*.yml" \) ! -path "./.crossplane/*" ! -path "./.git/*" -print0 2>/dev/null)
            fi
            
            # 2. Find Providers for managed resources (based on apiVersion)
            echo "  → Analyzing managed resources..."
            API_VERSIONS=$(grep -E "apiVersion:\s+" "$resource_file" | grep -v "apiextensions.crossplane.io" | grep -v "pkg.crossplane.io" | awk '{print $2}' | sort -u)
            
            for api_version in $API_VERSIONS; do
                # Extract provider hint (e.g., "ec2.aws.upbound.io/v1beta1" -> "aws")
                if [[ "$api_version" =~ ([a-z0-9]+)\.(upbound\.io|crossplane\.io) ]]; then
                    provider_hint="${BASH_REMATCH[1]}"
                    echo "    • Uses $api_version (provider: $provider_hint)"
                    
                    # Find matching Provider
                    while IFS= read -r -d '' prov_file; do
                        FILE_KIND=$(grep -E "^kind:\s*" "$prov_file" | awk '{print $2}' | tr -d '\r\n')
                        if [ "$FILE_KIND" = "Provider" ] || [ "$FILE_KIND" = "Configuration" ]; then
                            PACKAGE=$(grep "package:" "$prov_file" | awk '{print $2}' | tr -d '\r\n')
                            if [[ "$PACKAGE" =~ $provider_hint ]]; then
                                echo "    ✓ Found Provider: $prov_file"
                                if [[ ! " ${EXTENSION_FILES[@]} " =~ " ${prov_file} " ]]; then
                                    EXTENSION_FILES+=("$prov_file")
                                fi
                                break
                            fi
                        fi
                    done < <(find . -type f \( -name "*.yaml" -o -name "*.yml" \) ! -path "./.crossplane/*" ! -path "./.git/*" -print0 2>/dev/null)
                fi
            done
        fi
    done
    
    echo ""
    echo "✓ Found ${#EXTENSION_FILES[@]} required extension(s)"
    echo ""
fi

# Validation logic
if [ ${#RESOURCE_FILES[@]} -eq 0 ] && [ ${#EXTENSION_FILES[@]} -eq 0 ]; then
    echo "⚠ No files to validate"
    
    # Still write summary
    {
        echo "## Crossplane Validation Results"
        echo ""
        echo "| Metric | Count |"
        echo "|--------|-------|"
        echo "| Total Files | 0 |"
        echo "| ✅ Passed | 0 |"
        echo "| ❌ Failed | 0 |"
        echo "| ⚠ Missing Schemas | 0 |"
        echo ""
        echo "ℹ️ No Crossplane files changed in this commit."
    } >> "$GITHUB_STEP_SUMMARY"
    
    echo "validated-files=[]" >> "$GITHUB_OUTPUT"
    echo "validation-result=No Crossplane files to validate" >> "$GITHUB_OUTPUT"
    echo "success-count=0" >> "$GITHUB_OUTPUT"
    echo "failure-count=0" >> "$GITHUB_OUTPUT"
    echo "✅ Validation complete!"
    exit 0
elif [ ${#RESOURCE_FILES[@]} -eq 0 ]; then
    echo "⚠ Only extensions found, nothing to validate against them"
    SUCCESS_COUNT=${#EXTENSION_FILES[@]}
    VALIDATED_FILES=("${EXTENSION_FILES[@]}")
elif [ ${#EXTENSION_FILES[@]} -eq 0 ]; then
    echo "❌ No XRDs or Providers found to validate Compositions against"
    echo ""
    echo "To validate Compositions, you need:"
    echo "  1. An XRD (CompositeResourceDefinition) that defines the resource"
    echo "  2. A Provider that provides the managed resource schemas"
    echo ""
    FAILURE_COUNT=${#RESOURCE_FILES[@]}
    FAILED_FILES=("${RESOURCE_FILES[@]}")
else
    # Run validation
    echo "==========================================="
    echo "Starting validation..."
    echo "==========================================="
    echo ""
    
    # Join files with commas
    EXTENSIONS=$(IFS=,; echo "${EXTENSION_FILES[*]}")
    RESOURCES=$(IFS=,; echo "${RESOURCE_FILES[*]}")
    
    echo "Running: crossplane beta validate \"$EXTENSIONS\" \"$RESOURCES\""
    echo ""
    
    # Run validation and capture exit code (don't exit on failure due to set -e)
    set +e
    crossplane beta validate --cache-dir="$CACHE_DIR" "$EXTENSIONS" "$RESOURCES" > "$VALIDATION_OUTPUT" 2>&1
    VALIDATION_EXIT_CODE=$?
    set -e
    
    if [ $VALIDATION_EXIT_CODE -eq 0 ]; then
        VALIDATION_SUCCEEDED=true
    else
        VALIDATION_SUCCEEDED=false
    fi
    
    cat "$VALIDATION_OUTPUT"
    echo ""
fi

# Disable set -e for the rest of the script to ensure we always write outputs
set +e

# Parse validation output
if [ -n "$VALIDATION_OUTPUT" ] && [ -f "$VALIDATION_OUTPUT" ]; then
    while IFS= read -r line; do
        if [[ "$line" =~ ^\[✓\] ]]; then
            ((SUCCESS_COUNT++))
            if [[ "$line" =~ Kind=([^,]+),\ ([^\ ]+) ]]; then
                VALIDATED_FILES+=("${BASH_REMATCH[2]}")
            fi
        elif [[ "$line" =~ ^\[x\] ]]; then
            ((FAILURE_COUNT++))
            error_msg=$(echo "$line" | sed 's/^\[x\] //')
            ERROR_MESSAGES+=("$error_msg")
            if [[ "$line" =~ Kind=([^,]+),\ ([^\ ]+) ]]; then
                FAILED_FILES+=("${BASH_REMATCH[2]}")
            fi
        elif [[ "$line" =~ "missing schemas" ]]; then
            if [[ "$line" =~ ([0-9]+)\ missing\ schemas ]]; then
                MISSING_SCHEMA_COUNT="${BASH_REMATCH[1]}"
            fi
        fi
    done < "$VALIDATION_OUTPUT"
fi

# Fallback counting
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

# Output errors
if [ $FAILURE_COUNT -gt 0 ]; then
    echo "Validation Errors:"
    for error in "${ERROR_MESSAGES[@]}"; do
        echo "  ❌ $error"
    done
    echo ""
fi

# JSON output
validated_files_json="["
for i in "${!VALIDATED_FILES[@]}"; do
    [ $i -gt 0 ] && validated_files_json+=","
    escaped="${VALIDATED_FILES[$i]//\"/\\\"}"
    validated_files_json+="\"$escaped\""
done
validated_files_json+="]"

# Result summary
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

# GitHub Actions summary
if [ -z "$GITHUB_STEP_SUMMARY" ]; then
    echo "⚠ Warning: GITHUB_STEP_SUMMARY not set, cannot write summary"
    GITHUB_STEP_SUMMARY="/dev/null"
fi

echo "Writing summary to: $GITHUB_STEP_SUMMARY"

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

echo "✓ Summary written successfully"

# Exit based on fail-on-error
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
