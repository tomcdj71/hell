#!/usr/bin/env bash
set -e

# Usage: package_single.sh <package_name> <install_dir> <tmpdir> <full_version> <current_date>

# Input parameters
PACKAGE_NAME="$1"
INSTALL_DIR="$2"
TMPDIR="$3"
FULL_VERSION="$4"
CURRENT_DATE="$5"

# Map package name to package directory
PACKAGE_DIR="package/${PACKAGE_NAME}"

# Get username
USERNAME=$(whoami)

# Create package directory
mkdir -p "$PACKAGE_DIR/DEBIAN"

# Find the package file in tmpdir
PACKAGE_FILE=$(ls "$TMPDIR" | grep "^${PACKAGE_NAME}_")

if [ -z "$PACKAGE_FILE" ]; then
  echo "Error: Package file for $PACKAGE_NAME not found in $TMPDIR"
  exit 1
fi

# Step 1: Extract control files and modify dependencies
echo "Processing package $PACKAGE_FILE, package name is $PACKAGE_NAME, dest_dir is $PACKAGE_DIR"

sudo dpkg -e "$TMPDIR/$PACKAGE_FILE" "$PACKAGE_DIR/DEBIAN"
sudo chown -R "$USERNAME:$USERNAME" "$PACKAGE_DIR"
control_file="$PACKAGE_DIR/DEBIAN/control"

# Append COPYRIGHT message
COPYRIGHT=" .
   Packaged by MediaEase on $CURRENT_DATE."
echo "$COPYRIGHT" >> "$control_file"

# Modify the 'Depends' field to lock to current version
if [ "$PACKAGE_NAME" == "libtorrent-rasterbar-dev" ]; then
  sed -i "s/^\(Depends:.*libtorrent-rasterbar2.*(=\s*\)[^)]*\()\)/\1$FULL_VERSION\2/" "$control_file"
elif [ "$PACKAGE_NAME" == "python3-libtorrent" ]; then
  sed -i "s/^\(Depends:.*libtorrent-rasterbar2.*(>=\s*\)[^)]*\()\)/\1$FULL_VERSION\2/" "$control_file"
fi

cat "$control_file"

# Extract package files
sudo dpkg -x "$TMPDIR/$PACKAGE_FILE" "$PACKAGE_DIR"
sudo chown -R "$USERNAME:$USERNAME" "$PACKAGE_DIR"

# Step 2: Copy compiled files into package directory and update Installed-Size
echo "Processing package: $PACKAGE_NAME"

# Ensure we are in the correct directory
cd "$PACKAGE_DIR"

# Ensure DEBIAN directory exists
mkdir -p DEBIAN
control_file="DEBIAN/control"

# Extract old Installed-Size from control file
old_installed_size=$(grep "^Installed-Size:" "$control_file" | awk '{print $2}')

# Copy files from INSTALL_DIR to package directory
rsync -auv --existing "$INSTALL_DIR/" "./"

# Calculate new installed size
installed_size=$(du -sk . | cut -f1)

# Compare and output the sizes
echo "Old Installed-Size: $old_installed_size kB"
echo "New Installed-Size: $installed_size kB"

# Update Installed-Size in control file
sed -i "s/^Installed-Size: .*/Installed-Size: $installed_size/" "$control_file"

# Generate md5sums for the package
echo "Generating md5sums for $PACKAGE_NAME"
rm -f DEBIAN/md5sums
find . -type f ! -path './DEBIAN/*' -exec md5sum {} \; > DEBIAN/md5sums

# Return to the previous directory
cd - > /dev/null