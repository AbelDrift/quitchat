#!/usr/bin/env bash
# QuitChat – thuis-server, stap 9 (eenmalig)
# Zorgt dat de brug NOOIT kan starten zonder open kluis.
#
# Het probleem: Docker start de containers zelf bij het opstarten van de pc.
# Is de kluis dan nog dicht, dan is /srv/brug gewoon een lege map op de
# gewone schijf. Docker maakt daar dan zelf mappen aan, Postgres zet er een
# lege database in, en Synapse draait daarop: je ziet geen chats meer, en de
# bridges gaan in de war. (Zo ging het eind oktober en op 13 nov 2026.)
#
# De oplossing: de map /srv/brug ónder de kluis leegmaken en onveranderbaar
# maken (chattr +i). Docker kan er dan niets meer aanmaken, dus de containers
# weigeren te starten tot de kluis open is. Daarna start kluis-open.sh ze
# zelf, in de goede volgorde.
#
# Wat er onder de kluis stond, wordt niet weggegooid maar verplaatst naar
# /var/backups/quitchat-onder-kluis-<datum>.
#
# Gebruik: sudo ./09-kluis-afdichten.sh
# Ongedaan maken: zie het einde van dit script.
set -euo pipefail

MAP=/srv/brug
ONDER=/mnt/quitchat-onder-kluis

if [[ $EUID -ne 0 ]]; then
  echo "Start dit script met: sudo ./09-kluis-afdichten.sh"
  exit 1
fi
command -v chattr >/dev/null || { echo "chattr ontbreekt (pakket e2fsprogs)."; exit 1; }
[[ "$(findmnt -no FSTYPE /)" == ext4 ]] || { echo "Alleen getest op ext4."; exit 1; }

# Veiligheidstest vooraf: kan er nog iets gekoppeld worden op een
# onveranderbare map? Anders zou de kluis na een herstart niet meer opengaan.
TEST=/var/tmp/quitchat-afdicht-test-$$
mkdir -p "$TEST"; chattr +i "$TEST"
if mount -t tmpfs -o size=1m none "$TEST" && umount "$TEST"; then
  chattr -i "$TEST"; rmdir "$TEST"
  echo "==> Veiligheidstest geslaagd: koppelen op een onveranderbare map werkt."
else
  chattr -i "$TEST"; rmdir "$TEST" 2>/dev/null || true
  echo "FOUT: koppelen op een onveranderbare map lukt hier niet. Niets veranderd." >&2
  exit 1
fi

# De gewone schijf nog een keer koppelen, zonder de kluis erop: zo zien we
# wat er ónder /srv/brug staat, ook als de kluis open is.
mkdir -p "$ONDER"
mount --bind / "$ONDER"
trap 'umount "$ONDER" 2>/dev/null || true; rmdir "$ONDER" 2>/dev/null || true' EXIT
D="$ONDER$MAP"
mkdir -p "$D"

# Eerder al afgedicht? Dan alleen controleren.
if lsattr -d "$D" 2>/dev/null | cut -d' ' -f1 | grep -q i; then
  echo "Al afgedicht: $MAP onder de kluis is onveranderbaar."
else
  if [[ -n "$(ls -A "$D")" ]]; then
    BEWAAR="/var/backups/quitchat-onder-kluis-$(date +%Y%m%d-%H%M%S)"
    echo "==> Onder de kluis staat nog iets; dat gaat naar $BEWAAR:"
    du -sh "$D"/* 2>/dev/null | sed 's/^/    /'
    mkdir -p "$BEWAAR"
    chmod 700 "$BEWAAR"
    find "$D" -mindepth 1 -maxdepth 1 -exec mv -t "$BEWAAR" {} +
  fi
  chown root:root "$D"
  chmod 711 "$D"
  chattr +i "$D"
  echo "==> $MAP onder de kluis is nu leeg en onveranderbaar."
fi

# Test: kan er onder de kluis nog iets worden aangemaakt?
if mkdir "$D/test-$$" 2>/dev/null; then
  rmdir "$D/test-$$"
  echo "FOUT: er kan nog steeds iets worden aangemaakt onder de kluis." >&2
  exit 1
fi
echo "==> Test geslaagd: Docker kan zonder kluis niets meer onder $MAP aanmaken."
echo
echo "Klaar. Vanaf nu:"
echo "  - na een herstart starten de containers pas als je de kluis opent;"
echo "  - kluis-open.sh (en de burner-webapp) starten de brug zelf."
echo
echo "Ongedaan maken (normaal niet nodig):"
echo "  sudo mkdir -p $ONDER && sudo mount --bind / $ONDER && sudo chattr -i $ONDER$MAP && sudo umount $ONDER"
