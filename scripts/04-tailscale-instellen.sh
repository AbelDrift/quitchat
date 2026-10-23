#!/usr/bin/env bash
# QuitChat – thuis-server, stap 4
# Maakt je server bereikbaar voor je eigen telefoon via Tailscale, met HTTPS.
# Alleen jouw eigen apparaten in Tailscale kunnen erbij, niet de rest van internet.
# Gebruik: ./04-tailscale-instellen.sh   (zonder sudo; vraagt zelf om je wachtwoord)
set -euo pipefail

CONF="$HOME/.config/brug"

if [[ $EUID -eq 0 ]]; then
  echo "Start dit script zonder sudo: ./04-tailscale-instellen.sh"
  exit 1
fi
command -v brug >/dev/null || { echo "Het commando 'brug' ontbreekt; draai eerst stap 3."; exit 1; }
mountpoint -q /srv/brug || { echo "De kluis is dicht. Open hem eerst met: sudo ./kluis-open.sh"; exit 1; }
mkdir -p "$CONF"

if ! command -v tailscale >/dev/null; then
  echo "==> Tailscale installeren"
  curl -fsSL https://tailscale.com/install.sh | sudo sh
fi

if ! tailscale status >/dev/null 2>&1; then
  echo "==> Inloggen bij Tailscale"
  echo "    Open de link die zo verschijnt en log in (of maak een gratis account)."
  sudo tailscale up
fi

NAAM="$(tailscale status --json | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')"
if [[ -z "$NAAM" || "$NAAM" != *.ts.net ]]; then
  echo "Kon de Tailscale-naam van deze pc niet vinden. Staat MagicDNS aan?"
  echo "Kijk op https://login.tailscale.com/admin/dns"
  exit 1
fi
ADRES="https://$NAAM"

cat <<TEKST

==> Eenmalig in de browser:
    Ga naar https://login.tailscale.com/admin/dns en zet aan:
      - MagicDNS
      - HTTPS Certificates ("Enable HTTPS")

TEKST
read -r -p "Druk op Enter als dat aan staat..." _

echo "==> HTTPS instellen voor $ADRES"
# Het "visitekaartje" van de server: vertelt apps op welk adres de server zit.
printf '{"m.homeserver":{"base_url":"%s"}}\n' "$ADRES" > "$CONF/matrix-client.json"
sudo tailscale serve --bg http://localhost:8008
sudo tailscale serve --bg --set-path /.well-known/matrix/client "$CONF/matrix-client.json"

echo "==> Adres opslaan zodat 'brug' Synapse er na elke start op zet"
echo "$ADRES" > "$CONF/adres"
brug up

cat <<TEKST

Klaar. Je server is nu (alleen voor jouw Tailscale-apparaten) bereikbaar op:

    $ADRES

Op je telefoon:
  1. Installeer Tailscale, log in met hetzelfde account en zet het aan.
  2. Test in de browser: $ADRES/_matrix/client/versions
     (je ziet tekst met "versions" erin; de eerste keer kan 30 sec. duren)
  3. Installeer Element X (of FluffyChat) → Inloggen →
     Account-provider wijzigen → $NAAM → admin + je wachtwoord.
  4. Verifieer de telefoon via Element Web op deze pc
     (Settings → Devices), of met je herstelsleutel van Element.
TEKST
