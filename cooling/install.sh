#!/usr/bin/env bash
set -euo pipefail

# Скрипт установки и развертывания конфигурации охлаждения для Lenovo Legion
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$EUID" -ne 0 ]; then
    echo "Ошибка: Этот скрипт необходимо запускать с правами root (например, через sudo)."
    exit 1
fi

# RLCN/83LV (Legion R9000P ADR10, EC 0x5508) is not supported by the
# LenovoLegionLinux fan-curve backend yet. With force=1 the driver falls back
# to the old GKCN memory map: temperatures/RPM become garbage and curve writes
# are partial. Refuse to touch the EC on this hardware.
PRODUCT_NAME="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
BIOS_VERSION="$(cat /sys/class/dmi/id/bios_version 2>/dev/null || true)"
if [[ "$PRODUCT_NAME" == "83LV" || "$BIOS_VERSION" == RLCN* ]]; then
    cat >&2 <<EOF
Ошибка: $PRODUCT_NAME / $BIOS_VERSION пока не поддерживает пользовательские
кривые LenovoLegionLinux. force=1 ошибочно выбирает таблицу GKCN и может
повредить кривую в EC. Установка остановлена без изменений.

Используйте штатный профиль Performance (Fn+Q, красный индикатор) и не
включайте maximumfanspeed: на RLCN он может не выключиться до перезагрузки.
EOF
    exit 2
fi

echo "==> 1. Копирование параметров модуля ядра в /etc/modprobe.d/..."
cp "$SCRIPT_DIR/modprobe/legion.conf" /etc/modprobe.d/legion.conf

echo "==> 2. Создание каталога /etc/legion_linux и копирование профилей..."
mkdir -p /etc/legion_linux
cp "$SCRIPT_DIR/presets/"*.yaml /etc/legion_linux/
cp "$SCRIPT_DIR/presets/legiond.ini" /etc/legion_linux/

echo "==> 3. Проверка установленного LenovoLegionLinux..."
command -v legion_cli >/dev/null 2>&1 || {
    echo "Ошибка: legion_cli не найден. Установите lenovolegionlinux-git." >&2
    exit 1
}

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
