#!/bin/sh
# Downloads the official SDL2 and SDL2_ttf Windows x64 DLLs into build/win/ and checks them.
# Sources: github.com/libsdl-org/SDL (release-2.32.10) and github.com/libsdl-org/SDL_ttf (release-2.24.0).
# The SDL2 hash is the digest GitHub publishes for that release asset; the SDL2_ttf release has no
# published digest, so its hash below is the one measured when these were first fetched.
set -e
cd "$(dirname "$0")"
SDL_URL=https://github.com/libsdl-org/SDL/releases/download/release-2.32.10/SDL2-2.32.10-win32-x64.zip
SDL_SHA=6cf9706eefd0a4a06dc764007934d428afaf029fabdd408a9e646048c91e18fb
TTF_URL=https://github.com/libsdl-org/SDL_ttf/releases/download/release-2.24.0/SDL2_ttf-2.24.0-win32-x64.zip
TTF_SHA=8d72240aafc783d37d6cf960b1a2138e6ca4eb0c1b5b9a9e71ea299d1ef27ef9
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/sdl" "$T/ttf" build/win
fetch() { # url sha dir
  curl -fsSL -o "$T/$3.zip" "$1"
  echo "$2  $T/$3.zip" | sha256sum -c - >/dev/null || { echo "checksum mismatch for $1"; exit 1; }
  unzip -q "$T/$3.zip" -d "$T/$3"
}
fetch "$SDL_URL" "$SDL_SHA" sdl
fetch "$TTF_URL" "$TTF_SHA" ttf
cp "$T/sdl/SDL2.dll" "$T/ttf/SDL2_ttf.dll" build/win/
echo "SDL2.dll and SDL2_ttf.dll are in build/win/ (the only two DLLs needed)"
