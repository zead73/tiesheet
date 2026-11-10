#!/bin/sh
# Builds the Linux version into build/tiesheet
set -e
cd "$(dirname "$0")"
mkdir -p build/units
fpc -Mobjfpc -Sh -O2 -Xs -FUbuild/units -Fusrc -FEbuild -otiesheet src/tiesheet.lpr
echo "Built: build/tiesheet"
