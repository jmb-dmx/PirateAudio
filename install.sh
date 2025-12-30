#!/usr/bin/env bash
set -e

############################################
# PirateAudio – INSTALLATION FONCTIONNELLE
# Objectif : reproduction exacte du setup OK
############################################

USER="raspberry"
HOME_DIR="/home/$USER"
IMG_DIR="$HOME_DIR/images"

GITHUB_USER="jmb-dmx"
GITHUB_REPO="PirateAudio"
GITHUB_BRANCH="main"
RAW_BASE="https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/$GITHUB_BRANCH"

echo "=== PirateAudio install (solution stable) ==="
echo

############################################
# 1. SYSTEM UPDATE
############################################
sudo apt update
sudo apt upgrade -y

############################################
# 2. PACKAGES
############################################
sudo apt install -y \
  python3 python3-pip \
  python3-pil python3-numpy \
  curl git iw \
  alsa-utils \
  squeezelite shairport-sync

############################################
# 3. SPI / I2C / DAC
############################################
BOOTCFG="/boot/firmware/config.txt"

grep -q "^dtparam=spi=on" "$BOOTCFG" || echo "dtparam=spi=on" | sudo tee -a "$BOOTCFG"
grep -q "^dtparam=i2c_arm=on" "$BOOTCFG" || echo "dtparam=i2c_arm=on" | sudo tee -a "$BOOTCFG"
grep -q "^dtoverlay=hifiberry-dac" "$BOOTCFG" || echo "dtoverlay=hifiberry-dac" | sudo tee -a "$BOOTCFG"

############################################
# 4. PYTHON LIBS
############################################
pip3 install --break-system-packages \
  st7789 gpiodevice requests pillow spidev

############################################
# 5. ALSA DMIX (AIRPLAY + SQUEEZELITE)
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
# 6. DOSSIER IMAGES
############################################
mkdir -p "$IMG_DIR"

############################################
# 7. IMAGES
############################################
curl -fsSL "$RAW_BASE/images/boot.png"    -o "$IMG_DIR/boot.png"
curl -fsSL "$RAW_BASE/images/idle.png"    -o "$IMG_DIR/idle.png"
curl -fsSL "$RAW_BASE/images/airplay.png" -o "$IMG_DIR/airplay.png"

############################################
# 8. SCRIPTS PYTHON (INCHANGÉS)
############################################
curl -fsSL "$RAW_BASE/pirate_display.py" -o "$HOME_DIR/pirate_display.py"
curl -fsSL "$RAW_BASE/pirate_buttons.py" -o "$HOME_DIR/pirate_buttons.py"

chmod +x "$HOME_DIR/pirate_display.py" "$HOME_DIR/pirate_buttons.py"
chown -R $USER:$USER "$HOME_DIR"

############################################
# 9. DÉMARRAGE DÉCALÉ VIA CRON (LA CLÉ)
############################################
echo "Installing delayed startup via cron"

crontab -u $USER -l 2>/dev/null | grep -v pirate_ > /tmp/cron.tmp || true

cat >> /tmp/cron.tmp <<EOF
@reboot sleep 60 && python3 /home/raspberry/pirate_display.py >> /home/raspberry/display.log 2>&1 &
@reboot sleep 60 && python3 /home/raspberry/pirate_buttons.py >> /home/raspberry/buttons.log 2>&1 &
EOF

crontab -u $USER /tmp/cron.tmp
rm /tmp/cron.tmp

############################################
# 10. FIN
############################################
echo
echo "Installation terminée."
echo "Reboot dans 5 secondes..."
sleep 5
sudo reboot
