#!/bin/sh
# Builds and runs the headless engine tests.  Add "win" to cross-compile and run them under wine too.
set -e
cd "$(dirname "$0")/.."
mkdir -p build/units build/test
fpc -Mobjfpc -Sh -O1 -FUbuild/units -Fusrc -FEbuild/test -obuild/test/test_engine tests/test_engine.pas >build/test/compile.log 2>&1 \
  || { cat build/test/compile.log; exit 1; }
./build/test/test_engine
if [ "$1" = "win" ]; then
  mkdir -p build/units-win
  fpc -Twin64 -Px86_64 -Mobjfpc -Sh -O1 -FUbuild/units-win -Fusrc -FEbuild/test -obuild/test/test_engine.exe tests/test_engine.pas >build/test/compile-win.log 2>&1 \
    || { cat build/test/compile-win.log; exit 1; }
  WINEDEBUG=-all wine build/test/test_engine.exe
fi
