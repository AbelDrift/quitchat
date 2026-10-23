#!/usr/bin/env bash
# QuitChat – thuis-server, stap 1
# Installeert Docker, zet extra werkgeheugen (zram) aan en zet de slaapstand uit.
# Gebruik: sudo ./01-voorbereiden.sh
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Start dit script met: sudo ./01-voorbereiden.sh"
  exit 1
fi
GEBRUIKER="${SUDO_USER:-}"
if [[ -z "$GEBRUIKER" || "$GEBRUIKER" == "root" ]]; then
  echo "Start dit script met sudo vanaf je eigen account (niet als root)."
  exit 1
fi

echo "==> Benodigde pakketten installeren"
apt-get update
apt-get install -y ca-certificates curl gnupg cryptsetup zram-tools acl

echo "==> Docker installeren (officiële bron van Docker)"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
CODENAAM="$(. /etc/os-release && echo "$VERSION_CODENAME")"
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${CODENAAM} stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "==> Docker-logboeken klein houden (minder sporen op de schijf)"
if [[ ! -f /etc/docker/daemon.json ]]; then
  cat > /etc/docker/daemon.json <<'JSON'
{
  "log-driver": "local",
  "log-opts": { "max-size": "5m", "max-file": "2" }
}
JSON
  systemctl restart docker
else
  echo "    /etc/docker/daemon.json bestaat al; niet aangepast."
fi

echo "==> ${GEBRUIKER} toevoegen aan de groep docker"
usermod -aG docker "$GEBRUIKER"

echo "==> Extra werkgeheugen via zram (in het geheugen, niets op de schijf)"
# zram is gecomprimeerde swap in het werkgeheugen. Zo komen er nooit
# berichten onversleuteld op de schijf terecht, wat bij een swapbestand wel kan.
cat > /etc/default/zramswap <<'CONF'
ALGO=zstd
PERCENT=35
PRIORITY=100
CONF
systemctl restart zramswap

echo "==> Slaapstand en sluimerstand uitzetten (de pc moet altijd aan blijven)"
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

echo
echo "Klaar. Controle:"
docker --version
docker compose version
swapon --show
echo
echo "BELANGRIJK: log nu één keer uit en weer in (of herstart),"
echo "zodat je account Docker mag gebruiken. Ga daarna verder met stap 2."
