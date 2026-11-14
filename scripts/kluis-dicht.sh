#!/usr/bin/env bash
# Stopt de messenger-brug en sluit de versleutelde kluis.
# Gebruik: sudo ./kluis-dicht.sh
set -euo pipefail

KLUIS=/srv/brug.kluis
NAAM=brug
MAP=/srv/brug

if [[ $EUID -ne 0 ]]; then
  echo "Start dit script met: sudo ./kluis-dicht.sh"
  exit 1
fi
GEBRUIKER="${SUDO_USER:-}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../tools/burner/wrappers/kluis-hulp.sh
source "$SCRIPT_DIR/../tools/burner/wrappers/kluis-hulp.sh"

if mountpoint -q "$MAP"; then
  if [[ -n "$GEBRUIKER" && -x "/home/$GEBRUIKER/.local/bin/brug" ]]; then
    echo "==> Brug stoppen"
    sudo -u "$GEBRUIKER" -H "/home/$GEBRUIKER/.local/bin/brug" down || true
  fi
  echo "==> Kluis loskoppelen"
  if ! umount "$MAP"; then
    echo "De kluis is nog in gebruik:" >&2
    fuser -vm "$MAP" 2>&1 | head -n 12 >&2 || true
    echo "Stop die programma's en probeer opnieuw." >&2
    exit 1
  fi
fi
if [[ -e "/dev/mapper/$NAAM" ]] && ! cryptsetup close "$NAAM" 2>/dev/null; then
  # Zombie: hier losgekoppeld, maar elders nog open (zie kluis-hulp.sh).
  wie="$(kluis_vasthouders)"
  echo "LET OP: de kluis is hier losgekoppeld, maar nog NIET dicht." >&2
  if [[ -n "$wie" ]]; then
    echo "Hij wordt nog vastgehouden door:" >&2
    echo "$wie" >&2
  fi
  echo "Stop die programma's (of herstart de pc); daarna is hij echt dicht." >&2
  exit 2
fi
# Zet kluis-open.sh de loop zelf op (vanaf de udisks-fix), ruim die dan ook
# zelf op. Oudere kluizen gebruiken de loop-device die cryptsetup intern
# aanmaakte; dan vindt losetup -j hem niet en gebeurt hier niets.
for LOOP in $(losetup -j "$KLUIS" -O NAME --noheadings 2>/dev/null); do
  losetup -d "$LOOP" 2>/dev/null || true
done
echo "De kluis is dicht."
