#!/usr/bin/env bash
# QuitChat – thuis-server, stap 3
# Downloadt muxbee en maakt het commando "brug". Dat zorgt ervoor dat muxbee
# altijd vanuit de versleutelde kluis werkt, de rechten voor Docker goed staan
# en de bridges op een vaste, stabiele versie blijven.
# Gebruik: ./03-muxbee-installeren.sh   (zonder sudo)
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
  echo "Start dit script zonder sudo: ./03-muxbee-installeren.sh"
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  echo "Docker werkt nog niet voor jouw account."
  echo "Log na stap 1 uit en weer in, of typ eerst: newgrp docker"
  exit 1
fi

BIN="$HOME/.local/bin"
CONF="$HOME/.config/brug"
mkdir -p "$BIN" "$CONF"

case "$(uname -m)" in
  x86_64|amd64)  ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) echo "Onbekende processor: $(uname -m)"; exit 1 ;;
esac

echo "==> Laatste versie van muxbee opzoeken"
VERSIE="$(curl -fsSL https://api.github.com/repos/tobocop2/muxbee/releases/latest \
  | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/' || true)"
if [[ -z "$VERSIE" ]]; then
  echo "Kon geen versie van muxbee vinden. Controleer je internetverbinding."
  exit 1
fi

echo "==> muxbee ${VERSIE} downloaden"
curl -fSL "https://github.com/tobocop2/muxbee/releases/download/${VERSIE}/muxbee-linux-${ARCH}" \
  -o "$BIN/muxbee"
chmod +x "$BIN/muxbee"

echo "==> Vaste bridge-versies instellen"
if [[ ! -f "$CONF/versies.conf" ]]; then
  cat > "$CONF/versies.conf" <<'CONF'
# Vaste (stabiele) versies van de bridges.
# Muxbee haalt anders altijd de nieuwste testversie op, en die kan haperen.
# Nieuwe stabiele versies verschijnen rond de 16e van elke maand:
# https://mau.fi/blog/  Pas het nummer hier aan en draai: brug update
#
# Formaat: <naam> <versie>
signal   v26.10
whatsapp v26.10
# Telegram: muxbee maakt instellingen voor de oude (Python-)bridge, dus de
# laatste oude versie. Nieuwe Telegram-versies heten v0.2610.0 enz.
telegram v0.15.3
CONF
else
  echo "    $CONF/versies.conf bestaat al; niet aangepast."
fi

echo "==> Commando 'brug' maken"
cat > "$BIN/brug" <<'SCRIPT'
#!/usr/bin/env bash
# "brug" = muxbee, maar:
#  - altijd met alle gegevens in de versleutelde kluis (/srv/brug);
#  - met de juiste rechten voor Synapse (991) en de bridges (1337);
#  - met de bridges op de vaste versies uit ~/.config/brug/versies.conf.
set -euo pipefail
MAP=/srv/brug
VERSIES="$HOME/.config/brug/versies.conf"
MUXBEE="$HOME/.local/bin/muxbee"

if ! mountpoint -q "$MAP"; then
  echo "De kluis is dicht. Open hem eerst met: sudo ./kluis-open.sh"
  exit 1
fi
export XDG_CONFIG_HOME="$MAP/config"
export XDG_DATA_HOME="$MAP/data"

rechten_zetten() {
  local d wie
  wie="$(id -un)"
  for d in "$MAP"/config/muxbee/synapse "$MAP"/data/muxbee/synapse \
           "$MAP"/config/muxbee/bridges "$MAP"/data/muxbee/bridges; do
    mkdir -p "$d" 2>/dev/null || sudo mkdir -p "$d"
    sudo setfacl -R -m "u:$wie:rwX,u:991:rwX,u:1337:rwX,d:u:$wie:rwX,d:u:991:rwX,d:u:1337:rwX" "$d"
  done
}

# Zet elke bridge uit versies.conf vast: haal de vaste versie op (als die er
# nog niet is, of bij ophalen=ja) en laat "latest" ernaar wijzen.
versies_vastzetten() {
  local ophalen="${1:-nee}" naam versie img
  [[ -f "$VERSIES" ]] || return 0
  while read -r naam versie _; do
    [[ -z "${naam:-}" || "$naam" == \#* || -z "${versie:-}" ]] && continue
    img="dock.mau.dev/mautrix/$naam"
    if [[ "$ophalen" == "ja" ]] || ! docker image inspect "$img:$versie" >/dev/null 2>&1; then
      echo "==> $naam $versie ophalen"
      docker pull -q "$img:$versie" >/dev/null
    fi
    docker tag "$img:$versie" "$img:latest"
  done < "$VERSIES"
}

# Het adres waarop je telefoon de server bereikt (bijv. via Tailscale).
# Muxbee zet Synapse bij elke start op http://localhost:8008; apps als
# Element X gaan dan na het inloggen naar "localhost" en blijven offline.
# Staat er een adres in ~/.config/brug/adres, dan zetten we dat na elke start goed.
ADRES_CONF="$HOME/.config/brug/adres"
adres_zetten() {
  [[ -f "$ADRES_CONF" ]] || return 0
  local adres hs
  adres="$(head -n1 "$ADRES_CONF" | tr -d '[:space:]')"
  adres="${adres%/}"
  [[ -n "$adres" ]] || return 0
  hs="$MAP/config/muxbee/synapse/homeserver.yaml"
  [[ -f "$hs" ]] || { echo "Let op: $hs niet gevonden; adres niet ingesteld."; return 0; }
  sed -i '/^public_baseurl:/d' "$hs"
  printf 'public_baseurl: "%s/"\n' "$adres" >> "$hs"
  echo "==> Synapse herstarten met adres $adres"
  docker restart muxbee-synapse-1 >/dev/null
  echo "    Klaar (Synapse is over ongeveer 20 seconden weer bereikbaar)."
}

case "${1:-}" in
  update)
    # Niet muxbee update gebruiken: dat haalt testversies van de bridges op.
    rechten_zetten
    echo "==> Synapse en Element bijwerken"
    docker pull -q matrixdotorg/synapse:latest >/dev/null
    docker pull -q vectorim/element-web:latest >/dev/null
    versies_vastzetten ja
    "$MUXBEE" up
    adres_zetten
    exit 0
    ;;
  ""|tui|up|init|bridge|restore)
    rechten_zetten
    [[ "${1:-}" == "init" ]] || versies_vastzetten
    # Aan- of uitzetten van een bridge herstart Synapse met http://localhost:8008;
    # zet daarna het echte adres weer goed.
    if [[ "${1:-}" == "bridge" && ( "${2:-}" == "enable" || "${2:-}" == "disable" ) ]]; then
      "$MUXBEE" "$@"
      adres_zetten
      exit 0
    fi
    # "up --pull" zou testversies ophalen; daarom zonder --pull.
    if [[ "${1:-}" == "up" ]]; then
      shift
      args=()
      for a in "$@"; do [[ "$a" == "--pull" ]] || args+=("$a"); done
      "$MUXBEE" up "${args[@]+"${args[@]}"}"
      adres_zetten
      exit 0
    fi
    ;;
esac
exec "$MUXBEE" "$@"
SCRIPT
chmod +x "$BIN/brug"

echo
"$BIN/muxbee" --version || true
echo
if [[ ":$PATH:" != *":$BIN:"* ]]; then
  echo "Let op: $BIN staat nog niet in je PATH."
  echo "Log uit en weer in, dan werkt het commando 'brug' overal."
fi
echo "Klaar. Volg nu stap 4 in docs/installatie.md."
