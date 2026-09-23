#!/usr/bin/env bash
# Creates throwaway load-test students (loadtest_001, loadtest_002, ...) exactly like real
# ones: Linux user, folders, database, PHP pool, disk quota and SSH limits. Their passwords
# go into loadtest-accounts.csv in your home folder, for ssh_load.py.
# Accounts that already exist are kept and added to the file again, so it is safe to rerun,
# or to run again with a bigger number.
#
# Remove them all afterwards with:
#   sudo /usr/local/sbin/5cs045/bin/remove-all-students.sh --prefix loadtest_ --yes
#
# Usage: sudo ./test/loadtest/create-accounts.sh 800
set -euo pipefail

DEPLOY_ROOT="/usr/local/sbin/5cs045"
PREFIX="loadtest_"
COUNT="${1:-}"

[[ $EUID -eq 0 ]] || { echo "ERROR: run this with sudo" >&2; exit 1; }
if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || (( COUNT < 1 || COUNT > 2000 )); then
  echo "Usage: sudo $0 <how many accounts, 1-2000>" >&2
  exit 1
fi

OWNER="${SUDO_USER:-root}"
OWNER_HOME="$(getent passwd "$OWNER" | cut -d: -f6)"
CSV="${OWNER_HOME}/loadtest-accounts.csv"
ERRORS="${OWNER_HOME}/loadtest-create-errors.log"
WIDTH=$(( ${#COUNT} < 3 ? 3 : ${#COUNT} ))

(umask 077; echo "username,password" > "${CSV}.tmp"; : > "$ERRORS")
echo "Creating ${COUNT} load-test accounts. This takes about a second each."
started=$(date +%s)
created=0
failed=0
for ((i = 1; i <= COUNT; i++)); do
  user="$(printf "%s%0${WIDTH}d" "$PREFIX" "$i")"
  if ! id "$user" &>/dev/null; then
    # -R: no PHP or systemd reload per account; done once below
    if "${DEPLOY_ROOT}/bin/add-student.sh" -u "$user" -n "Load test ${i}" -R >/dev/null 2>>"$ERRORS"; then
      created=$((created + 1))
    else
      echo "  FAILED to create ${user} (see ${ERRORS})"
      failed=$((failed + 1))
      continue
    fi
  fi
  password="$(sed -n 's/^PASSWORD=//p' "/var/lib/5cs045-credentials/${user}" 2>/dev/null || true)"
  if [[ -z "$password" ]]; then
    # Half-created by an earlier failed run: no saved password, so it cannot be used
    echo "  SKIPPED ${user}: it exists but has no saved password. Remove it with remove-student.sh -u ${user}"
    failed=$((failed + 1))
    continue
  fi
  echo "${user},${password}" >> "${CSV}.tmp"
  if (( i % 50 == 0 )); then
    echo "  ${i}/${COUNT}  ($(( $(date +%s) - started ))s so far)"
  fi
done

echo "Reloading PHP and systemd once for all the new accounts..."
systemctl daemon-reload
systemctl reload php8.3-fpm

mv "${CSV}.tmp" "$CSV"
chown "$OWNER": "$CSV" "$ERRORS"
chmod 600 "$CSV"
echo ""
echo "Done in $(( $(date +%s) - started ))s: ${created} created, $((COUNT - created - failed)) already existed, ${failed} failed or skipped."
echo "Passwords: ${CSV}"
if [[ "$OWNER" == "root" ]]; then
  # root cannot log in over SSH, so the file has to go to your own login first
  echo "Copy it to your own login, then to the machine that runs the test:"
  echo "  cp ${CSV} /home/<your login>/ && chown <your login>: /home/<your login>/loadtest-accounts.csv"
  echo "  scp <your login>@<this server>:loadtest-accounts.csv ."
else
  echo "Copy it to the machine that runs the test, for example:"
  echo "  scp ${OWNER}@<this server>:loadtest-accounts.csv ."
fi
