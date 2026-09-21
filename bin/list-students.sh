#!/usr/bin/env bash
# Lists all students with their disk use and last login.
set -euo pipefail

printf "%-24s %-8s %s\n" "USERNAME" "DISK" "LAST LOGIN"
count=0
for home in /srv/students/*/; do
  [[ -d "$home" ]] || continue
  user="$(basename "$home")"
  id "$user" &>/dev/null || continue
  disk="$(du -sh "$home" 2>/dev/null | cut -f1)"
  last="$(lastlog -u "$user" 2>/dev/null | tail -1 | awk '{$1=""; print}' | sed 's/^ *//')"
  printf "%-24s %-8s %s\n" "$user" "$disk" "$last"
  count=$((count + 1))
done
echo ""
echo "Students: ${count}"
