#!/usr/bin/env bash
# QuitChat – kijkt of een backup gemaakt moet worden volgens de triggers
# BACKUP_PER_MB en BACKUP_PER_BERICHTEN in ~/.config/brug/backup.conf.
# Wordt automatisch opgeroepen door een systemd-timer. Je kunt hem ook met
# de hand draaien om te testen.
set -euo pipefail

CONF="$HOME/.config/brug/backup.conf"
MAP=/srv/brug
STATE_DIR="$HOME/.local/state/brug"
STATE="$STATE_DIR/backup-state"
mkdir -p "$STATE_DIR"

BACKUP_PER_MB=0
BACKUP_PER_BERICHTEN=0
if [[ -f "$CONF" ]]; then
  # shellcheck disable=SC1090
  source "$CONF"
fi

# Niets te doen als beide triggers uit staan
if (( BACKUP_PER_MB == 0 && BACKUP_PER_BERICHTEN == 0 )); then
  exit 0
fi
mountpoint -q "$MAP" || exit 0

LAATSTE_GROOTTE=0
LAATSTE_BERICHTEN=0
if [[ -f "$STATE" ]]; then
  # shellcheck disable=SC1090
  source "$STATE"
fi

HUIDIG_GROOTTE="$(du -sb "$MAP/data" 2>/dev/null | cut -f1 || echo 0)"
HUIDIG_BERICHTEN=0
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^muxbee-postgres-1$'; then
  HUIDIG_BERICHTEN="$(docker exec muxbee-postgres-1 psql -U synapse -tAc \
    "SELECT COUNT(*) FROM events WHERE type = 'm.room.message';" 2>/dev/null \
    | tr -d ' \n\r' || echo 0)"
  [[ "$HUIDIG_BERICHTEN" =~ ^[0-9]+$ ]] || HUIDIG_BERICHTEN=0
fi

MOET_BACKUP=0
REDEN=""

if (( BACKUP_PER_MB > 0 )); then
  DRIFT_MB=$(( (HUIDIG_GROOTTE - LAATSTE_GROOTTE) / 1048576 ))
  if (( DRIFT_MB >= BACKUP_PER_MB )); then
    MOET_BACKUP=1
    REDEN="data groeide met ${DRIFT_MB} MB (grens: ${BACKUP_PER_MB} MB)"
  fi
fi
if (( BACKUP_PER_BERICHTEN > 0 )); then
  DRIFT_B=$(( HUIDIG_BERICHTEN - LAATSTE_BERICHTEN ))
  if (( DRIFT_B >= BACKUP_PER_BERICHTEN )); then
    MOET_BACKUP=1
    REDEN="${DRIFT_B} nieuwe berichten (grens: ${BACKUP_PER_BERICHTEN})"
  fi
fi

if (( MOET_BACKUP == 1 )); then
  echo "Trigger gehaald: $REDEN. Backup wordt gemaakt."
  exec "$HOME/.local/bin/backup-maken.sh"
fi
