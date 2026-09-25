#!/bin/bash
# IP Monitor — встановлення та оновлення
# Usage:
#   install.sh              — повна установка (питає про інтервал)
#   install.sh --update     — оновити файли без запитань
#   install.sh --extract-only <dir> — створити файли в директорії
set -e

INSTALL_DIR="/opt/ip-monitor"
ENV_FILE="/etc/ip-monitor/env"
GIST_RAW="https://gist.githubusercontent.com/alex94aiss-tech/fb33fd645163ebc469869b6584a85263/raw/715c3d554da42f8103fb0c47579ede4a1c4735fb/install.sh"

# ===== Функція створення файлів =====
create_files() {
    local target="$1"
    mkdir -p "$target"
    cat > "$target/env" << 'ENVEOF'
IP_MONITOR_BOT_TOKEN=8905507918:AAFQixlsGfHIW06lPvBEoeVAFeaUus3tbUc
IP_MONITOR_CHAT_ID=850506439
IP_MONITOR_SYSTEM_NAME=ЛСДС_5
IP_MONITOR_SSH_PORT=22
IP_MONITOR_SSH_TIMEOUT=5
IP_MONITOR_CHECK_INTERVAL=5
ENVEOF

    cat > "$target/send_ip.py" << 'PYEOF'
#!/usr/bin/env python3
import os, sys, json, urllib.request, urllib.parse, socket, datetime

BOT_TOKEN    = os.environ.get("IP_MONITOR_BOT_TOKEN", "")
CHAT_ID      = os.environ.get("IP_MONITOR_CHAT_ID", "")
SYSTEM_NAME  = os.environ.get("IP_MONITOR_SYSTEM_NAME", "Обладнання")
IP_SERVICE   = os.environ.get("IP_SERVICE", "https://ifconfig.me/ip")
SSH_PORT     = int(os.environ.get("IP_MONITOR_SSH_PORT", "22"))
SSH_TIMEOUT  = int(os.environ.get("IP_MONITOR_SSH_TIMEOUT", "5"))
IP_FILE      = "/var/lib/ip-monitor/last_ip.txt"

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

def check_ssh(ip: str) -> dict:
    result = {"status": "unknown", "info": ""}
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(SSH_TIMEOUT)
        start = datetime.datetime.now()
        sock.connect((ip, SSH_PORT))
        elapsed = (datetime.datetime.now() - start).total_seconds()
        sock.close()
        result["status"] = "up"
        result["info"] = f"SSH відповідає ({elapsed:.2f}с)"
    except socket.timeout:
        result["status"] = "timeout"
        result["info"] = f"SSH таймаут ({SSH_TIMEOUT}с)"
    except ConnectionRefusedError:
        result["status"] = "refused"
        result["info"] = "SSH відмовляється (Connection refused)"
    except OSError as e:
        result["status"] = "down"
        result["info"] = f"SSH недоступний: {e}"
    except Exception as e:
        result["status"] = "error"
        result["info"] = f"Помилка перевірки: {e}"
    return result

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
    last_ip = read_last_ip()
    ssh = check_ssh(ip)
    ip_changed = (ip != last_ip)
    print(f"[INFO] {SYSTEM_NAME} — IP: {ip}, SSH: {ssh['status']}")
    if not ip_changed and ssh["status"] in ("up",):
        print("[OK] IP і SSH без змін")
        return
    save_ip(ip)
    ip_line = f"IP: <b><code>{ip}</code></b>" + (f" (<i>новий</i>)" if ip_changed else "") + "\n"
    ssh_line = f"SSH ({SSH_PORT}): "
    if ssh["status"] == "up":
        ssh_line += f"\U0001F7E2 <b>доступний</b> — {ssh['info']}"
    elif ssh["status"] == "timeout":
        ssh_line += f"\U0001F7E1 <b>таймаут</b> — {ssh['info']}"
    elif ssh["status"] == "refused":
        ssh_line += f"\U0001F7E2 <b>відмовлено</b> — {ssh['info']}"
    else:
        ssh_line += f"\u274c <b>не визначено</b> — {ssh['info']}"
    old_ip_line = f"Попередній IP: <code>{last_ip or '—'}</code>\n" if last_ip else ""
    msg = (f"\U0001F541 <b>{SYSTEM_NAME}</b>\n\n"
           f"{ip_line}"
           f"{old_ip_line}"
           f"{ssh_line}\n"
           f"Час: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    if send_to_telegram(msg):
        print("[OK] Telegram: надіслано")
    else:
        print("[ERROR] Telegram: не надіслано", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
PYEOF

    cat > "$target/ip-monitor.service" << 'EOF'
[Unit]
Description=IP Monitor — надсилання змін IP + SSH-статус в Telegram
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
EnvironmentFile=/etc/ip-monitor/env
ExecStart=/usr/bin/python3 /opt/ip-monitor/send_ip.py
WorkingDirectory=/opt/ip-monitor
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    cat > "$target/ip-monitor.timer" << 'EOF'
[Unit]
Description=Запускати IP Monitor періодично

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
AccuracySec=1min

[Install]
WantedBy=timers.target
EOF

    cat > "$target/ip-monitor-boot.service" << 'EOF'
[Unit]
Description=IP Monitor — повідомлення при старті системи
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
EnvironmentFile=/etc/ip-monitor/env
ExecStart=/usr/bin/python3 /opt/ip-monitor/send_ip.py
WorkingDirectory=/opt/ip-monitor
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    cat > "$target/telegram_bot.py" << 'PYEOF'
#!/usr/bin/env python3
"""
Telegram-бот для управління IP Monitor з Telegram.
Commands:
  /status  — поточний IP + SSH-статус
  /ip      — тільки поточний IP
  /update  — запустити update.sh
  /restart — перезапустити ip-monitor сервіс
  /help    — список команд
"""

import os
import sys
import json
import urllib.request
import urllib.parse
import subprocess
import time
import re

BOT_TOKEN = os.environ.get("IP_MONITOR_BOT_TOKEN", "")
CHAT_ID   = os.environ.get("IP_MONITOR_CHAT_ID", "")

if not BOT_TOKEN or not CHAT_ID:
    print("Помилка: не встановлено BOT_TOKEN або CHAT_ID", file=sys.stderr)
    sys.exit(1)

BASE_URL = f"https://api.telegram.org/bot{BOT_TOKEN}"
LAST_UPDATE_ID = 0

def send_message(text: str):
    url = f"{BASE_URL}/sendMessage"
    data = urllib.parse.urlencode({
        "chat_id": CHAT_ID,
        "text": text,
        "parse_mode": "HTML"
    }).encode()
    try:
        req = urllib.request.Request(url, data=data, method="POST")
        with urllib.request.urlopen(req, timeout=10) as resp:
            result = json.loads(resp.read().decode())
        if result.get("ok"):
            return result["result"]["message_id"]
    except Exception as e:
        print(f"[bot] send_message error: {e}", file=sys.stderr)
    return None

def get_updates(offset: int = 0, timeout: int = 30):
    url = f"{BASE_URL}/getUpdates"
    params = urllib.parse.urlencode({
        "offset": offset,
        "timeout": timeout,
        "allowed_updates": ["message"]
    }).encode()
    try:
        req = urllib.request.Request(url, data=params, method="POST")
        with urllib.request.urlopen(req, timeout=35) as resp:
            result = json.loads(resp.read().decode())
        if result.get("ok"):
            return result["result"]
    except Exception as e:
        print(f"[bot] get_updates error: {e}", file=sys.stderr)
    return []

def handle_command(command: str, args: str) -> str:
    cmd = command.lower()

    if cmd in ("/status", "/st"):
        try:
            result = subprocess.run(
                ["sudo", "bash", "-c",
                 'source /etc/ip-monitor/env && python3 /opt/ip-monitor/send_ip.py'],
                capture_output=True, text=True, timeout=30
            )
            output = result.stdout.strip() or result.stderr.strip()
            return f"✅ <b>Статус IP Monitor:</b>\n{output}"
        except Exception as e:
            return f"❌ Помилка: {e}"

    elif cmd in ("/ip", "/i"):
        try:
            result = subprocess.run(
                ["curl", "-s", "https://ifconfig.me/ip"],
                capture_output=True, text=True, timeout=10
            )
            ip = result.stdout.strip()
            return f"🌐 <b>Поточний IP:</b> <code>{ip}</code>"
        except Exception as e:
            return f"❌ Помилка: {e}"

    elif cmd in ("/update", "/u"):
        try:
            result = subprocess.run(
                ["sudo", "/opt/ip-monitor/update.sh"],
                capture_output=True, text=True, timeout=60
            )
            output = result.stdout.strip() or result.stderr.strip()
            return f"🔄 <b>Оновлення:</b>\n{output[-500:]}"
        except Exception as e:
            return f"❌ Помилка: {e}"

    elif cmd in ("/restart", "/r"):
        try:
            subprocess.run(["sudo", "systemctl", "restart", "ip-monitor.timer"], timeout=10)
            subprocess.run(["sudo", "systemctl", "restart", "ip-monitor-boot.service"], timeout=10)
            return "🔄 <b>Сервіси перезапущено.</b>"
        except Exception as e:
            return f"❌ Помилка: {e}"

    elif cmd in ("/help", "/h"):
        return ("📋 <b>Команди:</b>\n\n"
                "• <code>/status</code> / <code>/st</code> — IP + SSH-статус\n"
                "• <code>/ip</code> / <code>/i</code> — тільки IP\n"
                "• <code>/update</code> / <code>/u</code> — оновити з GitHub\n"
                "• <code>/restart</code> / <code>/r</code> — перезапустити сервіси\n"
                "• <code>/help</code> / <code>/h</code> — цей список")

    else:
        return f"❓ Невідома команда: <code>/{command}</code>. Використовуйте <code>/help</code>."

def main():
    print(f"[bot] Запуск бота для чату {CHAT_ID}")
    while True:
        updates = get_updates(offset=LAST_UPDATE_ID + 1, timeout=30)
        for update in updates:
            msg = update.get("message", {})
            if not msg:
                continue
            chat_id = str(msg.get("chat", {}).get("id", ""))
            if chat_id != CHAT_ID:
                continue
            text = msg.get("text", "")
            if not text:
                continue
            match = re.match(r"^/(\w+)(?:\s+(.*))?$", text)
            if not match:
                continue
            command = match.group(1)
            print(f"[bot] /{command}")
            response = handle_command(f"/{command}", match.group(2) or "")
            if response:
                send_message(response)
            LAST_UPDATE_ID = update["update_id"]
        time.sleep(0.5)

if __name__ == "__main__":
    main()
PYEOF

    cat > "$target/telegram-bot.service" << 'EOF'
[Unit]
Description=IP Monitor Telegram Bot — управління з Telegram
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/ip-monitor/env
ExecStart=/usr/bin/python3 /opt/ip-monitor/telegram_bot.py
WorkingDirectory=/opt/ip-monitor
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
}

# ===== Аргументи =====
if [ "$1" = "--extract-only" ] && [ -n "$2" ]; then
    echo "Extracting files to $2..."
    create_files "$2"
    echo "Done."
    exit 0
fi

if [ "$1" = "--update" ]; then
    echo "Updating installed files..."
    create_files "/opt/ip-monitor"
    sudo chmod 755 /opt/ip-monitor/send_ip.py
    sudo chmod 600 /etc/ip-monitor/env 2>/dev/null || true
    sudo systemctl daemon-reload
    if systemctl is-enabled ip-monitor.timer &>/dev/null && [ "$(systemctl is-active ip-monitor.timer 2>/dev/null)" = "active" ]; then
        sudo systemctl restart ip-monitor.timer
        echo "Timer restarted."
    fi
    sudo systemctl restart ip-monitor-boot.service 2>/dev/null || true
    echo "Update completed."
    exit 0
fi

# Запитання: як часто надсилати
echo ""
echo "Як часто надсилати повідомлення?"
echo "  1 — тільки при старті системи (boot)"
echo "  2 — при старті + кожні N хвилин (за замовчуванням 5 хв)"
echo ""
read -p "Ваш вибір (1 або 2, за замовчуванням 2): " MODE

sudo systemctl enable ip-monitor-boot.service

if [ "$MODE" = "1" ]; then
    echo ""
    echo "Вибрано: тільки при старті системи."
    echo "Таймер не активовано."
    sudo systemctl disable --now ip-monitor.timer 2>/dev/null || true
else
    INTERVAL=$(grep '^IP_MONITOR_CHECK_INTERVAL=' /etc/ip-monitor/env | cut -d= -f2 | tr -d ' "')
    echo ""
    echo "Вибрано: при старті + кожні $INTERVAL хвилин."
    echo "Таймер активовано."
    sudo systemctl enable --now ip-monitor.timer
fi

# Telegram-бот
sudo systemctl enable ip-monitor-telegram.service 2>/dev/null || true
sudo systemctl start ip-monitor-telegram.service 2>/dev/null || true

echo ""
echo "Готово. Первинний тест..."
sudo bash -c 'source /etc/ip-monitor/env && python3 /opt/ip-monitor/send_ip.py'
echo ""
echo "Логи: journalctl -u ip-monitor -f"
echo "Таймер: systemctl status ip-monitor.timer"
echo "Boot-сервіс: systemctl status ip-monitor-boot.service"
echo "Telegram-бот: systemctl status ip-monitor-telegram.service"
