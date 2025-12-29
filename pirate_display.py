#!/usr/bin/env python3
import os
import time
import requests
from io import BytesIO
from PIL import Image, ImageEnhance
import st7789

########################################
# LOAD HOME ASSISTANT ENV (SECURE)
########################################

ENV_FILE = "/home/raspberry/.pirateaudio.env"

if not os.path.exists(ENV_FILE):
    raise RuntimeError("Missing /home/raspberry/.pirateaudio.env")

with open(ENV_FILE) as f:
    for line in f:
        if "=" in line:
            k, v = line.strip().split("=", 1)
            os.environ[k] = v

HA_URL = os.environ.get("HA_URL")
HA_TOKEN = os.environ.get("HA_TOKEN")

if not HA_URL or not HA_TOKEN:
    raise RuntimeError("HA_URL or HA_TOKEN not defined")

HEADERS = {
    "Authorization": f"Bearer {HA_TOKEN}",
    "Content-Type": "application/json",
}

########################################
# CONFIG
########################################

MEDIA_PLAYER = "media_player.pirate_audio"
BRIGHTNESS_ENTITY = "input_number.pirate_brightness"

IMG_DIR = "/home/raspberry/images"
BOOT_IMG = f"{IMG_DIR}/boot.png"
IDLE_IMG = f"{IMG_DIR}/idle.png"
AIRPLAY_IMG = f"{IMG_DIR}/airplay.png"

########################################
# DISPLAY INIT (VALIDATED)
########################################

disp = st7789.ST7789(
    port=0,
    cs=0,
    dc=9,
    backlight=13,
    spi_speed_hz=80_000_000,
    width=240,
    height=240,
    rotation=90
)

disp.begin()
disp.set_backlight(1)

########################################
# HELPERS
########################################

def get_state(entity_id):
    r = requests.get(
        f"{HA_URL}/api/states/{entity_id}",
        headers=HEADERS,
        timeout=5
    )
    r.raise_for_status()
    return r.json()

def show_image(path, brightness=100):
    if not os.path.exists(path):
        return
    img = Image.open(path).convert("RGB").resize((240, 240))
    img = ImageEnhance.Brightness(img).enhance(max(0.05, brightness / 100))
    disp.display(img)

def show_cover(url, brightness):
    r = requests.get(url, headers=HEADERS, timeout=5)
    r.raise_for_status()
    img = Image.open(BytesIO(r.content)).convert("RGB").resize((240, 240))
    img = ImageEnhance.Brightness(img).enhance(max(0.05, brightness / 100))
    disp.display(img)

########################################
# STARTUP IMAGE
########################################

show_image(BOOT_IMG, 100)
time.sleep(1)

########################################
# MAIN LOOP
########################################

last_mode = None

while True:
    try:
        # Brightness
        try:
            brightness = int(float(get_state(BRIGHTNESS_ENTITY)["state"]))
        except Exception:
            brightness = 100

        # Media state
        player = get_state(MEDIA_PLAYER)
        state = player["state"]

        # AirPlay detection (Music Assistant sets source)
        source = player["attributes"].get("source", "").lower()
        is_airplay = "airplay" in source

        if is_airplay:
            if last_mode != "airplay":
                show_image(AIRPLAY_IMG, brightness)
                last_mode = "airplay"

        elif state != "playing":
            if last_mode != "idle":
                show_image(IDLE_IMG, brightness)
                last_mode = "idle"

        else:
            pic = player["attributes"].get("entity_picture")
            if pic:
                if not pic.startswith("http"):
                    pic = HA_URL + pic
                show_cover(pic, brightness)
                last_mode = "cover"

    except Exception:
        # fallback safe
        show_image(BOOT_IMG, 100)
        last_mode = "boot"

    time.sleep(1)