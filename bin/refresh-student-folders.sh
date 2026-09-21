#!/usr/bin/env bash
# Makes sure each student's web folders can be read by the web server, and adds a short
# note page to any folder that has no index file yet.
# Safe to run again at any time. It never touches a student's own files.
#
# Usage: sudo refresh-student-folders.sh [username ...]     (no names = all students)
set -euo pipefail

STUDENT_ROOT="/srv/students"
WEB_GROUP="www-data"

declare -A FOLDER_INFO=(
  [workshops]="Use this folder for your weekly workshop work. Make one folder for each week, for example week1."
  [exam]="Use this folder for the timed practical exam."
  [assessment]="Use this folder for your final assessment project."
)

[[ $EUID -eq 0 ]] || { echo "ERROR: run this with sudo" >&2; exit 1; }

if [[ $# -gt 0 ]]; then
  USERS=("$@")
else
  USERS=()
  for home in "$STUDENT_ROOT"/*/; do
    [[ -d "$home" ]] && USERS+=("$(basename "$home")")
  done
fi

for user in "${USERS[@]}"; do
  home="${STUDENT_ROOT}/${user}"
  id "$user" &>/dev/null && [[ -d "$home" ]] || { echo "skipped $user (no such student)"; continue; }

  setfacl -m "g:${WEB_GROUP}:x" "$home"
  for area in workshops exam assessment; do
    dir="${home}/${area}"
    mkdir -p "$dir"
    chown "${user}:${user}" "$dir"
    chmod 750 "$dir"
    setfacl -R -m "g:${WEB_GROUP}:rx" "$dir"
    setfacl -R -m "d:g:${WEB_GROUP}:rx" "$dir"
    if ! ls "$dir"/index.* >/dev/null 2>&1; then
      printf '<!doctype html>\n<html lang="en"><head><meta charset="utf-8"><title>%s</title></head>\n<body style="font-family:system-ui,sans-serif;max-width:40rem;margin:3rem auto;padding:0 1rem">\n<h1>%s</h1>\n<p>%s</p>\n</body></html>\n' \
        "$area" "$area" "${FOLDER_INFO[$area]}" > "${dir}/index.html"
      chown "${user}:${user}" "${dir}/index.html"
      setfacl -m "g:${WEB_GROUP}:r" "${dir}/index.html"
    fi
  done
  echo "checked $user"
done
