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
  # Loop-device zelf opzetten en udev laten settlen, voordat we cryptsetup
  # draaien. Doen we dat niet, dan graait udisksd op KDE/GNOME het verse
  # loop-device in om de metadata uit te lezen; de race die daardoor
  # ontstaat markeert loop0 als "busy for write", waarna cryptsetup
  # terugvalt op read-only. Dat leidt vervolgens tot ro LUKS en ro ext4.
  LOOP="$(losetup --find --show --nooverlap "$KLUIS")"
  udevadm settle --timeout=10 || true
  if ! cryptsetup open "$LOOP" "$NAAM"; then
    losetup -d "$LOOP" 2>/dev/null || true
    exit 1
  fi
fi
mkdir -p "$MAP"
mount "/dev/mapper/$NAAM" "$MAP"
# Controle: als het ondanks alles toch ro gemount is, meld het meteen.
if findmnt -nro OPTIONS "$MAP" | grep -q '\bro\b'; then
  echo "LET OP: de kluis is read-only gemount. Dat hoort niet; sluit af met"
  echo "sudo ./kluis-dicht.sh en probeer opnieuw. Blijft het ro, laat het weten."
  exit 2
fi
echo "De kluis is open. Start de brug met: brug up"
