#!/usr/bin/env bash
set -e

########################################
# MISE À JOUR SYSTÈME (AVANT TOUT)
########################################

echo "🔄 Mise à jour du système (obligatoire)"
sudo apt update
sudo apt upgrade -y

########################################
# CONFIG INTERACTIVE (TTY SAFE)
########################################

echo
echo "🏴‍☠️ Pirate Audio – Configuration Home Assistant"
echo

read -rp "Adresse Home Assistant (ex: http://192.168.1.161:8123) : " HA_URL </dev/tty
echo

read -rsp "Token Home Assistant (entrée masquée, collez puis ENTER) : " HA_TOKEN </dev/tty
echo
echo

if [[ -z "$HA_URL" || -z "$HA_TOKEN" ]]; then
  echo "❌ HA_URL ou HA_TOKEN vide — arrêt"
  exit 1
fi

# Vérification basique du token
TOKEN_LEN=${#HA_TOKEN}
TOKEN_TAIL="${HA_TOKEN: -4}"

if [[ "$TOKEN_LEN" -lt 150 ]]; then
  echo "❌ Token trop court ($TOKEN_LEN caractères)"
  echo "👉 Probable erreur de copier-coller"
  exit 1
fi

echo "✅ Token reçu : $TOKEN_LEN caractères — se termine par …$TOKEN_TAIL"
echo

########################################
# VALIDATION API HOME ASSISTANT
########################################

echo "🔍 Validation du token Home Assistant…"

if ! curl -fsSL \
  -H "Authorization: Bearer $HA_TOKEN" \
  "$HA_URL/api/" >/dev/null; then
  echo "❌ Impossible de valider le token (URL ou token invalide)"
  exit 1
fi

echo "✅ Connexion Home Assistant validée"
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
# INSTALLATION DÉPENDANCES
########################################

echo "➡️ Installation des dépendances système"
sudo apt install -y \
  python3 python3-pip python3-pil python3-numpy \
  curl git unzip iw \
  alsa-utils \
  squeezelite shairport-sync

########################################
# ACTIVATION SPI / I2C
########################################

echo "➡️ Activation SPI et I²C"

if ! grep -q "^dtparam=spi=on" "$CONFIG_FILE"; then
  echo "dtparam=spi=on" | sudo tee -a "$CONFIG_FILE"
fi

if ! grep -q "^dtparam=i2c_arm=on" "$CONFIG_FILE"; then
  echo "dtparam=i2c_arm=on" | sudo tee -a "$CONFIG_FILE"
fi

########################################
# ACTIVATION DAC I2S
########################################

echo "➡️ Activation DAC I2S"

if ! grep -q "^dtoverlay=hifiberry-dac" "$CONFIG_FILE"; then
  echo "dtoverlay=hifiberry-dac" | sudo tee -a "$CONFIG_FILE"
fi

########################################
# WIFI POWER SAVE OFF
########################################

echo "➡️ Désactivation Wi-Fi power save"

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
# LIBRAIRIES PYTHON
########################################

echo "➡️ Installation librairies Python"
pip3 install --break-system-packages \
  st7789 gpiodevice requests pillow

########################################
# IMAGES (GITHUB)
########################################

echo "➡️ Téléchargement des images"
mkdir -p "$IMG_DIR"

download_image() {
  local name="$1"
  local url="$IMG_BASE_URL/$name"
  local dest="$IMG_DIR/$name"

  echo "📥 $name"
  if ! curl -fsSL "$url" -o "$dest"; then
    echo "⚠️ Impossible de télécharger $name (continuation)"
  fi
}

download_image "boot.png"
download_image "idle.png"
download_image "airplay.png"

########################################
# AIRPLAY (SHAIRPORT-SYNC)
########################################

echo "➡️ Configuration AirPlay"

sudo tee /etc/shairport-sync.conf > /dev/null <<EOF
general =
{
  name = "$PLAYER_NAME";
};

alsa =
{
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

echo "➡️ Activation Squeezelite"
sudo systemctl enable squeezelite

########################################
# SCRIPT ÉCRAN pirate_display.py
########################################

echo "➡️ Création pirate_display.py"

cat > "$HOME/pirate_display.py" <<EOF
#!/usr/bin/env python3
import time, os, requests
from PIL import Image, ImageEnhance
from io import BytesIO
import st7789

HA_URL="$HA_URL"
TOKEN="$HA_TOKEN"

PLAYER="media_player.pirate_audio"
BRIGHT="input_number.pirate_brightness"

IMG_DIR="$IMG_DIR"
BOOT=f"{IMG_DIR}/boot.png"
IDLE=f"{IMG_DIR}/idle.png"
AIRPLAY=f"{IMG_DIR}/airplay.png"
FLAG="/tmp/airplay_active"

HEADERS={"Authorization":f"Bearer {TOKEN}"}

disp = st7789.ST7789(
    port=0,
    cs=1,
    dc=9,
    backlight=13,
    width=240,
    height=240,
    rotation=90
)
disp.begin()

def get_state(e):
    r = requests.get(f"{HA_URL}/api/states/{e}", headers=HEADERS, timeout=5)
    r.raise_for_status()
    return r.json()

def show(path, b):
    img = Image.open(path).resize((240,240)).convert("RGB")
    img = ImageEnhance.Brightness(img).enhance(max(0.05, b/100))
    disp.display(img)

last = None

while True:
    try:
        b = int(float(get_state(BRIGHT)["state"]))
    except:
        b = 100

    if os.path.exists(FLAG):
        if last != "airplay":
            show(AIRPLAY, b)
            last = "airplay"
        time.sleep(1)
        continue

    try:
        p = get_state(PLAYER)
        if p["state"] != "playing":
            if last != "idle":
                show(IDLE, b)
                last = "idle"
        else:
            pic = p["attributes"].get("entity_picture")
            if pic:
                url = pic if pic.startswith("http") else HA_URL + pic
                data = requests.get(url, headers=HEADERS, timeout=5).content
                img = Image.open(BytesIO(data)).resize((240,240))
                img = ImageEnhance.Brightness(img).enhance(b/100)
                disp.display(img)
                last = "cover"
    except:
        show(BOOT, b)
        last = "boot"

    time.sleep(1)
EOF

chmod +x "$HOME/pirate_display.py"

########################################
# SERVICE ÉCRAN
########################################

echo "➡️ Service pirate-display"

sudo tee /etc/systemd/system/pirate-display.service > /dev/null <<EOF
[Unit]
Description=Pirate Audio Display
After=network-online.target squeezelite.service shairport-sync.service

[Service]
User=$USER
ExecStartPre=/bin/sleep 5
ExecStart=/usr/bin/python3 $HOME/pirate_display.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

########################################
# FINALISATION
########################################

echo "➡️ Activation des services"
sudo systemctl daemon-reload
sudo systemctl enable pirate-display
sudo systemctl enable shairport-sync
sudo systemctl start pirate-display
sudo systemctl start shairport-sync

echo
echo "✅ INSTALLATION TERMINÉE"
echo "➡️ REDÉMARRAGE OBLIGATOIRE"
echo
