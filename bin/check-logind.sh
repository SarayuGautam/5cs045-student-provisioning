#!/usr/bin/env bash
# Runs every minute from /etc/cron.d/5cs045. If systemd-logind (which sets up every SSH login)
# stops answering for two checks in a row, it is restarted and the admin is emailed.
#
# Why: in load testing, hundreds of logins in the same second left logind stuck. From then on
# every new SSH login failed until someone rebooted. Restarting logind does not log anyone out.
# Two misses in a row, not one, so a busy minute during a login rush is not mistaken for a hang.
#
# Usage: sudo check-logind.sh
set -uo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

DEPLOY_ROOT="/usr/local/sbin/5cs045"
LOG_FILE="/var/log/5cs045-provisioning.log"
STRIKES_FILE="/run/5cs045-logind-strikes"

[[ $EUID -eq 0 ]] || { echo "ERROR: run this with sudo" >&2; exit 1; }
exec 9>/run/5cs045-check-logind.lock
flock -n 9 || exit 0

if timeout 20 loginctl list-sessions --no-legend >/dev/null 2>&1; then
  rm -f "$STRIKES_FILE"
  exit 0
fi

strikes=$(( $(cat "$STRIKES_FILE" 2>/dev/null || echo 0) + 1 ))
echo "$strikes" > "$STRIKES_FILE"
if (( strikes < 2 )); then
  echo "[$(date -Is)] check-logind: logind did not answer within 20s, checking again in a minute" >> "$LOG_FILE"
  exit 0
fi

echo "[$(date -Is)] check-logind: logind has not answered for 2 minutes, restarting it" >> "$LOG_FILE"
if timeout 120 systemctl restart systemd-logind; then
  result="restarted"
else
  result="could NOT be restarted - SSH logins may be failing, reboot the server"
fi
rm -f "$STRIKES_FILE"
echo "[$(date -Is)] check-logind: logind ${result}" >> "$LOG_FILE"

php "${DEPLOY_ROOT}/bin/send-admin-alert.php" "5CS045 server: login service ${result%% -*}" \
  "systemd-logind, which sets up every SSH login, stopped answering for 2 minutes and was ${result}.

This usually follows hundreds of logins in the same few seconds. Nobody was logged out.
Details: sudo journalctl -u systemd-logind --since '15 min ago'" >/dev/null 2>&1 || true
exit 0
