#!/usr/bin/env bash
# Installs the latest scripts and web files from this repository onto a server that is already set up.
# It does not touch SMTP settings or student accounts.
#
# Usage: cd /opt/5cs045-provisioning && git pull && sudo ./setup/update-server.sh
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run this with sudo."; exit 1; }
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_ROOT="/usr/local/sbin/5cs045"

install -d "${DEPLOY_ROOT}/bin" "${DEPLOY_ROOT}/templates" /var/www/html/lib
cp "${REPO_ROOT}"/bin/* "${DEPLOY_ROOT}/bin/"
cp "${REPO_ROOT}/templates/php-fpm-pool.conf.template" "${DEPLOY_ROOT}/templates/"
chmod 750 "${DEPLOY_ROOT}"/bin/*
chown -R root:root "${DEPLOY_ROOT}"

cp "${REPO_ROOT}/web/index.php" "${REPO_ROOT}/web/register_handler.php" /var/www/html/
cp "${REPO_ROOT}"/web/lib/*.php /var/www/html/lib/
chown -R www-data:www-data /var/www/html

cp "${REPO_ROOT}/templates/nginx-students.conf" /etc/nginx/sites-available/students
install -d -o www-data -g www-data -m 700 /var/lib/5cs045-registrations /var/lib/5cs045-ratelimit /var/lib/5cs045-ip-ratelimit /var/lib/5cs045-registration-locks

cp "${REPO_ROOT}/templates/sshd-students.conf" /etc/ssh/sshd_config.d/50-students.conf
sshd -t
cp "${REPO_ROOT}/templates/fail2ban-5cs045.conf" /etc/fail2ban/jail.d/5cs045-sshd.conf

# PHP's open-file limit only changes on a restart, so restart only when the setting changed
FPM_RESTART=0
if ! cmp -s "${REPO_ROOT}/templates/php-fpm-systemd.conf" /etc/systemd/system/php8.3-fpm.service.d/5cs045.conf; then
  install -D -o root -g root -m 644 "${REPO_ROOT}/templates/php-fpm-systemd.conf" /etc/systemd/system/php8.3-fpm.service.d/5cs045.conf
  systemctl daemon-reload
  FPM_RESTART=1
fi

# Let running requests finish when PHP reloads (a reload is enough for this one)
install -o root -g root -m 644 "${REPO_ROOT}/templates/php-fpm-global.conf" /etc/php/8.3/fpm/pool.d/00-5cs045-global.conf

# Room on the system bus for a whole class logging in at once. A reload is enough; never restart dbus.
if ! cmp -s "${REPO_ROOT}/templates/dbus-5cs045-limits.conf" /etc/dbus-1/system.d/5cs045-limits.conf; then
  install -o root -g root -m 644 "${REPO_ROOT}/templates/dbus-5cs045-limits.conf" /etc/dbus-1/system.d/5cs045-limits.conf
  systemctl reload dbus
fi
getent group 5cs045-students >/dev/null || groupadd 5cs045-students
install -o root -g root -m 644 "${REPO_ROOT}/templates/limits-5cs045-students.conf" /etc/security/limits.d/5cs045-students.conf

install -o root -g root -m 644 "${REPO_ROOT}/templates/cron-5cs045" /etc/cron.d/5cs045
echo root > /etc/cron.allow
echo root > /etc/at.allow
install -d -o root -g root -m 700 /var/lib/5cs045-db-over

# Move old credentials.txt files out of the students' homes (students could edit them)
install -d -o root -g root -m 700 /var/lib/5cs045-credentials
for old in /srv/students/*/credentials.txt; do
  [[ -f "$old" ]] || continue
  name="$(basename "$(dirname "$old")")"
  install -o root -g root -m 600 "$old" "/var/lib/5cs045-credentials/${name}"
  rm -f "$old"
done

"${REPO_ROOT}/setup/install-admin-panel.sh"

"${DEPLOY_ROOT}/bin/refresh-student-folders.sh" >/dev/null
"${DEPLOY_ROOT}/bin/apply-student-limits.sh" >/dev/null

nginx -t
systemctl reload nginx
if [[ "$FPM_RESTART" -eq 1 ]]; then
  systemctl restart php8.3-fpm   # a second or two of 502s on student sites
else
  systemctl reload php8.3-fpm
fi
# SSH and fail2ban read their settings only at (re)start. try-reload leaves a stopped service alone.
systemctl try-reload-or-restart ssh fail2ban
echo "Server updated. Admin panel: https://<server>:8443"
