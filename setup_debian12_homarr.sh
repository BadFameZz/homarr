#!/bin/bash

# Kopfzeile mit deinem Tag-Namen
echo "============================================"
echo "  Homarr Installationsskript von BadFameZz  "
echo "============================================"
echo ""

# Funktion zur Anzeige eines Fortschrittsbalkens
progress() {
  local current=$1
  local total=$2
  local message=$3
  local width=50
  local percent=$((current * 100 / total))
  local filled=$((current * width / total))
  local empty=$((width - filled))

  # Fortschrittsbalken mit Farben
  printf "\r\e[32m["
  printf "%${filled}s" | tr ' ' '='
  printf "%${empty}s" | tr ' ' ' '
  printf "]\e[0m %3d%% \e[34m%s\e[0m" "$percent" "$message"
}

# Funktion zur Ermittlung der nächsten verfügbaren Container-ID
get_next_ctid() {
  # Liste aller vorhandenen Container-IDs
  existing_ctids=$(pct list | awk 'NR>1 {print $1}')
  
  # Liste aller vorhandenen VM-IDs
  existing_vmids=$(qm list | awk 'NR>1 {print $1}')

  # Starte bei CTID 100 und suche die nächste freie ID
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
    echo "Debian 12-Vorlage nicht gefunden. Lade sie herunter..."
    wget http://download.proxmox.com/images/system/debian-12-standard_12.0-1_amd64.tar.zst -P /var/lib/vz/template/cache/ &
    wget_pid=$!
    while kill -0 $wget_pid 2>/dev/null; do
      progress 1 4 "Lade Debian 12-Vorlage herunter..."
      sleep 1
    done
    progress 2 4 "Debian 12-Vorlage erfolgreich heruntergeladen."
    echo
  else
    progress 2 4 "Debian 12-Vorlage ist bereits vorhanden."
    echo
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

# Funktion zur Auswahl der CPU-Kerne
select_cores() {
  CORES=$(whiptail --title "CPU-Kerne auswählen" --menu \
    "Wählen Sie die Anzahl der CPU-Kerne aus:" 15 40 5 \
    "1" "1 CPU-Kern" \
    "2" "2 CPU-Kerne" \
    "4" "4 CPU-Kerne" \
    "8" "8 CPU-Kerne" \
    "16" "16 CPU-Kerne" 3>&1 1>&2 2>&3)

  if [[ -z "$CORES" ]]; then
    echo "Fehler: Keine CPU-Kerne ausgewählt."
    exit 1
  fi
}

# Funktion zur Auswahl des RAM-Speichers
select_memory() {
  MEMORY=$(whiptail --title "RAM-Speicher auswählen" --menu \
    "Wählen Sie den RAM-Speicher in MB aus:" 15 40 5 \
    "512" "512 MB" \
    "1024" "1 GB" \
    "2048" "2 GB" \
    "4096" "4 GB" \
    "8192" "8 GB" 3>&1 1>&2 2>&3)

  if [[ -z "$MEMORY" ]]; then
    echo "Fehler: Kein RAM-Speicher ausgewählt."
    exit 1
  fi
}

# Funktion zur Auswahl der Sprache
select_language() {
  LANGUAGE=$(whiptail --title "Sprache auswählen" --menu \
    "Wählen Sie die Sprache für Homarr aus:" 15 40 5 \
    "en" "Englisch" \
    "de" "Deutsch" \
    "fr" "Französisch" \
    "es" "Spanisch" \
    "nl" "Niederländisch" 3>&1 1>&2 2>&3)

  if [[ -z "$LANGUAGE" ]]; then
    echo "Fehler: Keine Sprache ausgewählt."
    exit 1
  fi
}

# Funktion zur Eingabe der Konfiguration über eine grafische Oberfläche
get_configuration() {
  HOSTNAME=$(whiptail --inputbox "Geben Sie den Hostnamen des Containers ein:" 8 40 "homarr-container" 3>&1 1>&2 2>&3)
  PASSWORD=$(whiptail --passwordbox "Geben Sie das Root-Passwort für den Container ein:" 8 40 3>&1 1>&2 2>&3)
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

# CPU-Kerne auswählen
select_cores

# RAM-Speicher auswählen
select_memory

# Sprache auswählen
select_language

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
  --features nesting=1 &
pct_create_pid=$!

# Fortschrittsbalken für die Container-Erstellung
while kill -0 $pct_create_pid 2>/dev/null; do
  progress 3 4 "Erstelle Container..."
  sleep 1
done
progress 4 4 "Container erfolgreich erstellt."
echo

# Container starten
echo "Starte den Container..."
pct start $CTID

# Warte, bis der Container vollständig gestartet ist
sleep 10

# Container-Shell für die Installation vorbereiten
echo "Installiere die notwendigen Pakete..."
pct exec $CTID -- bash -c "apt update && apt upgrade -y" &
apt_update_pid=$!
while kill -0 $apt_update_pid 2>/dev/null; do
  progress 1 4 "Installiere Pakete..."
  sleep 1
done
progress 2 4 "Pakete erfolgreich installiert."
echo

pct exec $CTID -- bash -c "apt install -y curl sudo docker.io docker-compose" &
apt_install_pid=$!
while kill -0 $apt_install_pid 2>/dev/null; do
  progress 3 4 "Installiere Docker..."
  sleep 1
done
progress 4 4 "Docker erfolgreich installiert."
echo

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
    image: ghcr.io/ajnart/homarr:1.0
    container_name: homarr
    restart: unless-stopped
    ports:
      - '7575:7575'
    environment:
      - HOMARR_LANG=$LANGUAGE  # Sprache festlegen
    volumes:
      - ./configs:/app/data/configs
      - ./icons:/app/public/icons
EOF"

# Homarr starten
echo "Starte Homarr..."
pct exec $CTID -- bash -c "cd /opt/homarr && docker-compose up -d"

# Abschluss
echo "============================================"
echo "  Installation abgeschlossen! 🎉            "
echo "  Homarr wurde erfolgreich installiert.     "
echo "  Container-ID: $CTID                       "
echo "  Zugriff unter: http://$(echo $IP | cut -d'/' -f1):7575"
echo "============================================"
