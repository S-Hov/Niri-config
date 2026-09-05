#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Запустите через sudo: sudo $0" >&2
  exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
product="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
if [[ ${product} != "83LV" ]]; then
  echo "Остановка: конфигурация рассчитана на Lenovo 83LV, обнаружено ${product:-неизвестно}" >&2
  exit 1
fi

for required in legion-fan-curve.py legion-fan-curve.json legion-fan-curve.service blacklist-yogafan-83lv.conf; do
  [[ -r ${script_dir}/${required} ]] || { echo "Не найден ${script_dir}/${required}" >&2; exit 1; }
done

kernel="$(uname -r | cut -d- -f1)"
if [[ $(printf '%s\n' "7.2" "${kernel}" | sort -V | head -1) != "7.2" ]]; then
  echo "Требуется запущенное ядро 7.2 или новее; сейчас ${kernel}" >&2
  exit 1
fi

for command_name in python3 sensors systemctl; do
  command -v "${command_name}" >/dev/null || {
    echo "Не найдена команда ${command_name}; установите зависимости из cooling/README.md" >&2
    exit 1
  }
done

stamp="$(date +%Y%m%d-%H%M%S)"
backup_dir="/var/backups/legion-fan-curve-${stamp}"
install -d -m 0700 "${backup_dir}"

backup_path() {
  local path="$1"
  if [[ -e ${path} || -L ${path} ]]; then
    cp -a --parents "${path}" "${backup_dir}"
  fi
}

for path in \
  /usr/local/libexec/legion-fan-curve.py \
  /etc/legion-fan-curve.json \
  /etc/systemd/system/legion-fan-curve.service \
  /etc/modprobe.d/blacklist-yogafan-83lv.conf \
  /etc/modprobe.d/legion.conf \
  /etc/legion_linux \
  /etc/xdg/autostart/legion-toolkit.desktop \
  /usr/lib/legion-toolkit; do
  backup_path "${path}"
done

rollback() {
  /usr/bin/python3 "${script_dir}/legion-fan-curve.py" --reset 2>/dev/null || true
}
trap rollback ERR INT TERM

echo "[1/6] Остановка предыдущих контроллеров"
systemctl disable --now legiond.service 2>/dev/null || true
systemctl stop legion-fan-curve.service 2>/dev/null || true
modprobe -r legion_laptop 2>/dev/null || true

legacy_packages=()
for package_name in lenovolegionlinux-dkms-git lenovolegionlinux-git; do
  pacman -Q "${package_name}" &>/dev/null && legacy_packages+=("${package_name}")
done
if ((${#legacy_packages[@]})); then
  pacman -R --noconfirm "${legacy_packages[@]}"
fi

for legacy_path in /etc/modprobe.d/legion.conf /etc/xdg/autostart/legion-toolkit.desktop /usr/lib/legion-toolkit; do
  if [[ -e ${legacy_path} || -L ${legacy_path} ]]; then
    destination="${backup_dir}/removed-${legacy_path#/}"
    install -d "$(dirname "${destination}")"
    mv "${legacy_path}" "${destination}"
  fi
done

echo "[2/6] Загрузка штатного Lenovo WMI"
modprobe lenovo_wmi_other

echo "[3/6] Preflight: пять секунд на 50% допустимого диапазона"
/usr/bin/python3 "${script_dir}/legion-fan-curve.py" --preflight

echo "[4/6] Установка файлов"
install -D -m 0755 "${script_dir}/legion-fan-curve.py" /usr/local/libexec/legion-fan-curve.py
install -D -m 0644 "${script_dir}/legion-fan-curve.json" /etc/legion-fan-curve.json
install -D -m 0644 "${script_dir}/legion-fan-curve.service" /etc/systemd/system/legion-fan-curve.service
install -D -m 0644 "${script_dir}/blacklist-yogafan-83lv.conf" /etc/modprobe.d/blacklist-yogafan-83lv.conf
modprobe -r yogafan 2>/dev/null || true

echo "[5/6] Включение сервиса"
systemctl daemon-reload
systemctl enable --now legion-fan-curve.service
sleep 5
if ! systemctl is-active --quiet legion-fan-curve.service; then
  systemctl status legion-fan-curve.service --no-pager || true
  exit 1
fi

echo "[6/6] Проверка"
systemctl status legion-fan-curve.service --no-pager
sensors lenovo_wmi_other-virtual-0 2>/dev/null || true
journalctl -u legion-fan-curve.service -n 20 --no-pager

trap - ERR INT TERM
echo
echo "Установлено. Конфигурация: /etc/legion-fan-curve.json"
echo "Возврат в BIOS-auto: systemctl stop legion-fan-curve.service"
echo "Резервная копия: ${backup_dir}"
