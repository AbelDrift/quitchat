#!/usr/bin/env bash
# Start de brug (Postgres, Synapse, bridges, Element) in de goede volgorde,
# nadat de kluis open is. Wordt aangeroepen door kluis-open.sh en door de
# burner-webapp (open-kluis.sh). Gebruikt "docker start" en niet "brug up":
# muxbee schrijft bij elke "up" de bridge-instellingen opnieuw.
#
# Postgres wordt altijd opnieuw gestart: zo weten we zeker dat hij de map in
# de kluis gebruikt en niet een (lege) map eronder. Dat ging eind oktober en
# op 13 nov mis: Docker startte Postgres bij het opstarten vóór de kluis open
# was, en Synapse zag een lege database.
set -euo pipefail

MAP=/srv/brug
PG_DATA="$MAP/data/muxbee/postgres"

if ! mountpoint -q "$MAP"; then
  echo "De kluis is dicht; niets gestart." >&2
  exit 1
fi
if [[ ! -f "$PG_DATA/PG_VERSION" ]]; then
  echo "Geen database gevonden in $PG_DATA; niets gestart." >&2
  exit 1
fi

bestaat() { docker container inspect "$1" >/dev/null 2>&1; }
wacht_gezond() {   # $1 = container, $2 = max seconden
  local i status
  for (( i = 0; i < $2; i += 3 )); do
    status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$1" 2>/dev/null || true)"
    [[ "$status" == healthy ]] && return 0
    sleep 3
  done
  echo "  $1 is na $2 seconden nog niet gezond ($status)." >&2
  return 1
}

echo "==> Database starten"
bestaat muxbee-postgres-1 || { echo "Container muxbee-postgres-1 bestaat niet; draai eerst: brug up" >&2; exit 1; }
docker stop muxbee-synapse-1 >/dev/null 2>&1 || true
docker restart muxbee-postgres-1 >/dev/null
wacht_gezond muxbee-postgres-1 120

echo "==> Matrix-server starten (kan na een crash even duren)"
docker start muxbee-synapse-1 >/dev/null
wacht_gezond muxbee-synapse-1 300

echo "==> Bridges en Element starten"
for c in $(docker ps -a --format '{{.Names}}' | grep -E '^muxbee-(mautrix-.*|element)-1$'); do
  docker start "$c" >/dev/null && echo "  $c"
done
echo "De brug draait."
