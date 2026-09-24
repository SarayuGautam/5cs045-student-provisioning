#!/usr/bin/env bash
# Installs (or updates) the admin panel: https://<server>:8443
# Called by 00-server-setup.sh and update-server.sh; safe to run again. It does not reload
# nginx or PHP itself, the caller does that once at the end.
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run this with sudo."; exit 1; }
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_ROOT="/usr/local/sbin/5cs045"
PANEL_ROOT="/var/www/5cs045-admin"
PANEL_USER="5cs045-admin"

# The panel's own user. It has no password, no shell and no rights except running admin-action.
if ! id "$PANEL_USER" &>/dev/null; then
  useradd --system --no-create-home --home-dir /var/lib/5cs045-admin --shell /usr/sbin/nologin \
    --comment "5CS045 admin panel" "$PANEL_USER"
fi
install -d -o "$PANEL_USER" -g "$PANEL_USER" -m 700 /var/lib/5cs045-admin /var/lib/5cs045-admin/sessions

# State kept by admin-action (root only)
install -d -o root -g root -m 700 /var/lib/5cs045-admin-auth /var/lib/5cs045-admin-jobs /var/lib/5cs045-quota-overrides
touch /var/log/5cs045-admin.log
chmod 600 /var/log/5cs045-admin.log

# The smoke test, so the panel can run it
install -d -o root -g root -m 755 "${DEPLOY_ROOT}/test"
install -o root -g root -m 750 "${REPO_ROOT}/test/smoke-test.sh" "${DEPLOY_ROOT}/test/smoke-test.sh"

# The panel's files. The PHP is readable only by the panel's user; the CSS and JS by nginx too.
rm -rf "${PANEL_ROOT}.new"
install -d -o root -g root -m 755 "${PANEL_ROOT}.new"
cp -r "${REPO_ROOT}/admin/app" "${REPO_ROOT}/admin/public" "${PANEL_ROOT}.new/"
chown -R root:"$PANEL_USER" "${PANEL_ROOT}.new"
find "${PANEL_ROOT}.new" -type d -exec chmod 750 {} +
find "${PANEL_ROOT}.new" -type f -exec chmod 640 {} +
chmod 755 "${PANEL_ROOT}.new" "${PANEL_ROOT}.new/public"
find "${PANEL_ROOT}.new/public/assets" -type d -exec chmod 755 {} +
find "${PANEL_ROOT}.new/public/assets" -type f -exec chmod 644 {} +
rm -rf "${PANEL_ROOT}.old"
[[ -d "$PANEL_ROOT" ]] && mv "$PANEL_ROOT" "${PANEL_ROOT}.old"
mv "${PANEL_ROOT}.new" "$PANEL_ROOT"
rm -rf "${PANEL_ROOT}.old"

install -o root -g root -m 644 "${REPO_ROOT}/templates/php-fpm-admin-pool.conf" /etc/php/8.3/fpm/pool.d/5cs045-admin.conf

install -o root -g root -m 440 "${REPO_ROOT}/templates/sudoers-5cs045-admin" /etc/sudoers.d/5cs045-admin
visudo -cf /etc/sudoers.d/5cs045-admin >/dev/null

# Who may open the panel. On the first install: the computer you are SSH'd in from.
install -d -o root -g root -m 755 /etc/5cs045
if [[ ! -f /etc/5cs045/admin-allow.conf ]]; then
  MY_IP="$(who -m 2>/dev/null | sed -n 's/.*(\([0-9a-fA-F.:]*\)).*/\1/p')"
  {
    echo "# Addresses allowed to open the admin panel. Written by the panel (Security page)"
    echo "# or bin/admin-allow.sh. The server itself is always allowed."
    echo "allow 127.0.0.1;"
    echo "allow ::1;"
    [[ -n "$MY_IP" ]] && echo "allow ${MY_IP};"
    echo "deny all;"
  } > /etc/5cs045/admin-allow.conf
  chmod 644 /etc/5cs045/admin-allow.conf
  if [[ -n "$MY_IP" ]]; then
    echo "    The admin panel can be opened from ${MY_IP} (this SSH connection)."
  else
    echo "    The admin panel cannot be opened from any computer yet. Allow yours with:"
    echo "    sudo ${DEPLOY_ROOT}/bin/admin-allow.sh add <your computer's IP>"
  fi
fi

cp "${REPO_ROOT}/templates/nginx-admin.conf" /etc/nginx/sites-available/5cs045-admin
ln -sf /etc/nginx/sites-available/5cs045-admin /etc/nginx/sites-enabled/5cs045-admin
