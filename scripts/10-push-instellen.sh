#!/usr/bin/env bash
# QuitChat – thuis-server, stap 10 (eenmalig)
# Pushmeldingen voor de app (QuitChat, FluffyChat, Element X) via je eigen ntfy.
#
# Het probleem: de app vraagt Synapse om pushberichten naar je ntfy-server te
# sturen (https://<naam>.ts.net:10000). Synapse draait in Docker, en Tailscale
# neemt alleen verbindingen aan die via de tailnet binnenkomen. Vanuit Docker
# krijgt Synapse "connection refused", en je krijgt geen meldingen.
#
# De oplossing:
#  1. Een doorgeefluik op de Docker-host (systemd, geen extra pakketten). Het
#     luistert op <docker-gateway>:<ntfy-poort> en geeft de versleutelde
#     verbinding ongewijzigd door aan Tailscale, zodat het certificaat blijft
#     kloppen. Alleen containers (172.16.0.0/12) mogen erop.
#  2. "brug" stuurt Synapse voor de ntfy-naam naar dat doorgeefluik
#     (extra_hosts) en zet dat ene adres op de witte lijst van Synapse. Dat
#     gebeurt na elke "brug up" opnieuw, omdat muxbee de instellingen dan
#     overschrijft.
#
# Gebruik: sudo ./10-push-instellen.sh   (veilig om opnieuw te draaien)
# Ongedaan maken:
#   sudo systemctl disable --now quitchat-push.socket quitchat-push.service
#   sudo rm /etc/systemd/system/quitchat-push.{socket,service}
#   brug up
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Start dit script met: sudo ./10-push-instellen.sh"
  exit 1
fi
GEBRUIKER="${SUDO_USER:-}"
if [[ -z "$GEBRUIKER" || "$GEBRUIKER" == root ]]; then
  echo "Start dit script met sudo vanuit je eigen account (niet als root)."
  exit 1
fi
HOME_USER="$(getent passwd "$GEBRUIKER" | cut -d: -f6)"
MELDING_CONF="$HOME_USER/.config/brug/melding.conf"

# Adres van je ntfy-server, uit de instellingen van 08-meldingen-instellen.sh.
server=""
[[ -f "$MELDING_CONF" ]] \
  && server="$(sed -n 's/^MELDING_NTFY_SERVER=//p' "$MELDING_CONF" | tr -d "\"' " | head -n1)"
if [[ "$server" != https://* ]]; then
  echo "Geen eigen ntfy-server (https://...) gevonden in $MELDING_CONF."
  echo "Draai eerst 08-meldingen-instellen.sh met je eigen ntfy-server."
  exit 1
fi
naam="${server#https://}"; naam="${naam%%/*}"
poort=443
[[ "$naam" == *:* ]] && { poort="${naam##*:}"; naam="${naam%%:*}"; }

ts_ip="$(tailscale ip -4 2>/dev/null | head -n1)"
[[ -n "$ts_ip" ]] || { echo "Tailscale draait niet (tailscale ip -4 gaf niets)."; exit 1; }
gw="$(docker network inspect bridge -f '{{(index .IPAM.Config 0).Gateway}}' 2>/dev/null)"
[[ -n "$gw" ]] || { echo "Docker draait niet (geen bridge-netwerk gevonden)."; exit 1; }

echo "==> Doorgeefluik: $gw:$poort -> $ts_ip:$poort ($naam)"
cat > /etc/systemd/system/quitchat-push.socket <<UNIT
[Unit]
Description=QuitChat: doorgeefluik voor push van Synapse (Docker) naar ntfy

[Socket]
ListenStream=$gw:$poort
# Ook binden als docker0 nog geen adres heeft (bij het opstarten).
FreeBind=yes
# Alleen Docker-containers mogen erop, niet de rest van het netwerk.
IPAddressDeny=any
IPAddressAllow=172.16.0.0/12

[Install]
WantedBy=sockets.target
UNIT
cat > /etc/systemd/system/quitchat-push.service <<UNIT
[Unit]
Description=QuitChat: push van Synapse doorgeven aan ntfy via Tailscale
Requires=quitchat-push.socket
After=quitchat-push.socket tailscaled.service

[Service]
ExecStart=/lib/systemd/systemd-socket-proxyd $ts_ip:$poort
DynamicUser=yes
NoNewPrivileges=yes
PrivateTmp=yes
UNIT
systemctl daemon-reload
systemctl enable quitchat-push.socket >/dev/null 2>&1
systemctl restart quitchat-push.socket
systemctl stop quitchat-push.service 2>/dev/null || true   # pakt nieuw doel op

# Geen test vanaf de host: IPAddressAllow laat alleen containers toe, en
# verkeer van de host naar zichzelf komt er niet door. Synapse test hieronder.
echo "==> Synapse instellen (via brug)"
if ! mountpoint -q /srv/brug; then
  echo "    De kluis is dicht. Open hem, dan stelt 'brug up' Synapse vanzelf in."
  exit 0
fi
sudo -u "$GEBRUIKER" -H "$HOME_USER/.local/bin/brug" afstellen

echo "==> Testen vanuit Synapse"
for _ in $(seq 1 20); do
  docker exec muxbee-synapse-1 true 2>/dev/null && break
  sleep 3
done
if docker exec muxbee-synapse-1 python -c \
     "import urllib.request; urllib.request.urlopen('https://$naam:$poort/v1/health', timeout=10)" 2>/dev/null; then
  echo "    Synapse bereikt ntfy. Push werkt aan de serverkant."
else
  echo "    Synapse bereikt ntfy nog niet. Wacht een halve minuut en kijk met:"
  echo "    docker exec muxbee-synapse-1 python -c \"import urllib.request; print(urllib.request.urlopen('https://$naam:$poort/v1/health').read())\""
  exit 1
fi
echo
echo "Klaar. Kies op de telefoon in de app (of in Element X) ntfy als"
echo "meldingsdienst, met als server: https://$naam:$poort"
