#!/usr/bin/env bash
# Clears a student managed folder without changing its access policy.
# Workshops clears week1-week6 and week8-week12. Exam/Assessment clear their contents.
set -euo pipefail

STUDENT_ROOT="/srv/students"
WEB_GROUP="www-data"
FIXED_WORKSHOP_WEEKS=(1 2 3 4 5 6 8 9 10 11 12)
USERNAME_RE='^[a-z][a-z0-9_]{2,31}$'

die() { echo "ERROR: $*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die "run this as root"
[[ $# -eq 2 ]] || die "Usage: $0 USER workshops|exam|assessment"
USER="$1"
AREA="$2"
[[ "$USER" =~ $USERNAME_RE ]] || die "invalid username"
id "$USER" >/dev/null 2>&1 || die "no such student: $USER"
HOME_DIR="$STUDENT_ROOT/$USER"
[[ -d "$HOME_DIR" ]] || die "no student home: $USER"
case "$AREA" in workshops|exam|assessment) ;; *) die "unknown folder: $AREA" ;; esac

write_index() {
  local dir="$1" title="$2" text="$3"
  rm -f "$dir/index.php" "$dir/index.html"
  cat > "$dir/index.html" <<EOF
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>$title</title>
<style>body{margin:0;padding:64px 24px;font-family:system-ui,-apple-system,"Segoe UI",sans-serif;line-height:1.6;color:#000;background:#fff}main{max-width:36rem;margin:auto}h1{font-size:2rem;margin:0 0 18px}a{color:#000}</style>
</head><body><main><h1>$title</h1><p>$text</p><a href="/~$USER/">Back to your home page</a></main></body></html>
EOF
  chown "$USER:$(id -gn "$USER")" "$dir/index.html"
  chmod 640 "$dir/index.html"
  setfacl -m "g:$WEB_GROUP:r" "$dir/index.html" 2>/dev/null || true
}

clear_dir() {
  local dir="$1" title="$2" text="$3"
  mkdir -p "$dir"
  find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  write_index "$dir" "$title" "$text"

  if [[ "$(stat -c "%U" "$dir")" == "$USER" ]]; then
    chown "$USER:$(id -gn "$USER")" "$dir"
    chmod 750 "$dir"
    setfacl -m "g:$WEB_GROUP:rx" "$dir" 2>/dev/null || true
    setfacl -m "d:g:$WEB_GROUP:rx" "$dir" 2>/dev/null || true
  else
    chown root:root "$dir"
    chmod 700 "$dir"
    setfacl -b "$dir" 2>/dev/null || true
    chown root:root "$dir/index.html"
    chmod 600 "$dir/index.html"
  fi
}

case "$AREA" in
  workshops)
    mkdir -p "$HOME_DIR/workshops"
    chown root:"$(id -gn "$USER")" "$HOME_DIR/workshops"
    chmod 750 "$HOME_DIR/workshops"
    setfacl -m "g:$WEB_GROUP:rx" "$HOME_DIR/workshops" 2>/dev/null || true
    for week in "${FIXED_WORKSHOP_WEEKS[@]}"; do
      clear_dir "$HOME_DIR/workshops/week$week" "Week $week" "Upload this week's workshop files here."
    done
    ;;
  exam)
    clear_dir "$HOME_DIR/exam" "Exam" "Your exam folder is ready for your exam work."
    ;;
  assessment)
    clear_dir "$HOME_DIR/assessment" "Assessment" "Your assessment folder is ready for your project."
    ;;
esac

echo "cleared $USER/$AREA"
