#!/bin/bash
# Install or update Sporeline on a Steam Deck.
#
# Run this in Desktop Mode's Konsole (first time) or over SSH from your Mac
# (subsequent updates). Drops the AppImage into ~/Applications and prints the
# one-time steps to register it with Steam.
#
# Usage:
#   scripts/install-on-deck.sh path/to/Sporeline-x86_64.AppImage
#   scripts/install-on-deck.sh --latest                  # pull from GitHub release

set -euo pipefail

APP_NAME="Sporeline"
GITHUB_REPO="koaning/love-bacteria"
DEST_DIR="${HOME}/Applications"
DEST_APPIMAGE="${DEST_DIR}/Sporeline-x86_64.AppImage"

usage() {
  cat <<EOF
Usage:
  $0 <path-to-AppImage>
  $0 --latest    (download from https://github.com/${GITHUB_REPO}/releases/latest)
EOF
  exit 1
}

if [ $# -lt 1 ]; then
  usage
fi

source_path=""
cleanup_source=false

if [ "$1" = "--latest" ]; then
  echo "Fetching latest release from github.com/${GITHUB_REPO}..."
  url=$(curl -fsSL "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" \
    | grep -oE 'https://[^"]+Sporeline-x86_64\.AppImage' | head -1)
  if [ -z "${url}" ]; then
    echo "No Sporeline-x86_64.AppImage asset found in the latest release." >&2
    echo "Trigger the Release workflow in Actions first, or tag a vX.Y.Z." >&2
    exit 1
  fi
  tmp="$(mktemp)"
  echo "Downloading ${url}"
  curl -fsSL -o "${tmp}" "${url}"
  source_path="${tmp}"
  cleanup_source=true
elif [ -f "$1" ]; then
  source_path="$1"
else
  usage
fi

mkdir -p "${DEST_DIR}"
first_install=false
if [ ! -f "${DEST_APPIMAGE}" ]; then
  first_install=true
fi

install -m 0755 "${source_path}" "${DEST_APPIMAGE}"
echo "Installed: ${DEST_APPIMAGE}"

if ${cleanup_source}; then
  rm -f "${source_path}"
fi

if ${first_install}; then
  cat <<EOF

--- First-time setup: register with Steam ---

In Desktop Mode:
  1. Open Steam.
  2. Games → "Add a Non-Steam Game to My Library..." → Browse to:
       ${DEST_APPIMAGE}
  3. Tick ${APP_NAME}, click "Add Selected Programs".
  4. (Optional) right-click the shortcut → Properties → rename to "${APP_NAME}".
  5. Return to Gaming Mode. You're done.

Future updates don't need this step — just rerun this script (from SSH is fine)
and the existing Steam shortcut will pick up the new AppImage automatically.
EOF
else
  echo "Updated in place. Existing Steam shortcut will use the new build next launch."
fi
