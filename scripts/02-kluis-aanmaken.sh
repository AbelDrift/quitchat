#!/usr/bin/env bash
# QuitChat – thuis-server, stap 2
# Maakt een versleutelde kluis (LUKS2, AES) voor alle gegevens van de brug,
# met een eigen wachtwoord (vak 0) en een herstelcode voor op papier (vak 1).
# Gebruik: sudo ./02-kluis-aanmaken.sh [grootte]   (standaard 100G)
set -euo pipefail

KLUIS=/srv/brug.kluis      # het versleutelde bestand
NAAM=brug                  # naam als hij open is (/dev/mapper/brug)
MAP=/srv/brug              # waar de geopende kluis te zien is
GROOTTE="${1:-100G}"

if [[ $EUID -ne 0 ]]; then
  echo "Start dit script met: sudo ./02-kluis-aanmaken.sh"
  exit 1
fi
GEBRUIKER="${SUDO_USER:-}"
if [[ -z "$GEBRUIKER" || "$GEBRUIKER" == "root" ]]; then
  echo "Start dit script met sudo vanaf je eigen account (niet als root)."
  exit 1
fi
if [[ -e "$KLUIS" ]]; then
  echo "Er bestaat al een kluis ($KLUIS). Er is niets veranderd."
  echo "Was een eerdere poging halverwege gestopt? Verwijder hem dan met:"
  echo "  sudo rm $KLUIS"
  exit 1
fi
command -v cryptsetup >/dev/null || { echo "cryptsetup ontbreekt; draai eerst stap 1."; exit 1; }

# Maakt van ingetypte of geplakte invoer de juiste vorm: hoofdletters,
# streepjes op de goede plek, zonder spaties of onzichtbare plak-tekens.
normaliseer() {
  local s
  s="$(printf '%s' "$1" | sed $'s/\x1b\\[[0-9;]*~//g' | tr '[:lower:]' '[:upper:]' | tr -cd 'A-HJ-NP-Z2-9')"
  printf '%s' "$s" | fold -w4 | paste -sd- || true
}

echo "==> Kluisbestand van ${GROOTTE} maken in /srv"
mkdir -p /srv
fallocate -l "$GROOTTE" "$KLUIS"
chmod 600 "$KLUIS"

echo
echo "==> Kies nu het wachtwoord voor de kluis."
echo "    Dit typ je (voorlopig) na elke herstart. Kies iets lang en goed te onthouden."
echo "    Deel het nooit, ook niet in een chat."
echo
until cryptsetup luksFormat --type luks2 \
  --cipher aes-xts-plain64 --key-size 512 --hash sha512 --pbkdf argon2id \
  --key-slot 0 --batch-mode --verify-passphrase "$KLUIS"; do
  echo "    Dat ging mis (waarschijnlijk niet twee keer hetzelfde getypt). Opnieuw:"
done

echo
echo "==> Herstelcode maken"
# 32 tekens uit 32 goed leesbare tekens (geen I, O, 0 of 1) = 160 bits.
# ("|| true": tr stopt bewust als head genoeg heeft; dat is geen fout.)
HERSTEL="$(tr -dc 'A-HJ-NP-Z2-9' < /dev/urandom | head -c 32 | fold -w4 | paste -sd- || true)"
[[ ${#HERSTEL} -eq 39 ]] || { echo "Herstelcode maken mislukt. Probeer het opnieuw."; exit 1; }
echo "    Typ nu je wachtwoord nog één keer, om de herstelcode toe te voegen."
until cryptsetup luksAddKey --key-slot 1 "$KLUIS" <(printf '%s' "$HERSTEL"); do
  echo "    Dat was niet het wachtwoord. Opnieuw:"
done

clear
cat <<TEKST

  ============================================================
   JOUW HERSTELCODE  -  schrijf deze nu over op papier
  ============================================================

        ${HERSTEL}

  Met deze code open je de kluis als je het wachtwoord kwijt bent.
  Schrijf de streepjes mee. Bewaar het papier NIET bij de computer,
  en bewaar de code niet in een bestand op deze computer.
  ============================================================

TEKST
read -r -p "Druk op Enter als je de code hebt opgeschreven..." _
clear

echo "==> Controle: typ de herstelcode over van je papier (NIET je wachtwoord)."
echo "    Kleine letters en spaties mogen. Typ 'toon' om de code nog eens te zien."
while true; do
  read -r -p "Herstelcode: " INVOER
  if [[ "${INVOER,,}" == "toon" ]]; then
    printf '\n        %s\n\n' "$HERSTEL"
    continue
  fi
  POGING="$(normaliseer "$INVOER")"
  # Alleen vak 1 testen, zodat het wachtwoord hier níet wordt goedgekeurd.
  if printf '%s' "$POGING" | cryptsetup open --test-passphrase --key-slot 1 --key-file=- "$KLUIS" 2>/dev/null; then
    echo "    Klopt."
    break
  fi
  echo "    Dat klopt niet (je typte: ${POGING:-niets}). In de code komen geen"
  echo "    I, O, 0 of 1 voor. Typ 'toon' om hem opnieuw te zien."
done
unset INVOER POGING HERSTEL
clear

echo "==> Kluis openen (typ je wachtwoord)"
until cryptsetup open "$KLUIS" "$NAAM"; do echo "    Opnieuw:"; done
mkfs.ext4 -q -L brug "/dev/mapper/$NAAM"
mkdir -p "$MAP"
mount "/dev/mapper/$NAAM" "$MAP"
mkdir -p "$MAP/config" "$MAP/data"
chown -R "$GEBRUIKER":"$GEBRUIKER" "$MAP"
# 711: Docker-gebruikers mogen door deze map naar hun eigen submap,
# maar mogen niet zien wat er verder in staat.
chmod 711 "$MAP"

echo
echo "Klaar. De kluis is aangemaakt en staat nu open op $MAP."
echo "Ga verder met stap 3: ./03-muxbee-installeren.sh (zonder sudo)."
