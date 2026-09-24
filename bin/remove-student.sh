#!/usr/bin/env bash
# Removes one student: Linux account, home folder, database and PHP pool.
# This permanently deletes the student's files - there is no backup.
# The student's email is also forgotten, so they can register again.
#
# Usage: sudo remove-student.sh -u sarayu_gautam [--no-reload]
#
# --no-reload skips reloading PHP and systemd. remove-all-students.sh uses it and reloads
# once at the end, instead of once per student.
set -euo pipefail

PHP_VERSION="8.3"
REGISTRY_DIR="/var/lib/5cs045-registrations"
USERNAME_RE='^[a-z][a-z0-9_]{2,31}$'

USERNAME=""
RELOAD=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    -u) USERNAME="$2"; shift 2 ;;
    --no-reload) RELOAD=0; shift ;;
    -h) echo "Usage: $0 -u <username> [--no-reload]"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

die() { echo "ERROR: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run this with sudo"
[[ "$USERNAME" =~ $USERNAME_RE ]] || die "give a valid username with -u"
id "$USERNAME" &>/dev/null || die "no such user: $USERNAME"

HOME_DIR="$(getent passwd "$USERNAME" | cut -d: -f6)"
[[ "$HOME_DIR" == /srv/students/* ]] || die "$USERNAME is not a student account (home is $HOME_DIR)"
STUDENT_UID="$(id -u "$USERNAME")"

rm -f "/etc/php/${PHP_VERSION}/fpm/pool.d/${USERNAME}.conf" "/run/php/php${PHP_VERSION}-fpm-${USERNAME}.sock"
if [[ "$RELOAD" -eq 1 ]]; then
  systemctl reload "php${PHP_VERSION}-fpm"
fi

mysql -e "DROP DATABASE IF EXISTS \`${USERNAME}\`; DROP USER IF EXISTS '${USERNAME}'@'localhost'; FLUSH PRIVILEGES;"

pkill -u "$USERNAME" 2>/dev/null || true
sleep 1
userdel -r "$USERNAME" 2>&1 | grep -v "mail spool" || true

if [[ -d "$REGISTRY_DIR" ]]; then
  # grep finds nothing for accounts made without an email (exit 1). With pipefail that used to
  # stop the script here, after the account was gone but before the cleanup below.
  { grep -l "\"username\":\"${USERNAME}\"" "$REGISTRY_DIR"/* 2>/dev/null || true; } | xargs -r rm -f
fi

rm -f "/var/lib/5cs045-credentials/${USERNAME}" "/var/lib/5cs045-db-over/${USERNAME}" "/var/lib/5cs045-quota-overrides/${USERNAME}"

# The SSH limits and user-manager mask written by apply-student-limits.sh (the disk quota goes with the account)
rm -f "/etc/systemd/system/user-${STUDENT_UID}.slice.d/50-5cs045-limits.conf"
rmdir "/etc/systemd/system/user-${STUDENT_UID}.slice.d" 2>/dev/null || true
if [[ "$(readlink "/etc/systemd/system/user@${STUDENT_UID}.service" 2>/dev/null)" == /dev/null ]]; then
  rm -f "/etc/systemd/system/user@${STUDENT_UID}.service"
fi
if [[ "$RELOAD" -eq 1 ]] && [[ -d /run/systemd/system ]]; then
  systemctl daemon-reload
fi

echo "${USERNAME} removed."
