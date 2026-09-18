#!/usr/bin/env bash
# list-students.sh — quick audit of everyone currently provisioned
set -euo pipefail
STUDENT_ROOT="/srv/students"

printf "%-20s %-10s %-8s %-20s\n" "USERNAME" "UID" "DISK" "LAST LOGIN"
printf "%-20s %-10s %-8s %-20s\n" "--------" "---" "----" "----------"
for home in "$STUDENT_ROOT"/*/; do
  [[ -d "$home" ]] || continue
  user="$(basename "$home")"
  id "$user" &>/dev/null || continue
  uid="$(id -u "$user")"
  disk="$(du -sh "$home" 2>/dev/null | cut -f1)"
  last="$(lastlog -u "$user" 2>/dev/null | tail -1 | awk '{$1=""; print}' | sed 's/^ *//' || echo "never")"
  printf "%-20s %-10s %-8s %-20s\n" "$user" "$uid" "$disk" "$last"
done

echo ""
echo "Total students: $(find "$STUDENT_ROOT" -mindepth 1 -maxdepth 1 -type d | wc -l)"
echo "Total disk used: $(du -sh "$STUDENT_ROOT" 2>/dev/null | cut -f1)"
