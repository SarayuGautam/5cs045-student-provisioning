#!/usr/bin/env bash
# Creates one student account: Linux user, three web folders, database and PHP pool.
#
# Usage: sudo add-student.sh -u sarayu_gautam [-n "Full Name"] [-e email]
#
# -e records the email so the registration page will not create a second account for it.
# The script prints the password once. It is also saved in the student's credentials.txt.
# The same password works for SSH, SCP and MySQL.
set -euo pipefail

STUDENT_ROOT="/srv/students"
PHP_VERSION="8.3"
FPM_POOL_DIR="/etc/php/${PHP_VERSION}/fpm/pool.d"
FPM_SOCK_DIR="/run/php"
WEB_GROUP="www-data"
REGISTRY_DIR="/var/lib/5cs045-registrations"
LOG_FILE="/var/log/5cs045-provisioning.log"
POOL_TEMPLATE="$(dirname "$0")/../templates/php-fpm-pool.conf.template"
USERNAME_RE='^[a-z][a-z0-9_]{2,31}$'

USERNAME=""
FULLNAME=""
EMAIL=""
while getopts "u:n:e:h" opt; do
  case "$opt" in
    u) USERNAME="$OPTARG" ;;
    n) FULLNAME="$OPTARG" ;;
    e) EMAIL="$OPTARG" ;;
    h) echo "Usage: $0 -u <username> [-n \"Full Name\"] [-e email]"; exit 0 ;;
    *) exit 1 ;;
  esac
done

log() { echo "[$(date -Is)] $*" | tee -a "$LOG_FILE" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "run this with sudo"
[[ -n "$USERNAME" ]] || die "-u <username> is required"
[[ "$USERNAME" =~ $USERNAME_RE ]] || die "username must be 3-32 characters: lowercase letters, numbers and underscores, starting with a letter"
case "$USERNAME" in
  mysql|sys|test|root|admin|phpmyadmin|information_schema|performance_schema)
    die "'$USERNAME' is reserved, choose another username" ;;
esac
[[ -f "$POOL_TEMPLATE" ]] || die "missing $POOL_TEMPLATE"

HOME_DIR="${STUDENT_ROOT}/${USERNAME}"
DB_NAME="${USERNAME}"
CRED_FILE="${HOME_DIR}/credentials.txt"

log "creating ${USERNAME}"

# Linux user
if ! id "$USERNAME" &>/dev/null; then
  useradd --create-home --home-dir "$HOME_DIR" --shell /bin/bash --comment "${FULLNAME:-5CS045 student}" "$USERNAME"
fi

# 14 characters, without look-alike characters (0/O, 1/l/I)
PASSWORD_RAW="$(openssl rand -base64 48 | tr -dc 'A-HJ-NP-Za-km-z2-9')"
PASSWORD="${PASSWORD_RAW:0:14}"
[[ ${#PASSWORD} -eq 14 ]] || die "could not generate a password"
echo "${USERNAME}:${PASSWORD}" | chpasswd

# The home folder is private. The web server may only pass through it.
chmod 750 "$HOME_DIR"
setfacl -m "g:${WEB_GROUP}:x" "$HOME_DIR"

# The three web folders. The ACLs let the web server read anything the student
# uploads, without the student running chmod.
for area in workshops exams assessments; do
  dir="${HOME_DIR}/${area}"
  mkdir -p "$dir"
  chown "${USERNAME}:${USERNAME}" "$dir"
  chmod 750 "$dir"
  setfacl -R -m "g:${WEB_GROUP}:rx" "$dir"
  setfacl -R -m "d:g:${WEB_GROUP}:rx" "$dir"
done

# Private folders (not served by the web)
for private in .ssh .sessions; do
  mkdir -p "${HOME_DIR}/${private}"
  chown "${USERNAME}:${USERNAME}" "${HOME_DIR}/${private}"
  chmod 700 "${HOME_DIR}/${private}"
done

# Database, named like the username, with the same password.
# In GRANT an underscore means "any character", so it is escaped to keep the student inside their own database.
DB_PATTERN="${DB_NAME//_/\\_}"
mysql <<-SQL
	CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
	CREATE USER IF NOT EXISTS '${USERNAME}'@'localhost' IDENTIFIED BY '${PASSWORD}';
	ALTER USER '${USERNAME}'@'localhost' IDENTIFIED BY '${PASSWORD}';
	GRANT ALL PRIVILEGES ON \`${DB_PATTERN}\`.* TO '${USERNAME}'@'localhost';
	FLUSH PRIVILEGES;
SQL

cat > "$CRED_FILE" <<-EOF
	# Server login for ${USERNAME}. Keep this private.
	USERNAME=${USERNAME}
	PASSWORD=${PASSWORD}
	DB_HOST=localhost
	DB_NAME=${DB_NAME}
	EOF
chown "${USERNAME}:${USERNAME}" "$CRED_FILE"
chmod 600 "$CRED_FILE"

# PHP pool: the student's PHP runs as the student
sed \
  -e "s#{{USERNAME}}#${USERNAME}#g" \
  -e "s#{{HOME_DIR}}#${HOME_DIR}#g" \
  -e "s#{{FPM_SOCK_DIR}}#${FPM_SOCK_DIR}#g" \
  -e "s#{{WEB_GROUP}}#${WEB_GROUP}#g" \
  "$POOL_TEMPLATE" > "${FPM_POOL_DIR}/${USERNAME}.conf"
php-fpm${PHP_VERSION} -t >/dev/null 2>&1 || die "the PHP pool config is invalid, see: php-fpm${PHP_VERSION} -t"
systemctl reload "php${PHP_VERSION}-fpm"

# Remember the email so the registration page rejects it
if [[ -n "$EMAIL" ]]; then
  install -d -o www-data -g www-data -m 700 "$REGISTRY_DIR"
  KEY="$(printf '%s' "${EMAIL,,}" | sha256sum | cut -d' ' -f1)"
  printf '{"username":"%s","registered_at":"%s","status":"complete"}' "$USERNAME" "$(date -Is)" > "${REGISTRY_DIR}/${KEY}"
  chown www-data:www-data "${REGISTRY_DIR}/${KEY}"
  chmod 600 "${REGISTRY_DIR}/${KEY}"
fi

SERVER_URL="$(php -r '$c = @include "/etc/5cs045/smtp_config.php"; echo rtrim((string) ($c["server_url"] ?? ""), "/");' 2>/dev/null || true)"
SERVER_URL="${SERVER_URL:-https://<server>}"

log "${USERNAME} is ready"
echo ""
echo "Student:      ${USERNAME}"
echo "Password:     ${PASSWORD}   (same for SSH, SCP and MySQL)"
echo "Database:     ${DB_NAME}"
echo "Workshops:    ${SERVER_URL}/~${USERNAME}/workshops/   (one folder per week)"
echo "Assessments:  ${SERVER_URL}/~${USERNAME}/assessments/"
echo "Exams:        ${SERVER_URL}/~${USERNAME}/exams/"
