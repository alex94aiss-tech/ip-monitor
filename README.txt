IP Monitor — надсилання публічного IP обладнання в Telegram

Що робить:
- кожні 5 хвилин перевіряє поточний публічний IP
- якщо IP змінився — відправляє повідомлення в Telegram
- зберігає останній IP у /var/lib/ip-monitor/last_ip.txt

Що потрібно:
- Ubuntu (або інший Linux з systemd)
- Telegram-бот (токен вже встановлено в env)
- Chat ID (вже встановлено в env — 850506439)

Як встановити (через USB):
1. Скопіювати цю папку на флешку
2. На Ubuntu вставити флешку
3. Відкрити термінал і перейти в папку:
     cd /media/<користувач>/<назва>/ip_skrspo
4. Запустити:
     sudo bash install.sh
5. Скрипт сам скопирує файли, налаштує таймер і зробить перший запуск

Перевірка після встановлення:
- journalctl -u ip-monitor -f    # логи в реальному часі
- systemctl status ip-monitor.timer  # чи працює таймер

Вимкнення:
- sudo systemctl disable --now ip-monitor.timer
- sudo rm /opt/ip-monitor/send_ip.py /etc/ip-monitor/env \
         /etc/systemd/system/ip-monitor.service \
         /etc/systemd/system/ip-monitor.timer
