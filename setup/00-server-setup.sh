#!/usr/bin/env bash
#
# 00-server-setup.sh — one-time bootstrap for the 5CS045 student server
#
# Run ONCE, as root, on a fresh Ubuntu 24.04 LTS VM. After this, use
# bin/add-student.sh (directly, or via the web form) for every student.
#
# What this does:
#   1. Installs nginx, PHP 8.3-FPM, MariaDB, git, composer, phpMyAdmin, acl, fail2ban
#   2. Creates /srv/students with locked-down base permissions
#   3. Deploys the provisioning scripts to /usr/local/sbin/5cs045/
#   4. Generates a self-signed TLS cert and deploys nginx config, sshd
#      (password-based auth), the sudoers rule, and fail2ban's sshd jail
#   5. Deploys the email-based registration form (see web/smtp_config.php —
#      you MUST edit that with real SMTP relay details before it can send)
#   6. Sets an HTTP Basic Auth password for the registration form + phpMyAdmin
#   7. Enables and starts everything via systemd
#
# TLS uses a self-signed cert by default so HTTPS works immediately —
# swap for Let's Encrypt once you have a domain pointed at this VM (see
# README "HTTPS").
#
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run as root"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DEPLOY_ROOT="/usr/local/sbin/5cs045"

echo "==> Installing packages (nginx, PHP 8.3-FPM, MariaDB, git, composer, phpMyAdmin, acl, openssh-server)"
export DEBIAN_FRONTEND=noninteractive
# Tolerate a failing/unrelated third-party repo here (apt-get update exits
# non-zero if ANY configured repo fails, even one nothing below depends on).
# If a package genuinely can't be found, the apt-get install below will
# fail loudly and specifically, which is the failure worth stopping on.
apt-get update -qq || echo "    (apt-get update reported a problem with at least one repo — continuing; the install step below will fail clearly if a package we actually need is unreachable)"

# phpMyAdmin's installer prompts interactively by default (webserver choice,
# db config, admin password) - pre-seed debconf so this runs unattended.
# Task 1 in the assessment brief has students "creating a table in MySQL
# via phpMyAdmin" — it wasn't in the original stack list but the coursework
# needs it.
PMA_DB_PASS="$(openssl rand -hex 16)"
debconf-set-selections <<-EOF
	phpmyadmin phpmyadmin/dbconfig-install boolean true
	phpmyadmin phpmyadmin/app-password-confirm password ${PMA_DB_PASS}
	phpmyadmin phpmyadmin/mysql/admin-pass password
	phpmyadmin phpmyadmin/mysql/app-pass password ${PMA_DB_PASS}
	phpmyadmin phpmyadmin/reconfigure-webserver multiselect
EOF

apt-get install -y -qq \
  nginx \
  php8.3-fpm php8.3-mysql php8.3-cli php8.3-mbstring php8.3-xml php8.3-curl php8.3-zip \
  mariadb-server \
  git composer acl unzip \
  openssh-server \
  phpmyadmin \
  apache2-utils \
  fail2ban \
  sudo

echo "==> Creating /srv/students (base permissions: only root can list it)"
mkdir -p /srv/students
chown root:root /srv/students
chmod 711 /srv/students
mkdir -p /srv/students-archive
chmod 700 /srv/students-archive

echo "==> Deploying provisioning scripts to ${DEPLOY_ROOT}"
mkdir -p "${DEPLOY_ROOT}/bin" "${DEPLOY_ROOT}/templates"
cp "${REPO_ROOT}/bin/add-student.sh"    "${DEPLOY_ROOT}/bin/"
cp "${REPO_ROOT}/bin/remove-student.sh" "${DEPLOY_ROOT}/bin/"
cp "${REPO_ROOT}/bin/list-students.sh"  "${DEPLOY_ROOT}/bin/" 2>/dev/null || true
cp "${REPO_ROOT}/templates/php-fpm-pool.conf.template" "${DEPLOY_ROOT}/templates/"
chmod +x "${DEPLOY_ROOT}"/bin/*.sh
chown -R root:root "${DEPLOY_ROOT}"
chmod -R go-w "${DEPLOY_ROOT}"
echo "    (bin/ and templates/ must stay siblings — add-student.sh finds its"
echo "    template relative to its own path)"

echo "==> Generating a self-signed TLS cert (so HTTPS works today - swap for Let's Encrypt when you have a domain, see README)"
mkdir -p /etc/nginx/ssl
if [[ ! -f /etc/nginx/ssl/5cs045-selfsigned.crt ]]; then
  openssl req -x509 -nodes -days 825 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/5cs045-selfsigned.key \
    -out /etc/nginx/ssl/5cs045-selfsigned.crt \
    -subj "/CN=5cs045-student-server" \
    -addext "subjectAltName=DNS:localhost,IP:127.0.0.1"
  chmod 600 /etc/nginx/ssl/5cs045-selfsigned.key
fi

echo "==> Deploying nginx config"
cp "${REPO_ROOT}/templates/nginx-students.conf" /etc/nginx/sites-available/students
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/students /etc/nginx/sites-enabled/students

echo "==> Deploying sshd hardening (password-based auth, no chroot — see README for why)"
cp "${REPO_ROOT}/templates/sshd-students.conf" /etc/ssh/sshd_config.d/50-students.conf
sshd -t

echo "==> Enabling fail2ban for sshd (compensating control for password-based auth)"
cat > /etc/fail2ban/jail.d/5cs045-sshd.conf <<-'EOF'
	[sshd]
	enabled = true
	maxretry = 5
	findtime = 10m
	bantime = 1h
	EOF

echo "==> Installing the sudoers rule (www-data may run ONLY add-student.sh, as root)"
cp "${REPO_ROOT}/templates/sudoers-5cs045-provisioning" /etc/sudoers.d/5cs045-provisioning
chmod 440 /etc/sudoers.d/5cs045-provisioning
chown root:root /etc/sudoers.d/5cs045-provisioning
visudo -c

echo "==> Deploying the registration web form"
mkdir -p /var/www/html/lib
cp "${REPO_ROOT}/web/register.php" "${REPO_ROOT}/web/register_handler.php" /var/www/html/
cp "${REPO_ROOT}/web/lib/smtp_mailer.php" /var/www/html/lib/
chown -R www-data:www-data /var/www/html

echo "==> Deploying smtp_config.php OUTSIDE the web root (holds the SMTP password —"
echo "    keeping it physically outside /var/www/html means no nginx config"
echo "    mistake can ever expose it, on top of the explicit deny rule)"
mkdir -p /etc/5cs045
cp "${REPO_ROOT}/web/smtp_config.php" /etc/5cs045/smtp_config.php
chown root:www-data /etc/5cs045/smtp_config.php
chmod 640 /etc/5cs045/smtp_config.php
echo "    !!! Edit /etc/5cs045/smtp_config.php with your real SMTP relay details before going live !!!"

echo "==> Rate-limit state directory for the registration form"
mkdir -p /var/lib/5cs045-ratelimit
chown www-data:www-data /var/lib/5cs045-ratelimit
chmod 700 /var/lib/5cs045-ratelimit

echo "==> Registration log (must be writable by www-data, not world-readable — it logs IPs and usernames)"
touch /var/log/5cs045-registration.log
chown www-data:www-data /var/log/5cs045-registration.log
chmod 640 /var/log/5cs045-registration.log
touch /var/log/5cs045-provisioning.log
chmod 600 /var/log/5cs045-provisioning.log

echo ""
echo "==> Set the shared enrolment password for the registration form + phpMyAdmin"
echo "    (this is deliberately simple, not full SSO — see README 'About the registration form')"
read -r -p "Basic-auth username to give students [student2026]: " AUTH_USER
AUTH_USER="${AUTH_USER:-student2026}"
htpasswd -c /etc/nginx/.htpasswd-register "$AUTH_USER"

nginx -t
systemctl enable --now nginx php8.3-fpm mariadb ssh fail2ban
systemctl reload nginx php8.3-fpm

echo ""
echo "============================================================"
echo " Base setup complete. Still to do manually:"
echo "  1. mysql_secure_installation  (sets MariaDB root auth properly)"
echo "  2. Edit /var/www/html/smtp_config.php with your real SMTP relay"
echo "     details and confirm allowed_email_domain — registration emails"
echo "     will fail until this is done (see README 'Email delivery')."
echo "  3. If you have a domain pointed at this VM, swap the self-signed"
echo "     cert for a real one: certbot --nginx (see README 'HTTPS')."
echo "  4. Provision students by pointing them at https://<server>/register.php"
echo "     — or manually: bin/add-student.sh -u <id> [-n \"Full Name\"]"
echo "  5. Run test/smoke-test.sh to verify isolation on THIS box"
echo "     before trusting it with real student data."
echo "============================================================"
