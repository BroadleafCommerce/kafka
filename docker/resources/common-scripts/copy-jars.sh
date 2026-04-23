#!/usr/bin/env bash
#
# Copies files from SOURCE to TARGET.
# 1. If JAR exists in TARGET (ignoring version), skip.
# 2. If JAR exists in ADDITIONAL_CHECK_DIR (ignoring version), copy the version from ADDITIONAL_CHECK_DIR to TARGET.
# 3. Otherwise, copy from SOURCE to TARGET.
#
# Usage: copy-jars.sh <SOURCE_DIR> <TARGET_DIR> [ADDITIONAL_CHECK_DIR]

set -e

SOURCE_DIR="$1"
TARGET_DIR="$2"
ADDITIONAL_CHECK_DIR="$3"

if [ -z "$SOURCE_DIR" ] || [ -z "$TARGET_DIR" ]; then
    echo "Usage: $0 <SOURCE_DIR> <TARGET_DIR> [ADDITIONAL_CHECK_DIR]"
    exit 1
fi

# Ensure target exists
mkdir -p "$TARGET_DIR"

echo "Copying files from $SOURCE_DIR to $TARGET_DIR with version deduplication..."
if [ -n "$ADDITIONAL_CHECK_DIR" ]; then
    echo "Also checking for duplicates in $ADDITIONAL_CHECK_DIR"
fi

# Helper to extract base name (artifact ID)
get_base_name() {
    local filename=$1
    # Remove version suffix starting with a hyphen followed by a digit
    echo "$filename" | sed -E 's/-[0-9].*\.jar$//'
}

# Process JAR files
# We use a loop over the glob to handle filenames with spaces correctly
shopt -s nullglob
for src_jar in "$SOURCE_DIR"/*.jar; do
    filename=$(basename "$src_jar")
    base_name=$(get_base_name "$filename")

    duplicate_in_target=false

    # Check against all jars in target
    for target_jar in "$TARGET_DIR"/*.jar; do
        t_filename=$(basename "$target_jar")
        t_base_name=$(get_base_name "$t_filename")

        if [ "$base_name" == "$t_base_name" ]; then
            echo "Skipping $filename (duplicate of $t_filename in target)"
            duplicate_in_target=true
            break
        fi
    done

    if [ "$duplicate_in_target" = true ]; then
        continue
    fi

    # Check additional directory if provided
    copied_from_additional=false
    if [ -n "$ADDITIONAL_CHECK_DIR" ] && [ -d "$ADDITIONAL_CHECK_DIR" ]; then
        for check_jar in "$ADDITIONAL_CHECK_DIR"/*.jar; do
            c_filename=$(basename "$check_jar")
            c_base_name=$(get_base_name "$c_filename")

            if [ "$base_name" == "$c_base_name" ]; then
                echo "Found duplicate in additional dir: $c_filename. Copying that version to target."
                cp "$check_jar" "$TARGET_DIR/"
                copied_from_additional=true
                break
            fi
        done
    fi

    if [ "$copied_from_additional" = false ]; then
        echo "Copying $filename"
        cp "$src_jar" "$TARGET_DIR/"
    fi
done

# Process non-JAR files and directories
# We copy them if they don't exist in target (exact name match)
for src_file in "$SOURCE_DIR"/*; do
    filename=$(basename "$src_file")

    # Skip if it's a jar (already handled)
    if [[ "$filename" == *.jar ]]; then
        continue
    fi

    if [ ! -e "$TARGET_DIR/$filename" ]; then
        echo "Copying $filename"
        cp -r "$src_file" "$TARGET_DIR/"
    else
        echo "Skipping $filename (exists)"
    fi
done
