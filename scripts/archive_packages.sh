#!/bin/bash

# Define paths
CURRENT_DIR=$1
ARCHIVE_DIR=$2
PACKAGE_PATH=$3

# Ensure the archive and current directories exist
mkdir -p "$ARCHIVE_DIR"
mkdir -p "$CURRENT_DIR"

# Extract package name and version from the package metadata
PACKAGE_NAME=$(dpkg-deb -f "$PACKAGE_PATH" Package)

# Define the directory for the package in the current directory
PACKAGE_CURRENT_DIR="${CURRENT_DIR}"

# Define the pattern to find existing packages of the same name
PACKAGE_PATTERN="${PACKAGE_NAME}*.deb"

# Check if there's an existing package in the current directory
EXISTING_PACKAGE=$(find "$PACKAGE_CURRENT_DIR" -maxdepth 1 -name "$PACKAGE_PATTERN" -print -quit)
if [ -n "$EXISTING_PACKAGE" ]; then
    EXISTING_PACKAGE_BASENAME=$(basename "$EXISTING_PACKAGE")
    EXISTING_PACKAGE_PATH="$PACKAGE_CURRENT_DIR/$EXISTING_PACKAGE_BASENAME"
    NEW_CHECKSUM=$(sha256sum "$PACKAGE_PATH" | awk '{ print $1 }')
    EXISTING_CHECKSUM=$(sha256sum "$EXISTING_PACKAGE_PATH" | awk '{ print $1 }')
    if [ "$NEW_CHECKSUM" != "$EXISTING_CHECKSUM" ]; then
        echo "Checksums differ. Archiving the existing package."
        # Archive the existing package
        mv "$EXISTING_PACKAGE_PATH" "$ARCHIVE_DIR/"
        echo "Archived existing package to $ARCHIVE_DIR."
        # Move the new package to the specific package's current directory
        mv "$PACKAGE_PATH" "$PACKAGE_CURRENT_DIR/"
        echo "Moved new package to $PACKAGE_CURRENT_DIR."
    else
        echo "Checksums are the same. Skipping archival and move."
    fi
else
    echo "No existing package found for $PACKAGE_NAME. Moving the new package."
    # Move the new package to the specific package's current directory
    mv "$PACKAGE_PATH" "$PACKAGE_CURRENT_DIR/"
    echo "Moved new package to $PACKAGE_CURRENT_DIR."
fi
