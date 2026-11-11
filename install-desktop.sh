#!/bin/sh
# Adds TieSheet (with its icon) to the desktop's application menu for the current user.
#   ./install-desktop.sh              menu entry that runs build/tiesheet from this folder
#   ./install-desktop.sh /path/to/tiesheet   ... or any other copy of the program
#   ./install-desktop.sh --uninstall  removes it again
# Everything goes under ~/.local/share (or $XDG_DATA_HOME); nothing needs root.
set -e
cd "$(dirname "$0")"
data="${XDG_DATA_HOME:-$HOME/.local/share}"
icons="$data/icons/hicolor"
if [ "$1" = --uninstall ]; then
  rm -f "$data/applications/tiesheet.desktop" "$icons/scalable/apps/tiesheet.svg"
  for n in 16 24 32 48 64 128 256 512; do rm -f "$icons/${n}x$n/apps/tiesheet.png"; done
else
  exe=$(realpath "${1:-build/tiesheet}")
  [ -x "$exe" ] || { echo "$exe not found - run ./build.sh first" >&2; exit 1; }
  mkdir -p "$data/applications" "$icons/scalable/apps"
  sed "s|^Exec=.*|Exec=\"$exe\" %f|" assets/tiesheet.desktop > "$data/applications/tiesheet.desktop"
  cp assets/tiesheet.svg "$icons/scalable/apps/tiesheet.svg"
  for n in 16 24 32 48 64 128 256 512; do
    mkdir -p "$icons/${n}x$n/apps"
    cp assets/png/tiesheet-$n.png "$icons/${n}x$n/apps/tiesheet.png"
  done
fi
command -v update-desktop-database >/dev/null && update-desktop-database "$data/applications" 2>/dev/null || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -t "$icons" 2>/dev/null || true
echo "Done"
