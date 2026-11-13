#!/usr/bin/env bash
# QuitChat – thuis-server, stap 6
# Zet de burner op: web-app via Tailscale, auto-burn-bij-opstart,
# burner-PIN op papier.
# Gebruik: sudo ./06-burner-instellen.sh
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Start dit script met: sudo ./06-burner-instellen.sh"
  exit 1
fi
GEBRUIKER="${SUDO_USER:-}"
if [[ -z "$GEBRUIKER" || "$GEBRUIKER" == "root" ]]; then
  echo "Start dit script met sudo vanaf je eigen account (niet als root)."
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
BURNER_BRON="$REPO_DIR/tools/burner"

if [[ ! -d "$BURNER_BRON" ]]; then
  echo "Kan tools/burner/ niet vinden; staat de repo compleet in $REPO_DIR?"
  exit 1
fi

APP_DIR=/opt/quitchat-burner
STATE_DIR=/var/lib/quitchat-burner
LOG_DIR=/var/log/quitchat-burner
BURNER_USER=quitchat-burner

echo "==> Benodigde pakketten (python3-flask, python3-argon2)"
apt-get update -qq
apt-get install -y python3-flask python3-argon2

echo "==> Systeemgebruiker '$BURNER_USER' maken"
if ! id "$BURNER_USER" >/dev/null 2>&1; then
  useradd --system --home-dir "$APP_DIR" --shell /usr/sbin/nologin "$BURNER_USER"
fi

echo "==> App-bestanden plaatsen in $APP_DIR"
mkdir -p "$APP_DIR" "$STATE_DIR" "$LOG_DIR"
cp -R "$BURNER_BRON/app.py" "$BURNER_BRON/templates" "$BURNER_BRON/wrappers" "$APP_DIR/"
chmod +x "$APP_DIR"/wrappers/*.sh
chown -R "$BURNER_USER":"$BURNER_USER" "$APP_DIR" "$STATE_DIR" "$LOG_DIR"
# De wrappers draaien straks via sudo als root; eigenaarschap root is netter.
chown root:root "$APP_DIR"/wrappers/*.sh
chmod 755 "$APP_DIR/wrappers"

# Default grace-tijd
if [[ ! -f "$STATE_DIR/grace-minuten" ]]; then
  echo 60 > "$STATE_DIR/grace-minuten"
  chown "$BURNER_USER":"$BURNER_USER" "$STATE_DIR/grace-minuten"
fi

# Flask-sessiekey
if [[ ! -f "$STATE_DIR/session.key" ]]; then
  head -c 64 /dev/urandom > "$STATE_DIR/session.key"
  chown "$BURNER_USER":"$BURNER_USER" "$STATE_DIR/session.key"
  chmod 600 "$STATE_DIR/session.key"
fi

echo "==> Sudoers-regels (zodat de burner-user alleen de wrappers mag draaien)"
cat > /etc/sudoers.d/quitchat-burner <<SUDO
# Door /opt/quitchat-burner/ als app-pad te gebruiken, blokkeren we aanpassingen
# door de burner-user zelf; alleen root kan daar schrijven.
Defaults!/opt/quitchat-burner/wrappers/* !requiretty
${BURNER_USER} ALL=(root) NOPASSWD: /opt/quitchat-burner/wrappers/status.sh
${BURNER_USER} ALL=(root) NOPASSWD: /opt/quitchat-burner/wrappers/open-kluis.sh
${BURNER_USER} ALL=(root) NOPASSWD: /opt/quitchat-burner/wrappers/burn.sh --yes
SUDO
chmod 440 /etc/sudoers.d/quitchat-burner
visudo -c -f /etc/sudoers.d/quitchat-burner

echo
echo "==> Burner-PIN maken (6 cijfers)"
PIN="$(tr -dc '0-9' < /dev/urandom | head -c 6 || true)"
[[ ${#PIN} -eq 6 ]] || { echo "PIN maken mislukt."; exit 1; }
printf '%s' "$PIN" | python3 -c "import sys; from argon2 import PasswordHasher; print(PasswordHasher().hash(sys.stdin.read()))" > "$STATE_DIR/pin.hash"
chown "$BURNER_USER":"$BURNER_USER" "$STATE_DIR/pin.hash"
chmod 600 "$STATE_DIR/pin.hash"

clear
cat <<TEKST

  ============================================================
   BURNER-PIN  -  schrijf deze nu over op papier
  ============================================================

                     ${PIN}

  Deze PIN beschermt de web-app van de burner.
  Bewaar hem apart van je kluis-wachtwoord en je herstelcodes.
  De PIN wordt NERGENS op de computer bewaard.
  Vergeten? Draai dit script opnieuw om een nieuwe PIN te maken.
  ============================================================

TEKST
read -r -p "Druk op Enter als je de PIN hebt opgeschreven..." _
unset PIN
clear

echo "==> Systemd-service voor de web-app"
cat > /etc/systemd/system/quitchat-burner.service <<SERVICE
[Unit]
Description=QuitChat Burner web-app
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
Type=simple
User=${BURNER_USER}
WorkingDirectory=${APP_DIR}
ExecStart=/usr/bin/python3 ${APP_DIR}/app.py
Restart=on-failure
# Beperken wat de app kan. Geen NoNewPrivileges: de app moet via sudo de
# wrappers kunnen draaien (sudoers staat alleen die drie toe), en
# NoNewPrivileges blokkeert sudo volledig.
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadWritePaths=${STATE_DIR} ${LOG_DIR}

[Install]
WantedBy=multi-user.target
SERVICE

echo "==> Systemd-service voor auto-burn bij opstart"
cat > /etc/systemd/system/quitchat-auto-burn.service <<SERVICE
[Unit]
Description=QuitChat auto-burn-bij-opstart
After=network-online.target
# Alleen draaien als er een kluis-bestand is
ConditionPathExists=/srv/brug.kluis

[Service]
Type=oneshot
ExecStart=${APP_DIR}/wrappers/auto-burn-bij-opstart.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable --now quitchat-burner.service
systemctl enable quitchat-auto-burn.service  # alleen bij volgende boot actief

echo "==> Tailscale: pad /burner naar de web-app"
# Alleen als tailscale al werkt
if command -v tailscale >/dev/null && tailscale status >/dev/null 2>&1; then
  tailscale serve --bg --set-path /burner http://localhost:9090 || true
  NAAM="$(tailscale status --json | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))' || true)"
  echo
  echo "Burner is bereikbaar op: https://${NAAM:-<je-tailscale-naam>}/burner"
else
  echo "Tailscale is nog niet actief. Draai eerst ./04-tailscale-instellen.sh,"
  echo "en voeg dan de burner handmatig toe aan tailscale serve:"
  echo "    sudo tailscale serve --bg --set-path /burner http://localhost:9090"
fi

echo
echo "Klaar."
echo "  - Open de burner op je telefoon via het adres hierboven."
echo "  - Burn vanaf de pc:    sudo /opt/quitchat-burner/wrappers/burn.sh --yes"
echo "  - Grace-tijd/scherp:   via de web-app, met de burner-PIN."
echo "  - Logboek:             $LOG_DIR/"
