import lgpio
import time
import requests

# ===== CONFIG =====
HA_URL = "http://192.168.1.161:8123"
TOKEN = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJiMDNjNmY1OTBhNmY0ZGZmODU2Y2JmNDIxYjFlNDJjZSIsImlhdCI6MTc2NjgxMjc2NiwiZXhwIjoyMDgyMTcyNzY2fQ.asQBM2xpEjGJ3mw3XMXjIE-exjYWXJxeMVUcxjnubok"
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
    r = requests.post(
        f"{HA_URL}/api/services/media_player/{service}",
        headers=HEADERS,
        json={"entity_id": ENTITY_ID},
        timeout=3
    )
    if r.status_code not in (200, 201):
        print("Erreur HA:", r.status_code, r.text)

print("🎛️ Boutons Pirate Audio (lgpio) actifs")

try:
    while True:
        for pin, service in BUTTONS.items():
            if lgpio.gpio_read(h, pin) == 0:
                print(f"GPIO {pin} → {service}")
                call(service)
                time.sleep(0.4)
        time.sleep(0.05)
except KeyboardInterrupt:
    lgpio.gpiochip_close(h)

