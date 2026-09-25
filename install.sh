#!/bin/bash
set -e
echo "=== Встановлення IP Monitor ==="

# Створити директорії
sudo mkdir -p /opt/ip-monitor /var/lib/ip-monitor /etc/ip-monitor

# Скопіювати файли
sudo cp send_ip.py /opt/ip-monitor/
sudo cp env /etc/ip-monitor/
sudo cp ip-monitor.service /etc/systemd/system/
sudo cp ip-monitor.timer /etc/systemd/system/

# Права
sudo chmod 755 /opt/ip-monitor/send_ip.py
sudo chmod 600 /etc/ip-monitor/env

# Перевірка Chat ID
CHAT=$(grep '^IP_MONITOR_CHAT_ID=' /etc/ip-monitor/env | cut -d= -f2 | tr -d ' "')
if [ -z "$CHAT" ]; then
    echo "Введіть Chat ID (цифра, для групи/каналу з мінусом):"
    read -r CHAT
    echo "IP_MONITOR_CHAT_ID=$CHAT" | sudo tee /etc/ip-monitor/env > /dev/null
fi

# Активувати таймер
sudo systemctl daemon-reload
sudo systemctl enable --now ip-monitor.timer

echo ""
echo "Готово. Первинний запуск для тесту:"
sudo bash -c 'source /etc/ip-monitor/env && python3 /opt/ip-monitor/send_ip.py'

echo ""
echo "Перевірка:"
echo "  - логи: journalctl -u ip-monitor -f"
echo "  - статус таймера: systemctl status ip-monitor.timer"
