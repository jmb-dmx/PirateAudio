#!/usr/bin/env bash
set -e

############################################
# PIRATE AUDIO – REPRODUCTION INSTALL SCRIPT
# Objectif : refaire EXACTEMENT ce qui marche
############################################

USER="raspberry"
HOME_DIR="/home/$USER"
BOOTCFG="/boot/firmware/config.txt"

GITHUB_USER="jmb-dmx"
GITHUB_REPO="PirateAudio"
GITHUB_BRANCH="main"
RAW_BASE="https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/$GITHUB_BRANCH"

echo "=== PirateAudio install (reproduction mode) ==="
echo

############################################
# 1. SYSTEM UPDATE (COMME À LA MAIN)
############################################
echo "[1/14] apt update / upgrade"
sudo apt update
sudo apt upgrade -y

############################################
# 2. PACKAGES SYSTÈME (COMME À LA MAIN)
############################################
echo "[2/14] Installing system packages"
sudo apt install -y \
  python3 python3-pip \
  python3-pil python3-numpy \
  curl git iw \
  alsa-utils \
  squeezelite shairport-sync

############################################
# 3. SPI / I2C / DAC (COMME À LA MAIN)
############################################
echo "[3/14] Enabling SPI / I2C / DAC"

grep -q "^dtparam=spi=on" "$BOOTCFG" || echo "dtparam=spi=on" | sudo tee -a "$BOOTCFG"
grep -q "^dtparam=i2c_arm=on" "$BOOTCFG" || echo "dtparam=i2c_arm=on" | sudo tee -a "$BOOTCFG"
grep -q "^dtoverlay=hifiberry-dac" "$BOOTCFG" || echo "dtoverlay=hifiberry-dac" | sudo tee -a "$BOOTCFG"

############################################
# 4. PYTHON LIBS (COMME À LA MAIN)
############################################
echo "[4/14] Installing Python libraries"
pip3 install --break-system-packages \
  st7789 gpiodevice requests pillow spidev

############################################
# 5. ALSA DMIX (AIRPLAY + SQUEEZELITE)
############################################
echo "[5/14] Configuring ALSA dmix"

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
# 6. DOSSIER IMAGES (COMME AVANT)
############################################
echo "[6/14] Creating images directory"
mkdir -p "$HOME_DIR/images"
chown -R $USER:$USER "$HOME_DIR/images"

############################################
# 7. DOWNLOAD DES IMAGES
############################################
echo "[7/14] Downloading images"
curl -fsSL "$RAW_BASE/images/boot.png"    -o "$HOME_DIR/images/boot.png"
curl -fsSL "$RAW_BASE/images/idle.png"    -o "$HOME_DIR/images/idle.png"
curl -fsSL "$RAW_BASE/images/airplay.png" -o "$HOME_DIR/images/airplay.png"
chown -R $USER:$USER "$HOME_DIR/images"

############################################
# 8. DOWNLOAD DES SCRIPTS PYTHON (INTOUCHABLES)
############################################
echo "[8/14] Downloading Python scripts (unchanged)"
curl -fsSL "$RAW_BASE/pirate_display.py" -o "$HOME_DIR/pirate_display.py"
curl -fsSL "$RAW_BASE/pirate_buttons.py" -o "$HOME_DIR/pirate_buttons.py"
chmod +x "$HOME_DIR/pirate_display.py" "$HOME_DIR/pirate_buttons.py"
chown $USER:$USER "$HOME_DIR/pirate_display.py" "$HOME_DIR/pirate_buttons.py"

############################################
# 9. SERVICE ÉCRAN (RETARDÉ COMME TESTÉ)
############################################
echo "[9/14] Creating display service"

sudo tee /etc/systemd/system/pirate-display.service > /dev/null <<'EOF'
[Unit]
Description=Pirate Audio Display
After=network-online.target
Wants=network-online.target

[Service]
User=raspberry
ExecStartPre=/bin/sleep 15
ExecStart=/usr/bin/python3 /home/raspberry/pirate_display.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

############################################
# 10. SERVICE BOUTONS (SIMPLE)
############################################
echo "[10/14] Creating buttons service"

sudo tee /etc/systemd/system/pirate-buttons.service > /dev/null <<'EOF'
[Unit]
Description=Pirate Audio Buttons
After=network-online.target
Wants=network-online.target

[Service]
User=raspberry
ExecStart=/usr/bin/python3 /home/raspberry/pirate_buttons.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

############################################
# 11. SYSTEMD RELOAD
############################################
echo "[11/14] Reloading systemd"
sudo systemctl daemon-reload

############################################
# 12. ENABLE SERVICES (PAS DE START IMMÉDIAT)
############################################
echo "[12/14] Enabling services"
sudo systemctl enable pirate-display
sudo systemctl enable pirate-buttons
sudo systemctl enable squeezelite
sudo systemctl enable shairport-sync

############################################
# 13. FIN
############################################
echo "[13/14] Installation finished"
echo "[14/14] Rebooting in 5 seconds"

sleep 5
sudo reboot
