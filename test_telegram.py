#!/usr/bin/env python3
"""Тест — надіслати повідомлення в Telegram."""
import os, sys, json, urllib.request, urllib.parse

BOT_TOKEN = os.environ.get("IP_MONITOR_BOT_TOKEN", "")
CHAT_ID   = os.environ.get("IP_MONITOR_CHAT_ID", "")

def send(msg: str):
    if not BOT_TOKEN or not CHAT_ID:
        print("Помилка: не задано BOT_TOKEN або CHAT_ID", file=sys.stderr)
        sys.exit(1)
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    data = urllib.parse.urlencode({
        "chat_id": CHAT_ID,
        "text": msg
    }).encode()
    try:
        req = urllib.request.Request(url, data=data, method="POST")
        with urllib.request.urlopen(req, timeout=10) as resp:
            result = json.loads(resp.read().decode())
        if result.get("ok"):
            print(f"OK: повідомлення надіслано в чат {CHAT_ID}")
            print(f"    message_id = {result['result']['message_id']}")
        else:
            print(f"Помилка API: {result.get('description')}", file=sys.stderr)
            sys.exit(1)
    except Exception as e:
        print(f"Помилка мережі: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    send("тест скрспо")
