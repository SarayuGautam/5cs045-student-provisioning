#!/usr/bin/env bash
# Removes every student at once - for example at the end of a semester, before the next cohort.
# Accounts, files and databases are deleted permanently. There is no backup.
#
# Usage: sudo remove-all-students.sh [--prefix loadtest_] [--yes]
#
# --prefix only removes students whose username starts with it (for example throwaway
#          load-test accounts), and leaves everyone else alone.
# --yes    skips the typed confirmation (for scripts).
set -euo pipefail

STUDENT_ROOT="/srv/students"
PHP_VERSION="8.3"
PREFIX=""
ASSUME_YES=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX="${2:-}"; shift 2 ;;
    --yes) ASSUME_YES=1; shift ;;
    -h) echo "Usage: $0 [--prefix <start of username>] [--yes]"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

[[ $EUID -eq 0 ]] || { echo "ERROR: run this with sudo" >&2; exit 1; }
[[ -z "$PREFIX" || "$PREFIX" =~ ^[a-z][a-z0-9_]*$ ]] || { echo "ERROR: --prefix may only contain lowercase letters, numbers and underscores" >&2; exit 1; }

# Cleans up after accounts that are already gone: the SSH limits, user-manager mask, saved
# password and database-limit marker that remove-student.sh would normally delete. Earlier
# versions of remove-student.sh could stop before that step.
sweep_leftovers() {
  local dropin uid name file swept=0
  for dropin in /etc/systemd/system/user-*.slice.d/50-5cs045-limits.conf; do
    [[ -f "$dropin" ]] || continue
    uid="${dropin#/etc/systemd/system/user-}"; uid="${uid%%.slice.d/*}"
    [[ "$uid" =~ ^[0-9]+$ ]] || continue
    getent passwd "$uid" >/dev/null && continue
    rm -f "$dropin"
    rmdir "/etc/systemd/system/user-${uid}.slice.d" 2>/dev/null || true
    if [[ "$(readlink "/etc/systemd/system/user@${uid}.service" 2>/dev/null)" == /dev/null ]]; then
      rm -f "/etc/systemd/system/user@${uid}.service"
    fi
    swept=$((swept + 1))
  done
  for file in /var/lib/5cs045-credentials/* /var/lib/5cs045-db-over/*; do
    [[ -f "$file" ]] || continue
    name="$(basename "$file")"
    id "$name" &>/dev/null || { rm -f "$file"; swept=$((swept + 1)); }
  done
  if [[ "$swept" -gt 0 ]]; then
    [[ -d /run/systemd/system ]] && systemctl daemon-reload
    echo "Cleaned up ${swept} leftover file(s) from accounts that no longer exist."
  fi
  return 0
}

USERS=()
for home in "$STUDENT_ROOT"/*/; do
  [[ -d "$home" ]] || continue
  user="$(basename "$home")"
  [[ "$user" == "$PREFIX"* ]] || continue
  id "$user" &>/dev/null && USERS+=("$user")
done

if [[ ${#USERS[@]} -eq 0 ]]; then
  echo "No students to remove."
  sweep_leftovers
  exit 0
fi

echo "This permanently deletes ${#USERS[@]} student account(s), with their files and databases."
[[ -n "$PREFIX" ]] && echo "Only usernames starting with '${PREFIX}'."
if [[ "$ASSUME_YES" -eq 0 ]]; then
  read -r -p "Type DELETE ${#USERS[@]} to continue: " reply
  [[ "$reply" == "DELETE ${#USERS[@]}" ]] || { echo "Aborted. Nothing was removed."; exit 1; }
fi

removed=0
failed=0
for user in "${USERS[@]}"; do
  if out="$("$(dirname "$0")/remove-student.sh" -u "$user" --no-reload 2>&1)"; then
    removed=$((removed + 1))
  else
    echo "FAILED to remove ${user}: $(tail -1 <<<"$out")" >&2
    failed=$((failed + 1))
  fi
  (( (removed + failed) % 50 == 0 )) && echo "  ${removed} removed so far..."
done

# One reload at the end instead of one per student
systemctl reload "php${PHP_VERSION}-fpm"
[[ -d /run/systemd/system ]] && systemctl daemon-reload

sweep_leftovers
echo "Removed ${removed} student(s). Failed: ${failed}."
[[ "$failed" -eq 0 ]]
