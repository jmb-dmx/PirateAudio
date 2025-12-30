#!/usr/bin/env bash
set -e

USER="raspberry"
HOME_DIR="/home/$USER"
IMG_DIR="$HOME_DIR/images"
ENV_FILE="$HOME_DIR/.pirateaudio.env"

GITHUB_USER="jmb-dmx"
GITHUB_REPO="PirateAudio"
GITHUB_BRANCH="main"
RAW_BASE="https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/$GITHUB_BRANCH"

echo "=== PirateAudio install (version fonctionnelle) ==="
echo

############################################
# 1. SYSTEM UPDATE
############################################
sudo apt update
sudo apt upgrade -y

############################################
# 2. HOME ASSISTANT CONFIG (OBLIGATOIRE)
############################################
echo
read -rp "Home Assistant URL (ex: http://192.168.1.161:8123) : " HA_URL </dev/tty
read -rsp "Home Assistant TOKEN : " HA_TOKEN </dev/tty
echo
echo

if [[ -z "$HA_URL" || -z "$HA_TOKEN" ]]; then
  echo "ERREUR: URL ou TOKEN vide"
  exit 1
fi

cat > "$ENV_FILE" <<EOF
HA_URL=$HA_URL
HA_TOKEN=$HA_TOKEN
EOF

chmod 600 "$ENV_FILE"
chown $USER:$USER "$ENV_FILE"

############################################
# 3. PACKAGES
############################################
sudo apt install -y \
  python3 python3-pip \
  python3-pil python3-numpy \
  curl iw git \
  alsa-utils \
  squeezelite shairport-sync

############################################
# 4. PYTHON LIBS
############################################
pip3 install --break-system-packages \
  st7789 gpiodevice requests pillow spidev

############################################
# 5. ALSA DMIX
############################################
sudo tee /etc/asound.conf > /dev/null <<'EOF'
pcm.!default {
    type plug
    slave.pcm "dmix"
}

pcm.dmix {
    type dmix
    ipc_key 1024
    slave {
        pcm "hw:sndrpihifiberry"
        rate 44100
        channels 2
    }
}
EOF

############################################
# 6. IMAGES
############################################
mkdir -p "$IMG_DIR"

curl -fsSL "$RAW_BASE/images/boot.png"    -o "$IMG_DIR/boot.png"
curl -fsSL "$RAW_BASE/images/idle.png"    -o "$IMG_DIR/idle.png"
curl -fsSL "$RAW_BASE/images/airplay.png" -o "$IMG_DIR/airplay.png"

############################################
# 7. SCRIPTS PYTHON (INCHANGÉS)
############################################
curl -fsSL "$RAW_BASE/pirate_display.py" -o "$HOME_DIR/pirate_display.py"
curl -fsSL "$RAW_BASE/pirate_buttons.py" -o "$HOME_DIR/pirate_buttons.py"

chmod +x "$HOME_DIR/pirate_display.py" "$HOME_DIR/pirate_buttons.py"
chown -R $USER:$USER "$HOME_DIR"

############################################
# 8. DÉMARRAGE DÉCALÉ (LA SOLUTION)
############################################
crontab -u $USER -l 2>/dev/null | grep -v pirate_ > /tmp/cron.tmp || true

cat >> /tmp/cron.tmp <<EOF
@reboot sleep 60 && python3 /home/raspberry/pirate_display.py >> /home/raspberry/display.log 2>&1 &
@reboot sleep 60 && python3 /home/raspberry/pirate_buttons.py >> /home/raspberry/buttons.log 2>&1 &
EOF

crontab -u $USER /tmp/cron.tmp
rm /tmp/cron.tmp

############################################
# 9. FIN
############################################
echo
echo "Installation terminée."
echo "Redémarrage dans 5 secondes..."
sleep 5
sudo reboot
