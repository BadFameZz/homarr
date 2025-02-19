#!/bin/bash

# Funktion zur Ermittlung der nächsten verfügbaren Container-ID
get_next_ctid() {
  # Liste aller vorhandenen Container-IDs
  existing_ctids=$(pct list | awk 'NR>1 {print $1}')
  
  # Starte bei CTID 100 und suche die nächste freie ID
  ctid=100
  while [[ $existing_ctids =~ (^|[[:space:]])$ctid($|[[:space:]]) ]]; do
    ctid=$((ctid + 1))
  done
  echo $ctid
}

# Variablen
CTID=$(get_next_ctid)  # Automatisch nächste verfügbare CTID ermitteln
HOSTNAME="homarr-container"
PASSWORD="securepassword"  # Setze ein sicheres Passwort
IP="192.168.1.100/24"  # Statische IP (ändere dies entsprechend deinem Netzwerk)
GATEWAY="192.168.1.1"  # Gateway (ändere dies entsprechend deinem Netzwerk)
STORAGE="local-lvm"  # Speicherort (ändere dies, falls notwendig)
CORES="1"  # Anzahl der CPU-Kerne
MEMORY="512"  # RAM in MB
DISK="4"  # Disk-Speicher in GB

# Debian 12 LXC-Container erstellen
echo "Erstelle Debian 12 LXC-Container mit CTID $CTID..."
pct create $CTID /var/lib/vz/template/cache/debian-12-standard_12.0-1_amd64.tar.zst \
  --hostname $HOSTNAME \
  --password $PASSWORD \
  --rootfs $STORAGE:$DISK \
  --cores $CORES \
  --memory $MEMORY \
  --net0 name=eth0,ip=$IP,gw=$GATEWAY,bridge=vmbr0 \
  --unprivileged 1 \
  --features nesting=1

# Container starten
echo "Starte den Container..."
pct start $CTID

# Warte, bis der Container vollständig gestartet ist
sleep 10

# Container-Shell für die Installation vorbereiten
echo "Installiere die notwendigen Pakete..."
pct exec $CTID -- bash -c "apt update && apt upgrade -y"
pct exec $CTID -- bash -c "apt install -y curl sudo docker.io docker-compose"

# Docker-Dienst starten und aktivieren
echo "Aktiviere und starte Docker..."
pct exec $CTID -- bash -c "systemctl start docker"
pct exec $CTID -- bash -c "systemctl enable docker"

# Verzeichnis für Homarr erstellen
echo "Erstelle Verzeichnis für Homarr..."
pct exec $CTID -- bash -c "mkdir -p /opt/homarr"
pct exec $CTID -- bash -c "cd /opt/homarr"

# Docker-Compose-Datei für Homarr erstellen
echo "Erstelle Docker-Compose-Datei für Homarr..."
pct exec $CTID -- bash -c "cat > /opt/homarr/docker-compose.yml <<EOF
version: '3.3'
services:
  homarr:
    image: ghcr.io/ajnart/homarr:latest
    container_name: homarr
    restart: unless-stopped
    ports:
      - '7575:7575'
    volumes:
      - ./configs:/app/data/configs
      - ./icons:/app/public/icons
EOF"

# Homarr starten
echo "Starte Homarr..."
pct exec $CTID -- bash -c "cd /opt/homarr && docker-compose up -d"

# Abschluss
echo "Installation abgeschlossen!"
echo "Container-ID: $CTID"
echo "Du kannst jetzt auf Homarr zugreifen unter: http://$(echo $IP | cut -d'/' -f1):7575"
