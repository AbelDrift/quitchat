#!/usr/bin/env bash
# QuitChat – thuis-server, stap 5
# Zet versleutelde backups op: sleutels, herstelcode op papier, timers.
# Gebruik: sudo ./05-backups-instellen.sh
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Start dit script met: sudo ./05-backups-instellen.sh"
  exit 1
fi
GEBRUIKER="${SUDO_USER:-}"
if [[ -z "$GEBRUIKER" || "$GEBRUIKER" == "root" ]]; then
  echo "Start dit script met sudo vanaf je eigen account (niet als root)."
  exit 1
fi

MAP=/srv/brug
if ! mountpoint -q "$MAP"; then
  echo "De kluis is dicht. Open hem eerst met: sudo ./kluis-open.sh"
  exit 1
fi

HOME_USER="$(getent passwd "$GEBRUIKER" | cut -d: -f6)"
CONF_DIR="$HOME_USER/.config/brug"
BACKUP_CONF="$CONF_DIR/backup.conf"
BACKUP_DIR="$MAP/config/brug/backup"
BACKUP_HOOFD="$MAP/backups"
SYSTEMD_USER_DIR="$HOME_USER/.config/systemd/user"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Benodigde pakketten installeren (age, gnupg)"
apt-get update -qq
apt-get install -y age gnupg

echo "==> Mappen en configuratie klaarmaken"
mkdir -p "$BACKUP_DIR" "$BACKUP_HOOFD" "$CONF_DIR" "$SYSTEMD_USER_DIR"
chown -R "$GEBRUIKER":"$GEBRUIKER" "$BACKUP_DIR" "$BACKUP_HOOFD" "$CONF_DIR" "$SYSTEMD_USER_DIR"
chmod 700 "$BACKUP_DIR" "$CONF_DIR"

# Zelfde "goed leesbare" alfabet als de kluis-herstelcode: geen I, O, 0 of 1.
normaliseer() {
  local s
  s="$(printf '%s' "$1" | sed $'s/\x1b\\[[0-9;]*~//g' | tr '[:lower:]' '[:upper:]' | tr -cd 'A-HJ-NP-Z2-9')"
  printf '%s' "$s" | fold -w4 | paste -sd- || true
}

if [[ -f "$BACKUP_DIR/identity.txt" ]]; then
  echo
  echo "Er zijn al backup-sleutels aanwezig. Opnieuw aanmaken wist bestaande backups."
  read -r -p "Toch opnieuw aanmaken? Typ exact JA om door te gaan: " BEVESTIG
  if [[ "$BEVESTIG" != "JA" ]]; then
    echo "Geannuleerd. Niets veranderd."
    exit 0
  fi
  rm -f "$BACKUP_DIR"/identity.txt "$BACKUP_DIR"/public.txt "$BACKUP_DIR"/identity-herstel.gpg
fi

echo "==> Age-sleutelpaar maken (voor automatisch backuppen vanuit de kluis)"
sudo -u "$GEBRUIKER" age-keygen -o "$BACKUP_DIR/identity.txt" 2>/dev/null
chmod 600 "$BACKUP_DIR/identity.txt"
sudo -u "$GEBRUIKER" age-keygen -y "$BACKUP_DIR/identity.txt" > "$BACKUP_DIR/public.txt"
chown "$GEBRUIKER":"$GEBRUIKER" "$BACKUP_DIR/public.txt"

echo "==> Backup-herstelcode maken (voor herstel zonder de kluis)"
HERSTEL="$(tr -dc 'A-HJ-NP-Z2-9' < /dev/urandom | head -c 32 | fold -w4 | paste -sd- || true)"
[[ ${#HERSTEL} -eq 39 ]] || { echo "Herstelcode maken mislukt."; exit 1; }

echo "    De herstelcode versleutelt een kopie van de backup-sleutel."
sudo -u "$GEBRUIKER" bash -c "printf '%s' '$HERSTEL' | gpg --batch --yes --symmetric \
  --cipher-algo AES256 --s2k-digest-algo SHA512 --s2k-count 65011712 \
  --passphrase-fd 0 \
  -o '$BACKUP_DIR/identity-herstel.gpg' '$BACKUP_DIR/identity.txt'"

clear
cat <<TEKST

  ============================================================
   BACKUP-HERSTELCODE  -  schrijf deze nu over op papier
  ============================================================

        ${HERSTEL}

  Deze code opent een backup als je kluis is geburnd of kapot.
  Bewaar hem op papier, los van de kluis-herstelcode.
  De code wordt NERGENS op de computer bewaard.
  ============================================================

TEKST
read -r -p "Druk op Enter als je de code hebt opgeschreven..." _
clear

echo "==> Controle: typ de backup-herstelcode van je papier over."
echo "    Typ 'toon' om hem opnieuw te zien."
while true; do
  read -r -p "Backup-herstelcode: " INVOER
  if [[ "${INVOER,,}" == "toon" ]]; then
    printf '\n        %s\n\n' "$HERSTEL"
    continue
  fi
  POGING="$(normaliseer "$INVOER")"
  if [[ "$POGING" == "$HERSTEL" ]]; then
    echo "    Klopt."
    break
  fi
  echo "    Dat klopt niet. In de code komen geen I, O, 0 of 1 voor."
done
unset INVOER POGING HERSTEL
clear

echo "==> Standaardconfiguratie maken (als die er nog niet is)"
if [[ ! -f "$BACKUP_CONF" ]]; then
  cat > "$BACKUP_CONF" <<'CONF'
# QuitChat – backup-instellingen.
# Alles mag je aanpassen. Opslaan en 'brug backup' (of wacht op de timer).
#
# WANNEER BACKUPPEN (meer mag aan; leeg of 0 = uit)
BACKUP_DAGELIJKS_OM=03:00
BACKUP_PER_MB=0
BACKUP_PER_BERICHTEN=0

# Hoe vaak de MB/berichten-grens checken
BACKUP_CHECK_INTERVAL_MIN=15

# WAAR BACKUPS KOMEN
BACKUP_HOOFD=/srv/brug/backups       # primair in de kluis
BACKUP_EXTRA=                         # optionele 2e plek (map)

# HOEVEEL BEWAREN (oudste wordt weggegooid; 0 = alles bewaren)
BACKUP_MAX_AANTAL=14
CONF
  chown "$GEBRUIKER":"$GEBRUIKER" "$BACKUP_CONF"
  chmod 600 "$BACKUP_CONF"
else
  echo "    $BACKUP_CONF bestaat al; niet aangepast."
fi

echo "==> Scripts op hun plek zetten"
install -m 755 -o "$GEBRUIKER" -g "$GEBRUIKER" \
  "$SCRIPT_DIR/backup-maken.sh" "$HOME_USER/.local/bin/backup-maken.sh"
install -m 755 -o "$GEBRUIKER" -g "$GEBRUIKER" \
  "$SCRIPT_DIR/backup-herstellen.sh" "$HOME_USER/.local/bin/backup-herstellen.sh"
install -m 755 -o "$GEBRUIKER" -g "$GEBRUIKER" \
  "$SCRIPT_DIR/backup-triggers-controle.sh" "$HOME_USER/.local/bin/backup-triggers-controle.sh"

echo "==> Systemd-timers (lopen in de achtergrond onder jouw account)"
# Dagelijkse backup
cat > "$SYSTEMD_USER_DIR/quitchat-backup.service" <<SERVICE
[Unit]
Description=QuitChat dagelijkse backup
ConditionPathIsMountPoint=/srv/brug

[Service]
Type=oneshot
ExecStart=%h/.local/bin/backup-maken.sh
SERVICE

cat > "$SYSTEMD_USER_DIR/quitchat-backup.timer" <<TIMER
[Unit]
Description=QuitChat dagelijkse backup-timer

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
TIMER

# MB/berichten-trigger-check (loopt elke X minuten)
cat > "$SYSTEMD_USER_DIR/quitchat-backup-triggers.service" <<SERVICE
[Unit]
Description=QuitChat controle op backup-triggers (MB/berichten)
ConditionPathIsMountPoint=/srv/brug

[Service]
Type=oneshot
ExecStart=%h/.local/bin/backup-triggers-controle.sh
SERVICE

cat > "$SYSTEMD_USER_DIR/quitchat-backup-triggers.timer" <<TIMER
[Unit]
Description=QuitChat trigger-controle-timer

[Timer]
OnBootSec=5min
OnUnitActiveSec=15min

[Install]
WantedBy=timers.target
TIMER

chown -R "$GEBRUIKER":"$GEBRUIKER" "$SYSTEMD_USER_DIR"

# Zet "lingering" aan zodat de timers lopen zonder dat je ingelogd bent
loginctl enable-linger "$GEBRUIKER" 2>/dev/null || true

sudo -u "$GEBRUIKER" --preserve-env=HOME \
  XDG_RUNTIME_DIR="/run/user/$(id -u "$GEBRUIKER")" \
  bash -c '
    systemctl --user daemon-reload
    systemctl --user enable --now quitchat-backup.timer
    systemctl --user enable --now quitchat-backup-triggers.timer
  ' || echo "Let op: systemd-timers nog niet actief. Draai na uit/inloggen:
    systemctl --user daemon-reload
    systemctl --user enable --now quitchat-backup.timer
    systemctl --user enable --now quitchat-backup-triggers.timer"

echo
echo "Klaar."
echo "  - Instellingen aanpassen:  $BACKUP_CONF"
echo "  - Nu meteen een testbackup: backup-maken.sh"
echo "  - Backup terugzetten:      backup-herstellen.sh <backup-bestand>"
echo
echo "De dagelijkse backup draait automatisch om 03:00 (pas aan in backup.conf)."
