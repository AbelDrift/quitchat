#!/usr/bin/env bash
# QuitChat – backup-wachter.
# Kijkt of de nieuwste backup niet te oud is en stuurt anders een melding.
# Vangt ook de gevallen waarin de backup helemaal niet draait (bijvoorbeeld
# omdat de kluis dicht is: dan slaat systemd de backup stilletjes over).
# Draait elke 6 uur via quitchat-backup-wachter.timer, ook als de kluis dicht is.
set -euo pipefail

CONF="$HOME/.config/brug/backup.conf"
STATE_DIR="$HOME/.local/state/brug"
LAATSTE_MELDING="$STATE_DIR/wachter-laatste-melding"
mkdir -p "$STATE_DIR"

BACKUP_HOOFD=/srv/brug/backups
BACKUP_EXTRA=""
BACKUP_WACHTER_UREN="${BACKUP_WACHTER_UREN:-36}"                  # vanaf hoeveel uur oud een backup "te oud" is
BACKUP_WACHTER_HERHAAL_UREN="${BACKUP_WACHTER_HERHAAL_UREN:-12}"  # niet vaker dan dit een melding sturen
# shellcheck disable=SC1090
[[ -f "$CONF" ]] && source "$CONF"

# Nieuwste backup zoeken in alle bekende mappen (de extra map staat buiten de
# kluis en is dus ook te zien als de kluis dicht is).
nieuwste=0
for map in "$BACKUP_HOOFD" "${BACKUP_EXTRA:-}"; do
  [[ -n "$map" && -d "$map" ]] || continue
  t="$(find "$map" -maxdepth 1 -name 'quitchat-*.tar.gz.age' -printf '%T@\n' 2>/dev/null \
        | sort -n | tail -1 | cut -d. -f1)"
  [[ -n "$t" && "$t" -gt "$nieuwste" ]] && nieuwste="$t"
done

nu="$(date +%s)"
if (( nieuwste > 0 )); then
  uren=$(( (nu - nieuwste) / 3600 ))
  (( uren < BACKUP_WACHTER_UREN )) && exit 0
  tekst="De nieuwste backup is $uren uur oud (grens: $BACKUP_WACHTER_UREN uur)."
else
  tekst="Er is geen enkele backup gevonden."
fi

if mountpoint -q /srv/brug; then
  tekst+=" De kluis is open; kijk in ~/.local/state/brug/backup.log wat er misgaat."
else
  tekst+=" De kluis is dicht, daardoor kan er niet gebackupt worden. Open hem met: sudo ./kluis-open.sh"
fi

# Niet blijven zeuren: hooguit eens per BACKUP_WACHTER_HERHAAL_UREN.
if [[ -f "$LAATSTE_MELDING" ]]; then
  vorige="$(cat "$LAATSTE_MELDING" 2>/dev/null || echo 0)"
  (( nu - vorige < BACKUP_WACHTER_HERHAAL_UREN * 3600 )) && exit 0
fi

"$HOME/.local/bin/melding-sturen.sh" "QuitChat: backup te oud" "$tekst" high
echo "$nu" > "$LAATSTE_MELDING"
