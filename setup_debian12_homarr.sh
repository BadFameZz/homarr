#!/bin/bash

# Kopfzeile mit deinem Tag-Namen
whiptail --title "Homarr Installationsskript" --msgbox "Willkommen zum Homarr Installationsskript von BadFameZz!" 10 50

# Funktion zur Ermittlung der nächsten verfügbaren Container-ID
get_next_ctid() {
  existing_ctids=$(pct list | awk 'NR>1 {print $1}')
  existing_vmids=$(qm list | awk 'NR>1 {print $1}')
  ctid=100
  while [[ $existing_ctids =~ (^|[[:space:]])$ctid($|[[:space:]]) || \
        $existing_vmids =~ (^|[[:space:]])$ctid($|[[:space:]]) ]]; do
    ctid=$((ctid + 1))
  done
  echo $ctid
}

# Funktion zum Herunterladen der Debian 12-Vorlage
download_debian12_template() {
  template_path="/var/lib/vz/template/cache/debian-12-standard_12.0-1_amd64.tar.zst"
  if [[ ! -f "$template_path" ]]; then
    whiptail --title "Download" --infobox "Lade Debian 12-Vorlage herunter..." 10 50
    wget -q http://download.proxmox.com/images/system/debian-12-standard_12.0-1_amd64.tar.zst -P /var/lib/vz/template/cache/
  fi
}

# Funktion zur automatischen Ermittlung von IP und Gateway
get_network_config() {
  GATEWAY=$(ip route | grep default | awk '{print $3}')
  INTERFACE=$(ip route | grep default | awk '{print $5}')
  HOST_IP=$(ip addr show $INTERFACE | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
  IP=$(echo $HOST_IP | cut -d'.' -f1-3).$(($(echo $HOST_IP | cut -d'.' -f4) + 1))
  while ping -c 1 -W 1 $IP &> /dev/null; do
    IP=$(echo $IP | cut -d'.' -f1-3).$(($(echo $IP | cut -d'.' -f4) + 1))
  done
  IP="$IP/24"
}

# Funktion zur Auswahl des Speichermediums
select_storage() {
  storage_list=$(pvesm status | awk 'NR>1 {print $1}')
  storage_options=()
  while IFS= read -r line; do
    storage_options+=("$line" "")
  done <<< "$storage_list"
  STORAGE=$(whiptail --title "Speichermedium auswählen" --menu "Wählen Sie das Speichermedium für den Container aus:" 15 40 5 "${storage_options[@]}" 3>&1 1>&2 2>&3)
}

# Funktion zur Auswahl der CPU-Kerne
select_cores() {
  CORES=$(whiptail --title "CPU-Kerne auswählen" --menu "Wählen Sie die Anzahl der CPU-Kerne aus:" 15 40 5 \
    "1" "1 CPU-Kern" \
    "2" "2 CPU-Kerne" \
    "4" "4 CPU-Kerne" \
    "8" "8 CPU-Kerne" \
    "16" "16 CPU-Kerne" 3>&1 1>&2 2>&3)
}

# Funktion zur Auswahl des RAM-Speichers
select_memory() {
  MEMORY=$(whiptail --title "RAM-Speicher auswählen" --menu "Wählen Sie den RAM-Speicher in MB aus:" 15 40 5 \
    "512" "512 MB" \
    "1024" "1 GB" \
    "2048" "2 GB" \
    "4096" "4 GB" \
    "8192" "8 GB" 3>&1 1>&2 2>&3)
}

# Funktion zur Auswahl der Sprache
select_language() {
  LANGUAGE=$(whiptail --title "Sprache auswählen" --menu "Wählen Sie die Sprache für Homarr aus:" 15 40 5 \
    "en" "Englisch" \
    "de" "Deutsch" \
    "fr" "Französisch" \
    "es" "Spanisch" \
    "nl" "Niederländisch" 3>&1 1>&2 2>&3)
}

# Hauptskript
{
  # Netzwerkkonfiguration automatisch ermitteln
  get_network_config

  # Speichermedium auswählen
  select_storage

  # CPU-Kerne auswählen
  select_cores

  # RAM-Speicher auswählen
  select_memory

  # Sprache auswählen
  select_language

  # Debian 12-Vorlage herunterladen (falls nicht vorhanden)
  download_debian12_template

  # Debian 12 LXC-Container erstellen
  CTID=$(get_next_ctid)
  whiptail --title "Container erstellen" --infobox "Erstelle Debian 12 LXC-Container mit CTID $CTID..." 10 50
  pct create $CTID /var/lib/vz/template/cache/debian-12-standard_12.0-1_amd64.tar.zst \
    --hostname "homarr-container" \
    --password "securepassword" \
    --rootfs $STORAGE:4 \
    --cores $CORES \
    --memory $MEMORY \
    --net0 name=eth0,ip=$IP,gw=$GATEWAY,bridge=vmbr0 \
    --unprivileged 1 \
    --features nesting=1

  # Container starten
  whiptail --title "Container starten" --infobox "Starte den Container..." 10 50
  pct start $CTID

  # Warte, bis der Container vollständig gestartet ist
  sleep 10

  # Container-Shell für die Installation vorbereiten
  whiptail --title "Pakete installieren" --infobox "Installiere die notwendigen Pakete..." 10 50
  pct exec $CTID -- bash -c "apt update && apt upgrade -y && apt install -y curl sudo docker.io docker-compose"

  # Docker-Dienst starten und aktivieren
  whiptail --title "Docker aktivieren" --infobox "Aktiviere und starte Docker..." 10 50
  pct exec $CTID -- bash -c "systemctl start docker && systemctl enable docker"

  # Verzeichnis für Homarr erstellen
  whiptail --title "Homarr vorbereiten" --infobox "Erstelle Verzeichnis für Homarr..." 10 50
  pct exec $CTID -- bash -c "mkdir -p /opt/homarr && cd /opt/homarr"

  # Docker-Compose-Datei für Homarr erstellen
  whiptail --title "Homarr konfigurieren" --infobox "Erstelle Docker-Compose-Datei für Homarr..." 10 50
  pct exec $CTID -- bash -c "cat > /opt/homarr/docker-compose.yml <<EOF
version: '3.3'
services:
  homarr:
    image: ghcr.io/ajnart/homarr:latest
    container_name: homarr
    restart: unless-stopped
    ports:
      - '7575:7575'
    environment:
      - HOMARR_LANG=$LANGUAGE
    volumes:
      - ./configs:/app/data/configs
      - ./icons:/app/public/icons
EOF"

  # Homarr starten
  whiptail --title "Homarr starten" --infobox "Starte Homarr..." 10 50
  pct exec $CTID -- bash -c "cd /opt/homarr && docker-compose up -d"

  # Abschluss
  whiptail --title "Installation abgeschlossen" --msgbox "Homarr wurde erfolgreich installiert!\n\nContainer-ID: $CTID\nZugriff unter: http://$(echo $IP | cut -d'/' -f1):7575" 15 50
}
