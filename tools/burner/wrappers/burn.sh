#!/usr/bin/env bash
# QuitChat burn: vernietigt onherroepelijk alle LUKS-sleutels van de kluis.
# Daarna is de kluis onbruikbaar; herstel kan alleen via een versleutelde
# backup én de backup-herstelcode op papier.
#
# Gebruik:
#   sudo burn.sh --yes [--reden "tekst"]
set -euo pipefail

KLUIS=/srv/brug.kluis
NAAM=brug
MAP=/srv/brug
LOG=/var/log/quitchat-burner/burn.log

# shellcheck source=kluis-hulp.sh
source "$(dirname -- "$(readlink -f -- "$0")")/kluis-hulp.sh"
buiten_sandbox "$@"
REDEN="handmatig"
JA=nee

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes) JA=ja; shift ;;
    --reden) REDEN="$2"; shift 2 ;;
    *) echo "Onbekende optie: $1"; exit 2 ;;
  esac
done

if [[ "$JA" != "ja" ]]; then
  cat <<WARN
   DIT VERNIETIGT ONHERROEPELIJK ALLE BERICHTEN EN KOPPELINGEN
   De kluis-sleutels (wachtwoord én papieren herstelcode) worden gewist.
   Alleen een backup + backup-herstelcode kan dit nog terugbrengen.
   Gebruik --yes om door te gaan.
WARN
  exit 1
fi

mkdir -p "$(dirname "$LOG")"
echo "$(date -u -Iseconds) BURN start (reden: $REDEN)" >> "$LOG"

# 1. Muxbee stoppen (als die draait) — als abel, zodat Docker het toestaat
GEBRUIKER="$(stat -c %U "$MAP" 2>/dev/null || getent passwd 1000 | cut -d: -f1)"
HOME_USER="$(getent passwd "$GEBRUIKER" | cut -d: -f6)"
if [[ -x "$HOME_USER/.local/bin/brug" ]] && mountpoint -q "$MAP"; then
  echo "  muxbee stoppen"
  sudo -u "$GEBRUIKER" -H "$HOME_USER/.local/bin/brug" down 2>/dev/null || true
fi

# 2. Kluis ontkoppelen
if mountpoint -q "$MAP"; then
  echo "  kluis loskoppelen"
  umount "$MAP" || umount -l "$MAP"
fi
if [[ -e "/dev/mapper/$NAAM" ]]; then
  cryptsetup close "$NAAM"
fi
# Loop-devices die (nog) naar het kluisbestand wijzen opruimen —
# open-kluis.sh zet die zelf op sinds de udisks-fix.
for LOOP in $(losetup -j "$KLUIS" -O NAME --noheadings 2>/dev/null); do
  losetup -d "$LOOP" 2>/dev/null || true
done

# 3. LUKS-sleutels vernietigen (dit is de echte burn)
echo "  LUKS-sleutels vernietigen"
cryptsetup luksErase --batch-mode "$KLUIS"

# 4. Extra: de eerste 16 MB van het kluisbestand overschrijven met willekeur,
#    zodat ook de LUKS-header weg is.
echo "  kluisbestand-header overschrijven"
dd if=/dev/urandom of="$KLUIS" bs=1M count=16 conv=notrunc status=none 2>/dev/null || true

# 5. Alle Docker-containers van muxbee opruimen en hun data
echo "  Docker-containers van muxbee opruimen"
docker ps -a --filter 'name=muxbee-' --format '{{.Names}}' 2>/dev/null \
  | xargs -r docker rm -f 2>/dev/null || true
docker volume ls -q --filter 'name=muxbee' 2>/dev/null \
  | xargs -r docker volume rm 2>/dev/null || true

# 6. Scherp-vlag weg (zinloos nu, voor de netheid)
rm -f /var/lib/quitchat-burner/scherp 2>/dev/null || true

echo "$(date -u -Iseconds) BURN klaar" >> "$LOG"
echo
echo "BURN uitgevoerd. De kluis is onherroepelijk vernietigd."
echo "Herstel kan alleen via een versleutelde backup én de backup-herstelcode."
