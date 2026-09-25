#!/bin/bash
# IP Monitor — оновлення вже встановленої версії
# Оновлює файли з GitHub/Gist, зберігає конфігурацію, перезапускає сервіси
set -e

INSTALL_DIR="/opt/ip-monitor"
ENV_FILE="/etc/ip-monitor/env"
GIST_RAW="https://gist.githubusercontent.com/alex94aiss-tech/fb33fd645163ebc469869b6584a85263/raw/715c3d554da42f8103fb0c47579ede4a1c4735fb/install.sh"

echo "=== Оновлення IP Monitor ==="

# 1. Резервне копіювання env (щоб не втратити токен і налаштування)
if [ -f "$ENV_FILE" ]; then
    BACKUP="${ENV_FILE}.bak.$(date +%Y%m%d%H%M%S)"
    sudo cp "$ENV_FILE" "$BACKUP"
    echo "Резервна копія env: $BACKUP"
else
    echo "Внимание: env файл не знайдено — оновлення без конфігурації"
fi

# 2. Визначення способу оновлення
if [ -d "$INSTALL_DIR/.git" ]; then
    echo "Виявлено git-репозиторій — оновлюємо через git pull"
    cd "$INSTALL_DIR"
    git pull origin main
    echo "Git pull завершено"
else
    echo "Git-репозиторій не знайдено — оновлюємо через Gist"
    TMPDIR=$(mktemp -d)
    # Завантажуємо install.sh з Gist і розextract'имо файли
    # install.sh тепер підтримує аргумент --extract-only <dir>
    curl -sL "$GIST_RAW" | bash -s -- --extract-only "$TMPDIR"
    # Копіюємо оновлювані файли (крім env)
    for f in send_ip.py ip-monitor.service ip-monitor.timer ip-monitor-boot.service README.txt; do
        if [ -f "$TMPDIR/$f" ]; then
            sudo cp "$TMPDIR/$f" "$INSTALL_DIR/$f"
            echo "Оновлено: $f"
        fi
    done
    rm -rf "$TMPDIR"
fi

# 3. Відновлення env, якщо він був перезаписаний
if [ -f "$ENV_FILE" ]; then
    ORIG=$(ls -t "${ENV_FILE}.bak."* 2>/dev/null | head -1)
    if [ -n "$ORIG" ] && [ "$ORIG" -nt "$ENV_FILE" ]; then
        echo "Відновлено env з резервної копії: $ORIG"
        sudo cp "$ORIG" "$ENV_FILE"
        sudo chmod 600 "$ENV_FILE"
    fi
fi

# 4. Права
sudo chmod 755 "$INSTALL_DIR/send_ip.py" 2>/dev/null || true
sudo chmod 600 "$ENV_FILE" 2>/dev/null || true

# 5. Перезапуск systemd
sudo systemctl daemon-reload

# Перезапускаємо таймер, якщо він було активовано
if systemctl is-enabled ip-monitor.timer &>/dev/null && [ "$(systemctl is-active ip-monitor.timer 2>/dev/null)" = "active" ]; then
    echo "Таймер ip-monitor.timer активний — перезапускаємо"
    sudo systemctl restart ip-monitor.timer
else
    echo "Таймер не активовано — пропускаємо"
fi

# Boot-сервіс завжди перезапускаємо
sudo systemctl restart ip-monitor-boot.service 2>/dev/null || true

# 6. Тест
echo ""
echo "Готово. Тестовий запуск..."
sudo bash -c "source $ENV_FILE && python3 $INSTALL_DIR/send_ip.py"

echo ""
echo "Логи: journalctl -u ip-monitor -f"
echo "Таймер: systemctl status ip-monitor.timer"
echo "Boot-сервіс: systemctl status ip-monitor-boot.service"
