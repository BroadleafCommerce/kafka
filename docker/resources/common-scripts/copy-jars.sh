#!/usr/bin/env bash
#
# Copies files from SOURCE to TARGET.
# 1. If JAR exists in TARGET (ignoring version), skip.
# 2. If JAR exists in ADDITIONAL_CHECK_DIR (ignoring version), copy the version from ADDITIONAL_CHECK_DIR to TARGET.
# 3. Otherwise, copy from SOURCE to TARGET.
#
# Usage: copy-jars.sh <SOURCE_DIR> <TARGET_DIR> [ADDITIONAL_CHECK_DIR]
#
# Implementation note: name matching is done with pure bash builtins (parameter
# expansion + an associative-array index), so the only subprocesses spawned are
# the actual `cp` calls. The previous version shelled out to `basename` and
# `sed` inside an O(N*M) nested loop (~tens of thousands of process spawns),
# which is catastrophically slow when this stage runs under QEMU emulation
# (e.g. building the linux/amd64 image on an Apple Silicon host). Keep it
# fork-free.

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

# Extract the base name (artifact ID) by stripping the version suffix: the first
# '-' followed by a digit, through the trailing '.jar'. Mirrors the original
# `sed -E 's/-[0-9].*\.jar$//'` (leftmost match). Returns the result in the
# global variable 'base_name'. Deliberately no subshell / no fork.
strip_version() {
    local filename=$1
    base_name=$filename
    [[ $filename == *.jar ]] || return 0
    local n=${#filename} i
    for (( i = 0; i < n - 1; i++ )); do
        if [[ ${filename:i:1} == "-" && ${filename:i+1:1} == [0-9] ]]; then
            base_name=${filename:0:i}
            return 0
        fi
    done
}

shopt -s nullglob

# Index existing target jars by base name (built once: O(targets)).
declare -A target_index=()
for target_jar in "$TARGET_DIR"/*.jar; do
    strip_version "${target_jar##*/}"
    target_index[$base_name]=1
done

# Index additional-check jars by base name -> full path (first match wins, as before).
declare -A additional_index=()
if [ -n "$ADDITIONAL_CHECK_DIR" ] && [ -d "$ADDITIONAL_CHECK_DIR" ]; then
    for check_jar in "$ADDITIONAL_CHECK_DIR"/*.jar; do
        strip_version "${check_jar##*/}"
        [ -n "${additional_index[$base_name]+x}" ] || additional_index[$base_name]=$check_jar
    done
fi

# Process JAR files.
for src_jar in "$SOURCE_DIR"/*.jar; do
    filename=${src_jar##*/}
    strip_version "$filename"
    sbase=$base_name

    # 1. Already present in target (ignoring version) -> skip.
    #    target_index is updated as we copy, so two versions of the same artifact
    #    within SOURCE dedupe against each other (first one wins) -- matching the
    #    original "re-scan the target dir each iteration" behavior.
    if [ -n "${target_index[$sbase]+x}" ]; then
        echo "Skipping $filename (duplicate in target)"
        continue
    fi

    # 2. Present in the additional-check dir -> prefer that version.
    if [ -n "${additional_index[$sbase]+x}" ]; then
        check_jar=${additional_index[$sbase]}
        echo "Found duplicate in additional dir: ${check_jar##*/}. Copying that version to target."
        cp "$check_jar" "$TARGET_DIR/"
    else
        # 3. Otherwise copy from source.
        echo "Copying $filename"
        cp "$src_jar" "$TARGET_DIR/"
    fi

    target_index[$sbase]=1
done

# Process non-JAR files and directories
# We copy them if they don't exist in target (exact name match)
for src_file in "$SOURCE_DIR"/*; do
    filename=${src_file##*/}

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
