#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root."; exit 1; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

cp "$REPO_ROOT/web/register.php" "$REPO_ROOT/web/register_handler.php" /var/www/html/
cp "$REPO_ROOT/web/lib/smtp_mailer.php" /var/www/html/lib/
cp "$REPO_ROOT/templates/nginx-students.conf" /etc/nginx/sites-available/students
cp "$REPO_ROOT/bin/reset-student-password.sh" /usr/local/sbin/5cs045/bin/
chmod 750 /usr/local/sbin/5cs045/bin/reset-student-password.sh
chown root:root /usr/local/sbin/5cs045/bin/reset-student-password.sh

install -d -o www-data -g www-data -m 700 /var/lib/5cs045-registrations
install -d -o www-data -g www-data -m 700 /var/lib/5cs045-ratelimit
install -d -o www-data -g www-data -m 700 /var/lib/5cs045-registration-locks

if [[ -f /etc/nginx/.htpasswd-register && ! -f /etc/nginx/.htpasswd-admin ]]; then
  mv /etc/nginx/.htpasswd-register /etc/nginx/.htpasswd-admin
fi
[[ -f /etc/nginx/.htpasswd-admin ]] || { echo "Missing /etc/nginx/.htpasswd-admin"; exit 1; }
chown root:www-data /etc/nginx/.htpasswd-admin
chmod 640 /etc/nginx/.htpasswd-admin

chown www-data:www-data /var/www/html/register.php /var/www/html/register_handler.php
chown -R www-data:www-data /var/www/html/lib

nginx -t
systemctl reload nginx
systemctl reload php8.3-fpm

echo "v2 registration changes applied."
echo "Registration: https://<server>/register.php"
echo "phpMyAdmin remains protected by /etc/nginx/.htpasswd-admin"
