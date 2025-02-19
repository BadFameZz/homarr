#!/bin/bash

# Funktion zur Ermittlung der nächsten verfügbaren Container-ID
get_next_ctid() {
  existing_ctids=$(pct list | awk 'NR>1 {print $1}')
  ctid=100
  while [[ $existing_ctids =~ (^|[[:space:]])$ctid($|[[:space:]]) ]]; do
    ctid=$((ctid + 1))
  done
  echo $ctid
}

# Funktion zum Herunterladen der Debian 12-Vorlage
download_debian12_template() {
  template_path="/var/lib/vz/template/cache/debian-12-standard_12.0-1_amd64.tar.zst"
  if [[ ! -f "$template_path" ]]; then
    echo "Debian 12-Vorlage nicht gefunden. Lade sie herunter..."
    wget http://download.proxmox.com/images/system/debian-12-standard_12.0-1_amd64.tar.zst -P /var/lib/vz/template/cache/
    if [[ $? -ne 0 ]]; then
      echo "Fehler beim Herunterladen der Debian 12-Vorlage. Bitte überprüfe deine Internetverbindung."
      exit 1
    fi
    echo "Debian 12-Vorlage erfolgreich heruntergeladen."
  else
    echo "Debian 12-Vorlage ist bereits vorhanden."
  fi
}

# Funktion zur automatischen Ermittlung von IP und Gateway
get_network_config() {
  # Ermittle das Standard-Gateway
  GATEWAY=$(ip route | grep default | awk '{print $3}')
  if [[ -z "$GATEWAY" ]]; then
    echo "Fehler: Gateway konnte nicht ermittelt werden."
    exit 1
  fi

  # Ermittle das Netzwerk-Interface und die IP-Adresse
  INTERFACE=$(ip route | grep default | awk '{print $5}')
  HOST_IP=$(ip addr show $INTERFACE | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
  NETWORK=$(ip route | grep $INTERFACE | grep -v default | awk '{print $1}')

  # Generiere eine verfügbare IP-Adresse im Netzwerk
  IP=$(echo $HOST_IP | cut -d'.' -f1-3).$(($(echo $HOST_IP | cut -d'.' -f4) + 1))
  while ping -c 1 -W 1 $IP &> /dev/null; do
    IP=$(echo $IP | cut -d'.' -f1-3).$(($(echo $IP | cut -d'.' -f4) + 1))
  done
  IP="$IP/24"
}

# Funktion zur Auswahl des Speichermediums
select_storage() {
  # Liste der verfügbaren Speichermedien ermitteln
  storage_list=$(pvesm status | awk 'NR>1 {print $1}')
  if [[ -z "$storage_list" ]]; then
    echo "Fehler: Keine Speichermedien gefunden."
    exit 1
  fi

  # Speichermedien in ein Array speichern
  storage_options=()
  while IFS= read -r line; do
    storage_options+=("$line" "")
  done <<< "$storage_list"

  # Auswahlbox anzeigen
  STORAGE=$(whiptail --title "Speichermedium auswählen" --menu \
    "Wählen Sie das Speichermedium für den Container aus:" 15 40 5 \
    "${storage_options[@]}" 3>&1 1>&2 2>&3)

  if [[ -z "$STORAGE" ]]; then
    echo "Fehler: Kein Speichermedium ausgewählt."
    exit 1
  fi
}

# Funktion zur Eingabe der Konfiguration über eine grafische Oberfläche
get_configuration() {
  HOSTNAME=$(whiptail --inputbox "Geben Sie den Hostnamen des Containers ein:" 8 40 "homarr-container" 3>&1 1>&2 2>&3)
  PASSWORD=$(whiptail --passwordbox "Geben Sie das Root-Passwort für den Container ein:" 8 40 3>&1 1>&2 2>&3)
  CORES=$(whiptail --inputbox "Geben Sie die Anzahl der CPU-Kerne ein:" 8 40 "1" 3>&1 1>&2 2>&3)
  MEMORY=$(whiptail --inputbox "Geben Sie den RAM-Speicher in MB ein:" 8 40 "512" 3>&1 1>&2 2>&3)
  DISK=$(whiptail --inputbox "Geben Sie den Disk-Speicher in GB ein:" 8 40 "4" 3>&1 1>&2 2>&3)
}

# Hauptskript
if ! command -v whiptail &> /dev/null; then
  echo "whiptail ist nicht installiert. Bitte installiere es mit 'apt install whiptail'."
  exit 1
fi

# Netzwerkkonfiguration automatisch ermitteln
get_network_config

# Speichermedium auswählen
select_storage

# Konfiguration abfragen
get_configuration

# Debian 12-Vorlage herunterladen (falls nicht vorhanden)
download_debian12_template

# Debian 12 LXC-Container erstellen
CTID=$(get_next_ctid)
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
