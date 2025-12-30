import lgpio
import time
import requests
import os
import logging

# Configure logging
log_file = os.path.join(os.path.expanduser("~"), "buttons.log")
logging.basicConfig(
    filename=log_file,
    level=logging.INFO,
    format="%(asctime)s %(levelname)s:%(message)s",
)

# ===== CONFIG =====
ENV_FILE = os.path.join(os.path.expanduser("~"), ".pirateaudio.env")

if not os.path.exists(ENV_FILE):
    raise RuntimeError("Missing .pirateaudio.env file")

with open(ENV_FILE) as f:
    for line in f:
        if "=" in line:
            k, v = line.strip().split("=", 1)
            os.environ[k] = v

HA_URL = os.environ.get("HA_URL")
TOKEN = os.environ.get("HA_TOKEN")
ENTITY_ID = "media_player.pirate_audio"

HEADERS = {
    "Authorization": f"Bearer {TOKEN}",
    "Content-Type": "application/json",
}

# GPIO Pirate Audio
BUTTONS = {
    5: "media_play_pause",   # A
    6: "media_next_track",   # B
    16: "volume_up",         # X
    24: "volume_down"        # Y
}

h = lgpio.gpiochip_open(0)

for pin in BUTTONS:
    lgpio.gpio_claim_input(h, pin, lgpio.SET_PULL_UP)

def call(service):
    try:
        r = requests.post(
            f"{HA_URL}/api/services/media_player/{service}",
            headers=HEADERS,
            json={"entity_id": ENTITY_ID},
            timeout=3
        )
        r.raise_for_status()
    except requests.exceptions.RequestException as e:
        logging.error("Error calling Home Assistant: %s", e)

logging.info("🎛️ Boutons Pirate Audio (lgpio) actifs")

try:
    while True:
        for pin, service in BUTTONS.items():
            if lgpio.gpio_read(h, pin) == 0:
                logging.info(f"GPIO {pin} → {service}")
                call(service)
                time.sleep(0.4)
        time.sleep(0.05)
except KeyboardInterrupt:
    lgpio.gpiochip_close(h)
