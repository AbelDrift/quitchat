#!/usr/bin/env bash
# QuitChat – maakt een versleutelde backup van de kluis-inhoud.
# Gebruik:
#   backup-maken.sh                        volgens config in ~/.config/brug/backup.conf
#   backup-maken.sh /pad/naar/map          eenmalig naar die map (ook)
set -euo pipefail

CONF="$HOME/.config/brug/backup.conf"
MAP=/srv/brug
BACKUP_DIR="$MAP/config/brug/backup"
LOG_DIR="$HOME/.local/state/brug"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/backup.log"

log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG"; }

# Standaardwaarden
BACKUP_HOOFD="$MAP/backups"
BACKUP_EXTRA=""
BACKUP_MAX_AANTAL=14

if [[ -f "$CONF" ]]; then
  # shellcheck disable=SC1090
  source "$CONF"
fi

if ! mountpoint -q "$MAP"; then
  log "FOUT: kluis is dicht. Niets gebackupt."
  exit 1
fi
if [[ ! -f "$BACKUP_DIR/public.txt" ]]; then
  log "FOUT: backup-setup niet gevonden. Draai eerst sudo ./05-backups-instellen.sh"
  exit 1
fi

EXTRA_BESTEMMING="${1:-}"

STAMP="$(date +%Y%m%d-%H%M%S)"
NAAM="quitchat-${STAMP}.tar.gz.age"
WERK="$(mktemp -d)"
trap 'rm -rf "$WERK"' EXIT

log "Backup $STAMP: begin"

# 1. Postgres dumpen (consistent, zonder muxbee te hoeven stoppen)
if docker ps --format '{{.Names}}' | grep -q '^muxbee-postgres-1$'; then
  log "  postgres dumpen"
  docker exec muxbee-postgres-1 pg_dumpall -U synapse > "$WERK/postgres.sql" 2>/dev/null \
    || docker exec muxbee-postgres-1 pg_dumpall -U postgres > "$WERK/postgres.sql"
else
  log "  postgres niet actief; backup gaat door zonder database-dump"
fi

# 2. Configuratie en data kopiëren.
# Postgres' eigen datamap slaan we over: die mag abel niet lezen en we hebben
# de pg_dumpall-SQL al bij 1. We nemen muxbee en brug mee (synapse, bridges,
# instellingen, backup-sleutels).
log "  bestanden kopiëren"
mkdir -p "$WERK/bestanden"
tar -C "$MAP" \
    --exclude='data/muxbee/postgres' \
    --exclude='config/muxbee/postgres' \
    --exclude='backups' \
    -cf - config data 2>&1 \
  | tar -C "$WERK/bestanden" -xf -

# 3. Alles inpakken en versleutelen (age -R public.txt)
log "  inpakken en versleutelen"
mkdir -p "$BACKUP_HOOFD"
tar -C "$WERK" -czf - . | age -R "$BACKUP_DIR/public.txt" > "$BACKUP_HOOFD/$NAAM.tmp"
mv "$BACKUP_HOOFD/$NAAM.tmp" "$BACKUP_HOOFD/$NAAM"

# 4. Herstelbestand bijleggen (dezelfde voor alle backups; wordt vernieuwd)
cp -f "$BACKUP_DIR/identity-herstel.gpg" "$BACKUP_HOOFD/identity-herstel.gpg"

GROOTTE="$(du -h "$BACKUP_HOOFD/$NAAM" | cut -f1)"
log "  klaar: $BACKUP_HOOFD/$NAAM ($GROOTTE)"

# 5. Extra bestemmingen
kopieer_naar() {
  local doel="$1"
  mkdir -p "$doel" 2>/dev/null || { log "  kan $doel niet maken; overgeslagen"; return; }
  if ! cp "$BACKUP_HOOFD/$NAAM" "$doel/" 2>/dev/null; then
    log "  kon niet naar $doel kopiëren; overgeslagen"
    return
  fi
  cp -f "$BACKUP_DIR/identity-herstel.gpg" "$doel/identity-herstel.gpg"
  log "  ook naar: $doel"
}

if [[ -n "${BACKUP_EXTRA:-}" ]]; then
  kopieer_naar "$BACKUP_EXTRA"
fi
if [[ -n "$EXTRA_BESTEMMING" ]]; then
  kopieer_naar "$EXTRA_BESTEMMING"
fi

# 6. Oude backups opruimen
if [[ "${BACKUP_MAX_AANTAL:-0}" -gt 0 ]]; then
  opruimen() {
    local map="$1" aantal
    [[ -d "$map" ]] || return
    aantal="$(ls -1t "$map"/quitchat-*.tar.gz.age 2>/dev/null | wc -l)"
    if (( aantal > BACKUP_MAX_AANTAL )); then
      log "  opruimen in $map: $(( aantal - BACKUP_MAX_AANTAL )) oudste weg"
      ls -1t "$map"/quitchat-*.tar.gz.age | tail -n +$((BACKUP_MAX_AANTAL + 1)) | xargs -r rm -f
    fi
  }
  opruimen "$BACKUP_HOOFD"
  [[ -n "${BACKUP_EXTRA:-}" ]] && opruimen "$BACKUP_EXTRA"
  [[ -n "$EXTRA_BESTEMMING" ]] && opruimen "$EXTRA_BESTEMMING"
fi

# 7. Status voor trigger-check bijwerken
STATE="$HOME/.local/state/brug/backup-state"
GROOTTE_B="$(du -sb "$MAP/data" 2>/dev/null | cut -f1 || echo 0)"
BERICHTEN=0
if docker ps --format '{{.Names}}' | grep -q '^muxbee-postgres-1$'; then
  BERICHTEN="$(docker exec muxbee-postgres-1 psql -U synapse -tAc \
    "SELECT COUNT(*) FROM events WHERE type = 'm.room.message';" 2>/dev/null \
    || echo 0)"
fi
printf 'LAATSTE_GROOTTE=%s\nLAATSTE_BERICHTEN=%s\n' "$GROOTTE_B" "$BERICHTEN" > "$STATE"

log "Backup $STAMP: klaar"
