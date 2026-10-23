#!/usr/bin/env bash
# Stopt de messenger-brug en sluit de versleutelde kluis.
# Gebruik: sudo ./kluis-dicht.sh
set -euo pipefail

NAAM=brug
MAP=/srv/brug

if [[ $EUID -ne 0 ]]; then
  echo "Start dit script met: sudo ./kluis-dicht.sh"
  exit 1
fi
GEBRUIKER="${SUDO_USER:-}"

if mountpoint -q "$MAP"; then
  if [[ -n "$GEBRUIKER" && -x "/home/$GEBRUIKER/.local/bin/brug" ]]; then
    echo "==> Brug stoppen"
    sudo -u "$GEBRUIKER" -H "/home/$GEBRUIKER/.local/bin/brug" down || true
  fi
  echo "==> Kluis loskoppelen"
  umount "$MAP"
fi
if [[ -e "/dev/mapper/$NAAM" ]]; then
  cryptsetup close "$NAAM"
fi
echo "De kluis is dicht."
