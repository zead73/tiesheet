#!/bin/sh
# Builds dist/tiesheet-x86_64.AppImage inside a Debian 12 container (needs docker), so the
# AppImage carries a low glibc requirement and the real SDL2 libraries rather than the
# build machine's.  See packaging/appimage/.
set -e
cd "$(dirname "$0")"
docker build -t tiesheet-appimage-builder - < packaging/appimage/Dockerfile
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -v "$PWD":/src -w /src tiesheet-appimage-builder
