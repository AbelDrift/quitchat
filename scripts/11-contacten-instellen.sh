#!/usr/bin/env bash
# QuitChat – thuis-server, stap 11 (eenmalig, zonder sudo)
# Laat de server elk uur de telefoonnummers van je chatcontacten aan de app
# doorgeven (contacten-nummers.py), zodat de app de kanalen van één persoon
# kan samenvoegen tot één contact. Alles blijft op je eigen server.
#
# De eerste keer logt het script in op je Matrix-account (apparaat
# "QuitChat contacten (server)"); de sleutel daarvan staat in de kluis.
#
# Gebruik: ./11-contacten-instellen.sh
# Ongedaan maken: systemctl --user disable --now quitchat-contacten.timer
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HOME/.local/bin"
UNITS="$HOME/.config/systemd/user"
mkdir -p "$BIN" "$UNITS"

python3 -I "$SCRIPT_DIR/contacten-nummers.py" --test
install -m 755 "$SCRIPT_DIR/contacten-nummers.py" "$BIN/contacten-nummers.py"

cat > "$UNITS/quitchat-contacten.service" <<UNIT
[Unit]
Description=QuitChat: telefoonnummers van contacten voor de app

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 -I %h/.local/bin/contacten-nummers.py
UNIT
cat > "$UNITS/quitchat-contacten.timer" <<UNIT
[Unit]
Description=QuitChat: contacten elk uur bijwerken

[Timer]
OnBootSec=15min
OnUnitActiveSec=1h

[Install]
WantedBy=timers.target
UNIT
systemctl --user daemon-reload
systemctl --user enable --now quitchat-contacten.timer
systemctl --user start quitchat-contacten.service
journalctl --user -u quitchat-contacten.service -n 1 --no-pager -o cat
echo "Klaar. De nummers worden elk uur bijgewerkt."
