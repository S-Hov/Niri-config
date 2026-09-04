#!/usr/bin/env bash
set -euo pipefail

# Скрипт установки и развертывания конфигурации охлаждения для Lenovo Legion
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$EUID" -ne 0 ]; then
    echo "Ошибка: Этот скрипт необходимо запускать с правами root (например, через sudo)."
    exit 1
fi

echo "==> 1. Копирование параметров модуля ядра в /etc/modprobe.d/..."
cp "$SCRIPT_DIR/modprobe/legion.conf" /etc/modprobe.d/legion.conf

echo "==> 2. Создание каталога /etc/legion_linux и копирование профилей..."
mkdir -p /etc/legion_linux
cp "$SCRIPT_DIR/presets/"*.yaml /etc/legion_linux/
cp "$SCRIPT_DIR/presets/legiond.ini" /etc/legion_linux/

echo "==> 3. Применение патча совместимости для legion.py..."
python3 -c '
import glob
import sys

matches = glob.glob("/usr/lib/python3*/site-packages/legion_linux/legion.py")
if not matches:
    print("Внимание: legion.py не найден в python site-packages. Убедитесь, что установлен lenovolegionlinux-git.")
    sys.exit(0)

path = matches[0]
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

target = """    @staticmethod
    def _write_file(file_path, value):
        with open(file_path, "w", encoding=DEFAULT_ENCODING) as filepointer:
            filepointer.write(str(value))"""

replacement = """    @staticmethod
    def _write_file(file_path, value):
        try:
            with open(file_path, "w", encoding=DEFAULT_ENCODING) as filepointer:
                filepointer.write(str(value))
        except OSError:
            pass"""

if target in content:
    with open(path, "w", encoding="utf-8") as f:
        f.write(content.replace(target, replacement))
    print("Патч успешно применен к:", path)
elif replacement in content:
    print("Патч уже был применен ранее к:", path)
else:
    print("Сигнатура _write_file не совпала или уже модифицирована.")
'

echo "==> 4. Перезагрузка модуля ядра legion_laptop..."
if lsmod | grep -q "^legion_laptop"; then
    modprobe -r legion_laptop || true
fi
modprobe legion_laptop force=1

echo "==> 5. Включение и перезапуск фоновой службы legiond..."
systemctl enable legiond.service
systemctl restart legiond.service

echo "==> 6. Запись профиля охлаждения в контроллер..."
if command -v legion_cli >/dev/null 2>&1; then
    legion_cli fancurve-write-file-to-hw /etc/legion_linux/performance-ac.yaml || true
fi

echo ""
echo "=== Готово! Охлаждение успешно настроено. ==="
echo "Текущий статус службы:"
systemctl status legiond.service --no-pager -l || true
