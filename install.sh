#!/usr/bin/env bash
set -e

########################################
# SYSTEM UPDATE (BEFORE ANYTHING)
########################################

echo "[*] System update"
sudo apt update
sudo apt upgrade -y

########################################
# INTERACTIVE CONFIG (TTY SAFE)
########################################

echo
echo "[*] PirateAudio - Home Assistant configuration"
echo

read -rp "Home Assistant URL (ex: http://192.168.1.161:8123) : " HA_URL </dev/tty
echo

read -rsp "Home Assistant token (paste then ENTER) : " HA_TOKEN </dev/tty
echo
echo

if [[ -z "$HA_URL" || -z "$HA_TOKEN" ]]; then
  echo "[ERROR] HA_URL or HA_TOKEN empty"
  exit 1
fi

TOKEN_LEN=${#HA_TOKEN}
TOKEN_TAIL="${HA_TOKEN: -4}"

if [[ "$TOKEN_LEN" -lt 150 ]]; then
  echo "[ERROR] Token too short ($TOKEN_LEN chars)"
  exit 1
fi

echo "[OK] Token received: $TOKEN_LEN chars ...$TOKEN_TAIL"
echo

echo "[*] Validating Home Assistant API access"
if ! curl -fsSL -H "Authorization: Bearer $HA_TOKEN" "$HA_URL/api/" >/dev/null; then
  echo "[ERROR] Home Assistant unreachable or invalid token"
  exit 1
fi
echo "[OK] Home Assistant connection validated"
echo

########################################
# VARIABLES
########################################

USER="raspberry"
HOME="/home/$USER"
IMG_DIR="$HOME/images"
PLAYER_NAME="PirateAudio"
CONFIG_FILE="/boot/firmware/config.txt"

GITHUB_USER="jmb-dmx"
GITHUB_REPO="PirateAudio"
GITHUB_BRANCH="main"
IMG_BASE_URL="https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/$GITHUB_BRANCH/images"

########################################
# HOSTNAME
########################################

echo "[*] Setting hostname to PirateAudio"
sudo hostnamectl set-hostname PirateAudio
sudo sed -i 's/127.0.1.1.*/127.0.1.1\tPirateAudio/' /etc/hosts

########################################
# DEPENDENCIES
########################################

echo "[*] Installing system dependencies"
sudo apt install -y \
  python3 python3-pip python3-pil python3-numpy \
  curl git iw unzip \
  alsa-utils \
  squeezelite shairport-sync

########################################
# SPI / I2C / DAC
########################################

echo "[*] Enabling SPI, I2C and I2S DAC"

grep -q "^dtparam=spi=on" "$CONFIG_FILE" || echo "dtparam=spi=on" | sudo tee -a "$CONFIG_FILE"
grep -q "^dtparam=i2c_arm=on" "$CONFIG_FILE" || echo "dtparam=i2c_arm=on" | sudo tee -a "$CONFIG_FILE"
grep -q "^dtoverlay=hifiberry-dac" "$CONFIG_FILE" || echo "dtoverlay=hifiberry-dac" | sudo tee -a "$CONFIG_FILE"

########################################
# WIFI POWER SAVE OFF
########################################

echo "[*] Disabling WiFi power save"

sudo tee /etc/systemd/system/wifi-powersave-off.service > /dev/null <<EOF
[Unit]
Description=Disable WiFi Power Save
After=network.target

[Service]
Type=oneshot
ExecStart=/sbin/iw dev wlan0 set power_save off
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable wifi-powersave-off
sudo systemctl start wifi-powersave-off

########################################
# PYTHON LIBRARIES
########################################

echo "[*] Installing Python libraries"
pip3 install --break-system-packages st7789 gpiodevice requests pillow

########################################
# IMAGES
########################################

echo "[*] Downloading images"
mkdir -p "$IMG_DIR"

for img in boot.png idle.png airplay.png; do
  echo "    - $img"
  curl -fsSL "$IMG_BASE_URL/$img" -o "$IMG_DIR/$img" || echo "      [WARN] $img not downloaded"
done

########################################
# AIRPLAY
########################################

echo "[*] Configuring AirPlay"

sudo tee /etc/shairport-sync.conf > /dev/null <<EOF
general = { name = "$PLAYER_NAME"; };

alsa = {
  output_device = "hw:CARD=sndrpihifiberry";
  mixer_control_name = "none";
};
EOF

sudo mkdir -p /etc/systemd/system/shairport-sync.service.d
sudo tee /etc/systemd/system/shairport-sync.service.d/override.conf > /dev/null <<EOF
[Unit]
After=network-online.target squeezelite.service
Wants=network-online.target
EOF

########################################
# SQUEEZELITE
########################################

echo "[*] Enabling squeezelite"
sudo systemctl enable squeezelite

########################################
# DISPLAY SCRIPT
########################################

echo "[*] Creating pirate_display.py"

cat > "$HOME/pirate_display.py" <<EOF
#!/usr/bin/env python3
import time, requests
from PIL import Image, ImageEnhance
from io import BytesIO
import st7789

HA_URL="$HA_URL"
TOKEN="$HA_TOKEN"

PLAYER="media_player.pirate_audio"
BRIGHT="input_number.pirate_brightness"

IMG="$IMG_DIR"
BOOT=f"{IMG}/boot.png"
IDLE=f"{IMG}/idle.png"
AIR=f"{IMG}/airplay.png"

HEADERS={"Authorization":f"Bearer {TOKEN}"}

time.sleep(0.5)

disp = st7789.ST7789(
    port=0,
    cs=1,
    dc=9,
    backlight=13,
    width=240,
    height=240,
    rotation=90,
    spi_speed_hz=80000000,
    invert=True
)
disp.begin()

def ha(e):
    r = requests.get(f"{HA_URL}/api/states/{e}", headers=HEADERS, timeout=5)
    r.raise_for_status()
    return r.json()

def show(p, b):
    i = Image.open(p).resize((240,240))
    i = ImageEnhance.Brightness(i).enhance(max(0.05, b/100))
    disp.display(i)

last = None
while True:
    try:
        b = int(float(ha(BRIGHT)["state"]))
    except:
        b = 100
    try:
        p = ha(PLAYER)
        if p["state"] == "playing":
            pic = p["attributes"].get("entity_picture")
            if pic:
                u = pic if pic.startswith("http") else HA_URL + pic
                d = requests.get(u, headers=HEADERS, timeout=5).content
                i = Image.open(BytesIO(d)).resize((240,240))
                i = ImageEnhance.Brightness(i).enhance(b/100)
                disp.display(i)
                last = "play"
        else:
            if last != "idle":
                show(IDLE, b)
                last = "idle"
    except:
        if last != "boot":
            show(BOOT, b)
            last = "boot"
    time.sleep(1)
EOF

chmod +x "$HOME/pirate_display.py"

########################################
# DISPLAY SERVICE (WAIT FOR SPI)
########################################

echo "[*] Creating pirate-display.service"

sudo tee /etc/systemd/system/pirate-display.service > /dev/null <<EOF
[Unit]
Description=Pirate Audio Display
After=network-online.target squeezelite.service shairport-sync.service
Wants=network-online.target

[Service]
User=$USER
ExecStartPre=/usr/bin/bash -c 'until [ -e /dev/spidev0.0 ]; do sleep 0.2; done'
ExecStartPre=/bin/sleep 1
ExecStart=/usr/bin/python3 $HOME/pirate_display.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

########################################
# FINALIZATION
########################################

echo "[*] Enabling services"
sudo systemctl daemon-reload
sudo systemctl enable pirate-display
sudo systemctl enable shairport-sync
sudo systemctl start pirate-display
sudo systemctl start shairport-sync

echo
echo "[OK] Installation complete"
echo "[INFO] Reboot required"
echo
