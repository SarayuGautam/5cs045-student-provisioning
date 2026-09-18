#!/usr/bin/env bash
#
# uninstall.sh — cleanly revert everything 00-server-setup.sh and
# add-student.sh have done. Use this when you're test-driving the toolkit
# on a real, persistent VM and want to get back to a clean slate.
#
# By default this removes every provisioned student (backing each one up
# first, same as remove-student.sh does) and all 5CS045-specific config,
# but leaves nginx/PHP/MariaDB/git/composer/phpMyAdmin *installed* — on a
# VM that IT built specifically for this, reinstalling the base stack
# every time you want to retest isn't meaningfully "cleaner", just slower.
# Pass --purge-packages if you genuinely want those uninstalled too.
#
# The single cleanest revert, if it's available to you, is a VM snapshot
# taken before you ran setup — see README "Reverting / repeated testing".
# This script is for when that's not an option.
#
# Usage: sudo ./uninstall.sh [--purge-packages] [--yes]
#
set -uo pipefail  # not -e: keep going and report, don't stop on the first thing already absent
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

echo "This will remove every student account under /srv/students (backed up"
echo "first to /srv/students-archive/), and all 5CS045 nginx/ssh/sudoers config."
if [[ "$PURGE_PACKAGES" -eq 1 ]]; then
  echo "--purge-packages was passed: nginx, PHP, MariaDB, phpMyAdmin etc. will"
  echo "also be uninstalled, and /var/lib/mysql (ALL databases) will be deleted."
fi
if [[ "$ASSUME_YES" -eq 0 ]]; then
  read -r -p "Continue? [y/N] " REPLY
  [[ "$REPLY" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

echo "==> Removing all provisioned students"
if [[ -d /srv/students ]]; then
  for home in /srv/students/*/; do
    [[ -d "$home" ]] || continue
    user="$(basename "$home")"
    if id "$user" &>/dev/null && [[ -x "${DEPLOY_ROOT}/bin/remove-student.sh" ]]; then
      "${DEPLOY_ROOT}/bin/remove-student.sh" -u "$user" && echo "    removed $user"
    fi
  done
fi

echo "==> Removing nginx config, restoring the original default site"
rm -f /etc/nginx/sites-enabled/students
rm -f /etc/nginx/sites-available/students
if [[ -f /etc/nginx/sites-available/default && ! -e /etc/nginx/sites-enabled/default ]]; then
  ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
  echo "    restored the stock nginx default site"
fi
rm -rf /etc/nginx/ssl/5cs045-selfsigned.*
rm -f /etc/nginx/.htpasswd-register
nginx -t 2>&1 && (command -v systemctl &>/dev/null && systemctl is-system-running &>/dev/null && systemctl reload nginx || echo "    (reload nginx manually)")

echo "==> Removing sshd hardening"
rm -f /etc/ssh/sshd_config.d/50-students.conf
sshd -t 2>&1 && echo "    sshd config still valid after removal"

echo "==> Removing the sudoers rule"
rm -f /etc/sudoers.d/5cs045-provisioning
visudo -c 2>&1

echo "==> Removing deployed scripts and web files"
rm -rf "$DEPLOY_ROOT"
rm -f /var/www/html/register.php /var/www/html/register_handler.php

echo "==> Removing logs (if you want to keep them for reference, comment this out)"
rm -f /var/log/5cs045-registration.log /var/log/5cs045-provisioning.log

echo "==> Base directories left in place for inspection: /srv/students (should be"
echo "    empty now), /srv/students-archive (your backups). Delete by hand if you"
echo "    don't want them: rm -rf /srv/students /srv/students-archive"

if [[ "$PURGE_PACKAGES" -eq 1 ]]; then
  echo "==> Purging packages and ALL MariaDB data — this cannot be undone"
  export DEBIAN_FRONTEND=noninteractive
  systemctl stop nginx php8.3-fpm mariadb 2>/dev/null || true
  apt-get purge -y -qq nginx nginx-common php8.3-fpm php8.3-mysql php8.3-cli \
    php8.3-mbstring php8.3-xml php8.3-curl php8.3-zip mariadb-server \
    mariadb-server-10.11 phpmyadmin 2>&1 | tail -10
  apt-get autoremove -y -qq 2>&1 | tail -5
  rm -rf /var/lib/mysql /etc/mysql
  echo "    packages purged. git, composer, acl, sudo, openssh-server were left"
  echo "    installed — they're not 5CS045-specific and removing openssh-server"
  echo "    would lock you out of the VM over SSH."
fi

echo ""
echo "============================================================"
echo " Revert complete."
[[ "$PURGE_PACKAGES" -eq 0 ]] && echo " Base stack (nginx/PHP/MariaDB/phpMyAdmin) is still installed —"
[[ "$PURGE_PACKAGES" -eq 0 ]] && echo " re-run setup/00-server-setup.sh any time to reconfigure from here."
echo "============================================================"
