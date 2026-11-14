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

# Nooit twee backups tegelijk (de timer en de triggers kunnen samenvallen).
exec 9>"$LOG_DIR/backup.lock"
if ! flock -n 9; then
  log "Er loopt al een backup; deze slaat over."
  exit 0
fi

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
# Postgres' eigen datamap slaan we over: we hebben de pg_dumpall-SQL al bij 1.
# We nemen muxbee en brug mee (synapse, bridges, instellingen, backup-sleutels).
#
# Lezen gebeurt als root in een wegwerp-container: de mautrix-bridges zetten
# hun config.yaml bij elke herstart op 0600 (eigenaar 1337). Daardoor valt de
# ACL voor abel weg en faalde tar als abel sinds 8 nov elke nacht.
# We gebruiken het postgres-image omdat dat toch al lokaal staat.
log "  bestanden kopiëren"
mkdir -p "$WERK/bestanden"
LEES_IMAGE="${BACKUP_LEES_IMAGE:-postgres:17}"
if ! docker run --rm --network none -v "$MAP:/bron:ro" "$LEES_IMAGE" \
      tar -C /bron \
        --exclude='data/muxbee/postgres' \
        --exclude='config/muxbee/postgres' \
        --exclude='backups' \
        --exclude='data/muxbee/synapse/media_store' \
        -cf - config data 2>>"$LOG" \
    | tar -C "$WERK/bestanden" --no-same-owner -xf -; then
  log "FOUT: bestanden kopiëren mislukt (zie meldingen hierboven in $LOG)"
  exit 1
fi

# 3. Alles inpakken en versleutelen (age -R public.txt)
log "  inpakken en versleutelen"
mkdir -p "$BACKUP_HOOFD"
tar -C "$WERK" -czf - . | age -R "$BACKUP_DIR/public.txt" > "$BACKUP_HOOFD/$NAAM.tmp"
mv "$BACKUP_HOOFD/$NAAM.tmp" "$BACKUP_HOOFD/$NAAM"

# 3b. Media (foto's, filmpjes, spraakberichten) apart: elk bestand één keer,
# los versleuteld in $BACKUP_HOOFD/media. Synapse verandert een mediabestand
# nooit (vaste, unieke naam), dus alleen nieuwe bestanden komen erbij. Zo
# staan dezelfde media niet in elke backup opnieuw (2,8 GB × 14 in nov 2026).
# shortcut: media die Synapse verwijdert blijven in de backup staan; opruimen
# toevoegen als er ooit media-retentie aan gaat.
MEDIA_REL="data/muxbee/synapse/media_store"
MEDIA_DOEL="$BACKUP_HOOFD/media"
log "  media bijwerken"
mkdir -p "$WERK/media" "$MEDIA_DOEL"
find "$MEDIA_DOEL" -name '*.tmp' -delete   # resten van een afgebroken backup
if ! docker run --rm --network none -v "$MAP:/bron:ro" "$LEES_IMAGE" \
      sh -c "[ -d /bron/$MEDIA_REL ] || exit 0; cd /bron/$MEDIA_REL && find . -type f" \
      > "$WERK/media-alle.txt" 2>>"$LOG"; then
  log "FOUT: media-lijst maken mislukt"
  exit 1
fi
while IFS= read -r f; do
  [[ -f "$MEDIA_DOEL/${f#./}.age" ]] || printf '%s\n' "$f"
done < "$WERK/media-alle.txt" > "$WERK/media-nieuw.txt"
if [[ -s "$WERK/media-nieuw.txt" ]]; then
  if ! docker run --rm -i --network none -v "$MAP:/bron:ro" "$LEES_IMAGE" \
        tar -C "/bron/$MEDIA_REL" -cf - -T - < "$WERK/media-nieuw.txt" 2>>"$LOG" \
      | tar -C "$WERK/media" --no-same-owner -xf -; then
    log "FOUT: nieuwe media kopiëren mislukt"
    exit 1
  fi
  while IFS= read -r f; do
    f="${f#./}"
    mkdir -p "$MEDIA_DOEL/$(dirname "$f")"
    age -R "$BACKUP_DIR/public.txt" -o "$MEDIA_DOEL/$f.age.tmp" "$WERK/media/$f"
    mv "$MEDIA_DOEL/$f.age.tmp" "$MEDIA_DOEL/$f.age"
    rm -f "$WERK/media/$f"
  done < "$WERK/media-nieuw.txt"
fi
log "  media: $(wc -l < "$WERK/media-nieuw.txt") nieuw, $(wc -l < "$WERK/media-alle.txt") in totaal"

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
  media_spiegelen "$doel" || log "  let op: niet alle media konden naar $doel"
  log "  ook naar: $doel"
}

# Ontbrekende media-bestanden (al versleuteld) naar $1/media kopiëren.
media_spiegelen() {
  local f
  find "$1/media" -name '*.tmp' -delete 2>/dev/null || true
  (cd "$MEDIA_DOEL" && find . -type f -name '*.age') | while IFS= read -r f; do
    f="${f#./}"
    [[ -f "$1/media/$f" ]] && continue
    mkdir -p "$1/media/$(dirname "$f")"
    cp "$MEDIA_DOEL/$f" "$1/media/$f.tmp" && mv "$1/media/$f.tmp" "$1/media/$f"
  done
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
