#!/usr/bin/env bash
# Draait automatisch na elke boot (via systemd-service).
# Wacht de "grace"-tijd af. Opent de gebruiker de kluis in die tijd niet,
# dan wordt er geburnd. Als de "scherp"-vlag aan staat, geen wachttijd:
# meteen burnen.
set -euo pipefail

STATE_DIR=/var/lib/quitchat-burner
GRACE_FILE="$STATE_DIR/grace-minuten"
SCHERP_FILE="$STATE_DIR/scherp"
MAP=/srv/brug
LOG=/var/log/quitchat-burner/auto-burn.log

mkdir -p "$(dirname "$LOG")"
GRACE="$(cat "$GRACE_FILE" 2>/dev/null || echo 60)"
[[ "$GRACE" =~ ^[0-9]+$ ]] || GRACE=60

if [[ -f "$SCHERP_FILE" ]]; then
  echo "$(date -u -Iseconds) scherp-vlag aan; grace op 0" >> "$LOG"
  GRACE=0
fi

echo "$(date -u -Iseconds) auto-burn-check: wacht $GRACE minuten" >> "$LOG"

if (( GRACE > 0 )); then
  SECONDS_LEFT=$(( GRACE * 60 ))
  while (( SECONDS_LEFT > 0 )); do
    # Elke 15 sec kijken of de kluis is geopend
    if mountpoint -q "$MAP"; then
      echo "$(date -u -Iseconds) kluis geopend; auto-burn geannuleerd" >> "$LOG"
      exit 0
    fi
    sleep 15
    SECONDS_LEFT=$(( SECONDS_LEFT - 15 ))
  done
fi

# Nog eenmaal checken na de wachttijd
if mountpoint -q "$MAP"; then
  echo "$(date -u -Iseconds) kluis net op tijd geopend; auto-burn geannuleerd" >> "$LOG"
  exit 0
fi

echo "$(date -u -Iseconds) tijd om; BURN uitvoeren" >> "$LOG"
exec /opt/quitchat-burner/wrappers/burn.sh --yes --reden "auto bij opstart zonder goedkeuring"
