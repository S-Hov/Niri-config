#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Запустите через sudo: sudo $0" >&2
  exit 1
fi

stamp="$(date +%Y%m%d-%H%M%S)"
archive="/var/backups/legion-fan-curve-removed-${stamp}"
install -d -m 0700 "${archive}"

systemctl disable --now legion-fan-curve.service 2>/dev/null || true
/usr/bin/python3 /usr/local/libexec/legion-fan-curve.py --reset 2>/dev/null || true

for path in \
  /usr/local/libexec/legion-fan-curve.py \
  /etc/legion-fan-curve.json \
  /etc/systemd/system/legion-fan-curve.service \
  /etc/modprobe.d/blacklist-yogafan-83lv.conf; do
  if [[ -e ${path} || -L ${path} ]]; then
    mv "${path}" "${archive}/$(basename "${path}")"
  fi
done

systemctl daemon-reload
echo "Контроллер удалён, включён BIOS-auto. Архив: ${archive}"
