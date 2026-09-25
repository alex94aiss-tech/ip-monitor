IP Monitor — надсилання публічного IP + SSH-статус обладнання в Telegram

Що робить:
- кожні 5 хвилин перевіряє поточний публічний IP
- перевіряє, чи доступний SSH (порт 22 за замовчуванням) на цьому IP
- якщо IP або статус SSH змінився — відправляє повідомлення в Telegram
- при кожному запуску системи (boot) також перевіряє і надсилає, якщо щось змінилося
- зберігає останній IP у /var/lib/ip-monitor/last_ip.txt

Формат повідомлення в Telegram:
  🔁 <назва системи>
  IP: <ip> (новий) — або без (новий), якщо це не перший запуск
  SSH (порт): 🟢 доступний — SSH відповідає (0.12с)
  — або 🔴 відмовлено / 🟡 таймаут / ❌ не визначено

Що потрібно:
- Ubuntu (або інший Linux з systemd)
- Telegram-бот (токен і Chat ID задаються в /etc/ip-monitor/env)
- назва системи — теж в env (наприклад, ЛСДС_5)

Як встановити:

Варіант 1 — через GitHub (рекомендовано):
  curl -sL https://gist.githubusercontent.com/alex94aiss-tech/fb33fd645163ebc469869b6584a85263/raw/715c3d554da42f8103fb0c47579ede4a1c4735fb/install.sh | sudo bash

Під час встановлення скрипт запитає:
  Як часто надсилати повідомлення?
    1 — тільки при старті системи (boot)
    2 — при старті + кожні N хвилин (за замовчуванням 5 хв)

  Ваш вибір (1 або 2, за замовчуванням 2):

  Якщо обрано 1 — таймер не активується, повідомлення надходять лише при завантаженні системи.
  Якщо обрано 2 — додатково налаштовується таймер на зазначений інтервал (за замовчуванням 5 хв,
  змінюється в env через IP_MONITOR_CHECK_INTERVAL).

Встановлення (через USB):

Варіант 2 — з USB:
  1. Скопіювати цю папку на флешку
  2. На Ubuntu вставити флешку
  3. Відкрити термінал і перейти в папку:
       cd /media/<користувач>/<назва>/ip_skrspo
  4. Запустити:
       sudo bash install.sh
  Скрипт сам скопіює файли, налаштує таймер і зробить перший запуск.

Варіант 3 — вручну (через GitHub Gist):
  git clone https://github.com/alex94aiss-tech/ip-monitor.git
  cd ip-monitor
  sudo bash install.sh

Після встановлення:
- таймер запускається кожні 5 хвилин
- сервіс при старті системи (boot) також виконується
- перший запуск одразу надішле тестове повідомлення в Telegram

Перевірка після встановлення:
- journalctl -u ip-monitor -f          # логи в реальному часі
- systemctl status ip-monitor.timer     # чи працює таймер
- systemctl status ip-monitor-boot.service  # сервіс при старті
- cat /var/lib/ip-monitor/last_ip.txt   # останній відомий IP

Налаштування:
- файл конфігурації: /etc/ip-monitor/env
- редагувати: sudo nano /etc/ip-monitor/env
- після змін: sudo systemctl restart ip-monitor.timer

Поля в env:
  IP_MONITOR_BOT_TOKEN=<токен від BotFather>
  IP_MONITOR_CHAT_ID=<chat ID>
  IP_MONITOR_SYSTEM_NAME=<назва системи, наприклад ЛСДС_5>
  IP_MONITOR_SSH_PORT=22              # порт SSH
  IP_MONITOR_SSH_TIMEOUT=5            # таймаут перевірки SSH в секундах
  IP_MONITOR_CHECK_INTERVAL=5         # інтервал перевірки в хвилинах (таймер)

Оновлення:

Встановлена версія оновлюється з GitHub. Є три способи:

Варіант 1 — однією командою (рекомендовано):
  curl -sL https://raw.githubusercontent.com/alex94aiss-tech/ip-monitor/main/update.sh | sudo bash

Варіант 2 — через git (якщо система встановлена через git clone):
  cd /opt/ip-monitor
  git pull origin main
  sudo systemctl daemon-reload
  sudo systemctl restart ip-monitor.timer 2>/dev/null || true
  sudo systemctl restart ip-monitor-boot.service

Варіант 3 — через install.sh з аргументом --update:
  curl -sL https://gist.githubusercontent.com/alex94aiss-tech/fb33fd645163ebc469869b6584a85263/raw/715c3d554da42f8103fb0c47579ede4a1c4735fb/install.sh | sudo bash -- --update

Що робить update.sh:
- робить резервну копію /etc/ip-monitor/env (щоб не втратити токен і налаштування)
- оновлює файли: send_ip.py, ip-monitor.service, ip-monitor.timer, ip-monitor-boot.service
- не чіпає env (конфігурацію)
- перезапускає systemd
- робить тестовий запуск

Вимкнення:
- sudo systemctl disable --now ip-monitor.timer
- sudo systemctl disable ip-monitor-boot.service
- sudo systemctl disable ip-monitor-telegram.service
- sudo rm /opt/ip-monitor/send_ip.py /opt/ip-monitor/telegram_bot.py \
          /etc/ip-monitor/env \
          /etc/systemd/system/ip-monitor.service \
          /etc/systemd/system/ip-monitor.timer \
          /etc/systemd/system/ip-monitor-boot.service \
          /etc/systemd/system/ip-monitor-telegram.service

Telegram-керування:
Бот працює як systemd-сервіс ip-monitor-telegram.service.
Для управління з Telegram потрібно:
1. Додати бота @stasys_1994 як адміністратора в чат 850506439
2. Запустити сервіс: sudo systemctl start ip-monitor-telegram.service

Команди бота:
  /status  — поточний IP + SSH-статус
  /ip      — тільки поточний IP
  /update  — оновити IP Monitor з GitHub
  /restart — перезапустити сервіси
  /help    — список команд

Логи бота: journalctl -u ip-monitor-telegram -f

Репозиторій:
  https://github.com/alex94aiss-tech/ip-monitor

Автор:
  ПрАТ "Стабільні системи" (СТАСИС, stasys.com.ua)
