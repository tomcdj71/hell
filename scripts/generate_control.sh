#!/usr/bin/env bash
# generate_control.sh - Script to generate control file for a Debian package
set -e

# Parse options
NO_CHECK=false
for arg in "$@"; do
  case $arg in
    --no-check)
      NO_CHECK=true
      shift
      ;;
    *)
      ;;
  esac
done

# Script arguments
PACKAGE_NAME="$1"
INSTALL_DIR="$2"
TMPDIR="$3"
FULL_VERSION="$4"
CURRENT_DATE="$5"
POOL_PATH="$6"
PACKAGE_DIR="${TMPDIR}/package/${PACKAGE_NAME}"
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
echo "POOL_PATH: $POOL_PATH"
echo "PACKAGE_DIR: $PACKAGE_DIR"
echo "NO_CHECK: $NO_CHECK"
echo "=================="

# Find the correct package file
echo "Attempting to find package file matching: ${PACKAGE_NAME}"
PACKAGE_FILE=$(find "$TMPDIR" -type f -name "${PACKAGE_NAME}*" -print -quit)

if [ -z "$PACKAGE_FILE" ]; then
  echo "Error: Package file for $PACKAGE_NAME not found in $TMPDIR"
  echo "Contents of TMPDIR:"
  tree -L 2 "$TMPDIR"
  echo "Exiting with error."
  exit 1
fi

PACKAGE_FILE=$(basename "$PACKAGE_FILE")
echo "Found package file: $PACKAGE_FILE"

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
elif [ "$PACKAGE_NAME" == "libtorrent21t64-nightly" ]; then
  echo "Modifying control fields for $PACKAGE_NAME"
  sed -i "s/^Package: .*/Package: libtorrent21t64/" "$control_file"
  sed -i "s/^Provides: .*/Provides: libtorrent21 (= $FULL_VERSION)/" "$control_file"
  sed -i "s/^Breaks: .*/Breaks: libtorrent21t64 (<< $FULL_VERSION)/" "$control_file"
  sed -i "s/^Replaces: .*/Replaces: libtorrent21t64/" "$control_file"
elif [ "$PACKAGE_NAME" == "libtorrent-dev-nightly" ]; then
  echo "Modifying Depends field for $PACKAGE_NAME"
  sed -i "s/libtorrent21t64/libtorrent/g" "$control_file"
fi
current_version=$(grep "^Version:" "$control_file" | awk '{print $2}')
sed -i "s/$current_version/$FULL_VERSION/g" "$control_file"
# Reordering the Description field in the control file
echo "Reordering Description field in \"$control_file\""
desc_file="${control_file}.description"
tmp_file="${control_file}.tmp"
awk -v desc_file="$desc_file" -v tmp_file="$tmp_file" '
BEGIN { in_desc=0 }
# Start capturing Description
/^Description:/ { in_desc=1; print > desc_file; next }
# Stop capturing Description at the next non-indented line
/^[^ ]/ { if (in_desc==1) { in_desc=0 } }
# Write to the description file if in_desc is active
in_desc==1 { print > desc_file }
# Write everything else to the temp file
in_desc==0 { print > tmp_file }
' "$control_file"

# Overwrite the control file with reordered content
mv "$tmp_file" "$control_file"
cat "$desc_file" >> "$control_file"
rm -f "$desc_file"

echo "Contents of \"$control_file\" after modification:"
cat "$control_file"


# Extract package contents
echo "Extracting package contents to $PACKAGE_DIR"
sudo dpkg -x "$TMPDIR/$PACKAGE_FILE" "$PACKAGE_DIR" || {
  echo "Error running dpkg -x on $TMPDIR/$PACKAGE_FILE"
  exit 1
}

if [ "$NO_CHECK" == true ]; then
  rm -f "$TMPDIR/$PACKAGE_FILE"
fi

sudo chown -R "$USERNAME:$USERNAME" "$PACKAGE_DIR"

cd "$PACKAGE_DIR"

if [ "$NO_CHECK" = false ]; then
  control_file="DEBIAN/control"
  old_installed_size=$(grep "^Installed-Size:" "$control_file" | awk '{print $2}')
  echo "Performing rsync to merge installation files..."
  rsync -auv --existing "$INSTALL_DIR/" "./"
  installed_size=$(du -sk . | cut -f1)
  echo "Old Installed-Size: $old_installed_size kB"
  echo "New Installed-Size: $installed_size kB"
  sed -i "s/^Installed-Size: .*/Installed-Size: $installed_size/" "$control_file"
  rm -f DEBIAN/md5sums
  find . -type f ! -path './DEBIAN/*' -exec md5sum {} \; > DEBIAN/md5sums
fi

cd - > /dev/null

# Build the package
PACKAGE_FILE_BUILT="${PACKAGE_NAME}_${FULL_VERSION}_amd64.deb"
dpkg-deb --build "$PACKAGE_DIR" "$PACKAGE_FILE_BUILT" || {
  echo "Error building package: $PACKAGE_NAME"
  exit 1
}

mkdir -p "$POOL_PATH"
# Move the package to POOL_PATH
echo "Moving package from $PACKAGE_FILE_BUILT to $POOL_PATH"
mv "$PACKAGE_FILE_BUILT" "$POOL_PATH/" || {
  echo "Error moving package: $PACKAGE_FILE_BUILT"
  exit 1
}

echo "$PACKAGE_FILE_BUILT moved to $POOL_PATH"

# Compute the checksum
CHECKSUM=$(sha256sum "$POOL_PATH/$PACKAGE_FILE_BUILT" | awk '{ print $1 }')
echo "Checksum for $PACKAGE_NAME: $CHECKSUM"

# Write the checksum to a file
mkdir -p "$TMPDIR/checksums"
echo "$CHECKSUM" > "$TMPDIR/checksums/${PACKAGE_NAME}.sha256"
PACKAGE_NAME_CHECKSUM=$(cat "$TMPDIR/checksums/${PACKAGE_NAME}.sha256")
echo "Checksum written to $TMPDIR/checksums/${PACKAGE_NAME}.sha256"
echo "Checksum for $PACKAGE_NAME: $PACKAGE_NAME_CHECKSUM"
echo "Completed processing and packaging for $PACKAGE_NAME"
export PACKAGE_NAME_CHECKSUM
