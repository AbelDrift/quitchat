#!/usr/bin/env bash
# QuitChat – na het opstarten van de pc (bijv. na een stroomstoring):
# pushmelding naar je telefoon met een link naar de burner-pagina, en de
# tijd waarvoor je de kluis moet openen (anders volgt de auto-burn).
# Draait als gebruikersdienst (quitchat-opstart-melding.service).
set -euo pipefail

mountpoint -q /srv/brug && exit 0   # kluis al open: niets te melden

ADRES="$(head -n1 "$HOME/.config/brug/adres" 2>/dev/null | tr -d '[:space:]')"
ADRES="${ADRES%/}"
GRACE="$(cat /var/lib/quitchat-burner/grace-minuten 2>/dev/null || echo 60)"
[[ "$GRACE" =~ ^[0-9]+$ ]] || GRACE=60
OPGESTART="$(date -d "$(uptime -s)" +%s)"
UITERLIJK="$(date -d "@$(( OPGESTART + GRACE * 60 ))" +%H:%M)"

if [[ -f /var/lib/quitchat-burner/scherp ]]; then
  TEKST="Let op: scherp stond aan, de kluis wordt direct gewist."
else
  TEKST="Open de kluis vóór $UITERLIJK, anders wordt hij gewist. Tik hier om te openen."
fi

# Wachten tot ntfy (via Tailscale) bereikbaar is, hooguit 5 minuten.
for _ in $(seq 1 30); do
  "$HOME/.local/bin/melding-sturen.sh" "QuitChat: pc opnieuw opgestart" "$TEKST" urgent \
    "${ADRES:+$ADRES/burner/}" && exit 0
  sleep 10
done
exit 1
