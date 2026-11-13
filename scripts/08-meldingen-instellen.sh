#!/usr/bin/env bash
# QuitChat – thuis-server, stap 8
# Pushmeldingen op je telefoon (via ntfy) als er iets mis is met de backups:
#   - de dagelijkse backup of de trigger-controle mislukt;
#   - de nieuwste backup is ouder dan 36 uur (bijv. omdat de kluis dicht is,
#     dan draait de backup niet en zou je anders niets merken).
# Veilig om opnieuw te draaien: bestaande instellingen blijven staan.
#
# Gebruik: ./08-meldingen-instellen.sh [ntfy-server]
#   ntfy-server: bijv. https://ntfy.sh of je eigen server
#                (https://<jouw-pc>.<tailnet>.ts.net:10000)
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
  echo "Start dit script zonder sudo: ./08-meldingen-instellen.sh"
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HOME/.local/bin"
CONF="$HOME/.config/brug/melding.conf"
UNITS="$HOME/.config/systemd/user"
mkdir -p "$BIN" "$UNITS" "$(dirname "$CONF")"

echo "==> Scripts op hun plek zetten"
install -m 755 "$SCRIPT_DIR/melding-sturen.sh" "$BIN/melding-sturen.sh"
install -m 755 "$SCRIPT_DIR/backup-wachter.sh" "$BIN/backup-wachter.sh"
install -m 755 "$SCRIPT_DIR/opstart-melding.sh" "$BIN/opstart-melding.sh"

echo "==> ntfy instellen"
if [[ -f "$CONF" ]]; then
  echo "    $CONF bestaat al; niet aangepast."
else
  SERVER="${1:-}"
  if [[ -z "$SERVER" ]]; then
    echo "    Welke ntfy-server? Bijv. https://ntfy.sh of je eigen server."
    read -r -p "    ntfy-server: " SERVER
  fi
  SERVER="${SERVER%/}"
  [[ "$SERVER" =~ ^https?:// ]] || { echo "Geen geldig adres: $SERVER"; exit 1; }
  # Een willekeurige topic-naam: wie de naam kent, kan meelezen.
  TOPIC="quitchat-$(tr -dc 'a-z0-9' < /dev/urandom | head -c 20 || true)"
  umask 077
  cat > "$CONF" <<CONF
# QuitChat – pushmeldingen via ntfy.
# Abonneer je in de ntfy-app op deze server en dit topic.
# De topic-naam is geheim: wie hem kent, kan je meldingen lezen.
MELDING_NTFY_SERVER=$SERVER
MELDING_NTFY_TOPIC=$TOPIC
CONF
  echo "    Opgeslagen in $CONF"
fi

echo "==> Systemd: melding bij mislukken + backup-wachter"
cat > "$UNITS/quitchat-melding@.service" <<'UNIT'
[Unit]
Description=QuitChat melding: %i is mislukt

[Service]
Type=oneshot
ExecStart=%h/.local/bin/melding-sturen.sh "QuitChat: %i mislukt" "Bekijk wat er misging met: journalctl --user -u %i" high
UNIT

for svc in quitchat-backup quitchat-backup-triggers; do
  mkdir -p "$UNITS/$svc.service.d"
  cat > "$UNITS/$svc.service.d/melding.conf" <<'UNIT'
# Stuurt een pushmelding als deze dienst mislukt (zie 08-meldingen-instellen.sh).
[Unit]
OnFailure=quitchat-melding@%n.service
UNIT
done

cat > "$UNITS/quitchat-backup-wachter.service" <<'UNIT'
[Unit]
Description=QuitChat backup-wachter (melding als de nieuwste backup te oud is)

[Service]
Type=oneshot
ExecStart=%h/.local/bin/backup-wachter.sh
UNIT

cat > "$UNITS/quitchat-backup-wachter.timer" <<'UNIT'
[Unit]
Description=QuitChat backup-wachter-timer

[Timer]
OnBootSec=30min
OnUnitActiveSec=6h
Persistent=true

[Install]
WantedBy=timers.target
UNIT

# Na het opstarten van de pc (bijv. stroomstoring): melding met link naar de
# burner-pagina en de uiterste tijd om de kluis te openen. Loopt ook zonder
# dat je inlogt (lingering staat aan via 05-backups-instellen.sh).
cat > "$UNITS/quitchat-opstart-melding.service" <<'UNIT'
[Unit]
Description=QuitChat melding na opstarten: open de kluis

[Service]
Type=oneshot
ExecStart=%h/.local/bin/opstart-melding.sh

[Install]
WantedBy=default.target
UNIT

# En op de pc zelf: na inloggen de burner-pagina openen als de kluis dicht is.
ADRES="$(head -n1 "$HOME/.config/brug/adres" 2>/dev/null | tr -d '[:space:]')"
if [[ -n "$ADRES" ]]; then
  mkdir -p "$HOME/.config/autostart"
  cat > "$HOME/.config/autostart/quitchat-kluis-openen.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=QuitChat: kluis openen
Comment=Opent de burner-pagina na het opstarten als de kluis nog dicht is
Exec=sh -c 'sleep 15; mountpoint -q /srv/brug || xdg-open ${ADRES%/}/burner/'
X-GNOME-Autostart-enabled=true
DESKTOP
fi

systemctl --user daemon-reload
systemctl --user enable --now quitchat-backup-wachter.timer >/dev/null
systemctl --user enable quitchat-opstart-melding.service >/dev/null

echo "==> Testmelding sturen"
if "$BIN/melding-sturen.sh" "QuitChat: meldingen werken" \
     "Je krijgt hier een bericht als een backup mislukt of te oud is."; then
  echo "    Verstuurd."
else
  echo "    Versturen mislukt; zie ~/.local/state/brug/melding.log"
fi

# shellcheck disable=SC1090
source "$CONF"
cat <<TEKST

Klaar. Op je telefoon:
  1. Installeer de app ntfy (F-Droid of Play Store).
  2. Tik op + en vul in:
       Topic:  $MELDING_NTFY_TOPIC
       Server: $MELDING_NTFY_SERVER   (zet "Andere server gebruiken" aan)
  3. Je zou nu de testmelding moeten zien.

Zelf een melding testen:  melding-sturen.sh "Test" "Hallo"
TEKST
