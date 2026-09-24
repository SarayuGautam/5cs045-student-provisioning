#!/usr/bin/env bash
set -uo pipefail

DEPLOY_ROOT="/usr/local/sbin/5cs045"
PURGE_PACKAGES=0
ASSUME_YES=0
for arg in "$@"; do
  case "$arg" in
    --purge-packages) PURGE_PACKAGES=1 ;;
    --yes) ASSUME_YES=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done
[[ $EUID -eq 0 ]] || { echo "run as root"; exit 1; }

if [[ "$ASSUME_YES" -eq 0 ]]; then
  read -r -p "Remove all 5CS045 configuration and provisioned students? [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

if [[ -d /srv/students ]]; then
  for home in /srv/students/*/; do
    [[ -d "$home" ]] || continue
    user="$(basename "$home")"
    if id "$user" &>/dev/null && [[ -x "${DEPLOY_ROOT}/bin/remove-student.sh" ]]; then
      "${DEPLOY_ROOT}/bin/remove-student.sh" -u "$user" || true
    fi
  done
fi

rm -f /etc/nginx/sites-enabled/students /etc/nginx/sites-available/students
rm -rf /etc/nginx/ssl/5cs045-selfsigned.*
rm -f /etc/nginx/.htpasswd-admin /etc/nginx/.htpasswd-register
rm -f /etc/ssh/sshd_config.d/50-students.conf
rm -f /etc/sudoers.d/5cs045-provisioning
rm -f /etc/fail2ban/jail.d/5cs045-sshd.conf
rm -f /etc/systemd/system/php8.3-fpm.service.d/5cs045.conf
rmdir /etc/systemd/system/php8.3-fpm.service.d 2>/dev/null || true
rm -f /etc/cron.d/5cs045 /etc/cron.allow /etc/at.allow
rm -f /etc/dbus-1/system.d/5cs045-limits.conf /etc/security/limits.d/5cs045-students.conf
systemctl reload dbus 2>/dev/null || true
groupdel 5cs045-students 2>/dev/null || true
for dropin in /etc/systemd/system/user-*.slice.d/50-5cs045-limits.conf; do
  [[ -f "$dropin" ]] || continue
  uid="${dropin#/etc/systemd/system/user-}"; uid="${uid%%.slice.d/*}"
  [[ "$(readlink "/etc/systemd/system/user@${uid}.service" 2>/dev/null)" == /dev/null ]] && rm -f "/etc/systemd/system/user@${uid}.service"
done
rm -f /etc/systemd/system/user-*.slice.d/50-5cs045-limits.conf
rmdir /etc/systemd/system/user-*.slice.d 2>/dev/null || true
systemctl daemon-reload 2>/dev/null || true
rm -rf /etc/5cs045
rm -rf /var/lib/5cs045-ratelimit /var/lib/5cs045-ip-ratelimit /var/lib/5cs045-registration-locks /var/lib/5cs045-registrations /var/lib/5cs045-db-over /var/lib/5cs045-disk-alert-sent
rm -f /var/log/5cs045-registration.log /var/log/5cs045-provisioning.log
rm -f /var/www/html/index.php /var/www/html/register_handler.php
rm -rf /var/www/html/lib
rm -rf "$DEPLOY_ROOT"

if [[ -f /etc/nginx/sites-available/default && ! -e /etc/nginx/sites-enabled/default ]]; then
  ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
fi
nginx -t 2>&1 || true
sshd -t 2>&1 || true
visudo -c 2>&1 || true

if [[ "$PURGE_PACKAGES" -eq 1 ]]; then
  echo "Purging packages and MariaDB data. This is destructive."
  export DEBIAN_FRONTEND=noninteractive
  systemctl stop nginx php8.3-fpm mariadb 2>/dev/null || true
  apt-get purge -y -qq nginx nginx-common php8.3-fpm php8.3-mysql php8.3-cli \
    php8.3-mbstring php8.3-xml php8.3-curl php8.3-zip mariadb-server phpmyadmin 2>&1 | tail -20
  apt-get autoremove -y -qq 2>&1 | tail -10
  rm -rf /var/lib/mysql /etc/mysql
fi

echo "5CS045 configuration removed."
