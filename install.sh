#!/usr/bin/env bash
set -e

########################################
# PIRATE AUDIO - INSTALLATION STABLE
# - utilise les scripts existants
# - demande le token dans le terminal
# - ne stocke rien dans GitHub
########################################

USER="raspberry"
HOME_DIR="/home/$USER"
ENV_FILE="$HOME_DIR/.pirateaudio.env"
BOOTCFG="/boot/firmware/config.txt"

echo "[*] PirateAudio installation"
echo

########################################
# SYSTEM UPDATE
########################################
echo "[*] System update"
sudo apt update
sudo apt full-upgrade -y

########################################
# ASK HOME ASSISTANT CONFIG (SECURE)
########################################
echo
read -rp "Home Assistant URL (ex: http://192.168.1.161:8123): " HA_URL </dev/tty
read -rsp "Home Assistant TOKEN (input hidden): " HA_TOKEN </dev/tty
echo
echo

if [[ -z "$HA_URL" || -z "$HA_TOKEN" ]]; then
  echo "[ERROR] URL or TOKEN missing"
  exit 1
fi

########################################
# STORE LOCAL ENV (NOT IN GITHUB)
########################################
echo "[*] Storing local credentials"

cat > "$ENV_FILE" <<EOF
HA_URL=$HA_URL
HA_TOKEN=$HA_TOKEN
EOF

chmod 600 "$ENV_FILE"
chown $USER:$USER "$ENV_FILE"

########################################
# DEPENDENCIES
########################################
echo "[*] Installing dependencies"
sudo apt install -y \
  python3 python3-pip \
  python3-pil python3-numpy \
  curl git iw \
  alsa-utils \
  squeezelite shairport-sync

########################################
# ENABLE SPI / I2C / DAC
########################################
echo "[*] Enabling SPI / I2C / I2S DAC"

grep -q "^dtparam=spi=on" "$BOOTCFG" || echo "dtparam=spi=on" | sudo tee -a "$BOOTCFG"
grep -q "^dtparam=i2c_arm=on" "$BOOTCFG" || echo "dtparam=i2c_arm=on" | sudo tee -a "$BOOTCFG"
grep -q "^dtoverlay=hifiberry-dac" "$BOOTCFG" || echo "dtoverlay=hifiberry-dac" | sudo tee -a "$BOOTCFG"

########################################
# PYTHON LIBRARIES
########################################
echo "[*] Installing Python libraries"
pip3 install --break-system-packages \
  st7789 gpiodevice requests pillow

########################################
# COPY USER SCRIPTS (NO MODIFICATION)
########################################
echo "[*] Installing user scripts"

install -m 755 pirate_display.py "$HOME_DIR/pirate_display.py"
install -m 755 pirate_buttons.py "$HOME_DIR/pirate_buttons.py"

########################################
# DISPLAY SERVICE
########################################
echo "[*] Creating display service"

sudo tee /etc/systemd/system/pirate-display.service > /dev/null <<EOF
[Unit]
Description=Pirate Audio Display
After=network-online.target
Wants=network-online.target

[Service]
User=raspberry
EnvironmentFile=$ENV_FILE
ExecStartPre=/usr/bin/bash -c 'until [ -e /dev/spidev0.0 ]; do sleep 0.2; done'
ExecStart=/usr/bin/python3 /home/raspberry/pirate_display.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

########################################
# BUTTONS SERVICE
########################################
echo "[*] Creating buttons service"

sudo tee /etc/systemd/system/pirate-buttons.service > /dev/null <<EOF
[Unit]
Description=Pirate Audio Buttons
After=network-online.target
Wants=network-online.target

[Service]
User=raspberry
EnvironmentFile=$ENV_FILE
ExecStart=/usr/bin/python3 /home/raspberry/pirate_buttons.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

########################################
# ENABLE SERVICES (NO START)
########################################
echo "[*] Enabling services"
sudo systemctl daemon-reload
sudo systemctl enable pirate-display
sudo systemctl enable pirate-buttons
sudo systemctl enable squeezelite
sudo systemctl enable shairport-sync

########################################
# REBOOT
########################################
echo
echo "[OK] Installation finished"
echo "[INFO] Rebooting in 5 seconds"
sleep 5
sudo reboot
