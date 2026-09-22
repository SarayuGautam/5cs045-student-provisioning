#!/usr/bin/env bash
# Gives a student a new password (SSH, SCP and MySQL) and prints it once.
#
# Usage: sudo reset-student-password.sh -u sarayu_gautam
set -euo pipefail

USERNAME=""
while getopts "u:h" opt; do
  case "$opt" in
    u) USERNAME="$OPTARG" ;;
    h) echo "Usage: $0 -u <username>"; exit 0 ;;
    *) exit 1 ;;
  esac
done

[[ $EUID -eq 0 ]] || { echo "ERROR: run this with sudo" >&2; exit 1; }
[[ "$USERNAME" =~ ^[a-z][a-z0-9_]{2,31}$ ]] || { echo "ERROR: give a valid username with -u" >&2; exit 1; }
id "$USERNAME" >/dev/null 2>&1 || { echo "ERROR: no such user: $USERNAME" >&2; exit 1; }

HOME_DIR="/srv/students/${USERNAME}"
DB_NAME="${USERNAME}"

PASSWORD_RAW="$(openssl rand -base64 48 | tr -dc 'A-HJ-NP-Za-km-z2-9')"
PASSWORD="${PASSWORD_RAW:0:14}"
[[ ${#PASSWORD} -eq 14 ]] || { echo "ERROR: could not generate a password" >&2; exit 1; }

echo "${USERNAME}:${PASSWORD}" | chpasswd
mysql <<-SQL
	ALTER USER '${USERNAME}'@'localhost' IDENTIFIED BY '${PASSWORD}';
	FLUSH PRIVILEGES;
SQL

CRED_DIR="/var/lib/5cs045-credentials"
install -d -o root -g root -m 700 "$CRED_DIR"
(umask 077; cat > "${CRED_DIR}/${USERNAME}" <<-EOF
	# Server login for ${USERNAME}. Admin copy, students cannot read it.
	USERNAME=${USERNAME}
	PASSWORD=${PASSWORD}
	DB_HOST=localhost
	DB_NAME=${DB_NAME}
	EOF
)
chown root:root "${CRED_DIR}/${USERNAME}"
chmod 600 "${CRED_DIR}/${USERNAME}"

echo "Student:  ${USERNAME}"
echo "Password: ${PASSWORD}"
echo ""
echo "To email it to the student: sudo php /usr/local/sbin/5cs045/bin/resend-credentials.php <their email>"
