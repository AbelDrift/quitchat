#!/usr/bin/env bash
# Werkt een bestaande burner bij met de bestanden uit deze repo (app.py,
# templates, wrappers), zonder een nieuwe PIN te maken. 06-burner-instellen.sh
# doet dat wel, dus gebruik dit script na een wijziging in tools/burner/.
#
# Zet ook het eigenaarschap goed: /opt/quitchat-burner is van root, zodat de
# burner-user de wrappers (die via sudo als root draaien) niet kan vervangen.
#
# Gebruik: sudo ./burner-bijwerken.sh
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Start dit script met: sudo ./burner-bijwerken.sh"
  exit 1
fi
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BRON="$SCRIPT_DIR/../tools/burner"
APP_DIR=/opt/quitchat-burner
[[ -d "$APP_DIR" ]] || { echo "Geen burner in $APP_DIR; draai eerst 06-burner-instellen.sh."; exit 1; }

echo "==> Bestanden bijwerken in $APP_DIR"
cp -R "$BRON/app.py" "$BRON/templates" "$BRON/wrappers" "$APP_DIR/"
chmod +x "$APP_DIR"/wrappers/*.sh
chown -R root:root "$APP_DIR"
chmod -R go-w "$APP_DIR"

echo "==> Web-app herstarten"
systemctl restart quitchat-burner.service
systemctl is-active -q quitchat-burner.service && echo "    De burner draait weer."
