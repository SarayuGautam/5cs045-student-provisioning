#!/usr/bin/env bash
set -euo pipefail

# First-time setup of the 5CS045 student server.
# Run once, as root, on a fresh Ubuntu 24.04 VM. Do not run it again on a working server
# (use update-server.sh instead).

[[ $EUID -eq 0 ]] || { echo "run as root"; exit 1; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DEPLOY_ROOT="/usr/local/sbin/5cs045"
ADMIN_AUTH_FILE="/etc/nginx/.htpasswd-admin"

export DEBIAN_FRONTEND=noninteractive

echo "==> Installing packages"
apt-get update -qq || echo "    apt-get update reported a problem; continuing to the package install"
PMA_DB_PASS="$(openssl rand -hex 16)"
debconf-set-selections <<-EOF2
	phpmyadmin phpmyadmin/dbconfig-install boolean true
	phpmyadmin phpmyadmin/app-password-confirm password ${PMA_DB_PASS}
	phpmyadmin phpmyadmin/mysql/admin-pass password
	phpmyadmin phpmyadmin/mysql/app-pass password ${PMA_DB_PASS}
	phpmyadmin phpmyadmin/reconfigure-webserver multiselect
EOF2
apt-get install -y -qq \
  nginx \
  php8.3-fpm php8.3-mysql php8.3-cli php8.3-mbstring php8.3-xml php8.3-curl php8.3-zip \
  mariadb-server \
  git composer acl unzip openssh-server phpmyadmin apache2-utils fail2ban sudo curl

echo "==> Creating student directories"
mkdir -p /srv/students /srv/students-archive
chown root:root /srv/students
chmod 711 /srv/students
chmod 700 /srv/students-archive

echo "==> Deploying provisioning tools"
mkdir -p "${DEPLOY_ROOT}/bin" "${DEPLOY_ROOT}/templates"
cp "${REPO_ROOT}"/bin/* "${DEPLOY_ROOT}/bin/"
cp "${REPO_ROOT}/templates/php-fpm-pool.conf.template" "${DEPLOY_ROOT}/templates/"
chmod 750 "${DEPLOY_ROOT}"/bin/*
chown -R root:root "${DEPLOY_ROOT}"
chmod -R go-w "${DEPLOY_ROOT}"

echo "==> Creating self-signed TLS certificate"
mkdir -p /etc/nginx/ssl
if [[ ! -f /etc/nginx/ssl/5cs045-selfsigned.crt ]]; then
  openssl req -x509 -nodes -days 825 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/5cs045-selfsigned.key \
    -out /etc/nginx/ssl/5cs045-selfsigned.crt \
    -subj "/CN=5cs045-student-server" \
    -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"
  chmod 600 /etc/nginx/ssl/5cs045-selfsigned.key
fi

echo "==> Deploying nginx"
cp "${REPO_ROOT}/templates/nginx-students.conf" /etc/nginx/sites-available/students
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/students /etc/nginx/sites-enabled/students

echo "==> Deploying SSH hardening"
cp "${REPO_ROOT}/templates/sshd-students.conf" /etc/ssh/sshd_config.d/50-students.conf
sshd -t

echo "==> Enabling fail2ban for SSH"
cat > /etc/fail2ban/jail.d/5cs045-sshd.conf <<-'EOF2'
	[sshd]
	enabled = true
	maxretry = 5
	findtime = 10m
	bantime = 1h
	EOF2

echo "==> Deploying sudo rule"
cp "${REPO_ROOT}/templates/sudoers-5cs045-provisioning" /etc/sudoers.d/5cs045-provisioning
chmod 440 /etc/sudoers.d/5cs045-provisioning
chown root:root /etc/sudoers.d/5cs045-provisioning
visudo -c

echo "==> Deploying public registration form"
mkdir -p /var/www/html/lib
cp "${REPO_ROOT}/web/register.php" "${REPO_ROOT}/web/register_handler.php" /var/www/html/
cp "${REPO_ROOT}"/web/lib/*.php /var/www/html/lib/
chown -R www-data:www-data /var/www/html

echo "==> Deploying SMTP config outside web root"
mkdir -p /etc/5cs045
if [[ ! -f /etc/5cs045/smtp_config.php ]]; then
  cp "${REPO_ROOT}/web/smtp_config.example.php" /etc/5cs045/smtp_config.php
  echo "    Created /etc/5cs045/smtp_config.php from the template - edit it with the real SMTP values."
else
  echo "    /etc/5cs045/smtp_config.php already exists - leaving it untouched."
fi
chown root:www-data /etc/5cs045/smtp_config.php
chmod 640 /etc/5cs045/smtp_config.php

echo "==> Creating registration state"
install -d -o www-data -g www-data -m 700 /var/lib/5cs045-ratelimit
install -d -o www-data -g www-data -m 700 /var/lib/5cs045-registration-locks
install -d -o www-data -g www-data -m 700 /var/lib/5cs045-registrations

echo "==> Creating logs"
touch /var/log/5cs045-registration.log /var/log/5cs045-provisioning.log
chown www-data:www-data /var/log/5cs045-registration.log
chmod 640 /var/log/5cs045-registration.log
chown root:root /var/log/5cs045-provisioning.log
chmod 600 /var/log/5cs045-provisioning.log

echo "==> Protecting phpMyAdmin with Basic Auth"
read -r -p "phpMyAdmin username [student2026]: " AUTH_USER
AUTH_USER="${AUTH_USER:-student2026}"
htpasswd -c "${ADMIN_AUTH_FILE}" "$AUTH_USER"
chown root:www-data "${ADMIN_AUTH_FILE}"
chmod 640 "${ADMIN_AUTH_FILE}"

nginx -t
systemctl enable --now nginx php8.3-fpm mariadb ssh fail2ban
systemctl reload nginx php8.3-fpm

echo ""
echo "============================================================"
echo " Base setup complete."
echo ""
echo " Public registration: https://<server>/register.php"
echo " phpMyAdmin: https://<server>/phpmyadmin/"
echo " SMTP config: /etc/5cs045/smtp_config.php"
echo " Admin scripts: /usr/local/sbin/5cs045/bin/"
echo ""
echo " Next: run mysql_secure_installation, put the real SMTP details in"
echo " /etc/5cs045/smtp_config.php, run test/smoke-test.sh, then try one registration."
echo "============================================================"
