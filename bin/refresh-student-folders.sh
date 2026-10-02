#!/usr/bin/env bash
# Makes sure each student's web folders can be read by the web server, and adds a short
# note page to any folder that has no index file yet.
# Safe to run again at any time. It never touches a student's own files.
#
# Usage: sudo refresh-student-folders.sh [username ...]     (no names = all students)
set -euo pipefail

STUDENT_ROOT="/srv/students"
WEB_GROUP="www-data"

declare -A FOLDER_TITLE=([workshops]="Workshops" [exam]="Exam" [assessment]="Assessment")
declare -A FOLDER_INFO=(
  [workshops]="Open the week folder you were given, for example week1. The workshops folder itself is not a place to upload files."
  [exam]="Your exam folder is opened by your tutor when the exam is available."
  [assessment]="Your assessment folder is opened by your tutor when the assessment is available."
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
      cat > "${dir}/index.html" <<PAGE
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${FOLDER_TITLE[$area]}</title>
<style>
body{margin:0;padding:clamp(48px,12vh,128px) 24px 64px;font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;font-size:17px;line-height:1.65;color:#000;background:#fff}
main{max-width:34rem;margin:0 auto}
h1{margin:0 0 20px;font-size:2rem;line-height:1.2;font-weight:600;letter-spacing:-.01em;overflow-wrap:anywhere}
h2{margin:56px 0 24px;font-size:1rem;font-weight:600}
p{margin:0}
ul{margin:0;padding:0;list-style:none}
li{margin:0 0 28px}
li a{font-weight:600}
li p{margin-top:2px}
a{color:#000;text-underline-offset:3px}
.back{display:inline-block;margin-top:48px}
</style>
</head>
<body>
<main>
<h1>${FOLDER_TITLE[$area]}</h1>
<p>${FOLDER_INFO[$area]}</p>
<a class="back" href="/~${user}/">Back to your home page</a>
</main>
</body>
</html>
PAGE
      chown "${user}:${user}" "${dir}/index.html"
      setfacl -m "g:${WEB_GROUP}:r" "${dir}/index.html"
    fi
  done
  echo "checked $user"
done
