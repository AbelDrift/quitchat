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
# Telegram: de nieuwe Go-bridge. Muxbee maakt nog instellingen voor de oude
# Python-bridge (v0.15.3); die kan niet meer inloggen. Draai na
# "brug bridge enable telegram" daarom ./07-bridges-afstellen.sh, dat zet de
# instellingen om naar het nieuwe formaat.
telegram v26.10
discord  v0.7.7
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

# Muxbee schrijft bij elke start (ook via tui, bridge, restore) de
# Synapse-instellingen opnieuw. Daarna zetten we twee dingen goed:
#  - Het adres waarop je telefoon de server bereikt (~/.config/brug/adres).
#    Muxbee zet http://localhost:8008; apps als Element X gaan dan na het
#    inloggen naar "localhost" en blijven offline.
#  - Push naar je eigen ntfy (als 10-push-instellen.sh gedraaid is). Synapse
#    in Docker kan de Tailscale-naam niet zelf bereiken; via extra_hosts gaat
#    hij naar het doorgeefluik op de Docker-host. Synapse blokkeert privé-
#    adressen standaard, daarom staat dat ene adres op de witte lijst.
# Veilig om vaak te draaien: Synapse herstart alleen als er iets veranderde.
ADRES_CONF="$HOME/.config/brug/adres"
synapse_afstellen() {
  [[ -f "$ADRES_CONF" ]] || return 0
  local adres naam gw hs dc hs_oud
  adres="$(head -n1 "$ADRES_CONF" | tr -d '[:space:]')"
  adres="${adres%/}"
  [[ -n "$adres" ]] || return 0
  naam="${adres#*://}"; naam="${naam%%[:/]*}"
  hs="$MAP/config/muxbee/synapse/homeserver.yaml"
  dc="$MAP/config/muxbee/docker-compose.yml"
  [[ -f "$hs" ]] || { echo "Let op: $hs niet gevonden; adres niet ingesteld."; return 0; }
  hs_oud="$(md5sum < "$hs")"
  if ! grep -qxF "public_baseurl: \"$adres/\"" "$hs"; then
    sed -i '/^public_baseurl:/d' "$hs"
    printf 'public_baseurl: "%s/"\n' "$adres" >> "$hs"
  fi
  if systemctl is-enabled -q quitchat-push.socket 2>/dev/null && [[ -f "$dc" ]]; then
    gw="$(docker network inspect bridge -f '{{(index .IPAM.Config 0).Gateway}}')"
    if ! grep -qxF "ip_range_whitelist: [\"$gw\"]" "$hs"; then
      sed -i '/^ip_range_whitelist:/d' "$hs"
      printf 'ip_range_whitelist: ["%s"]\n' "$gw" >> "$hs"
    fi
    grep -qF "$naam:host-gateway" "$dc" \
      || sed -i "/^  synapse:\$/a\\    extra_hosts: [\"$naam:host-gateway\"]" "$dc"
    # Docker bewaart het als "naam:host-gateway" of (nieuwer) "naam=host-gateway".
    if ! docker inspect -f '{{.HostConfig.ExtraHosts}}' muxbee-synapse-1 2>/dev/null \
         | grep -qE "$naam[:=]host-gateway"; then
      echo "==> Synapse opnieuw aanmaken (adres $adres, push via ntfy)"
      local uit
      if uit="$(CONFIG_DIR="$MAP/config/muxbee" DATA_DIR="$MAP/data/muxbee" \
                docker compose -f "$dc" up -d --no-deps synapse 2>&1)"; then
        echo "    Klaar (Synapse is over ongeveer 20 seconden weer bereikbaar)."
      else
        grep -v 'variable is not set' <<< "$uit" >&2
        echo "Let op: Synapse opnieuw aanmaken lukte niet; probeer: brug up" >&2
      fi
      return 0
    fi
  fi
  if [[ "$(md5sum < "$hs")" != "$hs_oud" ]]; then
    echo "==> Synapse herstarten met adres $adres"
    docker restart muxbee-synapse-1 >/dev/null
    echo "    Klaar (Synapse is over ongeveer 20 seconden weer bereikbaar)."
  fi
}

# Muxbee schrijft bij elke "up" de bridge-instellingen opnieuw (oude
# Telegram-config, 50 berichten geschiedenis, statussen uit). Zet ze daarna
# weer goed met 07-bridges-afstellen.sh (geïnstalleerd als bridges-afstellen.sh).
bridges_afstellen() {
  local s="$HOME/.local/bin/bridges-afstellen.sh"
  [[ -x "$s" ]] || return 0
  echo "==> Bridge-instellingen herstellen"
  "$s" || echo "Let op: bridges-afstellen.sh gaf een fout."
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
    synapse_afstellen
    bridges_afstellen
    exit 0
    ;;
  afstellen)
    # Alleen de Synapse-instellingen goedzetten (gebruikt door 10-push-instellen.sh).
    synapse_afstellen
    exit 0
    ;;
  ""|tui|up|init|bridge|restore)
    rechten_zetten
    [[ "${1:-}" == "init" ]] || versies_vastzetten
    # "up --pull" zou testversies ophalen; daarom zonder --pull.
    if [[ "${1:-}" == "up" ]]; then
      shift
      args=()
      for a in "$@"; do [[ "$a" == "--pull" ]] || args+=("$a"); done
      "$MUXBEE" up "${args[@]+"${args[@]}"}"
      synapse_afstellen
      bridges_afstellen
      exit 0
    fi
    # De rest (tui, bridge enable/disable, restore) kan Synapse terugzetten
    # op http://localhost:8008; zet daarna het echte adres weer goed.
    status=0
    "$MUXBEE" "$@" || status=$?
    synapse_afstellen
    exit "$status"
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
