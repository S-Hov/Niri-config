#!/usr/bin/env bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Ошибка: запустите скрипт через sudo." >&2
    exit 1
fi

PRODUCT_NAME="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
BIOS_VERSION="$(cat /sys/class/dmi/id/bios_version 2>/dev/null || true)"
if [[ "$PRODUCT_NAME" != "83LV" || "$BIOS_VERSION" != RLCN* ]]; then
    echo "Отказ: ожидались 83LV и RLCN*, обнаружены $PRODUCT_NAME / $BIOS_VERSION." >&2
    exit 2
fi

echo "Отключение legiond, который пытается записывать несовместимую кривую..."
systemctl disable --now legiond.service

if [ -f /etc/modprobe.d/legion.conf ]; then
    mv /etc/modprobe.d/legion.conf /etc/modprobe.d/legion.conf.disabled
    echo "force=1 отключён; исходный файл сохранён как legion.conf.disabled."
fi

if [ -w /sys/firmware/acpi/platform_profile ]; then
    echo performance > /sys/firmware/acpi/platform_profile
fi

cat <<'EOF'
Готово. Включён штатный профиль Performance.
Перезагрузите ноутбук, чтобы выгрузить принудительно загруженный legion_laptop
и вернуть управление вентиляторами прошивке.
EOF
