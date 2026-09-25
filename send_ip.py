#!/usr/bin/env python3
import os, sys, json, urllib.request, urllib.parse
from datetime import datetime

BOT_TOKEN = os.environ.get("IP_MONITOR_BOT_TOKEN", "")
CHAT_ID   = os.environ.get("IP_MONITOR_CHAT_ID", "")
IP_SERVICE = os.environ.get("IP_SERVICE", "https://ifconfig.me/ip")
IP_FILE    = "/var/lib/ip-monitor/last_ip.txt"

def get_public_ip():
    try:
        req = urllib.request.Request(IP_SERVICE, headers={"User-Agent": "IPMonitor/1.0"})
        with urllib.request.urlopen(req, timeout=10) as r:
            ip = r.read().decode().strip()
        return ip if ip and ("." in ip or ":" in ip) else None
    except Exception as e:
        print(f"[ERROR] get_public_ip: {e}", file=sys.stderr)
        return None

def read_last_ip():
    try:
        if os.path.exists(IP_FILE):
            with open(IP_FILE) as f:
                v = f.read().strip()
                return v if v else None
    except Exception:
        pass
    return None

def save_ip(ip):
    os.makedirs(os.path.dirname(IP_FILE), exist_ok=True)
    with open(IP_FILE, "w") as f:
        f.write(ip)

def send_to_telegram(msg: str):
    if not BOT_TOKEN or not CHAT_ID:
        print("[ERROR] BOT_TOKEN або CHAT_ID не задано", file=sys.stderr)
        return False
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    data = urllib.parse.urlencode({
        "chat_id": CHAT_ID,
        "text": msg,
        "parse_mode": "HTML"
    }).encode()
    try:
        with urllib.request.urlopen(urllib.request.Request(url, data=data, method="POST"), timeout=10) as r:
            return json.loads(r.read().decode()).get("ok", False)
    except Exception as e:
        print(f"[ERROR] telegram: {e}", file=sys.stderr)
        return False

def main():
    ip = get_public_ip()
    if not ip:
        print("[ERROR] Не вдалося визначити IP", file=sys.stderr)
        sys.exit(1)
    last = read_last_ip()
    if ip == last:
        print(f"[OK] IP не змінився: {ip}")
        return
    print(f"[CHANGE] {last or '—'} → {ip}")
    save_ip(ip)
    msg = (f"🔁 <b>Зміна IP обладнання</b>\n\n"
           f"Старий: <code>{last or '—'}</code>\n"
           f"Новий:  <b><code>{ip}</code></b>\n"
           f"Час: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    if send_to_telegram(msg):
        print("[OK] Telegram: надіслано")
    else:
        print("[ERROR] Telegram: не надіслано", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
