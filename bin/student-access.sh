#!/usr/bin/env bash
# Controls student folder layout and scheduled access.
#
# Student home and the workshops root are not writable. Student content belongs in:
#   ~/workshops/weekN
#   ~/assessment
#   ~/exam
#
# Exam and assessment are either open, locked, or scheduled to open at a Unix timestamp.
# State is kept outside student homes so the student cannot change their own access.
#
# Usage:
#   sudo student-access.sh get USER
#   sudo student-access.sh set USER WEEKS EXAM_MODE EXAM_AT ASSESSMENT_MODE ASSESSMENT_AT
#   sudo student-access.sh apply USER
#   sudo student-access.sh all
#   sudo student-access.sh scheduled
set -euo pipefail

STUDENT_ROOT="/srv/students"
POLICY_DIR="/var/lib/5cs045-student-access"
LOCK_DIR="${POLICY_DIR}/.locks"
WEB_GROUP="www-data"
FIXED_WORKSHOP_WEEKS=(1 2 3 4 5 6 8 9 10 11 12)
WORKSHOP_FOLDER_COUNT=${#FIXED_WORKSHOP_WEEKS[@]}
USERNAME_RE='^[a-z][a-z0-9_]{2,31}$'

die() {
  echo "ERROR: $*" >&2
  exit 1
}

valid_user() {
  local user="$1"
  [[ "$user" =~ $USERNAME_RE ]] || die "invalid username"
  id "$user" >/dev/null 2>&1 || die "no such student: $user"
  [[ -d "${STUDENT_ROOT}/$user" ]] || die "no student home: $user"
}

policy_file() {
  printf '%s/%s' "$POLICY_DIR" "$1"
}

policy_value() {
  local key="$1" file="$2" default="$3"
  local value
  value="$(sed -n "s/^${key}=//p" "$file" 2>/dev/null | head -1 || true)"
  printf '%s' "${value:-$default}"
}

ensure_dirs() {
  local user="$1" home="${STUDENT_ROOT}/$user" group
  group="$(id -gn "$user")"

  mkdir -p "$home/workshops" "$home/exam" "$home/assessment"
  mkdir -p "$home/.ssh" "$home/.sessions"

  # The top level is only a container. Students can enter it but cannot create or delete
  # siblings. The three private/system directories remain owned by the student.
  chown root:"$group" "$home"
  chmod 750 "$home"
  setfacl -m "g:$WEB_GROUP:x" "$home" 2>/dev/null || true

  for private in .ssh .sessions; do
    chown "$user:$group" "$home/$private"
    chmod 700 "$home/$private"
  done

  # Students must put workshop work in weekN folders, not directly in ~/workshops.
  chown root:"$group" "$home/workshops"
  chmod 750 "$home/workshops"
  setfacl -m "g:$WEB_GROUP:rx" "$home/workshops" 2>/dev/null || true
}

write_week_index() {
  local user="$1" week="$2"
  local dir="${STUDENT_ROOT}/$user/workshops/week$week"
  [[ -f "$dir/index.php" || -f "$dir/index.html" ]] && return 0
  cat > "$dir/index.html" <<PAGE
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Week $week</title>
<style>
body{margin:0;padding:clamp(48px,12vh,128px) 24px 64px;font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;font-size:17px;line-height:1.65;color:#000;background:#fff}
main{max-width:34rem;margin:0 auto}
h1{margin:0 0 20px;font-size:2rem;line-height:1.2;font-weight:600;letter-spacing:-.01em}
p{margin:0}
a{color:#000;text-underline-offset:3px}
.back{display:inline-block;margin-top:48px}
</style>
</head>
<body>
<main>
<h1>Week $week</h1>
<p>Upload this week's workshop files here.</p>
<a class="back" href="../">Back to workshops</a>
</main>
</body>
</html>
PAGE
  chown "$user:$(id -gn "$user")" "$dir/index.html"
}

ensure_workshop_weeks() {
  local user="$1" home="${STUDENT_ROOT}/$user" group
  group="$(id -gn "$user")"

  for n in "${FIXED_WORKSHOP_WEEKS[@]}"; do
    dir="$home/workshops/week$n"
    mkdir -p "$dir"
    chown "$user:$group" "$dir"
    chmod 750 "$dir"
    setfacl -m "g:$WEB_GROUP:rx" "$dir" 2>/dev/null || true
    setfacl -m "d:g:$WEB_GROUP:rx" "$dir" 2>/dev/null || true
    write_week_index "$user" "$n"
  done

  # Keep legacy/unmanaged week folders inaccessible without deleting their contents.
  shopt -s nullglob
  for dir in "$home"/workshops/week*/; do
    name="$(basename "$dir")"
    [[ "$name" =~ ^week([0-9]+)$ ]] || continue
    n="${BASH_REMATCH[1]}"
    keep=0
    for allowed in "${FIXED_WORKSHOP_WEEKS[@]}"; do
      if (( n == allowed )); then
        keep=1
        break
      fi
    done
    (( keep == 1 )) && continue
    chown root:root "$dir"
    chmod 700 "$dir"
    setfacl -b "$dir" 2>/dev/null || true
  done
  shopt -u nullglob
}

set_area_open() {
  local user="$1" area="$2" home="${STUDENT_ROOT}/$user" group
  group="$(id -gn "$user")"
  dir="$home/$area"
  mkdir -p "$dir"
  chown "$user:$group" "$dir"
  chmod 750 "$dir"
  setfacl -m "g:$WEB_GROUP:rx" "$dir" 2>/dev/null || true
  setfacl -m "d:g:$WEB_GROUP:rx" "$dir" 2>/dev/null || true
}

set_area_locked() {
  local user="$1" area="$2" home="${STUDENT_ROOT}/$user"
  dir="$home/$area"
  mkdir -p "$dir"
  # The student cannot chmod/chown the directory back because root owns it while locked.
  chown root:root "$dir"
  chmod 700 "$dir"
  setfacl -b "$dir" 2>/dev/null || true
}

area_is_open() {
  local mode="$1" at="$2" now="$3"
  case "$mode" in
    open) return 0 ;;
    locked) return 1 ;;
    scheduled) [[ "$at" =~ ^[0-9]+$ ]] && (( at <= now )) ;;
    *) return 1 ;;
  esac
}

default_workshop_weeks() {
  printf "%s" "$WORKSHOP_FOLDER_COUNT"
}

default_area_mode() {
  local user="$1" area="$2" home="${STUDENT_ROOT}/$user" owner
  [[ -d "$home/$area" ]] || { printf 'locked'; return; }
  owner="$(stat -c '%U' "$home/$area" 2>/dev/null || true)"
  if [[ "$owner" == "$user" ]]; then
    printf 'open'
  else
    printf 'locked'
  fi
}
read_policy() {
  local user="$1" file
  file="$(policy_file "$user")"
  WORKSHOP_WEEKS="$WORKSHOP_FOLDER_COUNT"
  EXAM_MODE="$(policy_value EXAM_MODE "$file" "$(default_area_mode "$user" exam)")"
  EXAM_AT="$(policy_value EXAM_AT "$file" 0)"
  ASSESSMENT_MODE="$(policy_value ASSESSMENT_MODE "$file" "$(default_area_mode "$user" assessment)")"
  ASSESSMENT_AT="$(policy_value ASSESSMENT_AT "$file" 0)"

  WORKSHOP_WEEKS="$WORKSHOP_FOLDER_COUNT"
}

apply_user() {
  local user="$1" now="${2:-$(date +%s)}"
  valid_user "$user"
  read_policy "$user"
  ensure_dirs "$user"
  ensure_workshop_weeks "$user" "$WORKSHOP_WEEKS"

  if area_is_open "$EXAM_MODE" "$EXAM_AT" "$now"; then
    set_area_open "$user" exam
  else
    set_area_locked "$user" exam
  fi

  if area_is_open "$ASSESSMENT_MODE" "$ASSESSMENT_AT" "$now"; then
    set_area_open "$user" assessment
  else
    set_area_locked "$user" assessment
  fi

  flock -u "$lock_fd"
  eval "exec $lock_fd>&-"
}

apply_scheduled_user() {
  local user="$1" now="$2" home="${STUDENT_ROOT}/$user" file
  file="$(policy_file "$user")"
  [[ -f "$file" ]] || return 0
  valid_user "$user"

  local lock_file="$LOCK_DIR/$user"
  exec {lock_fd}>"$lock_file"
  flock -n "$lock_fd" || return 0

  EXAM_MODE="$(policy_value EXAM_MODE "$file" open)"
  EXAM_AT="$(policy_value EXAM_AT "$file" 0)"
  ASSESSMENT_MODE="$(policy_value ASSESSMENT_MODE "$file" open)"
  ASSESSMENT_AT="$(policy_value ASSESSMENT_AT "$file" 0)"

  if area_is_open "$EXAM_MODE" "$EXAM_AT" "$now"; then
    set_area_open "$user" exam
  else
    set_area_locked "$user" exam
  fi

  if area_is_open "$ASSESSMENT_MODE" "$ASSESSMENT_AT" "$now"; then
    set_area_open "$user" assessment
  else
    set_area_locked "$user" assessment
  fi
}

get_user() {
  local user="$1" file
  valid_user "$user"
  file="$(policy_file "$user")"
  echo "workshop_weeks=$(policy_value WORKSHOP_WEEKS "$file" "$(default_workshop_weeks "$user")")"
  echo "exam_mode=$(policy_value EXAM_MODE "$file" "$(default_area_mode "$user" exam)")"
  echo "exam_at=$(policy_value EXAM_AT "$file" 0)"
  echo "assessment_mode=$(policy_value ASSESSMENT_MODE "$file" "$(default_area_mode "$user" assessment)")"
  echo "assessment_at=$(policy_value ASSESSMENT_AT "$file" 0)"
}

set_user() {
  local user="$1" weeks="$2" exam_mode="$3" exam_at="$4" assessment_mode="$5" assessment_at="$6"
  valid_user "$user"
  [[ "$weeks" =~ ^[0-9]+$ ]] || weeks="$WORKSHOP_FOLDER_COUNT"
  [[ "$exam_mode" =~ ^(open|locked|scheduled)$ ]] || die "exam mode must be open, locked or scheduled"
  [[ "$assessment_mode" =~ ^(open|locked|scheduled)$ ]] || die "assessment mode must be open, locked or scheduled"

  if [[ "$exam_mode" == scheduled ]]; then
    [[ "$exam_at" =~ ^[0-9]+$ ]] && (( exam_at > 0 )) || die "exam scheduled time is invalid"
  else
    exam_at=0
  fi

  if [[ "$assessment_mode" == scheduled ]]; then
    [[ "$assessment_at" =~ ^[0-9]+$ ]] && (( assessment_at > 0 )) || die "assessment scheduled time is invalid"
  else
    assessment_at=0
  fi

  install -d -o root -g root -m 700 "$POLICY_DIR" "$LOCK_DIR"
  local file tmp
  file="$(policy_file "$user")"
  tmp="$(mktemp "$POLICY_DIR/.$user.XXXXXX")"
  cat > "$tmp" <<EOF
WORKSHOP_WEEKS=$WORKSHOP_FOLDER_COUNT
EXAM_MODE=$exam_mode
EXAM_AT=$exam_at
ASSESSMENT_MODE=$assessment_mode
ASSESSMENT_AT=$assessment_at
EOF
  chown root:root "$tmp"
  chmod 600 "$tmp"
  mv -f "$tmp" "$file"
  local lock_file="$LOCK_DIR/$user"
  exec {lock_fd}>"$lock_file"
  flock "$lock_fd"
  apply_user "$user"
  flock -u "$lock_fd"
  eval "exec $lock_fd>&-"
  echo "saved $user"
}

install -d -o root -g root -m 700 "$POLICY_DIR"

cmd="${1:-}"
case "$cmd" in
  get)
    [[ $# -eq 2 ]] || die "Usage: $0 get USER"
    get_user "$2"
    ;;
  set)
    [[ $# -eq 7 ]] || die "Usage: $0 set USER WEEKS EXAM_MODE EXAM_AT ASSESSMENT_MODE ASSESSMENT_AT"
    set_user "$2" "$3" "$4" "$5" "$6" "$7"
    ;;
  apply)
    [[ $# -eq 2 ]] || die "Usage: $0 apply USER"
    apply_user "$2"
    ;;
  all)
    for home in "$STUDENT_ROOT"/*/; do
      [[ -d "$home" ]] || continue
      user="$(basename "$home")"
      id "$user" >/dev/null 2>&1 && apply_user "$user"
    done
    ;;
  scheduled)
    now="$(date +%s)"
    for home in "$STUDENT_ROOT"/*/; do
      [[ -d "$home" ]] || continue
      user="$(basename "$home")"
      id "$user" >/dev/null 2>&1 && apply_scheduled_user "$user" "$now"
    done
    ;;
  *)
    die "Usage: $0 {get|set|apply|all|scheduled} ..."
    ;;
esac
