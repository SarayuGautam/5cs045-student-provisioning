#!/usr/bin/env bash
#
# add-student.sh — provision one student on the 5CS045 full-stack server
#
# Creates:
#   - a Linux user, home at $STUDENT_ROOT/<username>
#   - three subfolders: workshops/ exams/ assessments/ (each independently web-servable)
#   - default ACLs so anything the student uploads is auto-readable by nginx (www-data)
#     with no manual chmod required
#   - a randomly generated password, used for BOTH SSH/SCP login and MySQL
#     (matches your old server's model — see Server_Access_Guide)
#   - a MariaDB database + user scoped to that student only
#   - a PHP-FPM pool that runs the student's PHP code AS that student (not as www-data),
#     with open_basedir as a second layer of isolation
#
# Safe to re-run for the same username (idempotent): re-running GENERATES
# A NEW PASSWORD and updates both system + MySQL to match — this is what
# powers the registration form's implicit "forgot my password" behaviour
# (resubmitting the form just re-provisions with fresh credentials).
#
# Usage:
#   sudo ./add-student.sh -u jbloggs21 [-n "J Bloggs"] [-k "ssh-ed25519 AAAA..."]
#
# -k is optional — students authenticate with the generated password by
# default (see README "Password-based auth, and why"). Pass -k if you want
# to ALSO install an SSH key for a specific account (e.g. a TA who prefers
# key-based login); it works alongside the password, not instead of it.
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration (adjust to match the real VM if paths differ)
# ---------------------------------------------------------------------------
STUDENT_ROOT="/srv/students"
PHP_VERSION="8.3"
FPM_POOL_DIR="/etc/php/${PHP_VERSION}/fpm/pool.d"
FPM_SOCK_DIR="/run/php"
NGINX_WEB_GROUP="www-data"
LOG_FILE="/var/log/5cs045-provisioning.log"
POOL_TEMPLATE="$(dirname "$0")/../templates/php-fpm-pool.conf.template"
AREAS=(workshops exams assessments)
USERNAME_RE='^[a-z][a-z0-9_]{2,31}$'

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
FULLNAME=""
PUBKEY=""
USERNAME=""
while getopts "u:k:n:h" opt; do
  case "$opt" in
    u) USERNAME="$OPTARG" ;;
    k) PUBKEY="$OPTARG" ;;
    n) FULLNAME="$OPTARG" ;;
    h) echo "Usage: $0 -u <username> [-n \"Full Name\"] [-k <ssh-public-key>]"; exit 0 ;;
    *) echo "Unknown option" >&2; exit 1 ;;
  esac
done

log() { echo "[$(date -Is)] $*" | tee -a "$LOG_FILE" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "must be run as root (use sudo)"
[[ -n "$USERNAME" ]] || die "-u <username> is required"
[[ "$USERNAME" =~ $USERNAME_RE ]] || die "username '$USERNAME' invalid — must match $USERNAME_RE (lowercase letters/digits/underscore, 3-32 chars, start with a letter). This becomes a Linux user, a MySQL user and a URL path segment, so it must stay in this safe character set."
if [[ -n "$PUBKEY" ]]; then
  [[ "$PUBKEY" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-) ]] || die "-k does not look like a valid SSH public key (expected it to start with ssh-ed25519/ssh-rsa/ecdsa-sha2-...)"
fi

HOME_DIR="${STUDENT_ROOT}/${USERNAME}"

log "=== provisioning ${USERNAME} ==="

# ---------------------------------------------------------------------------
# 1. Linux user + home directory
# ---------------------------------------------------------------------------
if id "$USERNAME" &>/dev/null; then
  log "user ${USERNAME} already exists — skipping useradd, will refresh config below"
else
  useradd \
    --create-home \
    --home-dir "$HOME_DIR" \
    --shell /bin/bash \
    --comment "${FULLNAME:-5CS045 student}" \
    "$USERNAME"
  log "created linux user ${USERNAME} (uid $(id -u "$USERNAME")), home ${HOME_DIR}"
fi

# One password, generated fresh on every run, used for both SSH/SCP login
# and MySQL (see README "Password-based auth, and why"). Re-running this
# script for an existing student is therefore also how you reset a lost
# password — the registration form's resubmit-to-reset behaviour relies on
# this. Character set avoids visually ambiguous characters (0/O, 1/l/I)
# since students read this off an email, often on a phone.
#
# NOTE: generate the full string first, THEN slice it with bash's own
# ${var:0:N} — piping into `head -c` here has the exact same SIGPIPE-under-
# pipefail risk as the DB_PASS bug below (tr's filtered output can still be
# longer than N when head closes the pipe early). Slicing in-memory avoids
# a pipe at the truncation step entirely.
PASSWORD_RAW="$(openssl rand -base64 48 | tr -dc 'A-HJ-NP-Za-km-z2-9')"
PASSWORD="${PASSWORD_RAW:0:14}"
echo "${USERNAME}:${PASSWORD}" | chpasswd
log "set login password for ${USERNAME}"

# Home directory itself: owner-only. www-data gets a traverse-only ACL further
# down so it can reach the three subfolders without being able to list or read
# anything sitting loose in the home directory root (ssh keys, db credentials).
chmod 750 "$HOME_DIR"

# ---------------------------------------------------------------------------
# 2. The three work areas + automatic read access for nginx
# ---------------------------------------------------------------------------
for area in "${AREAS[@]}"; do
  dir="${HOME_DIR}/${area}"
  mkdir -p "$dir"
  chown "${USERNAME}:${USERNAME}" "$dir"
  chmod 750 "$dir"

  # This is the mechanism that satisfies "content they upload will automatically
  # have read access, they do not have to manually give access":
  #   - a *default* ACL is inherited by every new file/dir created underneath,
  #     recursively, regardless of the student's umask
  #   - a normal (non-default) ACL is also applied now, so anything already
  #     there (e.g. on a re-run) is fixed up immediately
  # www-data gets read+execute (rx) — enough to serve files and traverse
  # directories, never write.
  setfacl -R  -m "g:${NGINX_WEB_GROUP}:rx"   "$dir"
  setfacl -R  -m "d:g:${NGINX_WEB_GROUP}:rx" "$dir"
done

# Traverse-only on the home dir so www-data can walk *through* it into the
# three area folders above, without being able to `ls` the home directory
# itself or read anything outside those three folders (ssh keys, db creds).
setfacl -m "g:${NGINX_WEB_GROUP}:x" "$HOME_DIR"

# ---------------------------------------------------------------------------
# 3. SSH key (optional, additive) — password (above) is the primary auth
# ---------------------------------------------------------------------------
SSH_DIR="${HOME_DIR}/.ssh"
mkdir -p "$SSH_DIR"
chown "${USERNAME}:${USERNAME}" "$SSH_DIR"
chmod 700 "$SSH_DIR"
touch "${SSH_DIR}/authorized_keys"
chmod 600 "${SSH_DIR}/authorized_keys"
chown "${USERNAME}:${USERNAME}" "${SSH_DIR}/authorized_keys"
if [[ -n "$PUBKEY" ]]; then
  echo "$PUBKEY" > "${SSH_DIR}/authorized_keys"
  chmod 600 "${SSH_DIR}/authorized_keys"
  log "installed SSH key for ${USERNAME} (in addition to password login)"
fi

# ---------------------------------------------------------------------------
# 4. Private, non-web-accessible session directory (used by the FPM pool below)
# ---------------------------------------------------------------------------
SESS_DIR="${HOME_DIR}/.sessions"
mkdir -p "$SESS_DIR"
chown "${USERNAME}:${USERNAME}" "$SESS_DIR"
chmod 700 "$SESS_DIR"

# ---------------------------------------------------------------------------
# 5. MariaDB database + user, scoped to this student only — same PASSWORD
#    as the system login (set in step 1), kept in sync on every run
# ---------------------------------------------------------------------------
DB_NAME="student_${USERNAME}"
CRED_FILE="${HOME_DIR}/credentials.txt"

mysql <<-SQL
	CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
	CREATE USER IF NOT EXISTS '${USERNAME}'@'localhost' IDENTIFIED BY '${PASSWORD}';
	ALTER USER '${USERNAME}'@'localhost' IDENTIFIED BY '${PASSWORD}';
	GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${USERNAME}'@'localhost';
	FLUSH PRIVILEGES;
SQL
log "synced database ${DB_NAME} and MySQL user ${USERNAME}@localhost to the current password"

cat > "$CRED_FILE" <<-EOF
	# 5CS045 server credentials for ${USERNAME} — keep this private.
	# This password works for BOTH SSH/SCP login and MySQL.
	USERNAME=${USERNAME}
	PASSWORD=${PASSWORD}
	DB_HOST=localhost
	DB_NAME=${DB_NAME}
	EOF
chown "${USERNAME}:${USERNAME}" "$CRED_FILE"
chmod 600 "$CRED_FILE"

# ---------------------------------------------------------------------------
# 6. PHP-FPM pool — runs this student's PHP code AS this student
# ---------------------------------------------------------------------------
[[ -f "$POOL_TEMPLATE" ]] || die "pool template not found at $POOL_TEMPLATE"
POOL_FILE="${FPM_POOL_DIR}/${USERNAME}.conf"
sed \
  -e "s#{{USERNAME}}#${USERNAME}#g" \
  -e "s#{{HOME_DIR}}#${HOME_DIR}#g" \
  -e "s#{{FPM_SOCK_DIR}}#${FPM_SOCK_DIR}#g" \
  -e "s#{{WEB_GROUP}}#${NGINX_WEB_GROUP}#g" \
  "$POOL_TEMPLATE" > "$POOL_FILE"
log "wrote FPM pool ${POOL_FILE}"

php-fpm${PHP_VERSION} -t 2>&1 | tee -a "$LOG_FILE" || die "generated FPM pool config is invalid — see $LOG_FILE"

if command -v systemctl &>/dev/null && systemctl is-system-running &>/dev/null; then
  systemctl reload "php${PHP_VERSION}-fpm"
  log "reloaded php${PHP_VERSION}-fpm"
else
  log "NOTE: systemd not available in this shell — reload php${PHP_VERSION}-fpm manually"
fi

log "=== ${USERNAME} provisioned OK ==="
echo ""
echo "Student:   ${USERNAME}"
echo "Home:      ${HOME_DIR}"
echo "Password:  ${PASSWORD}   (same password for SSH/SCP and MySQL)"
echo "Workshops: https://<server>/~${USERNAME}/workshops/"
echo "Exams:     https://<server>/~${USERNAME}/exams/"
echo "Assessments: https://<server>/~${USERNAME}/assessments/"
echo "Database:  ${DB_NAME}"
echo "SSH:       ssh ${USERNAME}@<server>"
echo "Credentials file (for register_handler.php or manual lookup): ${CRED_FILE}"
