#!/usr/bin/env bash
# Installs the latest scripts and web files from this repository onto a server that is already set up.
# It does not touch SMTP settings, student accounts or the phpMyAdmin password.
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

cp "${REPO_ROOT}/web/register.php" "${REPO_ROOT}/web/register_handler.php" /var/www/html/
cp "${REPO_ROOT}"/web/lib/*.php /var/www/html/lib/
chown -R www-data:www-data /var/www/html

cp "${REPO_ROOT}/templates/nginx-students.conf" /etc/nginx/sites-available/students
install -d -o www-data -g www-data -m 700 /var/lib/5cs045-registrations /var/lib/5cs045-ratelimit /var/lib/5cs045-registration-locks

# Move old credentials.txt files out of the students' homes (students could edit them)
install -d -o root -g root -m 700 /var/lib/5cs045-credentials
for old in /srv/students/*/credentials.txt; do
  [[ -f "$old" ]] || continue
  name="$(basename "$(dirname "$old")")"
  install -o root -g root -m 600 "$old" "/var/lib/5cs045-credentials/${name}"
  rm -f "$old"
done

"${DEPLOY_ROOT}/bin/refresh-student-folders.sh" >/dev/null

nginx -t
systemctl reload nginx php8.3-fpm
echo "Server updated."
