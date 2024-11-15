#!/usr/bin/env bash
set -e
PACKAGE_NAME="$1"
INSTALL_DIR="$2"
TMPDIR="$3"
FULL_VERSION="$4"
CURRENT_DATE="$5"
PACKAGE_DIR="package/${PACKAGE_NAME}"
USERNAME=$(whoami)

# Create necessary directories
mkdir -p "$PACKAGE_DIR/DEBIAN"

echo "Debug Information:"
echo "=================="
echo "PACKAGE_NAME: $PACKAGE_NAME"
echo "INSTALL_DIR: $INSTALL_DIR"
echo "TMPDIR: $TMPDIR"
echo "FULL_VERSION: $FULL_VERSION"
echo "CURRENT_DATE: $CURRENT_DATE"
echo "PACKAGE_DIR: $PACKAGE_DIR"
echo "TMPDIR Content:"
ls -lah "$TMPDIR"
echo "=================="

# Find the correct package file
echo "Attempting to find package file matching: ${PACKAGE_NAME}"
PACKAGE_FILE=$(find "$TMPDIR" -type f -name "${PACKAGE_NAME}" -print -quit)

if [ -z "$PACKAGE_FILE" ]; then
  echo "Error: Package file for $PACKAGE_NAME not found in $TMPDIR"
  echo "Contents of TMPDIR:"
  tree -L 2 "$TMPDIR"
  echo "Exiting with error."
  exit 1
fi

PACKAGE_FILE=$(basename "$PACKAGE_FILE")
echo "Found package file: $PACKAGE_FILE"
echo "Processing package $PACKAGE_FILE, package name is $PACKAGE_NAME, dest_dir is $PACKAGE_DIR"

# Extract package metadata
sudo dpkg -e "$TMPDIR/$PACKAGE_FILE" "$PACKAGE_DIR/DEBIAN" || {
  echo "Error running dpkg -e on $TMPDIR/$PACKAGE_FILE"
  exit 1
}

sudo chown -R "$USERNAME:$USERNAME" "$PACKAGE_DIR"

control_file="$PACKAGE_DIR/DEBIAN/control"
COPYRIGHT=" .
   Packaged by MediaEase on $CURRENT_DATE."
echo "$COPYRIGHT" >> "$control_file"

# Modify the 'Depends' field to lock to current version
if [ "$PACKAGE_NAME" == "libtorrent-rasterbar-dev" ]; then
  echo "Modifying 'Depends' field for $PACKAGE_NAME"
  sed -i "s/^\(Depends:.*libtorrent-rasterbar2.*(=\s*\)[^)]*\()\)/\1$FULL_VERSION\2/" "$control_file"
elif [ "$PACKAGE_NAME" == "python3-libtorrent" ]; then
  echo "Modifying 'Depends' field for $PACKAGE_NAME"
  sed -i "s/^\(Depends:.*libtorrent-rasterbar2.*(>=\s*\)[^)]*\()\)/\1$FULL_VERSION\2/" "$control_file"
fi

echo "Contents of $control_file after modification:"
cat "$control_file"

# Extract package contents
echo "Extracting package contents to $PACKAGE_DIR"
sudo dpkg -x "$TMPDIR/$PACKAGE_FILE" "$PACKAGE_DIR" || {
  echo "Error running dpkg -x on $TMPDIR/$PACKAGE_FILE"
  exit 1
}

sudo chown -R "$USERNAME:$USERNAME" "$PACKAGE_DIR"
echo "Processing package: $PACKAGE_NAME"

cd "$PACKAGE_DIR"
control_file="DEBIAN/control"

# Update installed size
old_installed_size=$(grep "^Installed-Size:" "$control_file" | awk '{print $2}')
rsync -auv --existing "$INSTALL_DIR/" "./"
installed_size=$(du -sk . | cut -f1)
echo "Old Installed-Size: $old_installed_size kB"
echo "New Installed-Size: $installed_size kB"
sed -i "s/^Installed-Size: .*/Installed-Size: $installed_size/" "$control_file"

echo "Generating md5sums for $PACKAGE_NAME"
rm -f DEBIAN/md5sums
find . -type f ! -path './DEBIAN/*' -exec md5sum {} \; > DEBIAN/md5sums

# Return to the previous directory
cd - > /dev/null

echo "Completed processing for $PACKAGE_NAME"
