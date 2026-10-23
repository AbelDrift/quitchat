#!/usr/bin/env bash
# QuitChat – geheimen-check
# Zoekt naar dingen die nooit in een openbare repository horen:
# wachtwoorden, sleutels, herstelcodes, Tailscale-adressen, telefoonnummers
# en bestanden uit de kluis.
#
# Gebruik:
#   tools/geheimen-check.sh            controleert wat klaarstaat voor een commit
#   tools/geheimen-check.sh --alles    controleert alle bestanden in de repository
#
# Wordt automatisch uitgevoerd vóór elke commit als je eenmalig draait:
#   git config core.hooksPath .githooks
set -euo pipefail

ZELF="tools/geheimen-check.sh"

# Bestandsnamen die nooit in de repository mogen.
VERBODEN_NAMEN='(^|/)(settings\.yaml|homeserver\.yaml|registration\.yaml|config\.yaml|adres|matrix-client\.json|id_[a-z0-9]+|[^/]*\.(kluis|signing\.key|key|pem|db|sqlite3?))$'

# Inhoud die nooit in de repository mag (uitgebreide reguliere expressies).
PATRONEN=(
  'privésleutel|-----BEGIN [A-Z ]*PRIVATE KEY-----'
  'Tailscale-adres van een apparaat|[a-z0-9-]+\.tail[0-9a-f]{4,}\.ts\.net'
  'Tailscale-IP-adres|(^|[^0-9.])100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}([^0-9]|$)'
  'telefoonnummer|\+[1-9][0-9]{9,13}([^0-9]|$)'
  'herstelcode van de kluis|(^|[^A-Z0-9])[A-HJ-NP-Z2-9]{4}(-[A-HJ-NP-Z2-9]{4}){7}([^A-Z0-9]|$)'
  'Matrix-toegangssleutel|syt_[A-Za-z0-9_]{10,}'
  'bridge- of appservice-sleutel|(as_token|hs_token|registration_shared_secret|macaroon_secret_key|form_secret)[\"'"'"']?[:=][ ]*[\"'"'"']?[A-Za-z0-9_-]{16,}'
  'wachtwoord in een instelling|(password|wachtwoord)[\"'"'"']?[ ]*[:=][ ]*[\"'"'"']?[^ \"'"'"'$<{][^ \"'"'"']{7,}'
)

if [[ "${1:-}" == "--alles" ]]; then
  mapfile -t BESTANDEN < <(git ls-files)
  lees() { cat -- "$1"; }
else
  mapfile -t BESTANDEN < <(git diff --cached --name-only --diff-filter=ACMR)
  lees() { git show ":$1"; }
fi

FOUTEN=0
for f in "${BESTANDEN[@]}"; do
  [[ -z "$f" || "$f" == "$ZELF" ]] && continue
  if [[ "$f" =~ $VERBODEN_NAMEN ]]; then
    echo "STOP  $f: dit soort bestand hoort niet in de repository."
    FOUTEN=$((FOUTEN + 1))
    continue
  fi
  inhoud="$(lees "$f" 2>/dev/null || true)"
  for p in "${PATRONEN[@]}"; do
    uitleg="${p%%|*}"
    regex="${p#*|}"
    if treffers="$(printf '%s\n' "$inhoud" | grep -nE -- "$regex" | head -n 3)"; then
      [[ -n "$treffers" ]] || continue
      echo "STOP  $f: mogelijk een $uitleg"
      printf '%s\n' "$treffers" | cut -c1-120 | sed 's/^/        regel /'
      FOUTEN=$((FOUTEN + 1))
    fi
  done
done

if (( FOUTEN > 0 )); then
  echo
  echo "Er zijn $FOUTEN mogelijke geheimen gevonden. Er is NIETS opgeslagen."
  echo "Haal ze weg (of vervang ze door een voorbeeld zoals jouw-pc.tailXXXX.ts.net)"
  echo "en probeer het opnieuw. Zeker weten dat het veilig is? git commit --no-verify"
  exit 1
fi
echo "Geheimen-check: niets gevonden."
