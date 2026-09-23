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

USERS=()
for home in "$STUDENT_ROOT"/*/; do
  [[ -d "$home" ]] || continue
  user="$(basename "$home")"
  [[ "$user" == "$PREFIX"* ]] || continue
  id "$user" &>/dev/null && USERS+=("$user")
done

if [[ ${#USERS[@]} -eq 0 ]]; then
  echo "No students to remove."
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
  if "$(dirname "$0")/remove-student.sh" -u "$user" --no-reload >/dev/null 2>&1; then
    removed=$((removed + 1))
  else
    echo "FAILED to remove ${user}" >&2
    failed=$((failed + 1))
  fi
  (( (removed + failed) % 50 == 0 )) && echo "  ${removed} removed so far..."
done

# One reload at the end instead of one per student
systemctl reload "php${PHP_VERSION}-fpm"
[[ -d /run/systemd/system ]] && systemctl daemon-reload

echo "Removed ${removed} student(s). Failed: ${failed}."
[[ "$failed" -eq 0 ]]
