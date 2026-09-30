#!/bin/bash
# Lets the web server read everything in a student's three web folders. Runs as the student,
# after each of their SSH sessions (see bin/student-ssh-session.sh). An admin can run it for one
# student with: sudo -u <username> /usr/local/sbin/5cs045/bin/fix-web-access.sh
#
# On a file with an ACL, the group permission bits are the ACL mask, so find picks out exactly the
# folders and files the web server cannot read, and adding the www-data entry again recalculates
# the mask. Folders and files that are fine are not touched.
set -u
user="$(id -un)"
home="/srv/students/${user}"
[[ -d "$home" && "$(id -u)" -ne 0 ]] || exit 0

# One repair at a time for each student. A session that ends during a repair waits for it, but only
# one waits: if another is already waiting, it will also cover this session's uploads.
if [[ -d "$home/.sessions" ]]; then
  exec 8>>"$home/.sessions/.fix-web-access.wait" || exit 0
  flock -n 8 || exit 0
  exec 9>>"$home/.sessions/.fix-web-access.lock" || exit 0
  flock -w 120 9 || exit 0
  flock -u 8
fi

renice -n 10 -p $$ >/dev/null 2>&1
ionice -c 3 -p $$ >/dev/null 2>&1

setfacl -m g:www-data:x -- "$home" 2>/dev/null
for area in workshops exam assessment; do
  [[ -d "$home/$area" ]] || continue
  find "$home/$area" \( -type d ! -perm -g=rx -exec setfacl -m g:www-data:rx -- {} + \) \
                  -o \( -type f ! -perm -g=r -exec setfacl -m g:www-data:r -- {} + \) 2>/dev/null
done
exit 0
