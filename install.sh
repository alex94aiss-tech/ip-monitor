#!/bin/bash
# IP Monitor — встановлення через GitHub Gist
# Одна команда: curl -sL <цей-URL> | sudo bash
set -e

echo "=== Встановлення IP Monitor ==="

# 1. Створити директорії
sudo mkdir -p /opt/ip-monitor /var/lib/ip-monitor /etc/ip-monitor

# 2. Файл конфігурації
sudo tee /etc/ip-monitor/env > /dev/null << 'ENVEOF'
IP_MONITOR_BOT_TOKEN=8905507918:AAFQixlsGfHIW06lPvBEoeVAFeaUus3tbUc
IP_MONITOR_CHAT_ID=850506439
IP_MONITOR_SYSTEM_NAME=ЛСДС_5
IP_MONITOR_SSH_PORT=22
IP_MONITOR_SSH_TIMEOUT=5
IP_MONITOR_CHECK_INTERVAL=5
ENVEOF
sudo chmod 600 /etc/ip-monitor/env

# 3. Скрипт моніторингу (IP + SSH + Telegram)
sudo tee /opt/ip-monitor/send_ip.py > /dev/null << 'PYEOF'
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
        ssh_line += f"\U0001F7E2 <b>доступний</b> \u2014 {ssh['info']}"
    elif ssh["status"] == "timeout":
        ssh_line += f"\U0001F7E1 <b>таймаут</b> \u2014 {ssh['info']}"
    elif ssh["status"] == "refused":
        ssh_line += f"\U0001F7E2 <b>відмовлено</b> \u2014 {ssh['info']}"
    else:
        ssh_line += f"\u274c <b>не визначено</b> \u2014 {ssh['info']}"
    old_ip_line = f"Попередній IP: <code>{last_ip or '\u2014'}</code>\n" if last_ip else ""
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

sudo chmod 755 /opt/ip-monitor/send_ip.py

# 4. systemd-сервіс
sudo tee /etc/systemd/system/ip-monitor.service > /dev/null << 'EOF'
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

# 5. systemd-таймер (періодичний)
sudo tee /etc/systemd/system/ip-monitor.timer > /dev/null << 'EOF'
[Unit]
Description=Запускати IP Monitor періодично

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
AccuracySec=1min

[Install]
WantedBy=timers.target
EOF

# 6. systemd-сервіс при старті
sudo tee /etc/systemd/system/ip-monitor-boot.service > /dev/null << 'EOF'
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

# 7. Активувати
sudo systemctl daemon-reload

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

echo ""
echo "Готово. Первинний тест..."
sudo bash -c 'source /etc/ip-monitor/env && python3 /opt/ip-monitor/send_ip.py'
echo ""
echo "Логи: journalctl -u ip-monitor -f"
echo "Таймер: systemctl status ip-monitor.timer"
echo "Boot-сервіс: systemctl status ip-monitor-boot.service"
