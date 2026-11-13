#!/usr/bin/env bash
# QuitChat – stuurt een pushmelding naar je telefoon via ntfy.
# Gebruik: melding-sturen.sh "titel" "tekst" [prioriteit]
#   prioriteit: min, low, default, high of urgent (standaard: default)
# Instellingen in ~/.config/brug/melding.conf (zie 08-meldingen-instellen.sh).
# Zonder instellingen wordt er niets verstuurd (alleen gelogd).
set -euo pipefail

CONF="$HOME/.config/brug/melding.conf"
LOG="$HOME/.local/state/brug/melding.log"
mkdir -p "$(dirname "$LOG")"
log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }

MELDING_NTFY_SERVER=""
MELDING_NTFY_TOPIC=""
# shellcheck disable=SC1090
[[ -f "$CONF" ]] && source "$CONF"

TITEL="${1:?Gebruik: melding-sturen.sh \"titel\" \"tekst\" [prioriteit]}"
TEKST="${2:-}"
PRIO="${3:-default}"

if [[ -z "$MELDING_NTFY_SERVER" || -z "$MELDING_NTFY_TOPIC" ]]; then
  log "niet verstuurd (geen ntfy ingesteld): $TITEL"
  exit 0
fi

# Als JSON versturen: dan kunnen titel en tekst gewoon é, ë enz. bevatten.
JSON="$(python3 -I -c '
import json, sys
prio = {"min": 1, "low": 2, "default": 3, "high": 4, "urgent": 5}.get(sys.argv[4], 3)
print(json.dumps({"topic": sys.argv[1], "title": sys.argv[2], "message": sys.argv[3] or sys.argv[2],
                  "priority": prio, "tags": ["floppy_disk"]}))
' "$MELDING_NTFY_TOPIC" "$TITEL" "$TEKST" "$PRIO")"

if curl -fsS --max-time 20 -H 'Content-Type: application/json' -d "$JSON" \
     "${MELDING_NTFY_SERVER%/}/" >/dev/null 2>>"$LOG"; then
  log "verstuurd: $TITEL"
else
  log "VERSTUREN MISLUKT: $TITEL"
  exit 1
fi
