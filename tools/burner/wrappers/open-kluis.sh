#!/usr/bin/env bash
# Opent de kluis met een wachtwoord dat via stdin binnenkomt.
# Wordt aangeroepen door de burner-webapp.
set -euo pipefail

KLUIS=/srv/brug.kluis
NAAM=brug
MAP=/srv/brug

# shellcheck source=kluis-hulp.sh
source "$(dirname -- "$(readlink -f -- "$0")")/kluis-hulp.sh"
buiten_sandbox "$@"

if mountpoint -q "$MAP"; then
  if findmnt -nro OPTIONS "$MAP" | grep -q '\bro\b'; then
    echo "Kluis is open, maar alleen-lezen. Sluit hem op de pc (kluis-dicht.sh) en open opnieuw." >&2
    exit 2
  fi
  echo "Kluis is al open."
  exit 0
fi

# Een oude alleen-lezen mapper eerst opruimen (of: herstart nodig).
mapper_opruimen_voor_openen

# Lees het wachtwoord van stdin, geef het aan cryptsetup via file descriptor
# (zodat het nergens op schijf of in de proceslijst verschijnt).
#
# We zetten de loop-device zelf op en wachten op udev voordat cryptsetup
# zijn werk doet. Doen we dat niet, dan graait udisksd op KDE/GNOME het
# verse loop-device in om de metadata uit te lezen; de race die daardoor
# ontstaat markeert loop als "busy for write", waarna cryptsetup
# terugvalt op read-only. Dat leidt vervolgens tot ro LUKS en ro ext4.
if [[ ! -e "/dev/mapper/$NAAM" ]]; then
  LOOP="$(losetup --find --show --nooverlap "$KLUIS")"
  udevadm settle --timeout=10 || true
  if ! cryptsetup open --key-file=- "$LOOP" "$NAAM"; then
    losetup -d "$LOOP" 2>/dev/null || true
    exit 1
  fi
fi
mkdir -p "$MAP"
mount "/dev/mapper/$NAAM" "$MAP"
if findmnt -nro OPTIONS "$MAP" | grep -q '\bro\b'; then
  echo "Kluis is read-only gemount. Sluit af en probeer opnieuw." >&2
  exit 2
fi
echo "Kluis geopend. De brug start op de achtergrond (een paar minuten)."
# Op de achtergrond: de webapp wacht maar 60 seconden op dit script.
setsid /opt/quitchat-burner/wrappers/containers-starten.sh \
  >> /var/log/quitchat-burner/starten.log 2>&1 < /dev/null &

# De scherp-vlag wissen (we zijn blijkbaar nog bij ons verstand)
rm -f /var/lib/quitchat-burner/scherp 2>/dev/null || true
