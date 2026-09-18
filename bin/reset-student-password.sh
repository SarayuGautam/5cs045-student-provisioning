#!/usr/bin/env bash
set -euo pipefail

STUDENT_ROOT="/srv/students"
PHP_VERSION="8.3"
LOG_FILE="/var/log/5cs045-provisioning.log"
USERNAME_RE='^[a-z][a-z0-9_]{2,31}$'

usage() {
  echo "Usage: $0 -u <username>"
}
log() { echo "[$(date -Is)] $*" | tee -a "$LOG_FILE" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

USERNAME=""
while getopts "u:h" opt; do
  case "$opt" in
    u) USERNAME="$OPTARG" ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

[[ $EUID -eq 0 ]] || die "must be run as root"
[[ -n "$USERNAME" ]] || die "-u <username> is required"
[[ "$USERNAME" =~ $USERNAME_RE ]] || die "invalid username"
id "$USERNAME" >/dev/null 2>&1 || die "student '$USERNAME' does not exist"

HOME_DIR="${STUDENT_ROOT}/${USERNAME}"
CRED_FILE="${HOME_DIR}/credentials.txt"
DB_NAME="student_${USERNAME}"

PASSWORD_RAW="$(openssl rand -base64 48 | tr -dc 'A-HJ-NP-Za-km-z2-9')"
PASSWORD="${PASSWORD_RAW:0:14}"
[[ ${#PASSWORD} -eq 14 ]] || die "could not generate a password"

echo "${USERNAME}:${PASSWORD}" | chpasswd
mysql <<-SQL
ALTER USER '${USERNAME}'@'localhost' IDENTIFIED BY '${PASSWORD}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${USERNAME}'@'localhost';
FLUSH PRIVILEGES;
SQL

cat > "$CRED_FILE" <<-EOF2
# 5CS045 server credentials for ${USERNAME} - keep this private.
USERNAME=${USERNAME}
PASSWORD=${PASSWORD}
DB_HOST=localhost
DB_NAME=${DB_NAME}
EOF2
chown "${USERNAME}:${USERNAME}" "$CRED_FILE"
chmod 600 "$CRED_FILE"

log "password reset for ${USERNAME}"
echo ""
echo "Student:  ${USERNAME}"
echo "Password: ${PASSWORD}"
echo "Database: ${DB_NAME}"
echo ""
echo "Send this password to the student using the approved communication method."
