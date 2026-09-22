#!/usr/bin/env bash
# Removes one student: Linux account, home folder, database and PHP pool.
# The home folder is saved to /srv/students-archive first, unless you add --no-backup.
# The student's email is also forgotten, so they can register again.
#
# Usage: sudo remove-student.sh -u sarayu_gautam [--no-backup]
set -euo pipefail

PHP_VERSION="8.3"
ARCHIVE_DIR="/srv/students-archive"
REGISTRY_DIR="/var/lib/5cs045-registrations"
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

die() { echo "ERROR: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run this with sudo"
[[ "$USERNAME" =~ $USERNAME_RE ]] || die "give a valid username with -u"
id "$USERNAME" &>/dev/null || die "no such user: $USERNAME"

HOME_DIR="$(getent passwd "$USERNAME" | cut -d: -f6)"
[[ "$HOME_DIR" == /srv/students/* ]] || die "$USERNAME is not a student account (home is $HOME_DIR)"

if [[ "$DO_BACKUP" -eq 1 ]]; then
  mkdir -p "$ARCHIVE_DIR"
  ARCHIVE_FILE="${ARCHIVE_DIR}/${USERNAME}-$(date +%Y%m%d-%H%M%S).tar.gz"
  tar -czf "$ARCHIVE_FILE" -C "$(dirname "$HOME_DIR")" "$(basename "$HOME_DIR")"
  echo "Backup saved: ${ARCHIVE_FILE}"
fi

rm -f "/etc/php/${PHP_VERSION}/fpm/pool.d/${USERNAME}.conf" "/run/php/php${PHP_VERSION}-fpm-${USERNAME}.sock"
systemctl reload "php${PHP_VERSION}-fpm"

mysql -e "DROP DATABASE IF EXISTS \`${USERNAME}\`; DROP USER IF EXISTS '${USERNAME}'@'localhost'; FLUSH PRIVILEGES;"

pkill -u "$USERNAME" 2>/dev/null || true
sleep 1
userdel -r "$USERNAME" 2>&1 | grep -v "mail spool" || true

if [[ -d "$REGISTRY_DIR" ]]; then
  grep -l "\"username\":\"${USERNAME}\"" "$REGISTRY_DIR"/* 2>/dev/null | xargs -r rm -f
fi

rm -f "/var/lib/5cs045-credentials/${USERNAME}"

echo "${USERNAME} removed."
