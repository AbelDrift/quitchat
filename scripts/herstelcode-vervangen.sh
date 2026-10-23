#!/usr/bin/env bash
# Maakt een nieuwe herstelcode voor de kluis en verwijdert de oude.
# Gebruik: sudo ./herstelcode-vervangen.sh   (je hebt je wachtwoord nodig)
set -euo pipefail

KLUIS=/srv/brug.kluis
SLOT=1   # vak 0 = wachtwoord, vak 1 = herstelcode

if [[ $EUID -ne 0 ]]; then
  echo "Start dit script met: sudo ./herstelcode-vervangen.sh"
  exit 1
fi
[[ -e "$KLUIS" ]] || { echo "Geen kluis gevonden op $KLUIS."; exit 1; }

echo "==> Controle: typ je wachtwoord (niet de herstelcode)."
until cryptsetup open --test-passphrase --key-slot 0 "$KLUIS"; do
  echo "    Dat is niet het wachtwoord. Probeer het opnieuw."
done

HERSTEL="$(tr -dc 'A-HJ-NP-Z2-9' < /dev/urandom | head -c 32 | fold -w4 | paste -sd- || true)"
[[ ${#HERSTEL} -eq 39 ]] || { echo "Herstelcode maken mislukt. Probeer opnieuw."; exit 1; }

if cryptsetup luksDump "$KLUIS" | grep -qE "^[[:space:]]+${SLOT}: luks2"; then
  echo "==> Oude herstelcode verwijderen (typ je wachtwoord)"
  cryptsetup luksKillSlot "$KLUIS" "$SLOT"
fi
echo "==> Nieuwe herstelcode toevoegen (typ je wachtwoord)"
cryptsetup luksAddKey --key-slot "$SLOT" "$KLUIS" <(printf '%s' "$HERSTEL")

clear
cat <<TEKST

  ============================================================
   JOUW NIEUWE HERSTELCODE  -  schrijf deze nu over op papier
  ============================================================

        ${HERSTEL}

  Schrijf de streepjes mee. Bewaar het papier NIET bij de computer.
  De oude herstelcode werkt niet meer.
  ============================================================

TEKST
read -r -p "Druk op Enter als je de code hebt opgeschreven..." _
clear

# Maakt van de invoer de juiste vorm: hoofdletters, geen spaties,
# streepjes op de goede plek. Kleine letters of vergeten streepjes mogen dus.
normaliseer() {
  local s
  # Eerst onzichtbare plak-markeringen (ESC[200~ en ESC[201~) weghalen,
  # daarna alles behalve de tekens die in een herstelcode kunnen voorkomen.
  s="$(printf '%s' "$1" | sed $'s/\x1b\\[[0-9;]*~//g' | tr '[:lower:]' '[:upper:]' | tr -cd 'A-HJ-NP-Z2-9')"
  printf '%s' "$s" | fold -w4 | paste -sd- || true
}

echo "==> Controle: typ de herstelcode over van je papier."
echo "    Typen of plakken mag; kleine letters en spaties ook. Typ 'toon' om de code nog eens te zien."
while true; do
  read -r -p "Herstelcode: " INVOER
  if [[ "${INVOER,,}" == "toon" ]]; then
    echo
    echo "        ${HERSTEL}"
    echo
    continue
  fi
  POGING="$(normaliseer "$INVOER")"
  if printf '%s' "$POGING" | cryptsetup open --test-passphrase --key-slot "$SLOT" --key-file=- "$KLUIS" 2>/dev/null; then
    echo "    Klopt. De nieuwe herstelcode werkt."
    break
  fi
  if [[ "$POGING" == "$HERSTEL" ]]; then
    echo "    De code is goed getypt, maar de kluis accepteert hem niet."
    echo "    Stop met Ctrl+C en stuur de uitvoer van:"
    echo "    sudo cryptsetup luksDump $KLUIS | grep -A3 Keyslots"
    continue
  fi
  echo "    Dat klopt niet (je typte: ${POGING:-niets}). Let op: in de code"
  echo "    komen geen I, O, 0 of 1 voor. Typ 'toon' om hem opnieuw te zien."
done
unset INVOER POGING HERSTEL
clear
echo "Klaar. Bewaar het papier op een veilige plek, niet bij de computer."
