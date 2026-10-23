#!/usr/bin/env bash
# Opent de versleutelde kluis van de messenger-brug (na een herstart).
# Gebruik: sudo ./kluis-open.sh
# Je kunt je wachtwoord typen, of de herstelcode van papier.
set -euo pipefail

KLUIS=/srv/brug.kluis
NAAM=brug
MAP=/srv/brug

if [[ $EUID -ne 0 ]]; then
  echo "Start dit script met: sudo ./kluis-open.sh"
  exit 1
fi
if mountpoint -q "$MAP"; then
  echo "De kluis is al open."
  exit 0
fi
if [[ ! -e "/dev/mapper/$NAAM" ]]; then
  cryptsetup open "$KLUIS" "$NAAM"
fi
mkdir -p "$MAP"
mount "/dev/mapper/$NAAM" "$MAP"
echo "De kluis is open. Start de brug met: brug up"
