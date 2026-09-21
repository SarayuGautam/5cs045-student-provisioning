#!/usr/bin/env bash
#
# remove-student.sh — cleanly deprovision one student
#
# Removes the Linux user + home directory, the MariaDB database + user, and
# the PHP-FPM pool. By default it backs up the home directory to
# /srv/students-archive/<username>-<date>.tar.gz first (handy at end of
# term, or if a student is removed by mistake) — pass --no-backup to skip.
#
# Usage:
#   sudo ./remove-student.sh -u jbloggs21 [--no-backup]
#
set -euo pipefail

PHP_VERSION="8.3"
FPM_POOL_DIR="/etc/php/${PHP_VERSION}/fpm/pool.d"
FPM_SOCK_DIR="/run/php"
ARCHIVE_DIR="/srv/students-archive"
USERNAME_RE='^[a-z][a-z0-9_]{2,31}$'

USERNAME=""
DO_BACKUP=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    -u) USERNAME="$2"; shift 2 ;;
    --no-backup) DO_BACKUP=0; shift ;;
    -h) echo "Usage: $0 -u <username> [--no-backup]"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

log() { echo "[$(date -Is)] $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "must be run as root (use sudo)"
[[ -n "$USERNAME" ]] || die "-u <username> is required"
[[ "$USERNAME" =~ $USERNAME_RE ]] || die "username '$USERNAME' doesn't look valid"
id "$USERNAME" &>/dev/null || die "no such user: $USERNAME"

HOME_DIR=$(getent passwd "$USERNAME" | cut -d: -f6)
[[ "$HOME_DIR" == /srv/students/* ]] || die "refusing to act — $USERNAME's home ($HOME_DIR) isn't under /srv/students/. This looks like it might not be a student account created by add-student.sh."

log "=== removing ${USERNAME} (home: ${HOME_DIR}) ==="

if [[ "$DO_BACKUP" -eq 1 && -d "$HOME_DIR" ]]; then
  mkdir -p "$ARCHIVE_DIR"
  ARCHIVE_FILE="${ARCHIVE_DIR}/${USERNAME}-$(date +%Y%m%d-%H%M%S).tar.gz"
  tar -czf "$ARCHIVE_FILE" -C "$(dirname "$HOME_DIR")" "$(basename "$HOME_DIR")"
  log "backed up home directory to ${ARCHIVE_FILE}"
fi

# FPM pool first, so no in-flight request is mid-way through using the
# account while the rest of the teardown happens
POOL_FILE="${FPM_POOL_DIR}/${USERNAME}.conf"
if [[ -f "$POOL_FILE" ]]; then
  rm -f "$POOL_FILE"
  if command -v systemctl &>/dev/null && systemctl is-system-running &>/dev/null; then
    systemctl reload "php${PHP_VERSION}-fpm"
  else
    log "NOTE: systemd not available in this shell — reload php${PHP_VERSION}-fpm manually"
  fi
  log "removed FPM pool"
fi
rm -f "${FPM_SOCK_DIR}/php${PHP_VERSION}-fpm-${USERNAME}.sock"

# Database
DB_NAME="student_${USERNAME}"
mysql -e "DROP DATABASE IF EXISTS \`${DB_NAME}\`; DROP USER IF EXISTS '${USERNAME}'@'localhost'; FLUSH PRIVILEGES;"
log "dropped database ${DB_NAME} and MySQL user ${USERNAME}@localhost"

# Linux account + home directory. Kill any lingering processes/sessions first
# (userdel refuses if the user is logged in or has running processes).
pkill -u "$USERNAME" 2>/dev/null || true
sleep 1
userdel -r "$USERNAME" 2>&1 | grep -v "mail spool" || true
log "removed linux user and home directory"

log "=== ${USERNAME} fully removed ==="
