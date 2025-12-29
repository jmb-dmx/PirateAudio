#!/usr/bin/env bash
set -e

########################################
# PIRATE AUDIO – INSTALLATION STABLE
# Utilise EXACTEMENT les scripts fournis
########################################

USER="raspberry"
HOME_DIR="/home/$USER"

echo "[*] PirateAudio – installation"
echo

########################################
# SYSTEM UPDATE
########################################
echo "[*] Mise à jour du système"
sudo apt update
sudo apt full-upgrade -y

########################################
# DEPENDENCIES
########################################
echo "[*] Installation des dépendances"
sudo apt install -y \
  python3 python3-pip \
  python3-pil python3-numpy \
  curl git iw \
  alsa-utils \
  squeezelite shairport-sync

########################################
# ENABLE SPI / I2C / DAC
########################################
echo "[*] Activation SPI / I2C / I2S DAC"
BOOTCFG="/boot/firmware/config.txt"

grep -q "^dtparam=spi=on" "$BOOTCFG" || echo "dtparam=spi=on" | sudo tee -a "$BOOTCFG"
grep -q "^dtparam=i2c_arm=on" "$BOOTCFG" || echo "dtparam=i2c_arm=on" | sudo tee -a "$BOOTCFG"
grep -q "^dtoverlay=hifiberry-dac" "$BOOTCFG" || echo "dtoverlay=hifiberry-dac" | sudo tee -a "$BOOTCFG"

########################################
# PYTHON LIBS (DISPLAY + GPIO)
########################################
echo "[*] Installation librairies Python"
pip3 install --break-system-packages \
  st7789 gpiodevice requests pillow

########################################
# COPY USER SCRIPTS (NO MODIFICATION)
########################################
echo "[*] Installation des scripts utilisateur"

install -m 755 pirate_display.py "$HOME_DIR/pirate_display.py"
install -m 755 pirate_buttons.py "$HOME_DIR/pirate_buttons.py"

########################################
# DISPLAY SERVICE
########################################
echo "[*] Création service écran"

sudo tee /etc/systemd/system/pirate-display.service > /dev/null <<EOF
[Unit]
Description=Pirate Audio Display
After=network-online.target
Wants=network-online.target

[Service]
User=raspberry
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
echo "[*] Création service boutons"

sudo tee /etc/systemd/system/pirate-buttons.service > /dev/null <<EOF
[Unit]
Description=Pirate Audio Buttons
After=network-online.target
Wants=network-online.target

[Service]
User=raspberry
ExecStart=/usr/bin/python3 /home/raspberry/pirate_buttons.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

########################################
# ENABLE SERVICES
########################################
echo "[*] Activation des services"
sudo systemctl daemon-reload
sudo systemctl enable pirate-display
sudo systemctl enable pirate-buttons
sudo systemctl enable squeezelite
sudo systemctl enable shairport-sync

########################################
# FIN
########################################
echo
echo "[OK] Installation terminée"
echo "[INFO] Redémarrage dans 5 secondes"
sleep 5
sudo reboot
