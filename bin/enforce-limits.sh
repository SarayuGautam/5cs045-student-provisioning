#!/usr/bin/env bash
# Runs every 15 minutes from /etc/cron.d/5cs045 (also safe to run by hand). It does three things:
#   1. Stops a student's PHP error log from filling their disk quota.
#   2. Caps each student's database at 100 MB. MariaDB's files belong to the mysql user,
#      so the disk quota does not see them.
#   3. Emails the admin (admin_email in /etc/5cs045/smtp_config.php) when the disk is 80% full,
#      at most once a day.
# Everything it does is written to /var/log/5cs045-provisioning.log.
#
# Usage: sudo enforce-limits.sh
set -uo pipefail   # no -e: a problem with one student must not stop the checks for the rest
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

STUDENT_ROOT="/srv/students"
DEPLOY_ROOT="/usr/local/sbin/5cs045"
LOG_FILE="/var/log/5cs045-provisioning.log"
ERROR_LOG_MAX_KB=5120       # a PHP error log over 5 MB ...
ERROR_LOG_KEEP=1M           # ... is cut down to its last 1 MB
DB_MAX_MB=100
DB_OVER_DIR="/var/lib/5cs045-db-over"
DISK_ALERT_PERCENT=80
ALERT_STATE="/var/lib/5cs045-disk-alert-sent"
ALERT_EVERY_SECONDS=86400
USERNAME_RE='^[a-z][a-z0-9_]{2,31}$'

log() { echo "[$(date -Is)] enforce-limits: $*" >> "$LOG_FILE"; }
[[ $EUID -eq 0 ]] || { echo "ERROR: run this with sudo" >&2; exit 1; }

# Only one run at a time
exec 9>/run/5cs045-enforce-limits.lock
flock -n 9 || exit 0

STUDENTS=()
for home in "$STUDENT_ROOT"/*/; do
  [[ -d "$home" ]] || continue
  user="$(basename "$home")"
  [[ "$user" =~ $USERNAME_RE ]] && id "$user" &>/dev/null && STUDENTS+=("$user")
done

# 1. PHP error logs.
# The trim runs as the student, never as root: the student owns the folder and could replace
# the log with a link to a system file. As the student, that link would only reach files the
# student can already change.
while IFS= read -r -d '' logfile; do
  user="$(basename "$(dirname "$(dirname "$logfile")")")"
  [[ "$user" =~ $USERNAME_RE ]] && id "$user" &>/dev/null || continue
  # If the student is at their quota there is no room for the copy, so empty the log instead.
  if runuser -u "$user" -- sh -c 'tail -c "$2" "$1" > "$1.tmp" && mv -f "$1.tmp" "$1" || { rm -f "$1.tmp"; : > "$1"; }' \
       sh "$logfile" "$ERROR_LOG_KEEP" 2>/dev/null; then
    log "${user}: PHP error log was over $((ERROR_LOG_MAX_KB / 1024)) MB, kept the last ${ERROR_LOG_KEEP}"
  fi
done < <(find "$STUDENT_ROOT" -mindepth 3 -maxdepth 3 -path '*/.sessions/php-error.log' -type f -size +"${ERROR_LOG_MAX_KB}"k -print0 2>/dev/null)

# 2. Database size.
# Over the limit: the student keeps SELECT, DELETE and DROP, so the site still reads and they can
# clean up, but nothing new can be written. Under the limit again: full access comes back.
install -d -o root -g root -m 700 "$DB_OVER_DIR"
DATADIR="$(mysql -N -B -e 'SELECT @@datadir' 2>/dev/null)"
if [[ -z "$DATADIR" ]]; then
  log "could not reach MariaDB, database sizes not checked"
else
  for user in "${STUDENTS[@]}"; do
    dbdir="${DATADIR%/}/${user}"
    [[ -d "$dbdir" ]] || continue
    size_mb=$(( $(du -sk "$dbdir" 2>/dev/null | cut -f1) / 1024 ))
    # Same escaped pattern as add-student.sh (in GRANT an underscore means "any character")
    pattern="${user//_/\\_}"
    if (( size_mb > DB_MAX_MB )); then
      [[ -e "${DB_OVER_DIR}/${user}" ]] && continue
      if mysql -e "REVOKE ALL PRIVILEGES ON \`${pattern}\`.* FROM '${user}'@'localhost';
                   GRANT SELECT, DELETE, DROP ON \`${pattern}\`.* TO '${user}'@'localhost';
                   FLUSH PRIVILEGES;"; then
        touch "${DB_OVER_DIR}/${user}"
        log "${user}: database is ${size_mb} MB (limit ${DB_MAX_MB} MB) - writes blocked until it is smaller"
      fi
    elif [[ -e "${DB_OVER_DIR}/${user}" ]]; then
      if mysql -e "REVOKE ALL PRIVILEGES ON \`${pattern}\`.* FROM '${user}'@'localhost';
                   GRANT ALL PRIVILEGES ON \`${pattern}\`.* TO '${user}'@'localhost';
                   FLUSH PRIVILEGES;"; then
        rm -f "${DB_OVER_DIR}/${user}"
        log "${user}: database is ${size_mb} MB again - full access restored"
      fi
    fi
  done
fi

# 3. Disk space alert
used="$(df --output=pcent / | tail -1 | tr -dc '0-9')"
if [[ -n "$used" ]] && (( used >= DISK_ALERT_PERCENT )); then
  last="$(cat "$ALERT_STATE" 2>/dev/null || echo 0)"
  [[ "$last" =~ ^[0-9]+$ ]] || last=0
  if (( $(date +%s) - last >= ALERT_EVERY_SECONDS )); then
    body="The 5CS045 server disk is ${used}% full.

$(df -h /)

Accounts using the most space (the mysql account holds all databases):
$(repquota -us / 2>/dev/null | awk 'NR>5 && $1!~/^(root|#)/' | sort -k3 -h -r | head -10)

To grow the disk, see \"Growing the disk\" in the README."
    php "${DEPLOY_ROOT}/bin/send-admin-alert.php" "5CS045 server disk is ${used}% full" "$body" >/dev/null 2>&1
    rc=$?
    if [[ "$rc" -eq 0 ]]; then
      date +%s > "$ALERT_STATE"
      log "disk is ${used}% full - alert emailed"
    elif [[ "$rc" -eq 2 ]]; then
      date +%s > "$ALERT_STATE"   # so this is logged once a day, not every 15 minutes
      log "disk is ${used}% full - no alert sent because admin_email is not set in /etc/5cs045/smtp_config.php"
    else
      log "disk is ${used}% full - the alert email failed (run test/smtp-test.php)"
    fi
  fi
fi

exit 0
