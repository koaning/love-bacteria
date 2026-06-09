#!/bin/bash
# Update the Steam Deck from the latest GitHub release before archiving.

set -euo pipefail

echo "Updating Sporeline on steamdeck over Tailscale..."
ssh \
  -o BatchMode=yes \
  -o ConnectTimeout=10 \
  steamdeck \
  'bash -s -- --latest' < scripts/install-on-deck.sh
