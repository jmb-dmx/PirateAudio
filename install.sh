#!/usr/bin/env bash
set -e

########################################
# CONFIG INTERACTIVE
########################################

echo "🏴‍☠️ Pirate Audio – Installation automatique"
echo

read -rp "Adresse Home Assistant (ex: http://192.168.1.161:8123) : " HA_URL
echo
read -rsp "Token Home Assistant (entrée masquée) : " HA_TOKEN
echo
echo

if [[ -z "$HA_URL" || -z "$HA_TOKEN" ]]; then
  echo "❌ HA_URL ou HA_TOKEN vide — arrêt"
  exit 1
fi

########################################
# VARIABLES
########################################
USER="raspberry"
HOME="/home/$USER"
IMG_DIR="$HOME/images"
PLAYER_NAME="PirateAudio"

GITHUB_USER="jmb-dmx"
GITHUB_REPO="PirateAudio"
GITHUB_BRANCH="main"
IMG_BASE_URL="https://raw.githubusercontent.com/$GITHUB_USER/$GITHUB_REPO/$GITHUB_BRANCH/images"

########################################
echo "➡️ Mise à jour système"
########################################
sudo apt update
sudo apt full-upgrade -y

########################################
echo "➡️ Installation dépendances"
########################################
sudo apt install -y \
  python3 python3-pip python3-pil python3-numpy \
  curl git unzip iw \
  alsa-utils \
  squeezelite shairport-sync

########################################
echo "➡️ Désactivation Wi-Fi power save"
########################################
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
echo "➡️ Activation DAC I2S"
########################################
if ! grep -q "hifiberry-dac" /boot/firmware/config.txt; then
  echo "dtoverlay=hifiberry-dac" | sudo tee -a /boot/firmware/config.txt
fi

########################################
echo "➡️ Librairies Python écran / GPIO"
########################################
pip3 install --break-system-packages \
  st7789 gpiodevice requests pillow

########################################
echo "➡️ Téléchargement des images depuis GitHub"
########################################
mkdir -p "$IMG_DIR"

download_image() {
  local name="$1"
  local url="$IMG_BASE_URL/$name"
  local dest="$IMG_DIR/$name"

  echo "📥 Téléchargement $name"
  if ! curl -fsSL "$url" -o "$dest"; then
    echo "⚠️ Impossible de télécharger $name (continuation)"
  fi
}

download_image "boot.png"
download_image "idle.png"
download_image "airplay.png"

########################################
echo "➡️ Configuration AirPlay"
########################################
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
echo "➡️ Activation Squeezelite"
########################################
sudo systemctl enable squeezelite

########################################
echo "➡️ Script écran Pirate Audio"
########################################
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

disp=st7789.ST7789(
    port=0, cs=1, dc=9, backlight=13,
    width=240, height=240
)
disp.begin()

def get_state(e):
    r=requests.get(f"{HA_URL}/api/states/{e}",headers=HEADERS,timeout=5)
    r.raise_for_status()
    return r.json()

def show(img,b):
    img=Image.open(img).resize((240,240)).convert("RGB")
    img=ImageEnhance.Brightness(img).enhance(max(0.05,b/100))
    disp.display(img)

last=None
while True:
    try:
        b=int(float(get_state(BRIGHT)["state"]))
    except:
        b=100

    if os.path.exists(FLAG):
        if last!="airplay":
            show(AIRPLAY,b); last="airplay"
        time.sleep(1); continue

    try:
        p=get_state(PLAYER)
        if p["state"]!="playing":
            if last!="idle":
                show(IDLE,b); last="idle"
        else:
            pic=p["attributes"].get("entity_picture")
            if pic:
                url=pic if pic.startswith("http") else HA_URL+pic
                img=requests.get(url,headers=HEADERS,timeout=5).content
                im=Image.open(BytesIO(img)).resize((240,240))
                im=ImageEnhance.Brightness(im).enhance(b/100)
                disp.display(im)
                last="cover"
    except:
        show(BOOT,b); last="boot"

    time.sleep(1)
EOF

chmod +x "$HOME/pirate_display.py"

########################################
echo "➡️ Service écran"
########################################
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
echo "➡️ Finalisation services"
########################################
sudo systemctl daemon-reload
sudo systemctl enable pirate-display
sudo systemctl enable shairport-sync
sudo systemctl start pirate-display
sudo systemctl start shairport-sync

########################################
echo
echo "✅ INSTALLATION TERMINÉE"
echo "➡️ Redémarrage requis"
echo
