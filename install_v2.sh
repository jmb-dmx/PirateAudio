#!/usr/bin/env bash
set -e

# Auto-detect user and home directory
USER=$(whoami)
if [ -z "$USER" ]; then
    USER=$(logname) # fallback
fi
HOME_DIR=$(eval echo ~$USER)
IMG_DIR="$HOME_DIR/images"
ENV_FILE="$HOME_DIR/.pirateaudio.env"

echo "=== PirateAudio install (v2) ==="
echo

############################################
# 1. SYSTEM UPDATE
############################################
echo "--> 1. Updating system..."
sudo apt-get update
sudo apt-get upgrade -y

############################################
# 2. PACKAGES
############################################
echo "--> 2. Installing packages..."
# Try to fix any broken package states from previous runs
sudo dpkg --configure -a
sudo apt-get -f -y install
# Forcefully remove old config and purge a potentially broken installation first
sudo rm -f /etc/default/squeezelite
sudo apt-get purge -y squeezelite
# Now install everything
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
  python3 python3-pip \
  python3-pil python3-numpy \
  curl iw git \
  alsa-utils \
  squeezelite shairport-sync

############################################
# 3. PYTHON LIBS
############################################
echo "--> 3. Installing Python libraries..."
pip3 install --break-system-packages \
  st7789 gpiodevice requests pillow spidev

############################################
# 4. ENABLE SPI
############################################
echo "--> 4. Enabling SPI interface..."
if [ -f /boot/config.txt ]; then
    if ! grep -q "dtparam=spi=on" /boot/config.txt; then
      echo "dtparam=spi=on" | sudo tee -a /boot/config.txt > /dev/null
      echo "   SPI enabled. A reboot is required for changes to take effect."
    else
      echo "   SPI interface already enabled."
    fi
else
    echo "   /boot/config.txt not found, skipping SPI configuration. (Not a Raspberry Pi?)"
fi

############################################
# 5. ALSA DMIX
############################################
echo "--> 5. Configuring ALSA..."
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
# 6. HOME ASSISTANT CONFIG
############################################
echo "--> 6. Configuring Home Assistant connection..."
read -rp "   Home Assistant URL (ex: http://192.168.1.161:8123) : " HA_URL
read -rsp "   Home Assistant TOKEN : " HA_TOKEN
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
# 7. SQUEEZELITE
############################################
echo "--> 7. Configuring Squeezelite..."
read -rp "   Enter Squeezelite server address: " SQUEEZELITE_SERVER

cat << EOF | sudo tee /etc/default/squeezelite > /dev/null
# Squeezelite options
SL_OPTS="-s ${SQUEEZELITE_SERVER} -o default -n PirateAudio"
EOF

sudo systemctl enable squeezelite
sudo systemctl restart squeezelite

############################################
# 8. IMAGES
############################################
echo "--> 8. Downloading images..."
mkdir -p "$IMG_DIR"
chown $USER:$USER "$IMG_DIR"
RAW_BASE="https://raw.githubusercontent.com/jmb-dmx/PirateAudio/main"
curl -fsSL "$RAW_BASE/images/boot.png"    -o "$IMG_DIR/boot.png"
curl -fsSL "$RAW_BASE/images/idle.png"    -o "$IMG_DIR/idle.png"
curl -fsSL "$RAW_BASE/images/airplay.png" -o "$IMG_DIR/airplay.png"


############################################
# 9. SCRIPTS PYTHON
############################################
echo "--> 9. Installing Python scripts..."
# Copy local (fixed) scripts instead of downloading
cp pirate_display.py "$HOME_DIR/pirate_display.py"
cp pirate_buttons.py "$HOME_DIR/pirate_buttons.py"

chmod +x "$HOME_DIR/pirate_display.py" "$HOME_DIR/pirate_buttons.py"
chown $USER:$USER "$HOME_DIR/pirate_display.py" "$HOME_DIR/pirate_buttons.py"

############################################
# 10. CRONTAB
############################################
echo "--> 10. Setting up crontab..."
(crontab -u $USER -l 2>/dev/null | grep -v "pirate_display.py" | grep -v "pirate_buttons.py" ; \
echo "@reboot sleep 10 && python3 ${HOME_DIR}/pirate_display.py &"; \
echo "@reboot sleep 10 && python3 ${HOME_DIR}/pirate_buttons.py &" ) | crontab -u $USER -

############################################
# 11. FIN
############################################
echo
echo "Installation terminée."
echo "Redémarrage dans 5 secondes..."
sleep 5
# sudo reboot # commented out for sandbox execution
echo "Reboot would happen here."
