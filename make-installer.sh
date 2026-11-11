#!/bin/sh
# Builds dist/tiesheet-setup.exe (needs fpc with win64 units, curl, unzip and makensis).
set -e
cd "$(dirname "$0")"
./build-windows.sh
./fetch-windows-dlls.sh
VERSION=$(sed -n "s/^  Version = '\(.*\)';/\1/p" src/tiesheet.lpr)
mkdir -p dist
makensis -V2 -DVERSION="$VERSION" packaging/windows/installer.nsi
echo "Built: dist/tiesheet-setup.exe ($VERSION)"
