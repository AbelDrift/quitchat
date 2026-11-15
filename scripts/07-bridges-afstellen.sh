#!/usr/bin/env bash
# QuitChat – thuis-server, stap 7b
# Stelt de bridges af op wat muxbee zelf niet goed doet:
#   1. Telegram: muxbee maakt instellingen voor de oude Python-bridge
#      (v0.15.3). Die kan niet meer inloggen (Telegram weigert de oude
#      API-laag: "Connection not initialized"). De nieuwe Go-bridge (v26.xx)
#      zet oude instellingen niet meer zelf om ("Legacy bridge config
#      detected"). Dit script maakt een nieuwe config in het Go-formaat en
#      neemt je API-sleutel, tokens en rechten over.
#   2. Geschiedenis: Synapse kan achteraf geen oudere berichten in een chat
#      invoegen (dat kan alleen Beeper). Hoeveel geschiedenis je krijgt, wordt
#      dus bepaald op het moment dat een chat wordt aangemaakt. Muxbee zet dat
#      op 50 berichten; dit script zet het hoger.
#
# Gebruik: ./07-bridges-afstellen.sh            (zonder sudo, kluis open)
#          ./07-bridges-afstellen.sh --droog    (alleen laten zien wat er zou veranderen)
#
# Draai dit opnieuw na elke "brug bridge enable telegram": muxbee schrijft dan
# weer een config in het oude formaat.
set -euo pipefail

# Aantal berichten dat een nieuwe chat meekrijgt.
WHATSAPP_GESCHIEDENIS="${WHATSAPP_GESCHIEDENIS:-10000}"
TELEGRAM_GESCHIEDENIS="${TELEGRAM_GESCHIEDENIS:-2000}"
# WhatsApp-statussen van je contacten tonen (kamer "WhatsApp Status").
WHATSAPP_STATUS_BEKIJKEN="${WHATSAPP_STATUS_BEKIJKEN:-ja}"
# Je eigen status plaatsen: wat je in die kamer stuurt, wordt je status op
# WhatsApp. De QuitChat-app doet dat met de knop "Status plaatsen" en toont
# de kamer niet als gewone chat.
WHATSAPP_STATUS_PLAATSEN="${WHATSAPP_STATUS_PLAATSEN:-ja}"
# Namen zonder " (WA)" enz. erachter.
NAAM_ZONDER_KANAAL="${NAAM_ZONDER_KANAAL:-ja}"

BRIDGES="${BRIDGES_DIR:-/srv/brug/data/muxbee/bridges}"
KOPIE_MAP="${KOPIE_MAP:-/srv/brug/backups/handmatig}"
DROOG=nee
[[ "${1:-}" == "--droog" ]] && DROOG=ja

if [[ $EUID -eq 0 ]]; then
  echo "Start dit script zonder sudo: ./07-bridges-afstellen.sh"
  exit 1
fi
if [[ -z "${BRIDGES_DIR:-}" ]] && ! mountpoint -q /srv/brug; then
  echo "De kluis is dicht. Open hem eerst met: sudo ./kluis-open.sh"
  exit 1
fi

WERK="$(mktemp -d)"
chmod 700 "$WERK"
trap 'rm -rf "$WERK"' EXIT

image_van() { echo "dock.mau.dev/mautrix/$1:latest"; }

# Config lezen en schrijven gaat via een wegwerp-container: de bestanden zijn
# van de bridge-gebruiker (1337) met rechten 0600.
config_lezen() {   # $1 = bridge, $2 = doelbestand
  docker run --rm -v "$BRIDGES/$1:/data:ro" --entrypoint cat "$(image_van "$1")" \
    /data/config.yaml > "$2"
  chmod 600 "$2"
}
config_schrijven() {   # $1 = bridge, $2 = bronbestand
  cp "$2" "$WERK/schrijf.yaml"
  docker run --rm -v "$BRIDGES/$1:/data" -v "$WERK:/w:ro" --entrypoint sh "$(image_van "$1")" \
    -c 'cp /w/schrijf.yaml /data/config.yaml && chown 1337:1337 /data/config.yaml && chmod 600 /data/config.yaml'
}
herstarten() {
  if [[ -n "${QUITCHAT_GEEN_HERSTART:-}" ]]; then return; fi
  docker restart "muxbee-mautrix-$1-1" >/dev/null && echo "    $1 herstart"
}

# Zet in de sectie "backfill:" (bovenste niveau) de waarden goed.
# Geeft exit 0 als er iets veranderd is, 1 als alles al goed stond.
backfill_zetten() {   # $1 = bestand, $2 = aantal berichten
  python3 -I - "$1" "$2" <<'PY'
import re, sys
pad, aantal = sys.argv[1], sys.argv[2]
s = open(pad).read()
m = re.search(r'(?m)^backfill:\n((?:[ #].*\n|\n)*)', s)
if not m:
    sys.exit("Geen 'backfill:'-sectie gevonden in " + pad)
blok = m.group(1)
nieuw = re.sub(r'(?m)^    enabled: .*$', '    enabled: true', blok, count=1)
nieuw = re.sub(r'(?m)^    max_initial_messages: .*$', '    max_initial_messages: ' + aantal, nieuw, count=1)
if nieuw == blok:
    sys.exit(1)
open(pad, 'w').write(s[:m.start(1)] + nieuw + s[m.end(1):])
PY
}

# Oude (Python) Telegram-config omzetten naar het Go-formaat.
telegram_omzetten() {   # $1 = oude config, $2 = uitvoer
  local voorbeeld="$WERK/voorbeeld"
  mkdir -p "$voorbeeld"; chmod 777 "$voorbeeld"
  # Een lege /data laat de bridge een voorbeeldconfig schrijven en stoppen.
  docker run --rm -v "$voorbeeld:/data" "$(image_van telegram)" >/dev/null 2>&1 || true
  docker run --rm -v "$voorbeeld:/data:ro" --entrypoint cat "$(image_van telegram)" \
    /data/config.yaml > "$WERK/voorbeeld.yaml"
  # Het voorbeeld is door de container als root geschreven; daar weer opruimen.
  docker run --rm -v "$voorbeeld:/data" --entrypoint sh "$(image_van telegram)" -c 'rm -rf /data/*'
  python3 -I - "$WERK/voorbeeld.yaml" "$1" "$2" <<'PY'
import os, re, sys
voorbeeld, oud, uit = sys.argv[1:4]
o = open(oud).read()
def waarde(sleutel):
    m = re.search(r'(?m)^\s*' + sleutel + r':\s*["\']?([^"\'\n]+?)["\']?\s*$', o)
    if not m:
        sys.exit("Niet gevonden in de oude config: " + sleutel)
    return m.group(1)
w = {k: waarde(k) for k in ['as_token', 'hs_token', 'api_id', 'api_hash', 'domain']}
hs_adres = re.search(r'(?m)^homeserver:\n(?:\s+#.*\n|\s*\n)*\s+address:\s*(\S+)', o).group(1)
as_adres = re.search(r'(?m)^appservice:\n(?:\s+#.*\n|\s*\n)*\s+address:\s*(\S+)', o).group(1)
# Rechten: oude namen omzetten (relaybot -> relay; full/puppeting -> user).
# Rechten uit bridge.permissions halen, ongeacht de inspringing (muxbee
# gebruikt 2/4 spaties, een volledige oude config 4/8).
perm = re.search(r'(?m)^( +)permissions:\n((?:\1 +.*\n)+)', o)
regels = []
for sleutel, rol in re.findall(r'(?m)^ +["\']?([^"\':]+(?::[^"\':]+)?)["\']?:\s*(\w+)\s*$', perm.group(2) if perm else ''):
    rol = {'relaybot': 'relay', 'full': 'user', 'puppeting': 'user'}.get(rol, rol)
    regels.append(f'        "{sleutel}": {rol}\n')
if not any(r.endswith('admin\n') for r in regels):
    sys.exit("Geen admin gevonden in de oude rechten (bridge.permissions).")
s = open(voorbeeld).read()
def vervang(oud_stuk, nieuw_stuk):
    global s
    if s.count(oud_stuk) != 1:
        sys.exit("Voorbeeldconfig onverwacht (niet precies 1x gevonden): " + oud_stuk.strip()[:50])
    s = s.replace(oud_stuk, nieuw_stuk)
s = re.sub(r'(?m)^    api_id: .*$', f"    api_id: {w['api_id']}", s, count=1)
s = re.sub(r'(?m)^    api_hash: .*$', f"    api_hash: {w['api_hash']}", s, count=1)
s = re.sub(r'(?m)^    permissions:\n(?:        .*\n)+', '    permissions:\n' + ''.join(regels), s, count=1)
vervang("    type: postgres\n", "    type: sqlite3-fk-wal\n")
s = re.sub(r'(?m)^    uri: postgres://.*$', "    uri: file:/data/mautrix-telegram.db?_txlock=immediate", s, count=1)
s = re.sub(r'(?m)^(homeserver:\n(?:.*\n)*?)    address: .*$', lambda m: m.group(1) + f"    address: {hs_adres}", s, count=1)
s = re.sub(r'(?m)^(homeserver:\n(?:.*\n)*?)    domain: .*$', lambda m: m.group(1) + f"    domain: {w['domain']}", s, count=1)
s = re.sub(r'(?m)^(appservice:\n(?:.*\n)*?)    address: .*$', lambda m: m.group(1) + f"    address: {as_adres}", s, count=1)
s = re.sub(r'(?m)^(appservice:\n(?:.*\n)*?)    hostname: .*$', lambda m: m.group(1) + "    hostname: 0.0.0.0", s, count=1)
s = re.sub(r'(?m)^    as_token: .*$', f'    as_token: "{w["as_token"]}"', s, count=1)
s = re.sub(r'(?m)^    hs_token: .*$', f'    hs_token: "{w["hs_token"]}"', s, count=1)
fd = os.open(uit, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
os.write(fd, s.encode()); os.close(fd)
PY
}

veranderd() { echo "  $1: $2"; }

# Is dit een database van de Go-bridge (heeft de tabel user_login)?
is_go_database() {
  python3 -I - "$1" <<'PY' 2>/dev/null
import sqlite3, sys
c = sqlite3.connect("file:" + sys.argv[1] + "?mode=ro", uri=True)
rij = c.execute("select 1 from sqlite_master where name = 'user_login'").fetchone()
sys.exit(0 if rij else 1)
PY
}

# ---- WhatsApp ---------------------------------------------------------------
if [[ -f "$BRIDGES/whatsapp/registration.yaml" ]]; then
  echo "==> WhatsApp"
  config_lezen whatsapp "$WERK/wa.yaml"
  wa_veranderd=nee
  if backfill_zetten "$WERK/wa.yaml" "$WHATSAPP_GESCHIEDENIS"; then
    veranderd whatsapp "nieuwe chats krijgen tot $WHATSAPP_GESCHIEDENIS berichten mee"
    wa_veranderd=ja
  fi
  if [[ "$WHATSAPP_STATUS_BEKIJKEN" == ja ]] && grep -q '^    enable_status_broadcast: false$' "$WERK/wa.yaml"; then
    sed -i 's/^    enable_status_broadcast: false$/    enable_status_broadcast: true/' "$WERK/wa.yaml"
    veranderd whatsapp "statussen van contacten bekijken aan"
    wa_veranderd=ja
  fi
  if [[ "$WHATSAPP_STATUS_PLAATSEN" == ja ]] && grep -q '^    disable_status_broadcast_send: true$' "$WERK/wa.yaml"; then
    sed -i 's/^    disable_status_broadcast_send: true$/    disable_status_broadcast_send: false/' "$WERK/wa.yaml"
    veranderd whatsapp "eigen status plaatsen aan"
    wa_veranderd=ja
  fi
  if [[ "$wa_veranderd" == ja ]]; then
    if [[ "$DROOG" == nee ]]; then config_schrijven whatsapp "$WERK/wa.yaml"; herstarten whatsapp; fi
  else
    echo "  staat al goed"
  fi
fi

# ---- Telegram ---------------------------------------------------------------
if [[ -f "$BRIDGES/telegram/registration.yaml" ]]; then
  echo "==> Telegram"
  config_lezen telegram "$WERK/tg.yaml"
  tg_veranderd=nee
  if grep -q '^telegram:' "$WERK/tg.yaml" && ! grep -q '^network:' "$WERK/tg.yaml"; then
    veranderd telegram "oude (Python-)config omzetten naar de Go-bridge"
    if [[ "$DROOG" == nee ]]; then
      mkdir -p "$KOPIE_MAP"
      kopie="$KOPIE_MAP/telegram-config-oud-$(date +%Y%m%d-%H%M%S).yaml"
      cp "$WERK/tg.yaml" "$kopie"; chmod 600 "$kopie"
      echo "    kopie van de oude config: $kopie"
      # Alleen een database van de oude Python-bridge opzij zetten. Een database
      # van de Go-bridge blijft staan: daarin zit je koppeling. (muxbee schrijft
      # bij elke "brug up" weer een oude config, ook als de Go-bridge al draait.)
      if [[ -s "$BRIDGES/telegram/mautrix-telegram.db" ]] && ! is_go_database "$BRIDGES/telegram/mautrix-telegram.db"; then
        echo "    LET OP: er staat een database van de oude bridge. De Go-bridge zet die"
        echo "    niet betrouwbaar om; hij gaat opzij. Log daarna opnieuw in bij Telegram."
        docker run --rm -v "$BRIDGES/telegram:/data" --entrypoint sh "$(image_van telegram)" \
          -c 'mkdir -p /data/oud && mv /data/mautrix-telegram.db* /data/oud/'
      fi
    fi
    telegram_omzetten "$WERK/tg.yaml" "$WERK/tg-nieuw.yaml"
    mv "$WERK/tg-nieuw.yaml" "$WERK/tg.yaml"
    tg_veranderd=ja
  fi
  if backfill_zetten "$WERK/tg.yaml" "$TELEGRAM_GESCHIEDENIS"; then
    veranderd telegram "nieuwe chats krijgen tot $TELEGRAM_GESCHIEDENIS berichten mee"
    tg_veranderd=ja
  fi
  if [[ "$tg_veranderd" == ja ]]; then
    if [[ "$DROOG" == nee ]]; then config_schrijven telegram "$WERK/tg.yaml"; herstarten telegram; fi
  else
    echo "  staat al goed"
  fi
fi

# Geen " (WA)", " (Signal)" of " (Discord)" achter namen: QuitChat toont het
# kanaal met een logo. Bestaande namen passen zich aan bij de volgende
# profielwijziging of synchronisatie van dat contact.
if [[ "$NAAM_ZONDER_KANAAL" == ja ]]; then
  for b in whatsapp signal discord; do
    [[ -d "$BRIDGES/$b" ]] || continue
    echo "==> Namen ($b)"
    config_lezen "$b" "$WERK/naam.yaml"
    patroon="^( +displayname_template: '.*\}\}) \((WA|Signal|Discord)\)'$"
    if grep -qE "$patroon" "$WERK/naam.yaml"; then
      sed -i -E "s/$patroon/\1'/" "$WERK/naam.yaml"
      veranderd "$b" "geen kanaalnaam meer achter namen"
      if [[ "$DROOG" == nee ]]; then config_schrijven "$b" "$WERK/naam.yaml"; herstarten "$b"; fi
    else
      echo "  staat al goed"
    fi
  done
fi

# Zichzelf installeren, zodat "brug up" dit na elke start kan draaien
# (muxbee schrijft bij elke "up" de bridge-instellingen opnieuw).
if [[ "$DROOG" == nee && -z "${BRIDGES_DIR:-}" ]]; then
  mkdir -p "$HOME/.local/bin"
  install -m 755 "${BASH_SOURCE[0]}" "$HOME/.local/bin/bridges-afstellen.sh" 2>/dev/null || true
fi

[[ "$DROOG" == ja ]] && echo "(droog: er is niets veranderd)"
echo "Klaar."
