#!/usr/bin/env bash
# QuitChat – zet een versleutelde backup terug.
#
# Gebruik:
#   backup-herstellen.sh <backup.tar.gz.age>
#
# Werkt in twee situaties:
#   1. Kluis is open: de sleutel in de kluis ontgrendelt de backup.
#   2. Kluis is weg (geburnd/kapot): je typt de backup-herstelcode van papier.
#      Naast het backup-bestand moet dan identity-herstel.gpg staan.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Gebruik: $0 <backup.tar.gz.age>"
  exit 1
fi
BACKUP="$1"
[[ -f "$BACKUP" ]] || { echo "Backup-bestand niet gevonden: $BACKUP"; exit 1; }
BACKUP_MAP="$(cd -- "$(dirname -- "$BACKUP")" && pwd)"

MAP=/srv/brug
IDENTITY_IN_KLUIS="$MAP/config/brug/backup/identity.txt"
IDENTITY_HERSTEL="$BACKUP_MAP/identity-herstel.gpg"

WERK="$(mktemp -d)"
trap 'rm -rf "$WERK"' EXIT

# Welke sleutel gebruiken?
if mountpoint -q "$MAP" && [[ -f "$IDENTITY_IN_KLUIS" ]]; then
  echo "==> Kluis is open; backup wordt met de kluis-sleutel geopend."
  IDENTITY="$IDENTITY_IN_KLUIS"
else
  echo "==> Kluis niet beschikbaar; backup-herstelcode nodig."
  if [[ ! -f "$IDENTITY_HERSTEL" ]]; then
    echo "    identity-herstel.gpg niet gevonden naast de backup."
    echo "    Zoek dat bestand erbij en zet het in dezelfde map."
    exit 1
  fi
  echo "    Typ de backup-herstelcode van papier (streepjes mogen weg):"
  read -r -s -p "Code: " CODE
  echo
  POGING="$(printf '%s' "$CODE" | sed $'s/\x1b\\[[0-9;]*~//g' \
    | tr '[:lower:]' '[:upper:]' | tr -cd 'A-HJ-NP-Z2-9' \
    | fold -w4 | paste -sd- || true)"
  if ! printf '%s' "$POGING" | gpg --batch --yes --quiet --decrypt --passphrase-fd 0 \
       -o "$WERK/identity.txt" "$IDENTITY_HERSTEL" 2>/dev/null; then
    echo "    Code werkt niet. Herstel afgebroken."
    exit 1
  fi
  unset CODE POGING
  IDENTITY="$WERK/identity.txt"
  chmod 600 "$IDENTITY"
fi

echo "==> Backup openen en controleren"
mkdir -p "$WERK/uitpakken"
age -d -i "$IDENTITY" -o "$WERK/backup.tar.gz" "$BACKUP"
tar -tzf "$WERK/backup.tar.gz" >/dev/null
echo "    OK."

echo
echo "LET OP: dit vervangt de huidige inhoud van /srv/brug door de backup."
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^muxbee-'; then
  echo "    Muxbee draait; die wordt eerst gestopt."
fi
read -r -p "Typ exact HERSTEL om door te gaan: " BEV
[[ "$BEV" == "HERSTEL" ]] || { echo "Geannuleerd."; exit 0; }

if ! mountpoint -q "$MAP"; then
  echo "FOUT: er is geen open kluis op $MAP waar de backup heen moet."
  echo "Maak eerst een nieuwe kluis en open die, draai dan dit script opnieuw."
  exit 1
fi

echo "==> Muxbee stoppen (als die draait)"
if command -v brug >/dev/null && docker ps --format '{{.Names}}' | grep -q '^muxbee-'; then
  brug down || true
fi

echo "==> Backup uitpakken"
tar -C "$WERK/uitpakken" -xzf "$WERK/backup.tar.gz"

echo "==> Bestaande inhoud opzij zetten"
VEILIG="$MAP/_voor-herstel-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$VEILIG"
for d in config data; do
  [[ -d "$MAP/$d" ]] && mv "$MAP/$d" "$VEILIG/$d" || true
done

echo "==> Backup terugzetten"
if [[ -d "$WERK/uitpakken/bestanden" ]]; then
  mv "$WERK/uitpakken/bestanden"/* "$MAP/"
fi

echo "==> Database terugzetten (als die in de backup zit)"
if [[ -f "$WERK/uitpakken/postgres.sql" ]]; then
  # Muxbee opstarten zodat postgres draait, dan de dump terugzetten
  if command -v brug >/dev/null; then
    (brug up >/dev/null 2>&1 || true) &
    sleep 15
    docker exec -i muxbee-postgres-1 psql -U synapse -d postgres \
      < "$WERK/uitpakken/postgres.sql" >/dev/null 2>&1 \
      || docker exec -i muxbee-postgres-1 psql -U postgres -d postgres \
      < "$WERK/uitpakken/postgres.sql" >/dev/null 2>&1 \
      || echo "    Let op: database terugzetten gaf fouten; controleer brug logs synapse"
  fi
fi

echo
echo "Klaar. De oude inhoud staat in $VEILIG. Verwijder die zodra alles werkt:"
echo "    sudo rm -rf $VEILIG"
echo
echo "Draai 'brug status' om te zien of alles draait."
